-- preview.lua
-- Shows what clustering would produce, as empty items on a temporary
-- track, before anything is written to the project.
--
-- Not real regions, on purpose: real ones are slower to make and unmake,
-- they clutter the region list, and they survive a crash. Items on a track
-- we own are cheap and vanish with the track. RenderBuddy takes the same
-- approach for the same reasons.
--
-- The preview is built from plan_current_selection(), the very function
-- the creator uses, so it cannot drift from what you actually get,
-- including which selection mode is in play.

local PREVIEW_TAG   = "P_EXT:RF_PreviewTrack"
local PREVIEW_NAME  = "RenderSmith Preview"
local PREVIEW_HEIGHT = 28

-- Two alternating colours so neighbouring clusters stay distinguishable
-- even when they nearly touch.
local COLORS = {
    { 90, 160, 220 },
    { 90, 210, 160 },
}

local function native_color(rgb)
    return reaper.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000
end

-- Found by its P_EXT tag rather than its name, so renaming the track by
-- hand cannot orphan it.
function preview_track()
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local ok, tag = reaper.GetSetMediaTrackInfo_String(tr, PREVIEW_TAG, "", false)
        if ok and tag == "1" then return tr end
    end
    return nil
end

function preview_is_active()
    return preview_track() ~= nil
end

function preview_clear()
    local tr = preview_track()
    if not tr then return false end
    reaper.DeleteTrack(tr)
    reaper.UpdateArrange()
    return true
end

local function create_preview_track()
    local index = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(index, false)
    local tr = reaper.GetTrack(0, index)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", PREVIEW_NAME, true)
    reaper.GetSetMediaTrackInfo_String(tr, PREVIEW_TAG, "1", true)
    reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", PREVIEW_HEIGHT)
    -- It carries no audio; keeping it off the master avoids any doubt.
    reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
    return tr
end

-- Rebuilds the preview from the current folder selection and gap settings.
-- Returns how many regions it drew, and how many folders contributed.
function preview_build()
    reaper.PreventUIRefresh(1)
    preview_clear()

    local planned_all, folder_list = plan_current_selection()
    local folders = #folder_list

    if #planned_all == 0 then
        reaper.PreventUIRefresh(-1)
        reaper.UpdateArrange()
        return 0, 0
    end

    local tr = create_preview_track()
    for n, p in ipairs(planned_all) do
        local item = reaper.AddMediaItemToTrack(tr)
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", p.start)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(p.stop - p.start, 0.001))
        -- A NameSwitch colour wins, so the preview shows the sections the
        -- way the regions will end up.
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR",
            p.color or native_color(COLORS[(n - 1) % #COLORS + 1]))
        -- Empty items show their notes, which is how the name gets drawn.
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", p.name, true)
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    return #planned_all, folders
end

-- How many regions the current selection would produce, without drawing
-- anything. Used for the count shown on the Main tab.
function preview_count()
    local planned, folders, mode = plan_current_selection()
    return #planned, #folders, mode
end
