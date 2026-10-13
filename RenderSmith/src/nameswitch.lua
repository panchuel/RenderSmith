-- nameswitch.lua
-- NameSwitch markers: items that rename the regions after them and restart
-- the numbering.
--
-- They exist so one folder can hold many different sounds. Without them a
-- folder is one name, so "Shot", "Reload" and "Empty" need three folders;
-- with them you drop a marker before each run and get
-- sx_Weapons_Shot_01.. , sx_Weapons_Reload_01.. from a single folder.
--
-- A marker is an ordinary empty item carrying two P_EXT keys. Put it on
-- the folder track and it stays out of the audio entirely; put it on a
-- child track and it is still skipped when clustering, never treated as
-- sound. If the item has a custom colour, the regions it names inherit it.
--
-- RenderBuddy edits these by double-click, which needs JS_ReaScriptAPI to
-- intercept the item-notes window. RenderSmith has no JS_API dependency,
-- so editing goes through the button on the Main tab instead.

local NS_TAG  = "P_EXT:RF_NameSwitch"
local NS_NAME = "P_EXT:RF_NameSwitchName"

local COLOR_FLAG = 0x1000000

function is_name_switch(item)
    if not item then return false end
    local ok, tag = reaper.GetSetMediaItemInfo_String(item, NS_TAG, "", false)
    return ok and tag == "1"
end

function name_switch_name(item)
    local ok, name = reaper.GetSetMediaItemInfo_String(item, NS_NAME, "", false)
    if not ok then return "" end
    return name
end

-- Custom colour, or nil when the item just uses its track's. Passed
-- straight to AddProjectMarker2, which expects the same flagged form.
function name_switch_color(item)
    local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
    if color and color ~= 0 and (color & COLOR_FLAG) ~= 0 then return color end
    return nil
end

function name_switch_set(item, name)
    if not item then return false end
    reaper.GetSetMediaItemInfo_String(item, NS_TAG, "1", true)
    reaper.GetSetMediaItemInfo_String(item, NS_NAME, name or "", true)
    -- The notes are what REAPER draws on an empty item, so the marker
    -- shows its own name in the arrange view.
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", name or "", true)
    return true
end

-- Creates a zero-ish length marker at `pos` on `track`.
function name_switch_create(track, pos, name)
    if not track then return nil end
    local item = reaper.AddMediaItemToTrack(track)
    if not item then return nil end
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", 0.05)
    name_switch_set(item, name)
    return item
end

-- The first selected item that is a marker, or nil.
function name_switch_selected()
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if is_name_switch(item) then return item end
    end
    return nil
end

-- Every marker belonging to a folder, as cluster input. Scans the folder
-- track and its children, so a marker works wherever it was dropped.
function collect_folder_switches(folder_track)
    local switches = {}

    local tracks = { folder_track }
    for _, child in ipairs(get_child_tracks(folder_track)) do
        tracks[#tracks + 1] = child
    end

    for _, tr in ipairs(tracks) do
        for k = 0, reaper.CountTrackMediaItems(tr) - 1 do
            local item = reaper.GetTrackMediaItem(tr, k)
            if is_name_switch(item) then
                switches[#switches + 1] = {
                    pos    = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                    switch = name_switch_name(item),
                    color  = name_switch_color(item),
                }
            end
        end
    end

    return switches
end
