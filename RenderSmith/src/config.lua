RC.EXT_KEY       = "SFX_Renderer"

-- Product identity. The version lived in two unrelated places before this
-- (the ReaPack header and a hard-coded GUI.name string); both now read here.
RC.PRODUCT_NAME = "RenderSmith"
RC.VERSION      = "2.0"

-- Licensing. EXT_KEY above stays "SFX_Renderer" so existing settings are not
-- orphaned by the rename; the license gets its own ExtState section so that
-- resetting settings can never clear it.
RC.LIC_SECTION         = "RenderSmith"
-- Public identifiers, not secrets. The product id is shown inside the License
-- key module on the product's Content tab in Gumroad.
RC.GUMROAD_PRODUCT_ID  = "QLw0AR7Pky7Qa1Nfpvh2Iw=="
RC.BUY_URL             = "https://panchusound.gumroad.com/l/rendersmith"
RC.TRIAL_DAYS          = 7
RC.REVALIDATE_DAYS     = 14   -- re-check online no more often than this
RC.OFFLINE_GRACE_DAYS  = 60   -- keep working this long without a successful check
RC.ORIGINAL_TAG  = "SFX_ORIGINAL"
RC.VARIATION_TAG = "SFX_VARIATION"

RC.DEFAULT_UCS_WILDCARD = "$catid_$fxname_$creatorid_$sourceid"
RC.DEFAULT_WILDCARD     = "$prefix_$root_$parent_"
RC.MAX_AUDIO_TYPES      = 8
RC.MAX_CUSTOM_FIELDS    = 5

-- Wildcard names that user-defined custom fields may not use
RC.RESERVED_TOKENS = {
    prefix = true, root = true, parent = true, region = true,
    track = true, tracknumber = true, folders = true, number = true, rf = true,
    bpm = true, meter = true,
    character = true, questtype = true, questname = true, line = true,
    catid = true, fxname = true, creatorid = true, sourceid = true, userdata = true,
}

RC.default_audio_types = {
    {
        name = "SFX", prefix = "sx", wildcard = "$prefix_$root_$parent_",
        path_pattern = "{base}/$prefix/$root/$parent/",
        ucs_enabled = false, ucs_catid = "", ucs_wildcard = RC.DEFAULT_UCS_WILDCARD,
        fields = {},
        config = { bpm=0, meter="", character="", quest_type="", quest_name="", line_number=1 },
    },
    {
        name = "Music", prefix = "mx", wildcard = "$prefix_$root_$parent_$bpm_$meter_",
        path_pattern = "{base}/$prefix/$root/$parent/",
        ucs_enabled = false, ucs_catid = "", ucs_wildcard = RC.DEFAULT_UCS_WILDCARD,
        fields = {},
        config = { bpm=120, meter="4-4", character="", quest_type="", quest_name="", line_number=1 },
    },
    {
        name = "Dialogue", prefix = "dx", wildcard = "$prefix_$character_$questtype_$questname_$line_",
        path_pattern = "{base}/$prefix/$root/$parent/",
        ucs_enabled = false, ucs_catid = "", ucs_wildcard = RC.DEFAULT_UCS_WILDCARD,
        fields = {},
        config = { bpm=0, meter="", character="", quest_type="SQ", quest_name="", line_number=1 },
    },
    {
        name = "Environment", prefix = "env", wildcard = "$prefix_$root_$parent_",
        path_pattern = "{base}/$prefix/$root/$parent/",
        ucs_enabled = false, ucs_catid = "", ucs_wildcard = RC.DEFAULT_UCS_WILDCARD,
        fields = {},
        config = { bpm=0, meter="", character="", quest_type="", quest_name="", line_number=1 },
    },
}

RC.default_settings = {
    prefix             = "sx",
    prefix_type        = "sx",
    variations         = 0,
    separation_time    = 1.0,
    randomize_position = 0.0,
    wildcard_template  = "$region",
    music_bpm          = 120,
    music_meter        = "4-4",
    dx_character       = "",
    dx_quest_type      = "SQ",
    dx_quest_name      = "",
    dx_line_number     = 1,
    render_base_dir    = "",
    render_engine      = "direct",   -- "direct" (WAV, no window) | "reaper" (native)
    render_keep_regions = true,      -- Render Folders: keep regions, or discard after render
    cluster_enabled     = false,     -- off = one region per folder (pre-1.3 behaviour)
    gap_length          = 1.0,       -- seconds of silence that separate two sounds
    gap_use_beat        = false,     -- derive the gap from project tempo instead
    number_single_files = false,     -- number a folder that yields a single region
    warn_overwrite      = true,      -- confirm before replacing existing render files
    always_track_mode   = false,     -- ignore item selection; always work on folder tracks
    direct_bit_depth   = 24,         -- 16 | 24 | 32 (32 = float)
    direct_srate       = 0,          -- 0 = project rate | 44100 | 48000 | 88200 | 96000
    ucs_creator_id     = "",
    ucs_source_id      = "",
    ucs_user_data      = "",
    volume_enable      = false,  volume_amount   = 3.0,
    pan_enable         = false,  pan_amount      = 0.1,
    pitch_enable       = false,  pitch_amount    = 0.5,
    rate_enable        = false,  rate_amount     = 0.1,
    length_enable      = false,  length_amount   = 0.1,
    fadein_enable      = false,  fadein_amount   = 0.1,
    fadeout_enable     = false,  fadeout_amount  = 0.1,
    fadeshape_enable   = false,
}
