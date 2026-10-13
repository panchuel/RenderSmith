-- render.lua
-- Render orchestration. Two engines:
--   "direct"  → render_direct.lua (AudioAccessor → WAV, no REAPER window)
--   "reaper"  → native render via most-recent-settings action (any format)
--
-- Both render one region at a time in isolation, but they get there
-- differently. The native engine renders REAPER's master, so everything
-- outside the region's tracks is muted for the duration and put back by
-- the mutation journal. The direct engine sums tracks itself, so it is
-- simply handed the plan's source tracks and never touches the project.
--
-- Regions are hybrid: the queue can run over persistent regions the user
-- created, or build regions on the fly, render them and delete them again
-- (render_from_folders with RC.render_keep_regions off).

local RENDER_USING_LAST_SETTINGS_AUTOCLOSE = 42230

-- A folder track can carry its own output folder; see settings_cascade.lua.
local function resolve_base(track)
    local base = setting_resolve("base_dir", track, RC.render_base_dir)
    if base and base ~= "" then
        return base
    end
    local p = reaper.GetProjectPath(0)
    if not p or p == "" then p = reaper.GetResourcePath() end
    return p .. "/Renders"
end

local function normalize_path(p)
    if package.config:sub(1, 1) == "\\" then
        return (p:gsub("/", "\\"))
    end
    return p
end

-- Match an audio type by its prefix (or UCS CatID when UCS naming is on)
-- appearing at the start of a region name.
local function type_for_region(region_name)
    for _, t in ipairs(RC.audio_types) do
        if region_name:sub(1, #t.prefix + 1) == t.prefix .. "_" then
            return t
        end
    end
    for _, t in ipairs(RC.audio_types) do
        local cid = t.ucs_catid
        if cid and cid ~= "" and region_name:sub(1, #cid + 1) == cid .. "_" then
            return t
        end
    end
    return RC.audio_types[RC.selected_type_idx]
end

-- True when a region name belongs to this audio type (prefix or UCS CatID).
function region_matches_type(region_name, atype)
    if region_name:sub(1, #atype.prefix + 1) == atype.prefix .. "_" then
        return true
    end
    local cid = atype.ucs_catid
    return cid and cid ~= "" and region_name:sub(1, #cid + 1) == cid .. "_"
end

-- Shared by both engines: output folder + filename for one region.
function resolve_render_target(guid)
    local region = region_by_guid(guid)
    if not region then
        return nil, "region not found"
    end

    local hier   = get_region_hierarchy(guid)
    local root   = hier.root   or "Unknown"
    local parent = hier.parent or "Unknown"
    local atype  = type_for_region(region.name)

    local source_track = region_source_track(guid)
    local base    = resolve_base(source_track)
    local out_dir = (atype.path_pattern or "{base}/$prefix/$root/$parent/"):gsub("{base}", base)
    out_dir       = expand_wildcards(out_dir, atype.prefix, root, parent,
        { track = source_track })
    out_dir       = normalize_path(out_dir:gsub("[/\\]+$", ""))

    -- Use the region name directly: it was already expanded at creation time.
    return { id = guid, out_dir = out_dir, filename = region.name, region = region }
end

-- Native engine (REAPER render, most recent settings)

local saved_render_settings = nil

local function push_render_settings()
    local _, file    = reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    "", false)
    local _, pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
    local sel_s, sel_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    saved_render_settings = {
        file     = file,
        pattern  = pattern,
        bounds   = reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, false),
        settings = reaper.GetSetProjectInfo(0, "RENDER_SETTINGS",   0, false),
        sel_s    = sel_s,
        sel_e    = sel_e,
    }
end

local function pop_render_settings()
    local s = saved_render_settings
    if not s then return end
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    s.file,    true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", s.pattern, true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", s.bounds,   true)
    reaper.GetSetProjectInfo(0, "RENDER_SETTINGS",   s.settings, true)
    reaper.GetSet_LoopTimeRange(true, false, s.sel_s, s.sel_e, false)
    saved_render_settings = nil
end

local function render_target_reaper(target, plan_item)
    local region = target.region
    reaper.RecursiveCreateDirectory(target.out_dir, 0)

    -- Everything outside this region's tracks is muted so the master mix
    -- contains only this sound. The journal puts it all back afterwards.
    if plan_item then plan_apply_isolation(plan_item) end

    reaper.GetSet_LoopTimeRange(true, false, region.pos, region.rend, false)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    target.out_dir,  true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", target.filename, true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2, true)   -- 2 = time selection
    reaper.GetSetProjectInfo(0, "RENDER_SETTINGS",   0, true)   -- 0 = master mix

    -- Blocks until the render finishes or the user cancels
    reaper.Main_OnCommand(RENDER_USING_LAST_SETTINGS_AUTOCLOSE, 0)

    RC.last_render_dir = target.out_dir
end

local function run_queue_reaper(targets, plan_by_guid)
    push_render_settings()

    for n, target in ipairs(targets) do
        RC.render_status = string.format("Rendering %d/%d...", n, #targets)
        local ok, err = pcall(render_target_reaper, target, plan_by_guid[target.id])
        journal_restore()
        RC.render_results[#RC.render_results + 1] = {
            id  = target.id,
            ok  = ok,
            err = not ok and tostring(err) or nil,
        }
    end

    pop_render_settings()
    render_report_finished()
end

-- Completion

-- Called by whichever engine finishes last. RC.render_on_complete lets the
-- ephemeral path delete the regions it built once rendering is really done.
function render_report_finished()
    local done, failed = 0, 0
    for _, r in ipairs(RC.render_results) do
        if r.ok then done = done + 1 else failed = failed + 1 end
    end
    if failed == 0 then
        RC.render_status = string.format("Done (%d) \xe2\x86\x92 %s",
            done, RC.last_render_dir or "?")
    else
        RC.render_status = string.format("Done %d  Failed %d \xe2\x86\x92 %s",
            done, failed, RC.last_render_dir or "?")
    end

    local callback = RC.render_on_complete
    RC.render_on_complete = nil
    if callback then callback(done, failed) end
end

-- Overwrite detection

-- Files these targets would replace.
--
-- For the native engine we ask REAPER what it would write instead of
-- guessing: its output names depend on the format, the channel count and
-- its own auto-numbering, none of which we control. The direct engine
-- always writes one .wav per region, so there the path is known exactly.
local function existing_outputs(targets)
    local hits = {}

    if RC.render_engine ~= "reaper" then
        for _, target in ipairs(targets) do
            local path = direct_render_output_path(target)
            if reaper.file_exists(path) then hits[#hits + 1] = path end
        end
        return hits
    end

    push_render_settings()
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2, true)
    for _, target in ipairs(targets) do
        local region = target.region
        reaper.GetSet_LoopTimeRange(true, false, region.pos, region.rend, false)
        reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    target.out_dir,  true)
        reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", target.filename, true)

        local _, list = reaper.GetSetProjectInfo_String(0, "RENDER_TARGETS", "", false)
        for path in (list or ""):gmatch("[^;]+") do
            if reaper.file_exists(path) then hits[#hits + 1] = path end
        end
    end
    pop_render_settings()

    return hits
end

local OVERWRITE_PREVIEW_LINES = 8

local function confirm_overwrite(paths)
    local lines = {}
    for i = 1, math.min(#paths, OVERWRITE_PREVIEW_LINES) do
        lines[#lines + 1] = "  " .. paths[i]
    end
    if #paths > OVERWRITE_PREVIEW_LINES then
        lines[#lines + 1] = string.format("  ... and %d more",
            #paths - OVERWRITE_PREVIEW_LINES)
    end

    local msg = string.format(
        "%d file(s) already exist and will be overwritten:\n\n%s\n\nContinue?",
        #paths, table.concat(lines, "\n"))
    return reaper.ShowMessageBox(msg, RC.PRODUCT_NAME .. " - Overwrite", 4) == 6
end

-- Queue dispatch

function render_queue(guids)
    -- The funnel every render path reaches, so this is the backstop for
    -- Render Checked and Render by Type as well.
    local licensed, lic_msg = license_require()
    if not licensed then
        reaper.ShowMessageBox(lic_msg, RC.PRODUCT_NAME, 0)
        return false
    end

    if direct_render_is_active() then
        RC.render_status = "Render already in progress"
        return false
    end

    RC.render_results = {}
    if #guids == 0 then
        RC.render_status = "No regions selected"
        return false
    end

    local plan         = build_render_plan(guids)
    local plan_by_guid = {}
    for _, item in ipairs(plan) do plan_by_guid[item.guid] = item end

    local targets = {}
    for _, guid in ipairs(guids) do
        local target, err = resolve_render_target(guid)
        if target then
            targets[#targets + 1] = target
        else
            RC.render_results[#RC.render_results + 1] = { id = guid, ok = false, err = err }
        end
    end

    if #targets == 0 then
        RC.render_status = "Error: no valid regions to render"
        return false
    end

    if RC.warn_overwrite then
        local clashes = existing_outputs(targets)
        if #clashes > 0 and not confirm_overwrite(clashes) then
            RC.render_status = string.format("Cancelled: %d file(s) would be overwritten",
                #clashes)
            return false
        end
    end

    if RC.render_engine == "reaper" then
        run_queue_reaper(targets, plan_by_guid)
    else
        direct_render_start(targets, plan_by_guid)
    end
    return true
end

-- Regions whose folder track is marked excluded stay out of bulk renders.
function collect_project_region_guids()
    local guids = {}
    for _, region in ipairs(region_list()) do
        if not is_track_excluded(region_source_track(region.guid)) then
            guids[#guids + 1] = region.guid
        end
    end
    return guids
end

function render_all_regions()
    local guids = collect_project_region_guids()
    if #guids == 0 then
        RC.render_status = "No regions in project"
        return
    end
    render_queue(guids)
end

function render_regions_by_type(type_idx)
    local atype = RC.audio_types[type_idx]
    if not atype then
        RC.render_status = "Invalid type index"
        return
    end

    local guids = {}
    for _, region in ipairs(region_list()) do
        if region_matches_type(region.name, atype) then
            guids[#guids + 1] = region.guid
        end
    end

    if #guids == 0 then
        RC.render_status = "No regions found for: " .. atype.name
        return
    end
    render_queue(guids)
end

-- Hybrid: build regions, render, optionally discard

local function delete_regions(guids)
    for _, guid in ipairs(guids) do
        local idx = region_index_from_guid(guid)
        if idx then
            local _, _, _, _, _, number = reaper.EnumProjectMarkers(idx)
            if number then reaper.DeleteProjectMarker(0, number, true) end
        end
        RC.region_meta[guid] = nil
    end
    region_meta_save()
    reaper.UpdateArrange()
end

-- Renders the current selection without requiring the user to create
-- regions first: folder tracks, or just the items they picked. With
-- RC.render_keep_regions off the regions exist only for the length of the
-- render, which is RenderBuddy's model; with it on they stay in the
-- project, which is RenderSmith's.
function render_from_folders()
    -- Gated before anything is created: refusing further down would leave
    -- the regions behind with nothing rendered from them.
    local licensed, lic_msg = license_require()
    if not licensed then
        reaper.ShowMessageBox(lic_msg, RC.PRODUCT_NAME, 0)
        return
    end

    if direct_render_is_active() then
        RC.render_status = "Render already in progress"
        return
    end

    local valid, msg = validate_preconditions()
    if not valid then
        if msg ~= "" then
            reaper.ShowMessageBox(msg, RC.PRODUCT_NAME .. " - Cannot Proceed", 0)
        end
        return
    end

    reaper.Undo_BeginBlock()
    sync_config_to_audio_type()
    local guids, created = create_regions_from_selection()
    region_meta_save()

    if #guids == 0 then
        reaper.Undo_EndBlock("Render from folders", -1)
        RC.render_status = "Nothing selected to render"
        return
    end

    -- Only regions this run created are ours to throw away; any that were
    -- already in the project belong to the user and stay.
    RC.ephemeral_guids = (not RC.render_keep_regions) and #created > 0 and created or nil
    if RC.ephemeral_guids then
        RC.render_on_complete = function()
            delete_regions(RC.ephemeral_guids)
            RC.ephemeral_guids = nil
        end
    end

    if not render_queue(guids) and RC.ephemeral_guids then
        delete_regions(RC.ephemeral_guids)
        RC.ephemeral_guids   = nil
        RC.render_on_complete = nil
    end

    reaper.Undo_EndBlock("Render from folders", -1)
end

-- Cleanup

-- Killing the script from the actions menu stops the defer loop without
-- running any of our own teardown, so everything temporary is undone here.
function render_cleanup()
    direct_render_abort()
    preview_clear()
    journal_restore()
    pop_render_settings()
    if RC.ephemeral_guids then
        delete_regions(RC.ephemeral_guids)
        RC.ephemeral_guids = nil
    end
end

reaper.atexit(render_cleanup)

RC.render_status      = "Ready"
RC.render_results     = {}
RC.render_on_complete = nil
RC.ephemeral_guids    = nil
