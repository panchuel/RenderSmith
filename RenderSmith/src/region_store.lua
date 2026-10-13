-- region_store.lua
-- Region identity and per-region metadata.
--
-- Identity is REAPER's own marker GUID, read through
-- GetSetProjectInfo_String("MARKER_GUID:<enum index>"). Unlike the
-- "<pos>_<end>" string it replaces, a GUID survives moving, resizing and
-- renaming a region, and "MARKER_INDEX_FROM_GUID:<guid>" resolves it back
-- in one call instead of scanning every marker in the project.
--
-- Metadata (root, parent and the folder track the region was built from)
-- lives in ProjExtState, so it travels inside the .rpp instead of leaking
-- between projects the way the old global ExtState dictionary did.
-- Regions/markers have no P_EXT of their own, so a keyed blob is the only
-- per-project store available.

local HIERARCHY_KEY = "region_hierarchy"
local LEGACY_KEY    = "region_hierarchy"   -- same name, but in global ExtState

-- Identity

function region_guid(enum_index)
    local ok, guid = reaper.GetSetProjectInfo_String(
        0, "MARKER_GUID:" .. enum_index, "", false)
    if not ok or guid == "" then return nil end
    return guid
end

function region_index_from_guid(guid)
    if not guid or guid == "" then return nil end
    local ok, idx = reaper.GetSetProjectInfo_String(
        0, "MARKER_INDEX_FROM_GUID:" .. guid, "", false)
    if not ok then return nil end
    return tonumber(idx)
end

-- Full record for a GUID, or nil when the region no longer exists.
function region_by_guid(guid)
    local idx = region_index_from_guid(guid)
    if not idx then return nil end
    local ok, isrgn, pos, rend, name = reaper.EnumProjectMarkers(idx)
    if ok == 0 or not isrgn then return nil end
    return { guid = guid, index = idx, pos = pos, rend = rend, name = name }
end

-- Every region in the project, in timeline order, with its GUID resolved.
function region_list()
    local list = {}
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local ok, isrgn, pos, rend, name = reaper.EnumProjectMarkers(i)
        if ok ~= 0 and isrgn then
            local guid = region_guid(i)
            if guid then
                list[#list + 1] =
                    { guid = guid, index = i, pos = pos, rend = rend, name = name }
            end
        end
    end
    return list
end

-- AddProjectMarker2 hands back a markrgnindexnumber, not the enumeration
-- index the GUID lookup needs, so map one to the other after creating.
function region_enum_index_by_number(number)
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local ok, isrgn, _, _, _, num = reaper.EnumProjectMarkers(i)
        if ok ~= 0 and isrgn and num == number then return i end
    end
    return nil
end

-- An existing region with this exact name and range, or nil. Used so that
-- creating regions twice over the same folders reuses what is already
-- there instead of stacking duplicates on top of it.
local RANGE_EPSILON = 1e-6

function region_find_matching(name, pos, rend)
    for _, region in ipairs(region_list()) do
        if region.name == name
            and math.abs(region.pos - pos) < RANGE_EPSILON
            and math.abs(region.rend - rend) < RANGE_EPSILON then
            return region
        end
    end
    return nil
end

-- Metadata

function region_set_meta(guid, root, parent, track_guid)
    if not guid then return false end
    RC.region_meta[guid] = {
        root       = root or "",
        parent     = parent or "",
        track_guid = track_guid or "",
    }
    return true
end

function region_get_meta(guid)
    return guid and RC.region_meta[guid] or nil
end

function region_meta_save()
    local lines = {}
    for guid, meta in pairs(RC.region_meta) do
        lines[#lines + 1] = table.concat(
            { guid, meta.root or "", meta.parent or "", meta.track_guid or "" }, "|")
    end
    reaper.SetProjExtState(0, RC.EXT_KEY, HIERARCHY_KEY, table.concat(lines, "\n"))
end

-- Pre-GUID installs stored hierarchy in *global* ExtState keyed by
-- "<pos>_<end>". Match those keys against the regions actually present and
-- re-key them by GUID, so upgrading does not lose existing hierarchy.
local function migrate_legacy_hierarchy()
    local raw = reaper.GetExtState(RC.EXT_KEY, LEGACY_KEY)
    if raw == "" then return false end

    local legacy = {}
    for line in (raw .. "\n"):gmatch("([^\n]+)") do
        local id, root, parent = line:match("^([^|]+)|([^|]*)|(.-)$")
        if id then legacy[id] = { root = root or "", parent = parent or "" } end
    end

    local migrated = 0
    for _, region in ipairs(region_list()) do
        local key = string.format("%.10f_%.10f", region.pos, region.rend)
        local old = legacy[key]
        if old and not RC.region_meta[region.guid] then
            region_set_meta(region.guid, old.root, old.parent, "")
            migrated = migrated + 1
        end
    end

    if migrated > 0 then region_meta_save() end
    return migrated > 0
end

function region_meta_load()
    RC.region_meta = {}

    local _, raw = reaper.GetProjExtState(0, RC.EXT_KEY, HIERARCHY_KEY)
    if raw and raw ~= "" then
        for line in (raw .. "\n"):gmatch("([^\n]+)") do
            local guid, root, parent, track_guid =
                line:match("^([^|]+)|([^|]*)|([^|]*)|(.-)$")
            if guid then
                RC.region_meta[guid] =
                    { root = root, parent = parent, track_guid = track_guid or "" }
            end
        end
    else
        migrate_legacy_hierarchy()
    end

    return RC.region_meta
end

-- Track association

-- The folder track a region was built from, when we still know it. Regions
-- created before this was recorded (or by hand) return nil and the caller
-- falls back to overlap detection.
function region_source_track(guid)
    local meta = region_get_meta(guid)
    if not meta or not meta.track_guid or meta.track_guid == "" then return nil end

    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if reaper.GetTrackGUID(tr) == meta.track_guid then return tr end
    end
    return nil
end

RC.region_meta = {}
region_meta_load()
