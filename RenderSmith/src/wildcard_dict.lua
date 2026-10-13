-- wildcard_dict.lua
-- User-defined wildcards, written $RF[NAME].
--
-- These are different from the per-type custom fields in audio_types.lua:
-- a custom field belongs to one audio type and shows up on the Main tab,
-- while a dictionary entry is shared by every type and every pattern.
--
-- Two scopes, project beating global, so a project can override a studio
-- default without editing it:
--   global  → ExtState        (travels with the install)
--   project → ProjExtState    (travels inside the .rpp)
--
-- Values may themselves contain wildcards, including other $RF[...]
-- entries; wildcards.lua resolves them recursively with a depth cap.

local DICT_KEY = "wildcards"

local function serialize(dict)
    local names = {}
    for name in pairs(dict) do names[#names + 1] = name end
    table.sort(names)                       -- stable output, readable in ExtState

    local lines = {}
    for _, name in ipairs(names) do
        -- Newlines would break the line format; nothing else needs escaping.
        lines[#lines + 1] = name .. "=" .. tostring(dict[name]):gsub("[\r\n]", " ")
    end
    return table.concat(lines, "\n")
end

local function deserialize(str)
    local dict = {}
    if not str or str == "" then return dict end
    for line in (str .. "\n"):gmatch("([^\n]+)") do
        local name, value = line:match("^([^=]+)=(.*)$")
        if name and name ~= "" then dict[name] = value end
    end
    return dict
end

-- Names become $RF[NAME], so keep them to what survives a round trip.
function wildcard_normalize_name(name)
    return (name or ""):upper():gsub("[^%w_]", "")
end

function wildcard_dict_load()
    RC.wildcards_global = deserialize(reaper.GetExtState(RC.EXT_KEY, DICT_KEY))
    local _, raw = reaper.GetProjExtState(0, RC.EXT_KEY, DICT_KEY)
    RC.wildcards_project = deserialize(raw)
end

function wildcard_dict_save()
    reaper.SetExtState(RC.EXT_KEY, DICT_KEY, serialize(RC.wildcards_global), true)
    reaper.SetProjExtState(0, RC.EXT_KEY, DICT_KEY, serialize(RC.wildcards_project))
end

-- Project entries shadow global ones of the same name.
function wildcard_dict_merged()
    local merged = {}
    for name, value in pairs(RC.wildcards_global) do merged[name] = value end
    for name, value in pairs(RC.wildcards_project) do merged[name] = value end
    return merged
end

function wildcard_dict_set(name, value, scope)
    name = wildcard_normalize_name(name)
    if name == "" then
        return nil, "Wildcard name must contain letters or digits."
    end
    if scope == "project" then
        RC.wildcards_project[name] = tostring(value or "")
    else
        RC.wildcards_global[name] = tostring(value or "")
    end
    wildcard_dict_save()
    return name
end

function wildcard_dict_remove(name, scope)
    name = wildcard_normalize_name(name)
    local target = (scope == "project") and RC.wildcards_project or RC.wildcards_global
    if target[name] == nil then
        return nil, "No " .. (scope or "global") .. " wildcard named $RF[" .. name .. "]."
    end
    target[name] = nil
    wildcard_dict_save()
    return true
end

-- Sorted { name, value, scope } for the GUI list.
function wildcard_dict_entries()
    local merged = wildcard_dict_merged()
    local names  = {}
    for name in pairs(merged) do names[#names + 1] = name end
    table.sort(names)

    local list = {}
    for _, name in ipairs(names) do
        list[#list + 1] = {
            name  = name,
            value = merged[name],
            scope = (RC.wildcards_project[name] ~= nil) and "project" or "global",
        }
    end
    return list
end

RC.wildcards_global  = {}
RC.wildcards_project = {}
wildcard_dict_load()
