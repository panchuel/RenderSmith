-- plan.lua
-- Turns regions into a render plan and isolates them while rendering.
--
-- Isolation is what makes a batch render correct: without it the native
-- engine renders the whole master over the region's time range and the
-- direct engine sums every audible track in that range, so two folders
-- that overlap in time bleed into each other's files. For each plan item
-- we mute everything that is not part of that region, render, then let the
-- journal put the project back exactly as it was.
--
-- Tracks that must never be muted are the ancestors of a rendering track:
-- muting a parent folder silences its children on the way to the master.

-- Source tracks for a region: the folder it was built from, when we still
-- know it, else every track holding items inside the region's range.
local function collect_source_tracks(region, guid)
    local sources = {}
    local folder  = region_source_track(guid)

    if folder then
        sources[folder] = true
        for _, child in ipairs(get_child_tracks(folder)) do
            sources[child] = true
        end
        return sources, true
    end

    local preview = preview_track()
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        -- The preview track carries empty placeholder items; it is never
        -- a real source.
        if tr ~= preview and track_has_items_in_range(tr, region.pos, region.rend) then
            sources[tr] = true
        end
    end
    return sources, false
end

-- Every ancestor of every source track. These carry the audio to the
-- master, so they stay audible even though they hold no items themselves.
local function collect_mute_exclusions(sources)
    local exclusions = {}
    for tr in pairs(sources) do
        local parent = reaper.GetParentTrack(tr)
        while parent do
            exclusions[parent] = true
            parent = reaper.GetParentTrack(parent)
        end
    end
    return exclusions
end

function build_render_plan(guids)
    local plan = {}
    for _, guid in ipairs(guids) do
        local region = region_by_guid(guid)
        if region then
            local sources, from_folder = collect_source_tracks(region, guid)
            plan[#plan + 1] = {
                guid           = guid,
                region         = region,
                sources        = sources,
                mute_exclusion = collect_mute_exclusions(sources),
                from_folder    = from_folder,
            }
        end
    end
    return plan
end

-- Mutes everything outside this plan item. Recorded in the journal, so
-- journal_restore() undoes it whatever happens next.
function plan_apply_isolation(item)
    local muted = 0
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local keep = item.sources[tr] or item.mute_exclusion[tr]
        if not keep and reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 0 then
            journal_set_track_value(tr, "B_MUTE", 1)
            muted = muted + 1
        end
    end
    return muted
end

-- The audible source tracks of a plan item, as an array. Used by the
-- direct engine, which sums tracks itself instead of relying on mutes.
function plan_audible_sources(item)
    local list = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if item.sources[tr] then list[#list + 1] = tr end
    end
    return list
end
