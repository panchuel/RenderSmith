-- Serialization format history:
--   v1 (3 pipes):  name|prefix|wildcard|config
--   v2 (5 pipes):  name|prefix|bp|wildcard|uh|config  (legacy, unused fields)
--   v3 (4 pipes):  name|prefix|wildcard|path_pattern|config
--   v4 (7 pipes):  name|prefix|wildcard|path_pattern|ucs_enabled|ucs_catid|ucs_wildcard|config
--   v5 (8 pipes):  name|prefix|wildcard|path_pattern|ucs_enabled|ucs_catid|ucs_wildcard|fields|config  ← current
--   (fields = "key=value;key2=value2", custom per-type wildcards)
local DEFAULT_PATH = "{base}/$prefix/$root/$parent/"

local function serialize_fields(fields)
    local parts = {}
    for _, f in ipairs(fields or {}) do
        parts[#parts + 1] = f.key .. "=" .. tostring(f.value or ""):gsub("[|;]", "")
    end
    return table.concat(parts, ";")
end

local function parse_fields(str)
    local fields = {}
    for k, v in (str or ""):gmatch("([^;=]+)=([^;]*)") do
        fields[#fields + 1] = { key = k, value = v }
    end
    return fields
end

function load_audio_types()
    local types = {}
    local count = tonumber(reaper.GetExtState(RC.EXT_KEY, "audio_type_count")) or 0
    if count == 0 then return RC.default_audio_types end

    for i = 1, count do
        local str = reaper.GetExtState(RC.EXT_KEY, "audio_type_" .. i)
        if str ~= "" then
            local name, prefix, wildcard, path_pattern, config_str
            local ucs_enabled, ucs_catid, ucs_wildcard = false, "", RC.DEFAULT_UCS_WILDCARD
            local fields = {}
            local def_path = (RC.default_audio_types[i] or {}).path_pattern or DEFAULT_PATH
            local pipe_count = select(2, str:gsub("|", ""))

            if pipe_count >= 8 then
                -- v5 current: includes custom fields
                local ucs_en, fields_str
                name, prefix, wildcard, path_pattern, ucs_en, ucs_catid, ucs_wildcard, fields_str, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
                ucs_enabled = (ucs_en == "1")
                fields = parse_fields(fields_str)
                if not ucs_wildcard or ucs_wildcard == "" then
                    ucs_wildcard = RC.DEFAULT_UCS_WILDCARD
                end
            elseif pipe_count == 7 then
                -- v4: UCS fields, no custom fields
                local ucs_en
                name, prefix, wildcard, path_pattern, ucs_en, ucs_catid, ucs_wildcard, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
                ucs_enabled = (ucs_en == "1")
                if not ucs_wildcard or ucs_wildcard == "" then
                    ucs_wildcard = RC.DEFAULT_UCS_WILDCARD
                end
            elseif pipe_count >= 5 then
                -- v2 legacy: discard bp and uh fields
                local _bp, _uh
                name, prefix, _bp, wildcard, _uh, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
                path_pattern = def_path
            elseif pipe_count == 4 then
                -- v3: includes path_pattern
                name, prefix, wildcard, path_pattern, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
            else
                -- v1: no path_pattern
                name, prefix, wildcard, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|(.+)")
                path_pattern = def_path
            end

            if name then
                local config = {}
                for k, v in config_str:gmatch("([^,=]+)=([^,]*)") do
                    config[k] = tonumber(v) or v
                end
                table.insert(types, {
                    name         = name,
                    prefix       = prefix,
                    wildcard     = wildcard,
                    path_pattern = path_pattern,
                    ucs_enabled  = ucs_enabled,
                    ucs_catid    = ucs_catid or "",
                    ucs_wildcard = ucs_wildcard,
                    fields       = fields,
                    config       = config,
                })
            end
        end
    end
    return #types > 0 and types or RC.default_audio_types
end

function save_audio_types(types)
    reaper.SetExtState(RC.EXT_KEY, "audio_type_count", tostring(#types), true)
    for i, t in ipairs(types) do
        local cfg = ""
        for k, v in pairs(t.config) do cfg = cfg .. k .. "=" .. tostring(v) .. "," end
        -- v5 format: name|prefix|wildcard|path_pattern|ucs_enabled|ucs_catid|ucs_wildcard|fields|config
        reaper.SetExtState(RC.EXT_KEY, "audio_type_" .. i,
            string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
                t.name, t.prefix, t.wildcard,
                t.path_pattern or DEFAULT_PATH,
                t.ucs_enabled and "1" or "0",
                t.ucs_catid or "",
                t.ucs_wildcard or RC.DEFAULT_UCS_WILDCARD,
                serialize_fields(t.fields),
                cfg:gsub(",$", "")), true)
    end
    -- Drop stale slots left behind after removing a type
    for i = #types + 1, RC.MAX_AUDIO_TYPES do
        reaper.DeleteExtState(RC.EXT_KEY, "audio_type_" .. i, true)
    end
end

-- Type / custom-field management (called from GUI buttons)

function add_audio_type(name, prefix)
    if #RC.audio_types >= RC.MAX_AUDIO_TYPES then
        return nil, "Maximum number of audio types reached (" .. RC.MAX_AUDIO_TYPES .. ")."
    end
    name   = (name or ""):match("^%s*(.-)%s*$")
    prefix = (prefix or ""):match("^%s*(.-)%s*$"):gsub("[|_%s]", "")
    if name == "" or prefix == "" then
        return nil, "Name and prefix must not be empty."
    end
    for _, t in ipairs(RC.audio_types) do
        if t.prefix == prefix then
            return nil, "Prefix \"" .. prefix .. "\" is already used by \"" .. t.name .. "\"."
        end
    end
    table.insert(RC.audio_types, {
        name         = name,
        prefix       = prefix,
        wildcard     = RC.DEFAULT_WILDCARD,
        path_pattern = DEFAULT_PATH,
        ucs_enabled  = false,
        ucs_catid    = "",
        ucs_wildcard = RC.DEFAULT_UCS_WILDCARD,
        fields       = {},
        config       = { bpm=0, meter="", character="", quest_type="", quest_name="", line_number=1 },
    })
    save_audio_types(RC.audio_types)
    return #RC.audio_types
end

function remove_audio_type(idx)
    if #RC.audio_types <= 1 then
        return nil, "At least one audio type must remain."
    end
    if not RC.audio_types[idx] then
        return nil, "Invalid audio type."
    end
    table.remove(RC.audio_types, idx)
    save_audio_types(RC.audio_types)
    return true
end

function add_custom_field(atype, key, value)
    key = (key or ""):lower():gsub("[^%a%d]", "")
    if key == "" then
        return nil, "Field name must contain letters/digits (it becomes the $" ..
            "wildcard, e.g. \"weapontype\" \xe2\x86\x92 $weapontype)."
    end
    if RC.RESERVED_TOKENS[key] then
        return nil, "\"$" .. key .. "\" is a built-in wildcard. Pick another name."
    end
    atype.fields = atype.fields or {}
    if #atype.fields >= RC.MAX_CUSTOM_FIELDS then
        return nil, "Maximum " .. RC.MAX_CUSTOM_FIELDS .. " custom fields per type."
    end
    for _, f in ipairs(atype.fields) do
        if f.key == key then
            return nil, "Field \"$" .. key .. "\" already exists on this type."
        end
    end
    atype.fields[#atype.fields + 1] = { key = key, value = tostring(value or "") }
    save_audio_types(RC.audio_types)
    return true
end

function remove_custom_field(atype, key)
    key = (key or ""):lower():gsub("[^%a%d]", "")
    for i, f in ipairs(atype.fields or {}) do
        if f.key == key then
            table.remove(atype.fields, i)
            save_audio_types(RC.audio_types)
            return true
        end
    end
    return nil, "No field named \"$" .. key .. "\" on this type."
end

function sync_config_from_audio_type()
    local t = RC.audio_types[RC.selected_type_idx]
    if not t then return end
    RC.prefix            = t.prefix
    RC.prefix_type       = t.prefix
    RC.wildcard_template = t.wildcard
    RC.music_bpm         = t.config.bpm         or 120
    RC.music_meter       = t.config.meter        or "4-4"
    RC.dx_character      = t.config.character    or ""
    RC.dx_quest_type     = t.config.quest_type   or "SQ"
    RC.dx_quest_name     = t.config.quest_name   or ""
    RC.dx_line_number    = t.config.line_number  or 1
end

function sync_config_to_audio_type()
    local t = RC.audio_types[RC.selected_type_idx]
    if not t then return end
    t.wildcard           = RC.wildcard_template
    t.config.bpm         = RC.music_bpm
    t.config.meter       = RC.music_meter
    t.config.character   = RC.dx_character
    t.config.quest_type  = RC.dx_quest_type
    t.config.quest_name  = RC.dx_quest_name
    t.config.line_number = RC.dx_line_number
end

RC.audio_types       = load_audio_types()
RC.selected_type_idx = 1
