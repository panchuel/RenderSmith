-- settings_cascade.lua
-- Per-track and per-project overrides, resolved as a cascade:
--
--     track (P_EXT)  →  project (ProjExtState)  →  global (RC / ExtState)
--
-- The point is that a folder track can carry its own render intent inside
-- the .rpp: mark a folder as "Music" once and it stays Music no matter
-- what the Audio Type dropdown says, and mark a scratch folder excluded
-- and it drops out of "render everything" for good.
--
-- Each setting is declared once, here, with all of its representations;
-- everything else iterates over this table rather than naming keys by
-- hand. That is what keeps the cascade from turning into a pile of ifs.

RC.SETTING_REGISTRY = {
    { name = "audio_type", type = "string", label = "Audio type",
      pext = "P_EXT:RF_AudioType", proj = "RF_AudioType" },

    { name = "base_dir",   type = "string", label = "Output folder",
      pext = "P_EXT:RF_BaseDir",   proj = "RF_BaseDir" },

    { name = "gap_length", type = "number", label = "Gap (s)",
      pext = "P_EXT:RF_GapLength", proj = "RF_GapLength" },

    -- Track-only: "excluded" is a property of a track, not of a project.
    { name = "excluded",   type = "bool",   label = "Excluded",
      pext = "P_EXT:RF_Excluded",  proj = nil },
}

local by_name = {}
for _, entry in ipairs(RC.SETTING_REGISTRY) do by_name[entry.name] = entry end

function setting_entry(name)
    return by_name[name]
end

local function decode(entry, raw)
    if raw == nil or raw == "" then return nil end
    if entry.type == "number" then return tonumber(raw)
    elseif entry.type == "bool" then return raw == "1" end
    return raw
end

local function encode(entry, value)
    if value == nil then return "" end
    if entry.type == "bool" then return value and "1" or "0" end
    return tostring(value)
end

-- Track level

function setting_get_track(track, name)
    local entry = by_name[name]
    if not entry or not track then return nil end
    if not reaper.ValidatePtr(track, "MediaTrack*") then return nil end
    local ok, raw = reaper.GetSetMediaTrackInfo_String(track, entry.pext, "", false)
    if not ok then return nil end
    return decode(entry, raw)
end

function setting_set_track(track, name, value)
    local entry = by_name[name]
    if not entry or not track then return false end
    if not reaper.ValidatePtr(track, "MediaTrack*") then return false end
    return reaper.GetSetMediaTrackInfo_String(
        track, entry.pext, encode(entry, value), true)
end

function setting_clear_track(track, name)
    return setting_set_track(track, name, nil)
end

-- Project level

function setting_get_project(name)
    local entry = by_name[name]
    if not entry or not entry.proj then return nil end
    local _, raw = reaper.GetProjExtState(0, RC.EXT_KEY, entry.proj)
    return decode(entry, raw)
end

function setting_set_project(name, value)
    local entry = by_name[name]
    if not entry or not entry.proj then return false end
    reaper.SetProjExtState(0, RC.EXT_KEY, entry.proj, encode(entry, value))
    return true
end

-- Resolution

-- track override, else project default, else the global value the GUI
-- edits. `fallback` is what the caller would have used before overrides
-- existed, so a project with none behaves exactly as it did.
function setting_resolve(name, track, fallback)
    local value = setting_get_track(track, name)
    if value ~= nil then return value, "track" end

    value = setting_get_project(name)
    if value ~= nil then return value, "project" end

    return fallback, "global"
end

-- The audio type a folder should use: its own override wins over the
-- dropdown. Overrides are stored by prefix because that is what survives
-- the user renaming or reordering their types.
function resolve_audio_type(track)
    local prefix = setting_resolve("audio_type", track, nil)
    if prefix and prefix ~= "" then
        for _, t in ipairs(RC.audio_types or {}) do
            if t.prefix == prefix then return t end
        end
    end
    return RC.audio_types[RC.selected_type_idx]
end

function is_track_excluded(track)
    return setting_get_track(track, "excluded") == true
end

-- Human-readable summary of what a track overrides, for the GUI.
function track_override_summary(track)
    if not track then return "(no track selected)" end

    local parts = {}
    for _, entry in ipairs(RC.SETTING_REGISTRY) do
        local value = setting_get_track(track, entry.name)
        if value ~= nil and value ~= "" then
            if entry.type == "bool" then
                if value then parts[#parts + 1] = entry.label end
            else
                parts[#parts + 1] = entry.label .. " = " .. tostring(value)
            end
        end
    end

    if #parts == 0 then return "no overrides on this track" end
    return table.concat(parts, ", ")
end
