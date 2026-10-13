-- license.lua
-- Trial clock and Gumroad license activation.
--
-- What this protects against, stated plainly because the design only makes
-- sense in that light: ReaPack distributes Lua as plain text, so anyone can
-- open this file and delete the check. No obfuscation changes that in any
-- meaningful way, and bytecode would be fragile across Lua versions while
-- still being trivial to dump. This stops casual non-payment and nothing
-- more, which is the same bargain every commercial ReaScript makes.
--
-- The checksum below exists to notice hand-editing of the stored record, not
-- to resist anyone who has read this far.
--
-- Two stores, one in REAPER's ExtState and one in a file outside the REAPER
-- tree, both written on every change. The trial start is the oldest install
-- date found in either, so clearing one store cannot restart the trial.

local GUMROAD_VERIFY = "https://api.gumroad.com/v2/licenses/verify"
local DAY            = 86400
local STATE_KEY      = "rec"
local SALT           = "rs.9f2c"

-- Pure helpers. Nothing below touches reaper.* until the store section, so
-- the clock arithmetic and the response parsing stay unit-testable.

function lic_fnv1a(text)
    local hash = 0x811C9DC5
    for i = 1, #text do
        hash = hash ~ text:byte(i)
        hash = (hash * 0x01000193) & 0xFFFFFFFF
    end
    return string.format("%08x", hash)
end

local FIELDS = { "install", "last_seen", "key", "activated", "checked", "fp" }

local function is_text_field(name)
    return name == "key" or name == "fp"
end

function lic_encode(rec)
    local parts = {}
    for i, name in ipairs(FIELDS) do
        local value = rec[name]
        if value == nil then value = is_text_field(name) and "" or 0 end
        parts[i] = tostring(value)
    end
    local payload = table.concat(parts, "|")
    return payload .. "|" .. lic_fnv1a(payload .. SALT)
end

-- Returns the record, or nil plus "absent" when nothing is stored and nil
-- plus "tampered" when something is stored but does not add up. Callers must
-- treat those differently: absent means a fresh install, tampered must never
-- be rewarded with a new trial.
function lic_decode(text)
    if type(text) ~= "string" or text == "" then return nil, "absent" end

    local parts = {}
    for piece in (text .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = piece end
    if #parts ~= #FIELDS + 1 then return nil, "tampered" end

    local payload = table.concat(parts, "|", 1, #FIELDS)
    if parts[#parts] ~= lic_fnv1a(payload .. SALT) then return nil, "tampered" end

    local rec = {}
    for i, name in ipairs(FIELDS) do
        if is_text_field(name) then
            rec[name] = parts[i]
        else
            rec[name] = tonumber(parts[i])
            if not rec[name] then return nil, "tampered" end
        end
    end
    return rec
end

-- The clock the trial is measured against. Taking the high-water mark means
-- winding the system clock back cannot buy extra days, while winding it
-- forward and back again (timezones, a corrected clock) costs nothing.
function lic_effective_now(rec, now)
    return math.max(now, rec.last_seen or 0)
end

function lic_trial_days_left(rec, now, trial_days)
    local used = math.floor((lic_effective_now(rec, now) - rec.install) / DAY)
    local left = (trial_days or 7) - used
    return left > 0 and left or 0
end

-- Reads a Gumroad /v2/licenses/verify response. Returns an info table, or
-- nil plus a message fit to show the user.
function lic_parse_gumroad(body)
    local data = json_decode(body or "")
    if type(data) ~= "table" then
        return nil, "The license server sent an unreadable reply. Try again."
    end

    if data.success ~= true then
        return nil, data.message or "That license key is not valid for this product."
    end

    local p = data.purchase or {}
    if p.refunded then
        return nil, "This purchase was refunded, so the license is no longer active."
    end
    if p.chargebacked then
        return nil, "This purchase was charged back, so the license is no longer active."
    end
    -- Always nil for a one-time purchase. Checked anyway so that selling a
    -- subscription later would behave correctly without editing this.
    if p.subscription_ended_at or p.subscription_failed_at then
        return nil, "The subscription behind this license has ended."
    end

    return {
        uses    = data.uses or 0,
        email   = p.email,
        product = p.product_name,
    }
end

-- Store. Everything from here on touches reaper.* or the filesystem.

local function lic_file_path()
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        local base = os.getenv("APPDATA")
        if not base or base == "" then return nil end
        -- APPDATA's root, not a subfolder of it: creating a folder would
        -- need a shell call, and os.execute freezes REAPER.
        return base .. "\\.rendersmith"
    end
    local home = os.getenv("HOME")
    if not home or home == "" then return nil end
    return home .. "/.rendersmith"
end

local function read_all(path)
    if not path then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function write_all(path, text)
    if not path then return false end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

local function fingerprint()
    return lic_fnv1a(table.concat({
        os.getenv("COMPUTERNAME") or os.getenv("HOSTNAME") or "",
        os.getenv("USERNAME") or os.getenv("USER") or "",
        reaper.GetResourcePath() or "",
    }, "|"))
end

-- Returns rec, or nil plus "absent"/"tampered".
function lic_load()
    local a, a_why = lic_decode(reaper.GetExtState(RC.LIC_SECTION, STATE_KEY))
    local b, b_why = lic_decode(read_all(lic_file_path()))

    if not a and not b then
        -- Tampering in either store outweighs absence in the other.
        local why = (a_why == "tampered" or b_why == "tampered")
            and "tampered" or "absent"
        return nil, why
    end
    if a and not b then return a end
    if b and not a then return b end

    -- Both readable: start from the fresher record, then pull the oldest
    -- install date forward so neither store can be used to reset the trial.
    local base = (a.last_seen >= b.last_seen) and a or b
    base.install   = math.min(a.install, b.install)
    base.last_seen = math.max(a.last_seen, b.last_seen)

    if base.key == "" then
        local other = (a.key ~= "" and a) or (b.key ~= "" and b) or nil
        if other then
            base.key, base.activated = other.key, other.activated
            base.checked, base.fp    = other.checked, other.fp
        end
    end
    return base
end

function lic_save(rec)
    local blob = lic_encode(rec)
    reaper.SetExtState(RC.LIC_SECTION, STATE_KEY, blob, true)
    write_all(lic_file_path(), blob)
end

function lic_clear()
    local now = os.time()
    local rec = lic_load() or { install = now, last_seen = now }
    rec.key, rec.activated, rec.checked, rec.fp = "", 0, 0, ""
    lic_save(rec)
end

-- Public state. Cached briefly, because the GUI asks on every frame.

local _cached, _cached_at = nil, -1e9

function license_state(force)
    if not force and _cached and (reaper.time_precise() - _cached_at) < 5 then
        return _cached
    end

    local now = os.time()
    local rec, why = lic_load()

    if not rec then
        if why == "tampered" then
            _cached, _cached_at =
                { status = "expired", reason = "tampered", days_left = 0, key = "" },
                reaper.time_precise()
            return _cached
        end
        -- First run. Written at once: if a gate later returns early, GUI.exit
        -- never runs and the trial start would otherwise go unrecorded.
        rec = { install = now, last_seen = now, key = "",
                activated = 0, checked = 0, fp = "" }
        lic_save(rec)
    end

    local effective = lic_effective_now(rec, now)

    -- Persist the high-water mark sparingly: this runs often, and writing
    -- both stores every frame would gain nothing.
    if now > (rec.last_seen or 0) + 3600 then
        rec.last_seen = now
        lic_save(rec)
    end

    local state
    if rec.key ~= "" and rec.activated > 0 then
        local base  = rec.checked > 0 and rec.checked or rec.activated
        local stale = effective - base
        if stale > RC.OFFLINE_GRACE_DAYS * DAY then
            state = { status = "expired", reason = "stale",
                      days_left = 0, key = rec.key }
        else
            state = { status = "licensed", days_left = 0, key = rec.key,
                      checked = rec.checked,
                      revalidate_due = stale > RC.REVALIDATE_DAYS * DAY }
        end
    else
        local left = lic_trial_days_left(rec, now, RC.TRIAL_DAYS)
        state = {
            status    = left > 0 and "trial" or "expired",
            reason    = left > 0 and "trial" or "trial_over",
            days_left = left,
            key       = "",
        }
    end

    _cached, _cached_at = state, reaper.time_precise()
    return state
end

-- The gate for action entry points, shaped like validate_preconditions() so
-- its call sites read the same as the ones already there.
function license_require()
    local st = license_state()
    if st.status == "licensed" or st.status == "trial" then return true end

    if st.reason == "stale" then
        return false, RC.PRODUCT_NAME .. " could not confirm your license.\n\n" ..
            "It has been offline too long. Connect to the internet and open " ..
            "the License tab to re-check."
    elseif st.reason == "tampered" then
        return false, "The stored license record is unreadable.\n\n" ..
            "Enter your license key again in the License tab."
    end
    return false, "Your " .. RC.PRODUCT_NAME .. " trial has ended.\n\n" ..
        "Enter your license key in the License tab to keep going."
end

-- Activation, from the License tab's button. Calls on_done(ok, info_or_msg).
function license_activate(key, on_done)
    key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then
        on_done(false, "Paste your license key first.")
        return
    end

    local now = os.time()
    local rec = lic_load() or { install = now, last_seen = now, key = "",
                                activated = 0, checked = 0, fp = "" }
    local fp = fingerprint()

    -- Gumroad's `uses` counts verifications, not machines, and there is no
    -- deactivate endpoint to undo one. So only a genuinely new machine may
    -- bump it: re-activating this install must not inflate the number the
    -- seat policy is read from.
    local repeat_machine = (rec.fp == fp and rec.key == key)

    net_post_form(GUMROAD_VERIFY, {
        license_key          = key,
        product_id           = RC.GUMROAD_PRODUCT_ID,
        increment_uses_count = repeat_machine and "false" or "true",
    }, function(body, reason)
        if not body then
            on_done(false, net_error_text(reason))
            return
        end

        local info, msg = lic_parse_gumroad(body)
        if not info then
            on_done(false, msg)
            return
        end

        rec.key       = key
        rec.activated = rec.activated > 0 and rec.activated or os.time()
        rec.checked   = os.time()
        rec.fp        = fp
        lic_save(rec)
        license_state(true)
        on_done(true, info)
    end)
end

-- Silent re-check. Never increments the counter. A network failure is not a
-- license failure: the grace window in license_state is what eventually acts
-- on a run of them.
function license_revalidate(on_done)
    local rec = lic_load()
    if not rec or rec.key == "" then
        if on_done then on_done(nil, "no_key") end
        return
    end

    net_post_form(GUMROAD_VERIFY, {
        license_key          = rec.key,
        product_id           = RC.GUMROAD_PRODUCT_ID,
        increment_uses_count = "false",
    }, function(body, reason)
        if not body then
            if on_done then on_done(nil, reason) end
            return
        end

        local info, msg = lic_parse_gumroad(body)
        if info then
            rec.checked = os.time()
            lic_save(rec)
        else
            -- An actual rejection: refunded, charged back, or disabled from
            -- the Gumroad dashboard. That is the revocation path.
            lic_clear()
        end
        license_state(true)
        if on_done then on_done(info ~= nil, msg) end
    end)
end

-- Local only, because Gumroad has no deactivate endpoint. This frees the
-- machine so the key can be entered elsewhere; it cannot return the seat
-- server-side.
function license_deactivate()
    lic_clear()
    license_state(true)
end

-- Called once at startup. Fires a background re-check when the last
-- confirmation is old enough, and never delays the window opening.
function license_tick()
    local st = license_state(true)
    if st.status == "licensed" and st.revalidate_due then
        license_revalidate(nil)
    end
end
