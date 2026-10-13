--@description RenderSmith: region naming and batch asset delivery for REAPER
--@version 2.0
--@author Panchuel
--@link https://github.com/panchuel/RenderSmith
--@about
--  # RenderSmith
--
--  Turns a REAPER session into delivered game-audio assets. It finds the
--  individual sounds inside your track folders, names them from the folder
--  hierarchy or the UCS standard, and renders each one to its own file in an
--  organised output tree.
--
--  Free for 7 days, then it needs a license key. The trial unlocks every
--  feature, and the key is emailed the moment you buy.
--
--  Requires Lokasenna_GUI v2, which ReaPack can install for you.
--@provides
--  [main] RenderSmith.lua
--  src/config.lua
--  src/json.lua
--  src/net.lua
--  src/license.lua
--  src/audio_types.lua
--  src/settings.lua
--  src/settings_cascade.lua
--  src/track_utils.lua
--  src/ucs_data.lua
--  src/ucs.lua
--  src/cluster.lua
--  src/wildcard_dict.lua
--  src/wildcards.lua
--  src/wav_writer.lua
--  src/journal.lua
--  src/region_store.lua
--  src/plan.lua
--  src/nameswitch.lua
--  src/regions.lua
--  src/preview.lua
--  src/render_direct.lua
--  src/render.lua
--  src/gui.lua

RC = {}   -- shared namespace; all modules read/write through this table

local _PATH = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local function load_module(name)
    local fn, err = loadfile(_PATH .. "src/" .. name)
    if not fn then
        reaper.MB("Error loading " .. name .. ":\n\n" .. tostring(err),
            "RenderSmith", 0)
        return false
    end
    fn()
    return true
end

-- Order matters. config.lua must stay first: it defines the constants the
-- rest read at load time. json, net and license come next so the licence
-- gate is available to everything after them. gui.lua must stay last, since
-- it builds every widget against the other modules' globals and gui_start()
-- runs the moment it returns.
for _, m in ipairs({
    "config.lua",
    "json.lua",
    "net.lua",
    "license.lua",
    "audio_types.lua",
    "settings.lua",
    "settings_cascade.lua",
    "track_utils.lua",
    "ucs_data.lua",
    "ucs.lua",
    "cluster.lua",
    "wildcard_dict.lua",
    "wildcards.lua",
    "wav_writer.lua",
    "journal.lua",
    "region_store.lua",
    "plan.lua",
    "nameswitch.lua",
    "regions.lua",
    "preview.lua",
    "render_direct.lua",
    "render.lua",
    "gui.lua",
}) do
    if not load_module(m) then return end
end

-- The window always opens, even with the trial over. The gate lives inside
-- the GUI, which pins itself to the License tab, because somebody holding a
-- key needs somewhere to type it.
gui_start()
