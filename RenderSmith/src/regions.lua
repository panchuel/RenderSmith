-- regions.lua
-- Builds regions from the selected folder structure.
--
-- Regions are hybrid: "Create Regions" writes persistent regions into the
-- project (the tool's original purpose), while the render cycle can also
-- build regions, render them and delete them again (see render.lua).
-- Both paths go through the same builder so naming stays identical.

-- Hierarchy for a region, by GUID. Regions RenderSmith created carry their
-- root/parent in the project store; anything else (hand-made regions, or
-- regions from an older install whose positions no longer match) falls
-- back to reading the name. That fallback is best-effort by nature: the
-- store is the authority.
function get_region_hierarchy(guid)
    local meta = region_get_meta(guid)
    if meta and meta.root ~= "" then
        return { root = meta.root, parent = meta.parent }
    end

    local region = region_by_guid(guid)
    if not region then return { root = "General", parent = "Parent" } end

    local matched_prefix
    for _, t in ipairs(RC.audio_types or {}) do
        if region.name:sub(1, #t.prefix + 1) == t.prefix .. "_" then
            matched_prefix = t.prefix
            break
        end
    end

    local body = matched_prefix and region.name:match("^" .. matched_prefix .. "_(.+)$")
    if body then
        local segs = {}
        for s in body:gsub("_$", ""):gmatch("[^_]+") do segs[#segs + 1] = s end
        if #segs >= 2 then
            local parent = segs[#segs]
            table.remove(segs, #segs)
            return { root = table.concat(segs, "_"), parent = parent }
        elseif #segs == 1 then
            return { root = segs[1], parent = segs[1] }
        end
    end

    return { root = "General", parent = "Parent" }
end

function update_region_hierarchy(guid, root, parent)
    local meta = region_get_meta(guid)
    if not region_set_meta(guid, root, parent, meta and meta.track_guid or "") then
        return false
    end
    region_meta_save()
    return true
end

-- Sounds from the child tracks, plus this folder's NameSwitch markers.
-- A marker is metadata, never audio, so it is skipped even when it sits on
-- a child track among real items.
local function collect_folder_items(folder_track)
    local items = {}

    for _, child in ipairs(get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if not is_name_switch(item) then
                items[#items + 1] = {
                    pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                    len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
                }
            end
        end
    end

    for _, sw in ipairs(collect_folder_switches(folder_track)) do
        items[#items + 1] = sw
    end

    return items
end

-- Gap threshold in seconds. Clustering off means "one region per folder",
-- which is an infinite threshold, so both modes share one code path.
-- A folder track may carry its own gap; see settings_cascade.lua.
local function effective_gap_length(track)
    if not RC.cluster_enabled then return math.huge end
    if RC.gap_use_beat then
        local tempo = reaper.Master_GetTempo()
        if tempo and tempo > 0 then return 60 / tempo end
    end
    return setting_resolve("gap_length", track, RC.gap_length or 1.0)
end

-- Digit width for $number, matched to REAPER's own autoincrsuffix so
-- tool-made names line up with names REAPER generates itself.
-- reaper.ini is read once per session: plan_folder_regions runs per folder
-- and, with the preview open, repeatedly.
local cached_digits = nil
local function autoincr_digits()
    if cached_digits then return cached_digits end

    cached_digits = 2
    local f = io.open(reaper.GetResourcePath() .. "/REAPER.ini", "r")
    if f then
        local content = f:read("*a")
        f:close()
        local _, digits = parse_autoincr_suffix(content:match("autoincrsuffix=([^\r\n]+)"))
        cached_digits = digits
    end
    return cached_digits
end

local function is_valid_parent_folder(track)
    if get_folder_depth(track) ~= 1 then return false end
    for _, child in ipairs(get_child_tracks(track)) do
        if reaper.CountTrackMediaItems(child) > 0 then return true end
    end
    return false
end

-- Root/parent names a folder track contributes to its regions.
function folder_naming_context(folder_track)
    local folder_name = clean_name(get_track_name(folder_track))
    local parent_tr   = get_parent_track(folder_track)
    local root_name
    if parent_tr then
        root_name = clean_name(get_track_name(parent_tr))
    else
        local _, proj = reaper.EnumProjects(-1, "")
        root_name = (proj:match("([^\\/]+)$") or "Project"):gsub("%..+$", "")
    end
    return root_name, folder_name
end

-- Name a folder track would produce. Shared by the creator and by the GUI
-- preview so what you see is what gets written.
--
-- number_text is the cluster number already formatted, or "" when the
-- folder yields a single region and numbering of singles is off: the
-- underscore cleanup then removes the gap the empty token leaves behind.
-- `name_override` is a NameSwitch name; it replaces the folder name, so
-- $parent resolves to the section rather than the folder.
function build_region_name(folder_track, atype, number_text, name_override)
    local root_name, folder_name = folder_naming_context(folder_track)
    if name_override and name_override ~= "" then
        folder_name = clean_name(name_override)
    end

    local pattern = atype.ucs_enabled and atype.ucs_wildcard or atype.wildcard
    local name    = expand_wildcards(pattern, atype.prefix, root_name, folder_name,
        { track = folder_track, number_text = number_text })

    if atype.ucs_enabled or (number_text or "") == "" then
        -- UCS reserves "_" as field separator, and an empty $number leaves
        -- the same kind of gap: collapse doubled underscores and trim.
        name = name:gsub("__+", "_"):gsub("^_+", ""):gsub("_+$", "")
    end
    return name, root_name, folder_name
end

-- What regions a folder track would produce, without touching the project.
-- The creator and the preview both go through here, so what the preview
-- draws can never disagree with what you end up with.
--
-- `items` restricts the plan to a specific set of {pos, len}; that is how
-- item-selection mode works. Without it the whole folder is used, and the
-- track must be a folder holding items.
function plan_folder_regions(track, items)
    if is_track_excluded(track) then return {} end

    if not items then
        if not is_valid_parent_folder(track) then return {} end
        items = collect_folder_items(track)
    end
    if #items == 0 then return {} end

    -- Each folder resolves its own type and gap, so one selection can mix
    -- folders that render differently.
    local atype    = resolve_audio_type(track) or { prefix = "sx", wildcard = "$region" }
    local clusters = cluster_items(items, effective_gap_length(track))
    if #clusters == 0 then return {} end

    local digits     = autoincr_digits()
    local single     = (#clusters == 1) and not RC.number_single_files
    local track_guid = reaper.GetTrackGUID(track)
    local planned    = {}

    for _, c in ipairs(clusters) do
        local number_text = single and "" or format_cluster_number(c.index, digits)
        local name, root, parent = build_region_name(track, atype, number_text, c.name)
        planned[#planned + 1] = {
            name  = name,  start  = c.start, stop = c.stop,
            root  = root,  parent = parent,  track_guid = track_guid,
            color = c.color,
        }
    end
    return planned
end

-- Selection modes
-- Item selection wins over track selection, which is the behaviour people
-- expect but also the easiest to trip over: leaving items selected while
-- meaning to render whole folders silently narrows the job. That is what
-- RC.always_track_mode is for: it pins the tool to folders.

function determine_region_mode()
    if not RC.always_track_mode and reaper.CountSelectedMediaItems(0) > 0 then
        return "items"
    end
    return "tracks"
end

-- The folder a track's items belong to: the nearest ancestor that starts a
-- folder, or the track itself when it is one. Items on a loose track with
-- no folder above them name themselves.
local function owning_folder_track(track)
    if get_folder_depth(track) == 1 then return track end
    local parent = get_parent_track(track)
    while parent do
        if get_folder_depth(parent) == 1 then return parent end
        parent = get_parent_track(parent)
    end
    return track
end

-- Selected items grouped by the folder that owns them, so each group can
-- be clustered and named with that folder's own type and gap.
local function selected_items_by_folder()
    local groups, order = {}, {}

    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item   = reaper.GetSelectedMediaItem(0, i)
        local folder = owning_folder_track(reaper.GetMediaItem_Track(item))

        if not groups[folder] then
            groups[folder] = {}
            order[#order + 1] = folder
        end
        if not is_name_switch(item) then
            local group = groups[folder]
            group[#group + 1] = {
                pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
            }
        end
    end

    -- Markers apply to whatever was picked inside their section, so add
    -- each involved folder's markers even when they were not selected.
    for _, folder in ipairs(order) do
        for _, sw in ipairs(collect_folder_switches(folder)) do
            table.insert(groups[folder], sw)
        end
    end

    return groups, order
end

-- Every region the current selection would produce. The single entry point
-- for creation and preview alike, so both agree on mode as well as naming.
-- Returns the planned regions, the folder tracks involved, and the mode.
function plan_current_selection()
    local mode    = determine_region_mode()
    local planned = {}
    local folders = {}

    if mode == "items" then
        local groups, order = selected_items_by_folder()
        for _, folder in ipairs(order) do
            local part = plan_folder_regions(folder, groups[folder])
            if #part > 0 then
                folders[#folders + 1] = folder
                for _, p in ipairs(part) do planned[#planned + 1] = p end
            end
        end
    else
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            local part  = plan_folder_regions(track)
            if #part > 0 then
                folders[#folders + 1] = track
                for _, p in ipairs(part) do planned[#planned + 1] = p end
            end
        end
    end

    return planned, folders, mode
end

-- Creates one region per cluster over the selected folders.
--
-- Returns two lists: every GUID involved, and only those actually created
-- by this call. A region that already exists with the same name and range
-- is reused instead of duplicated, which matters twice over: pressing
-- Create Regions again no longer stacks copies, and the ephemeral render
-- path learns which regions are safe to delete afterwards (the ones you
-- already had are not).
function create_regions_from_selection()
    local planned, folders = plan_current_selection()

    if #planned == 0 then
        reaper.ShowMessageBox(
            "Nothing to work with.\n\nSelect parent folder tracks, or select the items " ..
            "you want to turn into regions.", "No Selection", 0)
        return {}, {}
    end

    for _, folder in ipairs(folders) do mark_original_items(folder) end

    local guids, created = {}, {}
    RC.valid_tracks = {}

    for _, p in ipairs(planned) do
        local existing = region_find_matching(p.name, p.start, p.stop)
        local guid

        if existing then
            guid = existing.guid
        else
            local marker_num = reaper.AddProjectMarker2(
                0, true, p.start, p.stop, p.name, -1, p.color or 0)
            local enum_idx = region_enum_index_by_number(marker_num)
            guid = enum_idx and region_guid(enum_idx)
            if guid then created[#created + 1] = guid end
        end

        if guid then
            region_set_meta(guid, p.root, p.parent, p.track_guid)
            guids[#guids + 1] = guid
        end

        table.insert(RC.valid_tracks, {
            name = p.name, start = p.start, end_pos = p.stop, variation = 1,
        })
    end

    return guids, created
end

function validate_preconditions()
    if reaper.GetSelectedTrack(0, 0) == nil
        and reaper.CountSelectedMediaItems(0) == 0 then
        return false,
            "Nothing selected.\n\nSelect one or more parent folder tracks, or select the " ..
            "items you want to turn into regions."
    end

    if not RC.audio_types or not RC.audio_types[RC.selected_type_idx or 0] then
        return false,
            "Audio type configuration is missing or corrupted.\n\n" ..
            "Go to the Audio Types tab and click Reset to Defaults."
    end

    local ext_ok = pcall(function()
        reaper.GetExtState(RC.EXT_KEY, "audio_type_count")
    end)
    if not ext_ok then
        return false,
            "Cannot read REAPER ExtState (key: " .. tostring(RC.EXT_KEY) .. ").\n\n" ..
            "Check script permissions or restart REAPER."
    end

    local lib_path = reaper.GetExtState("Lokasenna_GUI", "lib_path_v2")
    if not lib_path or lib_path == "" then
        return false,
            "Lokasenna_GUI v2 library path is not configured.\n\n" ..
            "Run: Scripts > ReaTeam Scripts > Development >\n" ..
            "Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua"
    end
    local f = io.open(lib_path .. "Core.lua", "r")
    if not f then
        return false,
            "Lokasenna_GUI v2 Core.lua not found at:\n" .. lib_path .. "\n\n" ..
            "Re-run the library path setter script."
    end
    f:close()

    local _, proj_path = reaper.EnumProjects(-1, "")
    if proj_path == "" then
        local choice = reaper.ShowMessageBox(
            "This project has never been saved.\n\n" ..
            "The region root name will default to \"Project\".\n\nContinue anyway?",
            RC.PRODUCT_NAME .. " - Unsaved Project", 4)
        if choice ~= 6 then return false, "" end
    end

    return true, ""
end

function create_regions()
    local licensed, lic_msg = license_require()
    if not licensed then
        reaper.ShowMessageBox(lic_msg, RC.PRODUCT_NAME, 0)
        return
    end

    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    if not RC.audio_types[RC.selected_type_idx] then
        reaper.ShowMessageBox("No audio type selected.", "Invalid Selection", 0)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Create Regions", -1)
        return
    end

    local valid, msg = validate_preconditions()
    if not valid then
        if msg ~= "" then
            reaper.ShowMessageBox(msg, RC.PRODUCT_NAME .. " - Cannot Proceed", 0)
        end
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Create Regions", -1)
        return
    end

    -- pcall protects against unexpected runtime errors in track/region logic
    local ok, err = pcall(function()
        sync_config_to_audio_type()
        local guids, created = create_regions_from_selection()
        if #guids > 0 then
            region_meta_save()
            local reused = #guids - #created
            local msg = string.format("Created %d region(s).", #created)
            if reused > 0 then
                msg = msg .. string.format("\n%d already existed and were reused.", reused)
            end
            reaper.ShowMessageBox(msg, "Regions Created", 0)
        end
    end)

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create Regions", -1)

    if not ok then
        reaper.ShowMessageBox(
            "Unexpected error in " .. RC.PRODUCT_NAME .. ":\n\n" .. tostring(err),
            RC.PRODUCT_NAME .. " - Error", 0)
    end
end

function update_selected_region_hierarchy()
    local pos = reaper.GetCursorPosition()
    local target
    for _, region in ipairs(region_list()) do
        if pos >= region.pos and pos <= region.rend then
            target = region
            break
        end
    end

    if not target then
        reaper.ShowMessageBox("Place cursor inside a region to update it.", "Region not detected", 0)
        return
    end

    local h = get_region_hierarchy(target.guid)
    local ok, input = reaper.GetUserInputs("Update Hierarchy", 2,
        "Root,Parent:", h.root .. "," .. h.parent)
    if not ok then return end

    local r, p = input:match("([^,]+),([^,]+)")
    if not r or not p then
        reaper.ShowMessageBox("Use format: root,parent", "Error", 0)
        return
    end

    r = r:match("^%s*(.-)%s*$")
    p = p:match("^%s*(.-)%s*$")
    if update_region_hierarchy(target.guid, r, p) then
        reaper.ShowMessageBox("Root: " .. r .. "\nParent: " .. p, "Updated", 0)
    else
        reaper.ShowMessageBox("Error updating hierarchy.", "Error", 0)
    end
end
