-- ucs.lua
-- UCS (Universal Category System) helpers: field sanitizing and catalog
-- lookups over RC.UCS (see ucs_data.lua).
-- Pure Lua, no reaper.* calls: reusable outside REAPER (future plugin port).

RC = RC or {}

-- UCS reserves "_" as the field separator, so inside a field only
-- alphanumerics and hyphens survive; words are joined as CamelCase.
-- e.g. "jungle  loop_01" → "JungleLoop01", "sword-hit heavy" → "Sword-hitHeavy"
function ucs_sanitize_field(s)
    if not s or s == "" then return "" end
    local words = {}
    for word in s:gmatch("[%w%-]+") do
        words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
    end
    return table.concat(words)
end

-- Ordered unique category names, preserving catalog order.
function ucs_categories()
    local seen, list = {}, {}
    for _, e in ipairs(RC.UCS) do
        if not seen[e.cat] then
            seen[e.cat] = true
            list[#list + 1] = e.cat
        end
    end
    return list
end

-- Subcategory entries ({cat, sub, id}) for one category, in catalog order.
function ucs_subcats_for(category)
    local list = {}
    for _, e in ipairs(RC.UCS) do
        if e.cat == category then list[#list + 1] = e end
    end
    return list
end

-- Catalog entry for a CatID, or nil.
function ucs_find(catid)
    for _, e in ipairs(RC.UCS) do
        if e.id == catid then return e end
    end
    return nil
end

-- Standard UCS filename: CatID_FXName_CreatorID_SourceID(_UserData).
-- Empty optional fields are skipped so no double underscores appear.
function ucs_build_filename(catid, fxname, creatorid, sourceid, userdata)
    local parts = { catid }
    for _, field in ipairs({ fxname, creatorid, sourceid, userdata }) do
        local clean = ucs_sanitize_field(field)
        if clean ~= "" then parts[#parts + 1] = clean end
    end
    return table.concat(parts, "_")
end
