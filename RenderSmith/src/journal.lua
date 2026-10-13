-- journal.lua
-- Mutation journal. Every temporary change the render cycle makes to the
-- project goes through here so it can be undone exactly.
--
-- Two rules keep it from corrupting projects:
--   1. A property is reverted only if its current value still equals what
--      we wrote. If it differs, the user changed it by hand while the
--      render was running and their value wins.
--   2. Pointers are validated before every read and write: a track or item
--      can be deleted between the mutation and the restore.

local entries = {}   -- object -> { [property] = entry }
local order   = {}   -- { object, object_type } in mutation order

local function record(object, object_type, property, value, getter, setter)
    if not object or not reaper.ValidatePtr(object, object_type) then
        return false
    end

    local props = entries[object]
    if not props then
        props = {}
        entries[object] = props
        order[#order + 1] = { object = object, object_type = object_type }
    end

    local entry = props[property]
    if not entry then
        entry = {
            getter         = getter,
            setter         = setter,
            original_value = getter(object, property),
        }
        props[property] = entry
    end

    setter(object, property, value)
    entry.applied_value = value
    return true
end

function journal_set_track_value(track, property, value)
    return record(track, "MediaTrack*", property, value,
        reaper.GetMediaTrackInfo_Value, reaper.SetMediaTrackInfo_Value)
end

function journal_set_item_value(item, property, value)
    return record(item, "MediaItem*", property, value,
        reaper.GetMediaItemInfo_Value, reaper.SetMediaItemInfo_Value)
end

-- Reverts in reverse mutation order. Returns restored and skipped, where
-- `skipped` counts properties the user changed underneath us and that were
-- therefore deliberately left alone.
function journal_restore()
    local restored, skipped = 0, 0

    for i = #order, 1, -1 do
        local object      = order[i].object
        local object_type = order[i].object_type
        local props       = entries[object]

        if props and reaper.ValidatePtr(object, object_type) then
            for property, entry in pairs(props) do
                if entry.getter(object, property) == entry.applied_value then
                    entry.setter(object, property, entry.original_value)
                    restored = restored + 1
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    journal_clear()
    return restored, skipped
end

function journal_clear()
    entries, order = {}, {}
end

function journal_is_empty()
    return #order == 0
end
