-- wildcards.lua
-- Pattern expansion. Three families of token, resolved in this order:
--
--   1. $RF[NAME]  user dictionary entries (wildcard_dict.lua). Resolved
--                 first and recursively, so an entry's value may contain
--                 other wildcards, its own or the built-in ones.
--   2. $fieldname per-type custom fields (audio_types.lua).
--   3. built-ins  $prefix, $root, $parent, $track, $number, UCS tokens…
--
-- Everything RenderSmith does not recognise is left untouched, so REAPER's
-- own render wildcards still pass through to the native engine.

local MAX_DEPTH = 8

-- Finds the audio type owning this prefix so UCS tokens can resolve
-- against it; falls back to the currently selected type.
local function type_for_prefix(prefix)
    for _, t in ipairs(RC.audio_types or {}) do
        if t.prefix == prefix then return t end
    end
    return (RC.audio_types or {})[RC.selected_type_idx]
end

-- $RF[NAME], and the bare RF[NAME] form for directory fields where a
-- leading $ is awkward. Unknown names are left literal rather than blanked,
-- so a typo is visible in the result instead of silently vanishing.
local function resolve_dictionary(str, dict, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then return str end

    return (str:gsub("%$?RF%[([^%]]+)%]", function(name)
        local value = dict[wildcard_normalize_name(name)]
        if not value then return nil end
        return resolve_dictionary(value, dict, depth + 1)
    end))
end

-- Every ancestor folder of a track, outermost first, joined with "/".
-- Meant for path patterns; in a filename the slashes get sanitised away.
local function folder_chain(track)
    if not track then return "" end
    local names  = {}
    local parent = reaper.GetParentTrack(track)
    while parent do
        table.insert(names, 1, clean_name(get_track_name(parent)))
        parent = reaper.GetParentTrack(parent)
    end
    return table.concat(names, "/")
end

-- ctx (all optional): track = the folder track this region came from,
-- number_text = pre-formatted cluster number, or "" to drop $number.
function expand_wildcards(pattern, prefix, root, parent, ctx)
    ctx = ctx or {}

    local qname = RC.dx_quest_name ~= "" and RC.dx_quest_name or parent
    local char  = RC.dx_character  ~= "" and RC.dx_character  or "unknown"
    local qtype = RC.dx_quest_type ~= "" and RC.dx_quest_type or "SQ"

    local atype = type_for_prefix(prefix)
    local catid = (atype and atype.ucs_catid ~= "" and atype.ucs_catid) or "NoCatID"

    pattern = resolve_dictionary(pattern, wildcard_dict_merged(), 0)

    -- Normalize $WildcardName to $wildcardname so patterns typed in any
    -- case expand correctly. $RF keeps its case: an unresolved dictionary
    -- token should stay readable as written.
    pattern = pattern:gsub("%$(%a+)", function(w)
        if w:upper() == "RF" then return "$" .. w end
        return "$" .. w:lower()
    end)

    -- Custom per-type fields first (longest keys first so e.g. $ammo2 wins
    -- over $ammo), then the built-in tokens.
    if atype and atype.fields and #atype.fields > 0 then
        local sorted = {}
        for i, f in ipairs(atype.fields) do sorted[i] = f end
        table.sort(sorted, function(a, b) return #a.key > #b.key end)
        for _, f in ipairs(sorted) do
            local value = (f.value and f.value ~= "") and f.value or "unknown"
            pattern = pattern:gsub("%$" .. f.key, (value:gsub("%%", "%%%%")))
        end
    end

    local track_name = ctx.track and clean_name(get_track_name(ctx.track)) or parent
    local track_num  = ctx.track
        and tostring(math.floor(reaper.GetMediaTrackInfo_Value(ctx.track, "IP_TRACKNUMBER")))
        or ""

    return pattern
        :gsub("%$tracknumber", track_num)
        :gsub("%$track",       track_name)
        :gsub("%$folders",     folder_chain(ctx.track))
        :gsub("%$number",      ctx.number_text or "")
        :gsub("%$prefix",      prefix)
        :gsub("%$root",        root)
        :gsub("%$parent",      parent)
        :gsub("%$bpm",         tostring(RC.music_bpm))
        :gsub("%$meter",       RC.music_meter)
        :gsub("%$character",   char)
        :gsub("%$questtype",   qtype)
        :gsub("%$questname",   qname)
        :gsub("%$line",        string.format("%02d", RC.dx_line_number))
        :gsub("%$catid",       catid)
        :gsub("%$fxname",      ucs_sanitize_field(parent))
        :gsub("%$creatorid",   ucs_sanitize_field(RC.ucs_creator_id or ""))
        :gsub("%$sourceid",    ucs_sanitize_field(RC.ucs_source_id or ""))
        :gsub("%$userdata",    ucs_sanitize_field(RC.ucs_user_data or ""))
        :gsub("%$region",      parent)   -- legacy alias
end
