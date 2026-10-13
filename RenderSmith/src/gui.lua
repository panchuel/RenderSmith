-- Lokasenna library
local lib_path = reaper.GetExtState("Lokasenna_GUI", "lib_path_v2")
if not lib_path or lib_path == "" then
    reaper.MB(
        "Couldn't load Lokasenna_GUI v2.\n\n" ..
        "Please run:\nScripts > ReaTeam Scripts > Development >\n" ..
        "Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua",
        RC.PRODUCT_NAME, 0)
    error("missing Lokasenna_GUI v2")
end
loadfile(lib_path .. "Core.lua")()
GUI.req(lib_path .. "Classes/Class - Button.lua")()
GUI.req(lib_path .. "Classes/Class - Tabs.lua")()
GUI.req(lib_path .. "Classes/Class - Menubox.lua")()
GUI.req(lib_path .. "Classes/Class - Options.lua")()
GUI.req(lib_path .. "Classes/Class - Textbox.lua")()
GUI.req(lib_path .. "Classes/Class - Label.lua")()
GUI.req(lib_path .. "Classes/Class - Frame.lua")()
if missing_lib then error("missing Lokasenna class") end

-- RC_Dropdown: themed dropdown overlay for all Menuboxes
-- The stock Menubox opens the native OS context menu (white, unthemed).
-- This single overlay element lives on z=1 (topmost), draws with the GUI
-- palette below the owning box, and supports mouse-wheel scrolling for
-- long lists (e.g. the 82 UCS categories).
GUI.RC_Dropdown = {}
GUI.RC_Dropdown.__index = GUI.RC_Dropdown

function GUI.RC_Dropdown:new(name, z)
    local e = setmetatable({}, self)
    e.name, e.type, e.z = name, "RC_Dropdown", z
    e.x, e.y, e.w, e.h  = -10000, -10000, 0, 0
    e.owner   = nil
    e.items   = {}
    e.scroll  = 0
    e.item_h  = 20
    e.max_vis = 14
    return e
end

function GUI.RC_Dropdown:init()             end
function GUI.RC_Dropdown:onupdate()         end
function GUI.RC_Dropdown:onresize()         end
function GUI.RC_Dropdown:lostfocus()        end
function GUI.RC_Dropdown:getfocus()         end
function GUI.RC_Dropdown:onmouseover()      end
function GUI.RC_Dropdown:onmousedown()      end
function GUI.RC_Dropdown:ondrag()           end
function GUI.RC_Dropdown:ondoubleclick()    end
function GUI.RC_Dropdown:ontype()           end
function GUI.RC_Dropdown:onmouser_down()    end
function GUI.RC_Dropdown:onr_drag()         end
function GUI.RC_Dropdown:onmouser_up()      end
function GUI.RC_Dropdown:onr_doubleclick()  end
function GUI.RC_Dropdown:onmousem_down()    end
function GUI.RC_Dropdown:onm_drag()         end
function GUI.RC_Dropdown:onmousem_up()      end
function GUI.RC_Dropdown:onm_doubleclick()  end
function GUI.RC_Dropdown:redraw()           end

function GUI.RC_Dropdown:open_for(owner)
    self.owner  = owner
    self.items  = owner.optarray or {}
    self.scroll = 0

    local vis = math.min(#self.items, self.max_vis)
    self.w = owner.w
    self.h = vis * self.item_h + 4
    self.x = owner.x
    self.y = owner.y + owner.h
    if self.y + self.h > gfx.h then
        self.y = math.max(0, owner.y - self.h)
    end
    -- Keep the current selection in view
    local sel = owner.retval or 1
    if sel > vis then
        self.scroll = math.min(sel - 1, #self.items - vis)
    end
    if GUI.redraw_z then GUI.redraw_z[self.z] = true end
end

function GUI.RC_Dropdown:close()
    self.owner = nil
    self.x, self.y, self.w, self.h = -10000, -10000, 0, 0
    if GUI.redraw_z then GUI.redraw_z[self.z] = true end
end

function GUI.RC_Dropdown:draw()
    if not self.owner then return end
    local x, y, w, h = self.x, self.y, self.w, self.h
    local vis = math.min(#self.items, self.max_vis)

    GUI.color("wnd_bg")
    gfx.rect(x - 1, y - 1, w + 2, h + 2, true)
    GUI.color("elm_bg")
    gfx.rect(x, y, w, h, true)
    GUI.color("elm_frame")
    gfx.rect(x, y, w, h, false)

    local hover
    if GUI.IsInside(self, GUI.mouse.x, GUI.mouse.y) then
        hover = math.floor((GUI.mouse.y - y - 2) / self.item_h) + 1
    end

    GUI.font(4)
    for i = 1, vis do
        local idx = i + self.scroll
        local iy  = y + 2 + (i - 1) * self.item_h
        if idx == (self.owner.retval or 0) then
            GUI.color("elm_fill")
            gfx.rect(x + 2, iy, w - 4, self.item_h, true)
            GUI.color("wnd_bg")
        elseif i == hover then
            GUI.color("elm_frame")
            gfx.rect(x + 2, iy, w - 4, self.item_h, true)
            GUI.color("txt")
        else
            GUI.color("txt")
        end
        gfx.x, gfx.y = x + 8, iy + 3
        gfx.drawstr(tostring(self.items[idx] or ""))
    end

    -- Scrollbar hint for long lists
    if #self.items > vis then
        local bar_h = math.max(12, h * vis / #self.items)
        local bar_y = y + (h - bar_h) * (self.scroll / (#self.items - vis))
        GUI.color("elm_fill")
        gfx.rect(x + w - 5, bar_y, 3, bar_h, true)
    end
end

function GUI.RC_Dropdown:onmouseup()
    if not self.owner then return end
    local i   = math.floor((GUI.mouse.y - self.y - 2) / self.item_h) + 1
    local idx = i + self.scroll
    if idx >= 1 and idx <= #self.items and i <= self.max_vis then
        self.owner.retval = idx
        if GUI.redraw_z then GUI.redraw_z[self.owner.z] = true end
    end
    self:close()
end

function GUI.RC_Dropdown:onwheel(inc)
    local vis = math.min(#self.items, self.max_vis)
    if #self.items <= vis then return end
    local step = inc > 0 and -2 or 2
    self.scroll = math.max(0, math.min(self.scroll + step, #self.items - vis))
    if GUI.redraw_z then GUI.redraw_z[self.z] = true end
end

GUI.New("rc_dropdown", "RC_Dropdown", 1)

-- All menuboxes open the themed overlay instead of the native OS menu
function GUI.Menubox:onmouseup()
    if not self.focus then
        self:redraw()
        return
    end
    local dd = GUI.elms.rc_dropdown
    if dd.owner == self then
        dd:close()
    else
        dd:open_for(self)
    end
    self.focus = false
    self:redraw()
end

-- Footer override
GUI.version = 0
GUI.Draw_Version = function()
    local str = RC.PRODUCT_NAME .. " v" .. RC.VERSION .. "  -  by Panchuel"
    GUI.font(4)
    GUI.color("txt")
    local sw, sh = gfx.measurestr(str)
    gfx.x = math.floor((gfx.w - sw) / 2)
    gfx.y = gfx.h - sh - 4
    gfx.drawstr(str)
end

-- RC_Checklist: custom checkbox list (no external class needed)
GUI.RC_Checklist = {}
GUI.RC_Checklist.__index = GUI.RC_Checklist

function GUI.RC_Checklist:new(name, z, x, y, w, h)
    local e = setmetatable({}, self)
    e.name     = name
    e.type     = "RC_Checklist"
    e.z        = z
    e.x, e.y, e.w, e.h = x, y, w, h
    e.optarray = {}
    e.optsel   = {}
    e.numopts  = 0
    e.item_h   = 19
    return e
end

function GUI.RC_Checklist:init()             end
function GUI.RC_Checklist:onupdate()         end
function GUI.RC_Checklist:onresize()         end
function GUI.RC_Checklist:lostfocus()        end
function GUI.RC_Checklist:getfocus()         end
function GUI.RC_Checklist:onmouseover()      end
function GUI.RC_Checklist:onmousedown()      end
function GUI.RC_Checklist:ondrag()           end
function GUI.RC_Checklist:ondoubleclick()    end
function GUI.RC_Checklist:onwheel()          end
function GUI.RC_Checklist:ontype()           end
function GUI.RC_Checklist:onmouser_down()    end
function GUI.RC_Checklist:onr_drag()         end
function GUI.RC_Checklist:onmouser_up()      end
function GUI.RC_Checklist:onr_doubleclick()  end
function GUI.RC_Checklist:onmousem_down()    end
function GUI.RC_Checklist:onm_drag()         end
function GUI.RC_Checklist:onmousem_up()      end
function GUI.RC_Checklist:onm_doubleclick()  end
function GUI.RC_Checklist:redraw()           end

function GUI.RC_Checklist:draw()
    local x, y, w, h = self.x, self.y, self.w, self.h
    GUI.color("elm_bg")
    gfx.rect(x, y, w, h, true)
    GUI.color("elm_frame")
    gfx.rect(x, y, w, h, false)
    if self.numopts == 0 then return end
    GUI.font(4)
    local ih   = self.item_h
    local maxv = math.floor((h - 4) / ih)
    for i = 1, math.min(self.numopts, maxv) do
        local iy = y + (i - 1) * ih + 3
        GUI.color("elm_frame")
        gfx.rect(x + 5, iy + 2, 12, 12, false)
        if self.optsel[i] then
            GUI.color("elm_fill")
            gfx.rect(x + 7, iy + 4, 8, 8, true)
        end
        GUI.color("txt")
        gfx.x, gfx.y = x + 24, iy + 1
        gfx.drawstr(self.optarray[i] or "")
    end
    if self.numopts > maxv then
        GUI.color("elm_frame")
        gfx.x, gfx.y = x + 5, y + h - ih + 2
        gfx.drawstr(string.format("... +%d more (click Refresh)", self.numopts - maxv))
    end
end

function GUI.RC_Checklist:onmousedown()
    local rel_y = GUI.mouse.y - self.y - 3
    local idx   = math.floor(rel_y / self.item_h) + 1
    if idx >= 1 and idx <= self.numopts then
        self.optsel[idx] = not self.optsel[idx]
        if GUI.redraw_z then GUI.redraw_z[self.z] = true end
    end
end

function GUI.RC_Checklist:onmouseup() end

-- Window
GUI.name   = RC.PRODUCT_NAME .. " v" .. RC.VERSION
GUI.w, GUI.h = 460, 642

-- Maps between menubox positions and setting values (Render tab)
local DEPTH_VALUES  = { 16, 24, 32 }
local DEPTH_INDEX   = { [16] = 1, [24] = 2, [32] = 3 }
local SRATE_VALUES  = { 0, 44100, 48000, 88200, 96000 }
local SRATE_INDEX   = { [0] = 1, [44100] = 2, [48000] = 3, [88200] = 4, [96000] = 5 }
GUI.fonts[5] = {"Calibri", 11}
GUI.anchor, GUI.corner = "screen", "C"

-- Layout constants
local LM    = 16
local TW    = GUI.w - LM * 2   -- 428
local TAB_H = 16
local HDR_Y = TAB_H + 2        -- header band top  = 18
local HDR_H = 26               -- header band height
local CY    = HDR_Y + HDR_H + 4 -- content start   = 48
local SUB_H  = 18               -- Config sub-tab bar height
local SUB_Y  = CY               -- it sits where content would start...
local SUB_CY = CY + SUB_H + 4   -- ...so its panes start lower

-- Z-layer map
--  1 = Tabs bar  (always visible)
--  2 = Main tab
--  3 = Audio Config tab
--  4 = UCS tab
--  5 = Music-specific fields   (managed manually, shown on Main tab)
--  6 = Dialogue-specific fields (managed manually, shown on Main tab)
--  7 = Render tab
--  8 = Audio-type header       (always visible, not in any tab set)
--  9 = Render checklist + selection buttons
-- 10 = Custom fields of the selected type (shown on Main tab)
-- 11 = Advanced pane
-- 12 = Render tab reflow group
-- 13 = Config sub-tab bar
-- 14 = License tab

-- Tabs
GUI.New("tabs", "Tabs", 1, 0, 0, 90, TAB_H, "Main,Config,Render,License", 3)

-- Config holds three panes that all configure something. Its sub-bar is a
-- plain Tabs element with no z-sets of its own: the update function reads
-- its value and drives GUI.elms_hide directly, the same way the Music and
-- Dialogue field groups are handled. Letting it manage z-sets would fight
-- the parent tab bar over the same layers.
GUI.New("subtabs", "Tabs", 13, 0, SUB_Y, 104, SUB_H, "Audio Types,UCS,Advanced", 3)

-- Forward-declared: the UCS button in the header below closes over this,
-- and a `local` further down would leave that closure reading a nil global.
local _ucs_subs

-- Always-visible audio type header (z=8)
local _type_names = {}
for _, t in ipairs(RC.audio_types) do _type_names[#_type_names + 1] = t.name end

GUI.New("lbl_atype_hdr", "Label",   8, LM,        HDR_Y + 6,  "Audio Type:", false, 3)
GUI.New("sel_type",      "Menubox", 8, LM + 96,   HDR_Y, TW - 96 - 84, HDR_H, "",
    table.concat(_type_names, ","))

-- UCS naming is a property of the selected type, so its switch lives beside
-- the type picker rather than buried inside the Config tab.
GUI.New("btn_ucs", "Button", 8, LM + TW - 80, HDR_Y + 1, 80, HDR_H - 2, "", function()
    local at = RC.audio_types[RC.selected_type_idx]
    if not at then return end
    at.ucs_enabled = not at.ucs_enabled

    -- First enable with no CatID picked yet: adopt whatever the UCS pane
    -- currently shows, so a name is never built from an empty CatID.
    if at.ucs_enabled and (not at.ucs_catid or at.ucs_catid == "") then
        local entry = _ucs_subs and _ucs_subs[GUI.Val("mnu_ucs_sub") or 1]
        if entry then at.ucs_catid = entry.id end
    end

    refresh_ucs_toggle()
    refresh_ucs_tab()
end)
GUI.New("frm_hdr_sep",   "Frame",   8, 0, CY - 2, GUI.w, 2,  false, true, "elm_frame", 0)

-- Markers go on the folder track by default, where they stay clear of the
-- audio; a marker already selected is edited in place instead.
function gui_edit_name_switch()
    local existing = name_switch_selected()

    if existing then
        local ok, name = reaper.GetUserInputs("Edit NameSwitch", 1,
            "Name:,extrawidth=180", name_switch_name(existing))
        if not ok then return end
        reaper.Undo_BeginBlock()
        name_switch_set(existing, name)
        reaper.Undo_EndBlock("Edit NameSwitch", -1)
        reaper.UpdateArrange()
        refresh_create_button()
        return
    end

    local track = reaper.GetSelectedTrack(0, 0)
    if not track then
        reaper.MB("Select the folder track to put the marker on, or select an " ..
            "existing marker to rename it.", "NameSwitch", 0)
        return
    end

    local ok, name = reaper.GetUserInputs("New NameSwitch", 1,
        "Name:,extrawidth=180", "")
    if not ok or name == "" then return end

    reaper.Undo_BeginBlock()
    name_switch_create(track, reaper.GetCursorPosition(), name)
    reaper.Undo_EndBlock("Add NameSwitch", -1)
    reaper.UpdateArrange()
    refresh_create_button()
end

function refresh_ucs_toggle()
    local btn = GUI.elms.btn_ucs
    if not btn then return end
    local at = RC.audio_types[RC.selected_type_idx]
    btn.caption = (at and at.ucs_enabled) and "UCS: On" or "UCS: Off"
    if GUI.redraw_z then GUI.redraw_z[8] = true end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 1: MAIN  (z=2)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local y = CY  -- 48

-- Track hierarchy tree view
GUI.New("lbl_tree_hdr", "Label", 2, LM, y + 4, "Hierarchy:", false, 3)
for _i = 0, 5 do
    GUI.New("lbl_tr" .. _i, "Label", 2, LM + 6, y + 24 + _i * 16, "", false, 4)
end
y = y + 116  -- 164

GUI.New("btn_create", "Button", 2, LM, y, TW, 40, "Create Regions",
    function() reaper.defer(create_regions) end)
y = y + 48

GUI.New("btn_hierarchy", "Button", 2, LM, y, TW, 26, "Update Hierarchy",
    function() reaper.defer(update_selected_region_hierarchy) end)
y = y + 34

-- One button for both jobs: with a marker selected it renames that one,
-- otherwise it drops a new marker at the edit cursor.
GUI.New("btn_nameswitch", "Button", 2, LM, y, TW, 26, "Add / Edit NameSwitch",
    function() reaper.defer(gui_edit_name_switch) end)
y = y + 34

-- Type-specific settings appear below (z=5 Music, z=6 Dialogue)
local MS_Y = y + 12  -- 280

-- Music settings (z=5)
GUI.New("lbl_music_hdr", "Label",   5, LM,        MS_Y,       "Music settings", false, 3)
GUI.New("lbl_bpm",       "Label",   5, LM,        MS_Y + 28,  "BPM:",   false, 3)
GUI.New("txt_bpm",       "Textbox", 5, LM + 52,   MS_Y + 24,  90, 24,  "", 4)
GUI.New("lbl_meter",     "Label",   5, LM + 156,  MS_Y + 28,  "Meter:", false, 3)
GUI.New("txt_meter",     "Textbox", 5, LM + 212,  MS_Y + 24,  90, 24,  "", 4)

-- Dialogue settings (z=6)
GUI.New("lbl_dx_hdr",  "Label",   6, LM,       MS_Y,       "Dialogue settings", false, 3)
GUI.New("lbl_char",    "Label",   6, LM,       MS_Y + 28,  "Character:",  false, 3)
GUI.New("txt_char",    "Textbox", 6, LM + 98,  MS_Y + 24,  TW - 98, 24, "", 4)
GUI.New("lbl_qtype",   "Label",   6, LM,       MS_Y + 58,  "Quest Type:", false, 3)
GUI.New("txt_qtype",   "Textbox", 6, LM + 98,  MS_Y + 54,  TW - 98, 24, "", 4)
GUI.New("lbl_qname",   "Label",   6, LM,       MS_Y + 88,  "Quest Name:", false, 3)
GUI.New("txt_qname",   "Textbox", 6, LM + 98,  MS_Y + 84,  TW - 98, 24, "", 4)
GUI.New("lbl_line",    "Label",   6, LM,       MS_Y + 118, "Line:",        false, 3)
GUI.New("txt_line",    "Textbox", 6, LM + 98,  MS_Y + 114,  60,     24,  "", 4)

-- Custom fields of the selected type (z=10, shown on Main tab)
-- Rows are pre-created and moved offscreen when the type has fewer fields.
local CF_Y   = MS_Y + 150   -- below the music/dialogue panels
local CF_OFF = -10000
GUI.New("lbl_cf_hdr", "Label", 10, LM, CF_Y,
    "Custom fields", false, 3)
for _i = 1, RC.MAX_CUSTOM_FIELDS do
    GUI.New("lbl_cf" .. _i, "Label",   10, LM,       CF_Y + 20 + (_i - 1) * 28 + 4, "", false, 3)
    GUI.New("txt_cf" .. _i, "Textbox", 10, LM + 110, CF_Y + 20 + (_i - 1) * 28, TW - 110, 24, "", 4)
end

-- Assigned after all elements exist; declared here so button callbacks
-- below can capture them as upvalues.
local refresh_type_selector, refresh_field_list, refresh_custom_fields

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 2: AUDIO CONFIG  (z=3)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = SUB_CY

-- All controls on this tab edit the type selected in the header above.
GUI.New("lbl_type_name", "Label",   3, LM,        y + 5, "Name:", false, 3)
GUI.New("txt_type_name", "Textbox", 3, LM + 56,   y, 180, 24, "", 4)
GUI.New("lbl_type_pfx",  "Label",   3, LM + 252,  y + 5, "Prefix:", false, 3)
GUI.New("txt_atpfx",     "Textbox", 3, LM + 308,  y, TW - 308, 24, "", 4)
y = y + 32  -- 80

GUI.New("lbl_pattern_hdr", "Label", 3, LM, y, "Wildcard pattern:", false, 3)
y = y + 20  -- 100
GUI.New("txt_pattern", "Textbox", 3, LM, y, TW, 24, "", 4)
y = y + 30  -- 130

local _wildcards = {
    "$prefix    -  Type prefix  (sx, mx, dx, env \xe2\x80\xa6)",
    "$root      -  Root folder name",
    "$parent    -  Parent / folder name",
    "$bpm       -  BPM  (Music)",
    "$meter     -  Meter  (Music)",
    "$character -  Character  (Dialogue)",
    "$questtype -  Quest type  (Dialogue)",
    "$questname -  Quest name  (Dialogue)",
    "$line      -  Line number  01, 02 \xe2\x80\xa6  (Dialogue)",
    "$catid $fxname $creatorid $sourceid $userdata  -  UCS  (see UCS tab)",
}
for i, wc in ipairs(_wildcards) do
    GUI.New("lbl_wc" .. i, "Label", 3, LM + 8, y, wc, false, 4)
    y = y + 16
end

y = y + 6
GUI.New("frm_sep", "Frame", 3, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 14

GUI.New("lbl_fields_hdr", "Label", 3, LM, y,
    "Custom fields of this type (usable as $name, edited on Main):", false, 3)
y = y + 20

for _i = 1, RC.MAX_CUSTOM_FIELDS do
    GUI.New("lbl_cfld" .. _i, "Label", 3, LM + 8, y, "", false, 4)
    y = y + 17
end
y = y + 8

local BW4 = math.floor((TW - 12) / 4)
GUI.New("btn_add_type", "Button", 3, LM, y, BW4, 24, "+ Type", function()
    local ok, input = reaper.GetUserInputs("New Audio Type", 2,
        "Name:,Prefix (e.g. ui):", ",")
    if not ok then return end
    local name, prefix = input:match("([^,]*),(.*)")
    local idx, err = add_audio_type(name, prefix)
    if not idx then
        reaper.MB(err, "Cannot add type", 0)
        return
    end
    refresh_type_selector()
    -- Selecting the new index lets the normal type-change logic in GUI.func
    -- save the previous type and load the new one next frame.
    GUI.Val("sel_type", idx)
end)

GUI.New("btn_del_type", "Button", 3, LM + BW4 + 4, y, BW4, 24, "\xe2\x88\x92 Type", function()
    local at = RC.audio_types[RC.selected_type_idx]
    if not at then return end
    local ok = reaper.ShowMessageBox(
        "Delete audio type \"" .. at.name .. "\"?", "Confirm Delete", 4)
    if ok ~= 6 then return end
    local done, err = remove_audio_type(RC.selected_type_idx)
    if not done then
        reaper.MB(err, "Cannot delete type", 0)
        return
    end
    RC.selected_type_idx = math.min(RC.selected_type_idx, #RC.audio_types)
    sync_config_from_audio_type()
    refresh_type_selector()
    GUI.Val("sel_type", RC.selected_type_idx)
    local nt = RC.audio_types[RC.selected_type_idx]
    GUI.Val("txt_type_name", nt.name)
    GUI.Val("txt_atpfx",     nt.prefix)
    GUI.Val("txt_pattern",   nt.wildcard)
    refresh_field_list()
    refresh_custom_fields()
end)

GUI.New("btn_add_field", "Button", 3, LM + (BW4 + 4) * 2, y, BW4, 24, "+ Field", function()
    local at = RC.audio_types[RC.selected_type_idx]
    if not at then return end
    local ok, input = reaper.GetUserInputs("New Custom Field", 2,
        "Field name (a-z 0-9):,Default value:", ",")
    if not ok then return end
    local key, value = input:match("([^,]*),(.*)")
    local done, err = add_custom_field(at, key, value)
    if not done then
        reaper.MB(err, "Cannot add field", 0)
        return
    end
    refresh_field_list()
    refresh_custom_fields()
end)

GUI.New("btn_del_field", "Button", 3, LM + (BW4 + 4) * 3, y, TW - (BW4 + 4) * 3, 24,
    "\xe2\x88\x92 Field", function()
    local at = RC.audio_types[RC.selected_type_idx]
    if not at then return end
    if #(at.fields or {}) == 0 then
        reaper.MB("This type has no custom fields.", "Remove Field", 0)
        return
    end
    local ok, input = reaper.GetUserInputs("Remove Custom Field", 1, "Field name:", "")
    if not ok then return end
    local done, err = remove_custom_field(at, input)
    if not done then
        reaper.MB(err, "Cannot remove field", 0)
        return
    end
    refresh_field_list()
    refresh_custom_fields()
end)
y = y + 32

local BW = math.floor((TW - 8) / 2)

GUI.New("btn_save_types", "Button", 3, LM, y, BW, 28, "Save Audio Types", function()
    local at = RC.audio_types[RC.selected_type_idx]
    if at then
        at.name     = GUI.Val("txt_type_name") or at.name
        at.prefix   = GUI.Val("txt_atpfx")     or at.prefix
        at.wildcard = GUI.Val("txt_pattern")   or at.wildcard
        RC.wildcard_template = at.wildcard
    end
    sync_config_to_audio_type()
    save_audio_types(RC.audio_types)
    refresh_type_selector()
    reaper.MB("Audio types saved.", "Saved", 0)
end)

GUI.New("btn_reset_types", "Button", 3, LM + BW + 8, y, BW, 28, "Reset to Defaults", function()
    local ok = reaper.ShowMessageBox("Reset all audio types to default settings?", "Confirm Reset", 4)
    if ok == 6 then
        RC.audio_types = {}
        for _, dt in ipairs(RC.default_audio_types) do
            local entry = {
                name         = dt.name,
                prefix       = dt.prefix,
                wildcard     = dt.wildcard,
                path_pattern = dt.path_pattern,
                ucs_enabled  = dt.ucs_enabled,
                ucs_catid    = dt.ucs_catid,
                ucs_wildcard = dt.ucs_wildcard,
                fields       = {},
                config       = {},
            }
            for k, v in pairs(dt.config) do entry.config[k] = v end
            table.insert(RC.audio_types, entry)
        end
        save_audio_types(RC.audio_types)
        RC.selected_type_idx = 1
        sync_config_from_audio_type()
        refresh_type_selector()
        GUI.Val("sel_type", 1)
        local nt = RC.audio_types[1]
        GUI.Val("txt_type_name", nt.name)
        GUI.Val("txt_atpfx",     nt.prefix)
        GUI.Val("txt_pattern",   RC.wildcard_template)
        GUI.Val("txt_rpath",     nt.path_pattern or "{base}/$prefix/$root/$parent/")
        refresh_field_list()
        refresh_custom_fields()
        reaper.MB("Audio types reset to defaults.", "Reset Complete", 0)
    end
end)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 3: UCS  (z=4)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local UCS_CATS = ucs_categories()
_ucs_subs = ucs_subcats_for(UCS_CATS[1])

local function ucs_sub_names(subs)
    local names = {}
    for i, e in ipairs(subs) do names[i] = e.sub end
    return names
end

y = SUB_CY

GUI.New("lbl_ucs_hdr", "Label", 4, LM, y,
    "UCS naming  (Universal Category System v" .. RC.UCS_VERSION .. ")", false, 3)
y = y + 24

GUI.New("lbl_ucs_cat", "Label",   4, LM,       y + 5, "Category:", false, 3)
GUI.New("mnu_ucs_cat", "Menubox", 4, LM + 100, y, TW - 100, 24, "", UCS_CATS)
y = y + 30

GUI.New("lbl_ucs_sub", "Label",   4, LM,       y + 5, "SubCategory:", false, 3)
GUI.New("mnu_ucs_sub", "Menubox", 4, LM + 100, y, TW - 100, 24, "", ucs_sub_names(_ucs_subs))
y = y + 30

GUI.New("lbl_ucs_catid", "Label", 4, LM, y, "CatID:  -", false, 3)
y = y + 26

GUI.New("lbl_ucs_pat",     "Label",   4, LM,       y + 5, "Pattern:", false, 3)
GUI.New("txt_ucs_pattern", "Textbox", 4, LM + 100, y, TW - 100, 24, "", 4)
y = y + 34

GUI.New("frm_ucs_sep", "Frame", 4, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 12

GUI.New("lbl_ucs_glob", "Label", 4, LM, y, "Shared UCS fields (all types):", false, 3)
y = y + 22

GUI.New("lbl_ucs_creator", "Label",   4, LM,       y + 5, "CreatorID:", false, 3)
GUI.New("txt_ucs_creator", "Textbox", 4, LM + 100, y, TW - 100, 24, "", 4)
y = y + 30

GUI.New("lbl_ucs_source", "Label",   4, LM,       y + 5, "SourceID:", false, 3)
GUI.New("txt_ucs_source", "Textbox", 4, LM + 100, y, TW - 100, 24, "", 4)
y = y + 30

GUI.New("lbl_ucs_user", "Label",   4, LM,       y + 5, "UserData:", false, 3)
GUI.New("txt_ucs_user", "Textbox", 4, LM + 100, y, TW - 100, 24, "", 4)
y = y + 34

GUI.New("frm_ucs_sep2", "Frame", 4, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 12

GUI.New("lbl_ucs_prev_hdr", "Label", 4, LM, y, "Filename preview:", false, 3)
y = y + 20
GUI.New("lbl_ucs_preview", "Label", 4, LM + 6, y, "-", false, 4)
y = y + 26
GUI.New("lbl_ucs_tokens", "Label", 4, LM, y,
    "Tokens: $catid  $fxname  $creatorid  $sourceid  $userdata  (+ all standard tokens)", false, 5)

local _prev_ucs_cat_idx = 0
local _prev_ucs_sub_idx = 0
local _prev_ucs_preview_key = nil

function refresh_ucs_tab()
    local at = RC.audio_types[RC.selected_type_idx]
    if not at then return end

    local entry = (at.ucs_catid and at.ucs_catid ~= "") and ucs_find(at.ucs_catid) or nil
    local cat   = entry and entry.cat or UCS_CATS[1]

    local cat_idx = 1
    for i, c in ipairs(UCS_CATS) do
        if c == cat then cat_idx = i break end
    end
    _ucs_subs = ucs_subcats_for(cat)
    GUI.elms.mnu_ucs_cat.retval  = cat_idx
    GUI.elms.mnu_ucs_sub.optarray = ucs_sub_names(_ucs_subs)

    local sub_idx = 1
    if entry then
        for i, e in ipairs(_ucs_subs) do
            if e.id == entry.id then sub_idx = i break end
        end
    end
    GUI.elms.mnu_ucs_sub.retval = sub_idx

    GUI.Val("txt_ucs_pattern", at.ucs_wildcard or RC.DEFAULT_UCS_WILDCARD)
    GUI.Val("lbl_ucs_catid", "CatID:  " ..
        ((at.ucs_catid and at.ucs_catid ~= "") and at.ucs_catid or _ucs_subs[sub_idx].id))

    _prev_ucs_cat_idx = cat_idx
    _prev_ucs_sub_idx = sub_idx
    _prev_ucs_preview_key = nil
    if GUI.redraw_z then GUI.redraw_z[4] = true end
end

local function update_ucs_preview()
    local at = RC.audio_types[RC.selected_type_idx]
    if not at then return end

    local sel    = reaper.GetSelectedTrack(0, 0)
    local parent = sel and get_track_name(sel) or "FxName"

    local key = table.concat({
        tostring(RC.selected_type_idx), tostring(at.ucs_enabled),
        at.ucs_catid or "", at.ucs_wildcard or "",
        RC.ucs_creator_id or "", RC.ucs_source_id or "", RC.ucs_user_data or "",
        parent,
    }, "|")
    if key == _prev_ucs_preview_key then return end
    _prev_ucs_preview_key = key

    local name = expand_wildcards(at.ucs_wildcard or RC.DEFAULT_UCS_WILDCARD,
        at.prefix, "Root", parent)
    name = name:gsub("__+", "_"):gsub("^_+", ""):gsub("_+$", "")
    GUI.Val("lbl_ucs_preview", name .. ".wav")
end

-- Dynamic type / custom-field helpers

-- Rebuilds the header type selector from RC.audio_types (after add/remove/rename)
refresh_type_selector = function()
    local names = {}
    for i, t in ipairs(RC.audio_types) do names[i] = t.name end
    local sel = GUI.elms.sel_type
    sel.optarray = names
    if sel.retval > #names then sel.retval = #names end
    if GUI.redraw_z then GUI.redraw_z[8] = true end
end

-- Audio Config tab: read-only list of the selected type's custom fields
refresh_field_list = function()
    local at = RC.audio_types[RC.selected_type_idx]
    local fields = at and at.fields or {}
    for i = 1, RC.MAX_CUSTOM_FIELDS do
        local text = ""
        if fields[i] then
            text = "$" .. fields[i].key .. "   =   " .. (fields[i].value or "")
        elseif i == 1 then
            text = "(none, use + Field)"
        end
        GUI.Val("lbl_cfld" .. i, text)
    end
    if GUI.redraw_z then GUI.redraw_z[3] = true end
end

-- Main tab: value editors for the selected type's custom fields
refresh_custom_fields = function()
    local at = RC.audio_types[RC.selected_type_idx]
    local fields = at and at.fields or {}
    GUI.elms.lbl_cf_hdr.x = (#fields > 0) and LM or CF_OFF
    for i = 1, RC.MAX_CUSTOM_FIELDS do
        local lbl, txt = GUI.elms["lbl_cf" .. i], GUI.elms["txt_cf" .. i]
        local f = fields[i]
        if f then
            lbl.x, txt.x = LM, LM + 110
            GUI.Val("lbl_cf" .. i, "$" .. f.key .. ":")
            GUI.Val("txt_cf" .. i, f.value or "")
        else
            lbl.x, txt.x = CF_OFF, CF_OFF
            GUI.Val("lbl_cf" .. i, "")
        end
    end
    if GUI.redraw_z then GUI.redraw_z[10] = true end
end

-- Region list builder
local function populate_region_checklist()
    -- Re-read metadata each time: the user may have switched project tab
    -- since the script started, and it lives in ProjExtState.
    region_meta_load()

    RC.region_list = {}
    for _, region in ipairs(region_list()) do
        local badge = ""
        for _, t in ipairs(RC.audio_types) do
            if region_matches_type(region.name, t) then
                badge = "[" .. t.prefix .. "] "
                break
            end
        end
        RC.region_list[#RC.region_list + 1] = {
            id = region.guid, raw_name = region.name, display = badge .. region.name,
        }
    end
    local chk = GUI.elms.chk_regions
    if not chk then return end
    if #RC.region_list == 0 then
        chk.optarray = { "(no regions in project)" }
        chk.numopts  = 1
        chk.optsel   = { false }
    else
        local opts = {}
        for _, r in ipairs(RC.region_list) do opts[#opts + 1] = r.display end
        chk.optarray = opts
        chk.numopts  = #opts
        chk.optsel   = {}
        for i = 1, #opts do chk.optsel[i] = true end
    end
    if GUI.redraw_z then GUI.redraw_z[9] = true end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 4: RENDER  (z=7 + z=9)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = CY  -- 48

GUI.New("lbl_rpath_hdr", "Label", 7, LM, y, "Output paths:", false, 3)
y = y + 18

GUI.New("lbl_base_lbl",   "Label",   7, LM,             y + 5, "Base folder:", false, 3)
GUI.New("txt_base_dir",   "Textbox", 7, LM + 90,        y,     TW - 90 - 74, 24, "", 4)
GUI.New("btn_browse_base","Button",  7, LM + TW - 70,   y,     70, 24, "Browse...", function()
    -- Fast path: native folder dialog from the js_ReaScriptAPI extension
    if reaper.JS_Dialog_BrowseForFolder then
        local initial = RC.render_base_dir ~= "" and RC.render_base_dir
            or reaper.GetProjectPath(0)
        local ret, folder = reaper.JS_Dialog_BrowseForFolder("Select base render folder", initial)
        if ret == 1 and folder and folder ~= "" then
            RC.render_base_dir = folder
            GUI.Val("txt_base_dir", folder)
        end
        return
    end

    local sep     = package.config:sub(1, 1)
    local tmp     = reaper.GetResourcePath() .. sep .. "Scripts"
    local out     = tmp .. sep .. "rf_browse.txt"
    local os_name = reaper.GetOS() or ""
    os.remove(out)

    local init = (RC.render_base_dir ~= "" and RC.render_base_dir
                 or reaper.GetProjectPath(0)):gsub(sep == "\\" and "/" or "\\", sep)

    local script_file  -- holds the temp script path for cleanup in poll

    if sep == "\\" then
        -- Windows: PowerShell + OpenFileDialog (modern Explorer dialog)
        script_file = tmp .. "\\rf_browse.ps1"
        local f = io.open(script_file, "w")
        if not f then return end
        f:write('Add-Type -AssemblyName System.Windows.Forms\n')
        f:write('$d = New-Object System.Windows.Forms.OpenFileDialog\n')
        f:write('$d.Title           = "Select base render folder"\n')
        f:write('$d.CheckFileExists = $false\n')
        f:write('$d.CheckPathExists = $true\n')
        f:write('$d.ValidateNames   = $false\n')
        f:write('$d.FileName        = "Select folder."\n')
        f:write(string.format('$d.InitialDirectory = "%s"\n', init:gsub('"', '`"')))
        f:write('$p = if ($d.ShowDialog() -eq "OK") { Split-Path $d.FileName } else { "" }\n')
        f:write(string.format('[IO.File]::WriteAllText("%s", $p, [Text.UTF8Encoding]::new($false))\n',
            out:gsub('"', '`"')))
        f:close()
        reaper.ExecProcess(string.format(
            'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%s"',
            script_file), -1)
    else
        -- Mac / Linux: shell script writes result then exits
        script_file = tmp .. "/rf_browse.sh"
        local f = io.open(script_file, "w")
        if not f then return end
        f:write("#!/bin/sh\n")
        if os_name:find("OSX") or os_name:find("macOS") then
            f:write(string.format(
                'result=$(osascript -e \'POSIX path of (choose folder with prompt "Select base render folder" default location POSIX file "%s")\' 2>/dev/null)\n',
                init:gsub("'", "'\\''")))
        else
            f:write(string.format(
                'result=$(zenity --file-selection --directory --title="Select base render folder" --filename="%s/" 2>/dev/null || kdialog --getexistingdirectory "%s" 2>/dev/null)\n',
                init:gsub('"', '\\"'), init:gsub('"', '\\"')))
        end
        f:write(string.format('printf "%%s" "$result" > "%s"\n', out:gsub('"', '\\"')))
        f:close()
        reaper.ExecProcess('/bin/sh "' .. script_file .. '"', -1)
    end

    local function poll()
        local r = io.open(out, "r")
        if not r then reaper.defer(poll); return end
        local path = r:read("*a"):gsub("^%s+", ""):gsub("[/\\]*%s*$", "")
        r:close()
        os.remove(out)
        os.remove(script_file)
        if path ~= "" then
            RC.render_base_dir = path
            GUI.Val("txt_base_dir", path)
        end
    end
    reaper.defer(poll)
end)
y = y + 32

-- Path template of the type selected in the header
GUI.New("lbl_rpath", "Label",   7, LM,      y + 5, "Type path:", false, 3)
GUI.New("txt_rpath", "Textbox", 7, LM + 90, y, TW - 90, 24, "", 4)
y = y + 32

y = y + 2
GUI.New("btn_save_paths", "Button", 7, LM, y, TW, 26, "Save Output Paths", function()
    local at = RC.audio_types[RC.selected_type_idx]
    if at then
        at.path_pattern = GUI.Val("txt_rpath") or at.path_pattern
    end
    save_audio_types(RC.audio_types)
    reaper.MB("Output paths saved.", "Saved", 0)
end)
y = y + 34

GUI.New("lbl_engine", "Label",   7, LM,      y + 5, "Engine:", false, 3)
GUI.New("mnu_engine", "Menubox", 7, LM + 60, y, TW - 60, 24, "",
    "Direct (WAV, no window),REAPER render (native)")
y = y + 30

GUI.New("lbl_depth", "Label",   7, LM,        y + 5, "Depth:", false, 3)
GUI.New("mnu_depth", "Menubox", 7, LM + 60,   y, 120, 24, "",
    "16-bit,24-bit,32-bit fl")
GUI.New("lbl_rate",  "Label",   7, LM + 200,  y + 5, "Rate:", false, 3)
GUI.New("mnu_rate",  "Menubox", 7, LM + 244,  y, TW - 244, 24, "",
    "Project rate,44100 Hz,48000 Hz,88200 Hz,96000 Hz")
y = y + 30

GUI.New("frm_sep_r", "Frame", 7, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 12

local _BH = math.floor((TW - 8) / 3)
GUI.New("lbl_rgn_hdr", "Label",  9, LM,            y + 5, "Regions:", false, 3)
GUI.New("btn_refresh",  "Button", 9, LM + TW - 70, y,     70, 22, "Refresh", function()
    populate_region_checklist()
end)
y = y + 30

GUI.New("chk_regions", "RC_Checklist", 9, LM, y, TW, 116)
y = y + 122

GUI.New("btn_sel_all",  "Button", 9, LM,               y, _BH, 22, "Select All", function()
    local chk = GUI.elms.chk_regions
    for i = 1, chk.numopts do chk.optsel[i] = true end
    if GUI.redraw_z then GUI.redraw_z[9] = true end
end)
GUI.New("btn_sel_none", "Button", 9, LM + _BH + 4,     y, _BH, 22, "None", function()
    local chk = GUI.elms.chk_regions
    for i = 1, chk.numopts do chk.optsel[i] = false end
    if GUI.redraw_z then GUI.redraw_z[9] = true end
end)
GUI.New("btn_filter",   "Button", 9, LM + (_BH + 4)*2, y, TW - (_BH + 4)*2, 22,
    "Filter by Type", function()
        if not RC.region_list then return end
        local atype = RC.audio_types[RC.selected_type_idx]
        if not atype then return end
        local chk = GUI.elms.chk_regions
        for i, r in ipairs(RC.region_list) do
            chk.optsel[i] = region_matches_type(r.raw_name, atype) and true or false
        end
        if GUI.redraw_z then GUI.redraw_z[9] = true end
    end)
y = y + 30

GUI.New("frm_sep_r2", "Frame", 7, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 10

local _RW = math.floor(TW / 2) - 4
GUI.New("btn_render", "Button", 12, LM, y, _RW, 40, "Render Checked", function()
    local ids = {}
    local chk = GUI.elms.chk_regions
    if chk and RC.region_list then
        for i, sel in ipairs(chk.optsel) do
            if sel and RC.region_list[i] then ids[#ids + 1] = RC.region_list[i].id end
        end
    end
    RC.render_status = "Rendering..."
    render_queue(ids)
end)

-- Builds regions from the current selection (folders, or just the items
-- picked) and renders them straight away. With "Regions: Temporary" those
-- regions are deleted once the render finishes.
GUI.New("btn_render_folders", "Button", 7, LM + _RW + 8, y, _RW, 40,
    "Build & Render", function()
        RC.render_status = "Rendering..."
        render_from_folders()
        populate_region_checklist()
    end)
y = y + 48

-- Hands a path or a URL to the OS without blocking REAPER's UI
-- (os.execute freezes REAPER until the shell returns).
local function open_external(path)
    if reaper.CF_ShellExecute then          -- SWS: clean and async
        reaper.CF_ShellExecute(path)
        return
    end
    local os_name = reaper.GetOS() or ""
    if os_name:find("Win") then
        reaper.ExecProcess('cmd.exe /C start "" "' .. path:gsub("/", "\\") .. '"', -1)
    elseif os_name:find("OSX") or os_name:find("macOS") then
        reaper.ExecProcess('/usr/bin/open "' .. path .. '"', -1)
    else
        reaper.ExecProcess('/usr/bin/xdg-open "' .. path .. '"', -1)
    end
end

local _FW = math.floor((TW - 16) / 3)
GUI.New("btn_keep_regions", "Button", 7, LM + _FW + 8, y, _FW, 22, "", function()
    RC.render_keep_regions = not RC.render_keep_regions
    refresh_cluster_labels()
end)
GUI.New("btn_overwrite", "Button", 7, LM + (_FW + 8) * 2, y, TW - (_FW + 8) * 2, 22,
    "", function()
        RC.warn_overwrite = not RC.warn_overwrite
        refresh_cluster_labels()
    end)

GUI.New("btn_open_folder", "Button", 7, LM, y, _FW, 22, "Open Folder", function()
    local d = RC.last_render_dir
    if d and d ~= "" then
        open_external(d)
    else
        reaper.MB("Render a region first.", "Open Folder", 0)
    end
end)
y = y + 30

GUI.New("lbl_render_status", "Label", 7, LM, y, "Ready", false, 5)

-- Controls that cannot do anything are hidden: the regions section when
-- the project has no regions, and "Render Checked" when nothing is ticked.
--
-- Lokasenna lays out in absolute coordinates, so hiding the regions block
-- means moving everything below it back up by the height it occupied.
-- Only x/y are ever changed: a Button bakes its width into its buffer at
-- init, so resizing one would need a re-init, while moving one does not.
local REGIONS_BLOCK_H = 182
local REFLOW_ELMS = {
    "frm_sep_r2", "btn_render", "btn_render_folders",
    "btn_open_folder", "btn_keep_regions", "btn_overwrite", "lbl_render_status",
}
local reflow_base_y  = nil
local render_layout  = nil

function layout_render_tab(has_regions, has_checked)
    local key = tostring(has_regions) .. tostring(has_checked)
    if key == render_layout then return end
    render_layout = key

    if not reflow_base_y then
        reflow_base_y = {}
        for _, name in ipairs(REFLOW_ELMS) do
            local e = GUI.elms[name]
            if e then reflow_base_y[name] = e.y end
        end
    end

    local shift = has_regions and 0 or REGIONS_BLOCK_H
    for _, name in ipairs(REFLOW_ELMS) do
        local e = GUI.elms[name]
        if e and reflow_base_y[name] then e.y = reflow_base_y[name] - shift end
    end

    -- Without the regions block there is already a separator right above,
    -- so the second one would read as a mistake: park it off-screen.
    local sep = GUI.elms.frm_sep_r2
    if sep then sep.x = has_regions and LM or -2000 end

    -- With no "Render Checked" beside it, the remaining button slides into
    -- the free slot rather than leaving a hole.
    local folders = GUI.elms.btn_render_folders
    if folders then folders.x = has_checked and (LM + _RW + 8) or LM end

    if GUI.redraw_z then
        GUI.redraw_z[7], GUI.redraw_z[9], GUI.redraw_z[12] = true, true, true
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 5: ADVANCED  (z=11)
-- Gap clustering and the shared $RF[NAME] wildcard dictionary.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local WC_ROWS = 9
local _wc_scope = "global"

y = SUB_CY

GUI.New("lbl_clu_hdr", "Label", 11, LM, y,
    "Clustering", false, 3)
y = y + 22

local _CW = math.floor(TW / 2) - 4
local _C3 = math.floor((TW - 16) / 3)
GUI.New("btn_cluster",  "Button", 11, LM,                y, _C3, 24, "", function()
    RC.cluster_enabled = not RC.cluster_enabled
    refresh_cluster_labels()
    refresh_create_button()
end)
GUI.New("btn_num_single", "Button", 11, LM + _C3 + 8,    y, _C3, 24, "", function()
    RC.number_single_files = not RC.number_single_files
    refresh_cluster_labels()
    refresh_create_button()
end)
-- Whether an item selection narrows the job, or folders always win.
GUI.New("btn_mode", "Button", 11, LM + (_C3 + 8) * 2, y, TW - (_C3 + 8) * 2, 24,
    "", function()
        RC.always_track_mode = not RC.always_track_mode
        refresh_cluster_labels()
        refresh_create_button()
    end)
y = y + 32

GUI.New("lbl_gap",    "Label",   11, LM,            y + 4, "Gap:", false, 3)
GUI.New("txt_gap",    "Textbox", 11, LM + 44,       y,     90, 24, "", 4)
GUI.New("btn_gap_unit", "Button", 11, LM + 144,     y,     TW - 144, 24, "", function()
    RC.gap_use_beat = not RC.gap_use_beat
    refresh_cluster_labels()
end)
y = y + 32

GUI.New("btn_preview", "Button", 11, LM, y, _CW, 24, "Preview clusters", function()
    local regions, folders = preview_build()
    if regions == 0 then
        RC.preview_status = "Preview: nothing to show (select folder tracks)"
    else
        local _, _, mode = preview_count()
        RC.preview_status = string.format(
            "Preview: %d region(s) from %d folder(s)  -  %s selection",
            regions, folders, mode == "items" and "item" or "track")
    end
    refresh_cluster_labels()
end)
GUI.New("btn_preview_clear", "Button", 11, LM + _CW + 8, y, _CW, 24,
    "Clear preview", function()
        preview_clear()
        RC.preview_status = "Preview cleared"
        refresh_cluster_labels()
    end)
y = y + 30

GUI.New("lbl_preview_status", "Label", 11, LM, y, "", false, 5)
y = y + 20

GUI.New("lbl_clu_hint", "Label", 11, LM, y,
    "Off = one region per folder. On = one region per sound.", false, 5)
y = y + 20
GUI.New("lbl_clu_hint2", "Label", 11, LM, y,
    "Mode Auto: selected items win over selected folders.", false, 5)
y = y + 24

GUI.New("frm_sep_a", "Frame", 11, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 12

GUI.New("lbl_wc_hdr", "Label", 11, LM, y,
    "User wildcards", false, 3)
y = y + 22

for _i = 0, WC_ROWS - 1 do
    GUI.New("lbl_rfw" .. _i, "Label", 11, LM + 6, y + _i * 16, "", false, 5)
end
y = y + WC_ROWS * 16 + 8

GUI.New("lbl_wc_name",  "Label",   11, LM,       y + 4, "Name:",  false, 3)
GUI.New("txt_wc_name",  "Textbox", 11, LM + 56,  y,     120, 24, "", 4)
GUI.New("lbl_wc_value", "Label",   11, LM + 188, y + 4, "Value:", false, 3)
GUI.New("txt_wc_value", "Textbox", 11, LM + 244, y,     TW - 244, 24, "", 4)
y = y + 32

local _AW = math.floor((TW - 16) / 3)
GUI.New("btn_wc_scope", "Button", 11, LM, y, _AW, 24, "", function()
    _wc_scope = (_wc_scope == "global") and "project" or "global"
    refresh_cluster_labels()
end)
GUI.New("btn_wc_add", "Button", 11, LM + _AW + 8, y, _AW, 24, "Add / Update", function()
    local name  = GUI.Val("txt_wc_name")  or ""
    local value = GUI.Val("txt_wc_value") or ""
    local ok, err = wildcard_dict_set(name, value, _wc_scope)
    if not ok then
        reaper.MB(err, "Wildcard", 0)
        return
    end
    GUI.Val("txt_wc_name", "")
    GUI.Val("txt_wc_value", "")
    refresh_wildcard_list()
end)
GUI.New("btn_wc_del", "Button", 11, LM + (_AW + 8) * 2, y, TW - (_AW + 8) * 2, 24,
    "Remove", function()
        local ok, err = wildcard_dict_remove(GUI.Val("txt_wc_name") or "", _wc_scope)
        if not ok then
            reaper.MB(err, "Wildcard", 0)
            return
        end
        GUI.Val("txt_wc_name", "")
        refresh_wildcard_list()
    end)
y = y + 30

GUI.New("lbl_wc_hint", "Label", 11, LM, y,
    "Use as $RF[NAME] in patterns, or RF[NAME] in paths.", false, 5)
y = y + 18
GUI.New("lbl_wc_hint2", "Label", 11, LM, y,
    "Values may contain other wildcards. Project entries beat global ones.", false, 5)

y = y + 24
GUI.New("frm_sep_a2", "Frame", 11, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 12

GUI.New("lbl_ovr_hdr", "Label", 11, LM, y,
    "Selected folder track", false, 3)
y = y + 22

GUI.New("lbl_ovr_sum", "Label", 11, LM + 6, y, "", false, 5)
y = y + 22

local _OW = math.floor((TW - 16) / 3)
GUI.New("btn_ovr_type", "Button", 11, LM, y, _OW, 24, "Pin type", function()
    local tr = reaper.GetSelectedTrack(0, 0)
    if not tr then return end
    local at = RC.audio_types[RC.selected_type_idx]
    if at then setting_set_track(tr, "audio_type", at.prefix) end
    refresh_track_overrides()
end)
GUI.New("btn_ovr_excl", "Button", 11, LM + _OW + 8, y, _OW, 24, "Exclude", function()
    local tr = reaper.GetSelectedTrack(0, 0)
    if not tr then return end
    setting_set_track(tr, "excluded", not is_track_excluded(tr))
    refresh_track_overrides()
end)
GUI.New("btn_ovr_clear", "Button", 11, LM + (_OW + 8) * 2, y, TW - (_OW + 8) * 2, 24,
    "Clear", function()
        local tr = reaper.GetSelectedTrack(0, 0)
        if not tr then return end
        for _, entry in ipairs(RC.SETTING_REGISTRY) do
            setting_clear_track(tr, entry.name)
        end
        refresh_track_overrides()
    end)
y = y + 28

GUI.New("lbl_ovr_hint", "Label", 11, LM, y,
    "Pinned settings live in the track and travel inside the project.", false, 5)

-- Overrides are stored on the track itself, so the summary has to be
-- re-read whenever the selection changes, not just when the tab opens.
function refresh_track_overrides()
    local tr = reaper.GetSelectedTrack(0, 0)
    GUI.Val("lbl_ovr_sum", track_override_summary(tr))

    local btn = GUI.elms.btn_ovr_excl
    if btn then
        btn.caption = (tr and is_track_excluded(tr)) and "Include" or "Exclude"
    end
    if GUI.redraw_z then GUI.redraw_z[11] = true end
end

-- Buttons carry their state in the caption, so refresh them together.
function refresh_cluster_labels()
    local function cap(name, text)
        local btn = GUI.elms[name]
        if not btn then return end
        btn.caption = text
        if GUI.redraw_z then GUI.redraw_z[btn.z] = true end
    end
    cap("btn_cluster",    RC.cluster_enabled and "Clustering: On" or "Clustering: Off")
    cap("btn_num_single", RC.number_single_files and "Number singles: On"
                                                 or "Number singles: Off")
    cap("btn_gap_unit",   RC.gap_use_beat and "Unit: 1 beat (tempo)" or "Unit: seconds")
    cap("btn_wc_scope",   (_wc_scope == "project") and "Scope: Project" or "Scope: Global")
    cap("btn_overwrite",  RC.warn_overwrite and "Overwrite: Warn" or "Overwrite: Silent")
    cap("btn_mode",       RC.always_track_mode and "Mode: Folders" or "Mode: Auto")
    GUI.Val("lbl_preview_status", RC.preview_status or "")
    cap("btn_keep_regions", RC.render_keep_regions and "Regions: Keep"
                                                    or "Regions: Temporary")
end

function refresh_wildcard_list()
    local entries = wildcard_dict_entries()
    for i = 0, WC_ROWS - 1 do
        local e = entries[i + 1]
        if e then
            local value = e.value
            if #value > 34 then value = value:sub(1, 31) .. "..." end
            GUI.Val("lbl_rfw" .. i, string.format("$RF[%s] = %s   (%s)",
                e.name, value, e.scope))
        elseif i == 0 then
            GUI.Val("lbl_rfw" .. i, "(no user wildcards yet)")
        else
            GUI.Val("lbl_rfw" .. i, "")
        end
    end
    if #entries > WC_ROWS then
        GUI.Val("lbl_rfw" .. (WC_ROWS - 1),
            string.format("... and %d more", #entries - WC_ROWS + 1))
    end
    if GUI.redraw_z then GUI.redraw_z[11] = true end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- UPDATE FUNCTION  (runs every frame)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local _prev_type_idx      = 0
local _prev_view           = 0
local _prev_state_count   = -1
local _prev_sel_track     = nil
local _prev_render_status = ""
local _prev_lic_status    = ""
local _prev_ovr_track     = false
local _prev_item_count    = -1
local _prev_item_first    = nil

local function refresh_tree_view()
    local L = "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 "
    local T = "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 "

    local sel = reaper.GetSelectedTrack(0, 0)
    if not sel then
        GUI.Val("lbl_tr0", "  No track selected")
        for i = 1, 5 do GUI.Val("lbl_tr" .. i, "") end
        return
    end

    local parent_name = get_track_name(sel)
    local root_folder = get_parent_track(sel)
    local root_name
    if root_folder then
        root_name = get_track_name(root_folder)
    else
        local _, proj_name = reaper.EnumProjects(-1, "")
        root_name = (proj_name:match("([^\\/]+)$") or "Project"):gsub("%..+$", "")
    end

    local all_desc    = get_child_tracks(sel)
    local item_tracks = {}
    for _, tr in ipairs(all_desc) do
        if reaper.CountTrackMediaItems(tr) > 0 then
            table.insert(item_tracks, tr)
        end
    end

    local total    = #item_tracks
    local max_show = 3

    GUI.Val("lbl_tr0", "Root   " .. root_name)
    GUI.Val("lbl_tr1", "  " .. L .. parent_name)

    if total == 0 then
        GUI.Val("lbl_tr2", "        " .. L .. "(no items)")
        for i = 3, 5 do GUI.Val("lbl_tr" .. i, "") end
        return
    end

    local show = math.min(max_show, total)
    for i = 1, show do
        local cname     = get_track_name(item_tracks[i])
        local n         = reaper.CountTrackMediaItems(item_tracks[i])
        local connector = (i == total and total <= max_show) and L or T
        GUI.Val("lbl_tr" .. (i + 1), "        " .. connector .. cname .. "   [" .. n .. " items]")
    end
    for i = show + 2, 5 do GUI.Val("lbl_tr" .. i, "") end
    if total > max_show then
        GUI.Val("lbl_tr5", "           ... " .. (total - max_show) .. " more")
    end

    refresh_create_button()
end

-- The button caption carries how many regions the current selection would
-- produce. With clustering on that number is the only way to tell whether
-- the Gap is set sensibly without creating anything first.
function refresh_create_button()
    local btn = GUI.elms.btn_create
    if not btn then return end

    local regions = preview_count()
    btn.caption = (regions > 0)
        and string.format("Create Regions  (%d)", regions)
        or "Create Regions"
    if GUI.redraw_z then GUI.redraw_z[btn.z] = true end
end

-- TAB 4: LICENSE  (z=14)
--
-- The window always opens, even once the trial is over. The gate at the top
-- of GUI.func pins it to this tab instead of refusing to start, because
-- somebody holding a key needs somewhere to type it.

local LIC_Y = CY + 10

GUI.New("lbl_lic_state", "Label", 14, LM, LIC_Y,      "", false, 2)
GUI.New("lbl_lic_sub",   "Label", 14, LM, LIC_Y + 28, "", false, 4)
GUI.New("frm_lic_sep",   "Frame", 14, LM, LIC_Y + 54, TW, 2, false, true, "elm_frame", 0)

local LIC_KY = LIC_Y + 68
GUI.New("lbl_lic_key", "Label",   14, LM,      LIC_KY + 5, "License key:", false, 3)
GUI.New("txt_license", "Textbox", 14, LM + 86, LIC_KY, TW - 86, 24, "", 4)

local LIC_BY = LIC_KY + 34
local _LBW   = math.floor((TW - 8) / 2)

GUI.New("btn_lic_activate", "Button", 14, LM, LIC_BY, _LBW, 26, "Activate", function()
    local key = GUI.Val("txt_license") or ""
    GUI.Val("lbl_lic_sub", "Checking with the license server...")
    if GUI.redraw_z then GUI.redraw_z[14] = true end

    license_activate(key, function(ok, info)
        refresh_license()
        if ok then
            GUI.Val("txt_license", "")
            reaper.MB("License activated. Thank you for buying " ..
                RC.PRODUCT_NAME .. ".", RC.PRODUCT_NAME, 0)
        else
            reaper.MB(tostring(info), RC.PRODUCT_NAME .. " - Activation failed", 0)
        end
    end)
end)

GUI.New("btn_lic_buy", "Button", 14, LM + _LBW + 8, LIC_BY, _LBW, 26,
    "Buy a license", function()
    if not RC.BUY_URL or RC.BUY_URL == "" then
        reaper.MB("This build has no purchase link configured.",
            RC.PRODUCT_NAME, 0)
        return
    end
    open_external(RC.BUY_URL)
end)

GUI.New("btn_lic_remove", "Button", 14, LM, LIC_BY + 34, TW, 22,
    "Remove the license from this computer", function()
    local choice = reaper.ShowMessageBox(
        "Remove the license from this computer?\n\n" ..
        "You can enter the key again here or on another machine. This does " ..
        "not free the activation on the store side.",
        RC.PRODUCT_NAME, 4)
    if choice ~= 6 then return end
    license_deactivate()
    refresh_license()
end)

local LIC_HY = LIC_BY + 76
local _lic_help = {
    "The trial unlocks everything for " .. RC.TRIAL_DAYS .. " days.",
    "",
    "Your key is emailed when you buy, next to the download link. Paste it",
    "above and press Activate. It needs the internet only that once: after",
    "that it re-checks roughly every " .. RC.REVALIDATE_DAYS ..
        " days and keeps working offline in",
    "between, so a studio with no connection is never locked out.",
    "",
    "One license covers the machines you work on yourself.",
}
for i, line in ipairs(_lic_help) do
    GUI.New("lbl_lic_h" .. i, "Label", 14, LM, LIC_HY + (i - 1) * 15, line, false, 5)
end

-- Shows a key as its first and last four characters, so the status line can
-- confirm which key is active without putting the whole thing on screen.
local function mask_key(key)
    if not key or #key < 10 then return key or "" end
    return key:sub(1, 4) .. "..." .. key:sub(-4)
end

function refresh_license()
    local st = license_state(true)
    local head, sub

    if st.status == "licensed" then
        head = "Licensed"
        sub  = "Key " .. mask_key(st.key) .. " is active on this computer."
    elseif st.status == "trial" then
        head = string.format("Trial: %d day%s left",
            st.days_left, st.days_left == 1 and "" or "s")
        sub  = "Everything is unlocked while the trial runs."
    elseif st.reason == "stale" then
        head = "License needs re-checking"
        sub  = "Connect to the internet and press Activate."
    elseif st.reason == "tampered" then
        head = "License record unreadable"
        sub  = "Enter your key again to restore it."
    else
        head = "Trial ended"
        sub  = "Enter your license key to keep using " .. RC.PRODUCT_NAME .. "."
    end

    GUI.Val("lbl_lic_state", head)
    GUI.Val("lbl_lic_sub",   sub)
    if GUI.redraw_z then GUI.redraw_z[14] = true end
end

GUI.func = function()
    -- Views keep the numbering the rest of this function was written
    -- against, so folding Audio Types / UCS / Advanced under one Config tab
    -- did not mean rewriting every branch.
    --   1 Main   2 Audio Types   3 UCS   4 Render   5 Advanced
    -- License gate. Pinning the tab is the whole lock: Tabs:val switches
    -- the z-sets too, so every other pane hides itself. Checked every
    -- frame, which is free because license_state caches for 5 seconds.
    local lic = license_state()
    if lic.status == "expired" and GUI.elms.tabs.retval ~= 4 then
        GUI.Val("tabs", 4)
    end

    -- A background revalidation can revoke a licence while the window is
    -- open, and the trial can run out mid-session. Either way the tab above
    -- locks, so the text on it has to agree.
    if lic.status ~= _prev_lic_status then
        _prev_lic_status = lic.status
        refresh_license()
    end

    local cur_tab = GUI.elms.tabs.retval        -- 1 Main, 2 Config, 3 Render
    local cur_sub = GUI.elms.subtabs.retval     -- 1 Types, 2 UCS, 3 Advanced
    local cur_view
    if     cur_tab == 1  then cur_view = 1
    elseif cur_tab == 3  then cur_view = 4
    elseif cur_tab == 4  then cur_view = 6
    elseif cur_sub == 2  then cur_view = 3
    elseif cur_sub == 3  then cur_view = 5
    else                      cur_view = 2 end

    -- The Config panes are not in any tab set; this drives them.
    GUI.elms_hide[3]  = (cur_view ~= 2)
    GUI.elms_hide[4]  = (cur_view ~= 3)
    GUI.elms_hide[11] = (cur_view ~= 5)
    -- z=8 is in no tab set so it can float above Main, Config and Render;
    -- that also means it would bleed onto the License tab unless hidden.
    GUI.elms_hide[8]  = (cur_view == 6)
    local effective_idx = GUI.Val("sel_type")

    -- Themed dropdown: live hover redraw; close on outside click or tab change
    local dd = GUI.elms.rc_dropdown
    if dd.owner then
        if GUI.redraw_z then GUI.redraw_z[1] = true end
        if cur_view ~= _prev_view then
            dd:close()
        elseif GUI.mouse.down
            and not GUI.IsInside(dd, GUI.mouse.x, GUI.mouse.y)
            and not GUI.IsInside(dd.owner, GUI.mouse.x, GUI.mouse.y) then
            dd:close()
        end
    end

    -- Save type edits (name/prefix/pattern) when leaving Audio Config
    if _prev_view == 2 and cur_view ~= 2 then
        RC.wildcard_template = GUI.Val("txt_pattern") or RC.wildcard_template
        local at = RC.audio_types[RC.selected_type_idx]
        if at then
            at.wildcard = RC.wildcard_template
            local new_name = GUI.Val("txt_type_name")
            local new_pfx  = GUI.Val("txt_atpfx")
            if new_name and new_name ~= "" then at.name   = new_name end
            if new_pfx  and new_pfx  ~= "" then at.prefix = new_pfx  end
        end
        refresh_type_selector()
    end

    -- When type changes: save old config, load new, refresh all fields
    if effective_idx ~= _prev_type_idx and _prev_type_idx > 0 then
        sync_config_to_audio_type()
        RC.selected_type_idx = effective_idx
        sync_config_from_audio_type()
        GUI.Val("sel_type",    RC.selected_type_idx)
        GUI.Val("txt_pattern", RC.wildcard_template)
        GUI.Val("txt_bpm",     tostring(RC.music_bpm))
        GUI.Val("txt_meter",   RC.music_meter)
        GUI.Val("txt_char",    RC.dx_character)
        GUI.Val("txt_qtype",   RC.dx_quest_type)
        GUI.Val("txt_qname",   RC.dx_quest_name)
        GUI.Val("txt_line",    tostring(RC.dx_line_number))
        local at = RC.audio_types[RC.selected_type_idx]
        if at then
            GUI.Val("txt_type_name", at.name)
            GUI.Val("txt_atpfx",     at.prefix)
            GUI.Val("txt_rpath",     at.path_pattern or "{base}/$prefix/$root/$parent/")
        end
        refresh_field_list()
        refresh_custom_fields()
        refresh_ucs_toggle()
        if cur_view == 3 then refresh_ucs_tab() end
    end

    -- Continuously sync type-specific fields to RC while on Main tab
    local on_main = (cur_view == 1)
    if on_main then
        local type_name = RC.audio_types[RC.selected_type_idx]
            and RC.audio_types[RC.selected_type_idx].name or ""
        if type_name == "Music" then
            RC.music_bpm   = tonumber(GUI.Val("txt_bpm"))  or RC.music_bpm
            RC.music_meter = GUI.Val("txt_meter")           or RC.music_meter
        elseif type_name == "Dialogue" then
            RC.dx_character   = GUI.Val("txt_char")           or RC.dx_character
            RC.dx_quest_type  = GUI.Val("txt_qtype")          or RC.dx_quest_type
            RC.dx_quest_name  = GUI.Val("txt_qname")          or RC.dx_quest_name
            RC.dx_line_number = tonumber(GUI.Val("txt_line")) or RC.dx_line_number
        end
        -- Custom field values of the selected type
        local at = RC.audio_types[RC.selected_type_idx]
        if at and at.fields then
            for i, f in ipairs(at.fields) do
                if i > RC.MAX_CUSTOM_FIELDS then break end
                f.value = GUI.Val("txt_cf" .. i) or f.value
            end
        end
    end

    -- Show type-specific panels only on Main tab with the matching type
    local type_name = RC.audio_types[RC.selected_type_idx]
        and RC.audio_types[RC.selected_type_idx].name or ""
    GUI.elms_hide[5] = not (on_main and type_name == "Music")
    GUI.elms_hide[6] = not (on_main and type_name == "Dialogue")

    -- UCS tab (tab 3)
    local on_ucs = (cur_view == 3)
    if on_ucs then
        if _prev_view ~= 3 then refresh_ucs_tab() end
        local at = RC.audio_types[RC.selected_type_idx]
        if at then
            local cat_idx = GUI.Val("mnu_ucs_cat")
            if cat_idx ~= _prev_ucs_cat_idx then
                _ucs_subs = ucs_subcats_for(UCS_CATS[cat_idx])
                GUI.elms.mnu_ucs_sub.optarray = ucs_sub_names(_ucs_subs)
                GUI.Val("mnu_ucs_sub", 1)
                _prev_ucs_cat_idx = cat_idx
                _prev_ucs_sub_idx = 0   -- force the CatID update below
            end
            local sub_idx = GUI.Val("mnu_ucs_sub")
            if sub_idx ~= _prev_ucs_sub_idx then
                local entry = _ucs_subs[sub_idx]
                if entry then
                    at.ucs_catid = entry.id
                    GUI.Val("lbl_ucs_catid", "CatID:  " .. entry.id)
                end
                _prev_ucs_sub_idx = sub_idx
            end

            at.ucs_wildcard = GUI.Val("txt_ucs_pattern") or at.ucs_wildcard
            RC.ucs_creator_id = GUI.Val("txt_ucs_creator") or ""
            RC.ucs_source_id  = GUI.Val("txt_ucs_source")  or ""
            RC.ucs_user_data  = GUI.Val("txt_ucs_user")    or ""
            update_ucs_preview()
        end
    end

    -- Render tab (tab 4)
    local on_render = (cur_view == 4)

    local has_regions = (RC.region_list and #RC.region_list > 0) or false
    local has_checked = false
    local chk_r = GUI.elms.chk_regions
    if has_regions and chk_r and chk_r.optsel then
        for i, sel in ipairs(chk_r.optsel) do
            if sel and RC.region_list[i] then has_checked = true break end
        end
    end
    GUI.elms_hide[9]  = not (on_render and has_regions)
    GUI.elms_hide[12] = not (on_render and has_checked)
    if on_render then layout_render_tab(has_regions, has_checked) end

    if on_render then
        RC.render_base_dir  = GUI.Val("txt_base_dir") or ""
        RC.render_engine    = (GUI.Val("mnu_engine") == 2) and "reaper" or "direct"
        RC.direct_bit_depth = DEPTH_VALUES[GUI.Val("mnu_depth")] or 24
        RC.direct_srate     = SRATE_VALUES[GUI.Val("mnu_rate")] or 0
        local at = RC.audio_types[RC.selected_type_idx]
        if at then
            at.path_pattern = GUI.Val("txt_rpath") or at.path_pattern
        end
        if _prev_view ~= 4 then populate_region_checklist() end
        if RC.render_status ~= _prev_render_status then
            GUI.Val("lbl_render_status", RC.render_status)
            _prev_render_status = RC.render_status
        end
    end

    -- Advanced tab (tab 5)
    if cur_view == 5 then
        RC.gap_length = tonumber(GUI.Val("txt_gap")) or RC.gap_length
        if _prev_view ~= 5 then
            -- The project dictionary lives in ProjExtState, so re-read it in
            -- case the user switched project tab since we last looked.
            wildcard_dict_load()
            refresh_wildcard_list()
            refresh_cluster_labels()
            _prev_ovr_track = false      -- force one summary refresh below
        end
        -- Reading a track's overrides means four P_EXT lookups and a
        -- redraw, so only do it when the selection actually changed.
        local ovr_sel = reaper.GetSelectedTrack(0, 0)
        if ovr_sel ~= _prev_ovr_track then
            refresh_track_overrides()
            _prev_ovr_track = ovr_sel
        end
    end

    local sc      = reaper.GetProjectStateChangeCount(0)
    local cur_sel = reaper.GetSelectedTrack(0, 0)
    -- In Auto mode the item selection decides what gets built, so the
    -- region count has to react to it and not only to track selection.
    local item_n   = reaper.CountSelectedMediaItems(0)
    local item_one = item_n > 0 and reaper.GetSelectedMediaItem(0, 0) or nil

    if sc ~= _prev_state_count or cur_sel ~= _prev_sel_track
        or item_n ~= _prev_item_count or item_one ~= _prev_item_first then
        refresh_tree_view()
        _prev_state_count = sc
        _prev_sel_track   = cur_sel
        _prev_item_count  = item_n
        _prev_item_first  = item_one
    end

    _prev_type_idx = effective_idx
    _prev_view      = cur_view
end

GUI.freq = 0

GUI.exit = function()
    direct_render_abort()
    preview_clear()

    RC.render_base_dir    = GUI.Val("txt_base_dir")         or RC.render_base_dir
    RC.render_engine      = (GUI.Val("mnu_engine") == 2) and "reaper" or "direct"
    RC.direct_bit_depth   = DEPTH_VALUES[GUI.Val("mnu_depth")] or 24
    RC.direct_srate       = SRATE_VALUES[GUI.Val("mnu_rate")] or 0
    RC.ucs_creator_id     = GUI.Val("txt_ucs_creator")      or RC.ucs_creator_id
    RC.ucs_source_id      = GUI.Val("txt_ucs_source")       or RC.ucs_source_id
    RC.ucs_user_data      = GUI.Val("txt_ucs_user")         or RC.ucs_user_data
    RC.wildcard_template  = GUI.Val("txt_pattern")         or RC.wildcard_template
    RC.music_bpm          = tonumber(GUI.Val("txt_bpm"))   or RC.music_bpm
    RC.music_meter        = GUI.Val("txt_meter")            or RC.music_meter
    RC.dx_character       = GUI.Val("txt_char")             or RC.dx_character
    RC.dx_quest_type      = GUI.Val("txt_qtype")            or RC.dx_quest_type
    RC.dx_quest_name      = GUI.Val("txt_qname")            or RC.dx_quest_name
    RC.dx_line_number     = tonumber(GUI.Val("txt_line"))   or RC.dx_line_number

    local at = RC.audio_types[RC.selected_type_idx]
    if at then
        local new_name = GUI.Val("txt_type_name")
        local new_pfx  = GUI.Val("txt_atpfx")
        if new_name and new_name ~= "" then at.name   = new_name end
        if new_pfx  and new_pfx  ~= "" then at.prefix = new_pfx  end
        at.wildcard     = RC.wildcard_template
        at.path_pattern = GUI.Val("txt_rpath") or at.path_pattern
    end
    sync_config_to_audio_type()

    save_settings({
        render_base_dir   = RC.render_base_dir,
        render_engine     = RC.render_engine,
        render_keep_regions = RC.render_keep_regions,
        cluster_enabled     = RC.cluster_enabled,
        gap_length          = RC.gap_length,
        gap_use_beat        = RC.gap_use_beat,
        number_single_files = RC.number_single_files,
        warn_overwrite      = RC.warn_overwrite,
        always_track_mode   = RC.always_track_mode,
        direct_bit_depth  = RC.direct_bit_depth,
        direct_srate      = RC.direct_srate,
        ucs_creator_id    = RC.ucs_creator_id,
        ucs_source_id     = RC.ucs_source_id,
        ucs_user_data     = RC.ucs_user_data,
        wildcard_template = RC.wildcard_template,
        prefix_type       = RC.prefix_type,
        music_bpm         = RC.music_bpm,
        music_meter       = RC.music_meter,
        dx_character      = RC.dx_character,
        dx_quest_type     = RC.dx_quest_type,
        dx_quest_name     = RC.dx_quest_name,
        dx_line_number    = RC.dx_line_number,
    })
    save_audio_types(RC.audio_types)
end

-- Entry point called by the controller
function gui_start()
    local function script()
        GUI.Init()

        GUI.Val("sel_type",    RC.selected_type_idx)
        GUI.Val("txt_base_dir", RC.render_base_dir or "")
        GUI.Val("mnu_engine",  RC.render_engine == "reaper" and 2 or 1)
        GUI.Val("mnu_depth",   DEPTH_INDEX[RC.direct_bit_depth] or 2)
        GUI.Val("mnu_rate",    SRATE_INDEX[RC.direct_srate] or 1)
        GUI.Val("txt_ucs_creator", RC.ucs_creator_id or "")
        GUI.Val("txt_ucs_source",  RC.ucs_source_id  or "")
        GUI.Val("txt_ucs_user",    RC.ucs_user_data  or "")
        GUI.Val("txt_pattern", RC.wildcard_template)
        GUI.Val("txt_bpm",     tostring(RC.music_bpm))
        GUI.Val("txt_meter",   RC.music_meter)
        GUI.Val("txt_char",    RC.dx_character)
        GUI.Val("txt_qtype",   RC.dx_quest_type)
        GUI.Val("txt_qname",   RC.dx_quest_name)
        GUI.Val("txt_line",    tostring(RC.dx_line_number))

        local at0 = RC.audio_types[RC.selected_type_idx]
        if at0 then
            GUI.Val("txt_type_name", at0.name)
            GUI.Val("txt_atpfx",     at0.prefix)
            GUI.Val("txt_rpath",     at0.path_pattern or "{base}/$prefix/$root/$parent/")
        end
        refresh_type_selector()
        refresh_field_list()
        refresh_custom_fields()

        GUI.Val("lbl_render_status", RC.render_status)
        GUI.Val("txt_gap", tostring(RC.gap_length))
        refresh_cluster_labels()
        refresh_wildcard_list()
        refresh_track_overrides()
        refresh_ucs_toggle()
        refresh_license()

        -- z=8 (audio type header) not in any set → always visible
        -- z 9 and 12 are managed by layout_render_tab, like 5 and 6 on Main
        GUI.elms.tabs:update_sets({ {2, 10}, {13}, {7}, {14} })
        GUI.elms_hide[5] = true
        GUI.elms_hide[6] = true

        _prev_type_idx      = RC.selected_type_idx
        _prev_render_status = RC.render_status
        _prev_lic_status    = license_state().status
        refresh_ucs_tab()
        refresh_tree_view()

        -- After the window is scheduled, so a slow network call can never
        -- delay it opening.
        license_tick()

        reaper.defer(GUI.Main)
    end

    xpcall(script, GUI.crash)
end
