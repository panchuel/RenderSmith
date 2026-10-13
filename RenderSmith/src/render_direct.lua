-- render_direct.lua
-- Direct render engine: no REAPER render window. Track AudioAccessors do
-- NOT capture project routing (a master accessor returns silence), so the
-- mix is built by summing every audible track that has items in the region
-- range: per-track items + track FX come from the accessor; track volume,
-- pan, mute, solo and the parent-folder volume chain are applied manually.
-- Limitation (documented in README): FX on parent buses / master are not
-- applied: use the native REAPER engine when those matter.
-- Runs as a deferred state machine so the GUI stays responsive.

local DIRECT_NCH      = 2
local BLOCK_FRAMES    = 16384
local TICK_BUDGET_SEC = 0.033
local FALLBACK_SRATE  = 48000

local job = nil

local function get_output_srate()
    local forced = tonumber(RC.direct_srate) or 0
    if forced > 0 then return math.floor(forced) end
    local use_proj = reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
    if use_proj == 1 then
        local srate = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
        if srate and srate > 0 then return math.floor(srate) end
    end
    local ok, srate = reaper.GetAudioDeviceInfo("SRATE")
    local n = tonumber(srate)
    if ok and n and n > 0 then return math.floor(n) end
    return FALLBACK_SRATE
end

local function sanitize_filename(name)
    return (name:gsub('[<>:"/\\|%?%*]', "-"))
end

-- Source track collection

local function is_effectively_muted(tr)
    while tr do
        if reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then return true end
        tr = reaper.GetParentTrack(tr)
    end
    return false
end

-- Track fader × every parent-folder fader × master fader
local function effective_volume(tr)
    local vol = 1.0
    while tr do
        vol = vol * reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
        tr = reaper.GetParentTrack(tr)
    end
    return vol * reaper.GetMediaTrackInfo_Value(reaper.GetMasterTrack(0), "D_VOL")
end

-- Candidate tracks for one region. With a plan item the candidates are the
-- region's own source tracks, which is what isolates the render: without
-- it every track holding items in range would be summed, so folders that
-- overlap in time would bleed into each other's files.
local function candidate_tracks(region, plan_item)
    if plan_item then return plan_audible_sources(plan_item) end

    local list = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if track_has_items_in_range(tr, region.pos, region.rend) then
            list[#list + 1] = tr
        end
    end
    return list
end

local function collect_source_tracks(region, plan_item)
    local any_solo = false
    for i = 0, reaper.CountTracks(0) - 1 do
        if reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_SOLO") > 0 then
            any_solo = true
            break
        end
    end

    local sources = {}
    for _, tr in ipairs(candidate_tracks(region, plan_item)) do
        local audible = track_has_items_in_range(tr, region.pos, region.rend)
            and not is_effectively_muted(tr)
            and reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND") == 1
            and (not any_solo or reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0)
        if audible then
            local vol = effective_volume(tr)
            local pan = reaper.GetMediaTrackInfo_Value(tr, "D_PAN")
            sources[#sources + 1] = {
                accessor = reaper.CreateTrackAudioAccessor(tr),
                vol_l    = vol * (pan > 0 and (1 - pan) or 1),
                vol_r    = vol * (pan < 0 and (1 + pan) or 1),
            }
        end
    end
    return sources
end

-- Job lifecycle

local function close_current_target(delete_partial)
    if not job then return end
    if job.wav then
        wav_close(job.wav)
        if delete_partial and job.wav_path then os.remove(job.wav_path) end
        job.wav = nil
    end
    if job.sources then
        for _, src in ipairs(job.sources) do
            reaper.DestroyAudioAccessor(src.accessor)
        end
        job.sources = nil
    end
end

local function fail_target(err)
    close_current_target(true)
    RC.render_results[#RC.render_results + 1] = {
        id = job.targets[job.idx].id, ok = false, err = err,
    }
    job.idx = job.idx + 1
end

local function open_next_target()
    local target = job.targets[job.idx]
    local region = target.region

    local total_frames = math.floor((region.rend - region.pos) * job.srate + 0.5)
    if total_frames <= 0 then
        fail_target("region has zero length")
        return
    end

    local sources = collect_source_tracks(region, job.plan_by_guid[target.id])
    if #sources == 0 then
        fail_target("no audible tracks with items in region range")
        return
    end

    reaper.RecursiveCreateDirectory(target.out_dir, 0)
    local sep  = package.config:sub(1, 1)
    local path = target.out_dir .. sep .. sanitize_filename(target.filename) .. ".wav"

    local wav, err = wav_open(path, job.srate, DIRECT_NCH, job.bit_depth)
    if not wav then
        for _, src in ipairs(sources) do reaper.DestroyAudioAccessor(src.accessor) end
        fail_target("cannot open file: " .. tostring(err))
        return
    end

    job.wav          = wav
    job.wav_path     = path
    job.sources      = sources
    job.total_frames = total_frames
    job.frames_done  = 0
    job.out_dir      = target.out_dir
end

local function process_one_block()
    local remaining = job.total_frames - job.frames_done
    local frames    = math.min(BLOCK_FRAMES, remaining)
    local n         = frames * DIRECT_NCH
    local time      = job.targets[job.idx].region.pos + job.frames_done / job.srate

    local acc = job.acc
    for j = 1, n do acc[j] = 0.0 end

    for _, src in ipairs(job.sources) do
        job.buffer.clear()
        local rv = reaper.GetAudioAccessorSamples(src.accessor, job.srate, DIRECT_NCH,
            time, frames, job.buffer)
        if rv > 0 then
            local t = job.buffer.table(1, n)
            local vl, vr = src.vol_l, src.vol_r
            for j = 1, n, 2 do
                acc[j]     = acc[j]     + t[j]     * vl
                acc[j + 1] = acc[j + 1] + t[j + 1] * vr
            end
        end
    end

    wav_write(job.wav, acc, frames)
    job.frames_done = job.frames_done + frames
end

local function process_current_target()
    local t0 = reaper.time_precise()
    repeat
        process_one_block()
    until job.frames_done >= job.total_frames
        or (reaper.time_precise() - t0) > TICK_BUDGET_SEC

    local pct = math.floor(job.frames_done / job.total_frames * 100)
    RC.render_status = string.format("Rendering %d/%d - %d%%",
        job.idx, #job.targets, pct)

    if job.frames_done >= job.total_frames then
        close_current_target(false)
        RC.render_results[#RC.render_results + 1] = {
            id = job.targets[job.idx].id, ok = true,
        }
        RC.last_render_dir = job.out_dir
        job.idx = job.idx + 1
    end
end

local function finish_job()
    job = nil
    render_report_finished()
end

local function tick()
    if not job then return end

    if job.idx > #job.targets then
        finish_job()
        return
    end

    if not job.wav then
        open_next_target()
    else
        local ok, err = pcall(process_current_target)
        if not ok then fail_target(tostring(err)) end
    end

    reaper.defer(tick)
end

-- Public API

function direct_render_is_active()
    return job ~= nil
end

-- The exact file this target would write. Used by the overwrite check.
function direct_render_output_path(target)
    return target.out_dir .. package.config:sub(1, 1)
        .. sanitize_filename(target.filename) .. ".wav"
end

-- targets:      list of { id, out_dir, filename, region = {pos, rend, name} }
-- plan_by_guid: region GUID -> plan item, so each target is summed from
--               only its own tracks (see plan.lua)
function direct_render_start(targets, plan_by_guid)
    if job then return end
    RC.render_results = {}
    job = {
        targets      = targets,
        plan_by_guid = plan_by_guid or {},
        idx       = 1,
        srate     = get_output_srate(),
        bit_depth = tonumber(RC.direct_bit_depth) or 24,
        buffer    = reaper.new_array(BLOCK_FRAMES * DIRECT_NCH),
        acc       = {},
    }
    RC.render_status = string.format("Rendering 1/%d - 0%%", #targets)
    reaper.defer(tick)
end

-- Called from GUI.exit so a partial file is never left behind.
function direct_render_abort()
    if not job then return end
    close_current_target(true)
    RC.render_status = "Render aborted"
    job = nil
end
