-- Parenthesised so the gsub replacement count never leaks out as a second
-- return value: that breaks any caller that uses this in an argument list.
function clean_name(name)
    return (name:gsub("[^%w_]", "_"):gsub("__+", "_"))
end

function get_track_name(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or "Unnamed"
end

function get_track_index(track)
    return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

function get_folder_depth(track)
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
end

-- REAPER already answers this in one call. The hand-rolled walk this
-- replaces summed I_FOLDERDEPTH over every preceding track, inside a loop
-- over every preceding track -- O(n^2) per call, on a path that now runs
-- on every selection change to keep the region count live.
function get_parent_track(track)
    return reaper.GetParentTrack(track)
end

function get_child_tracks(folder_track)
    local children = {}
    local idx   = get_track_index(folder_track)
    local total = reaper.CountTracks(0)
    for i = idx + 1, total - 1 do
        local tr = reaper.GetTrack(0, i)
        table.insert(children, tr)
        if get_folder_depth(tr) < 0 then break end
    end
    return children
end

function get_item_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

function set_item_notes(item, notes)
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

function is_original_item(item)
    local n = get_item_notes(item)
    return n:find(RC.ORIGINAL_TAG) and not n:find(RC.VARIATION_TAG)
end

function is_variation_item(item)
    return get_item_notes(item):find(RC.VARIATION_TAG) ~= nil
end

function mark_original_items(folder_track)
    for _, child in ipairs(get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if not is_original_item(item) and not is_variation_item(item) then
                set_item_notes(item, get_item_notes(item) .. " " .. RC.ORIGINAL_TAG)
            end
        end
    end
end

-- True when the track holds at least one item overlapping [range_start, range_end).
function track_has_items_in_range(track, range_start, range_end)
    for k = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, k)
        local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if pos < range_end and (pos + len) > range_start then return true end
    end
    return false
end
