-- test_license.lua
-- Mock-REAPER suite for json.lua, net.lua helpers and license.lua.
-- Run from the "Region Creator" directory.

local passed, failed = 0, 0

local function ok(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. label)
    end
end

local function eq(got, want, label)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL: %s\n   got:  %s\n   want: %s",
            label, tostring(got), tostring(want)))
    end
end

-- Mock REAPER and a controllable clock

local ext_store = {}
local fake_time = 1000000000    -- os.time
local fake_prec = 0             -- reaper.time_precise

reaper = {
    GetExtState = function(sec, key)
        return (ext_store[sec] or {})[key] or ""
    end,
    SetExtState = function(sec, key, val, _)
        ext_store[sec] = ext_store[sec] or {}
        ext_store[sec][key] = val
    end,
    DeleteExtState = function(sec, key, _)
        if ext_store[sec] then ext_store[sec][key] = nil end
    end,
    time_precise    = function() return fake_prec end,
    GetResourcePath = function() return "C:\\fake\\reaper" end,
    ExecProcess     = function() return "" end,
    defer           = function() end,
    MB              = function() end,
}

local real_os_time = os.time
os.time = function() return fake_time end

-- The file store is redirected by pointing APPDATA at a scratch folder; see
-- the runner script. Wipe it between cases through this helper.
local function store_file_path()
    local base = os.getenv("APPDATA")
    return base and (base .. "\\.rendersmith") or nil
end

local function reset_stores()
    ext_store = {}
    local p = store_file_path()
    if p then os.remove(p) end
    -- license_state caches for 5 seconds of time_precise; step past it.
    fake_prec = fake_prec + 100
end

-- Resolve the product folder from this file, so the suite runs from
-- anywhere rather than only from the product directory.
local _here = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
local _src  = _here .. "../RenderSmith/src/"

RC = {}
dofile(_src .. "config.lua")
dofile(_src .. "json.lua")
dofile(_src .. "net.lua")
dofile(_src .. "license.lua")

local DAY = 86400

-- json.lua

do
    local v = json_decode('{"a":1,"b":"two"}')
    eq(type(v), "table", "json: object decodes to table")
    eq(v.a, 1, "json: number field")
    eq(v.b, "two", "json: string field")

    v = json_decode('{"success":true,"uses":3,"purchase":{"email":"a@b.c","refunded":false}}')
    eq(v.success, true, "json: true")
    eq(v.uses, 3, "json: integer")
    eq(v.purchase.email, "a@b.c", "json: nested object")
    eq(v.purchase.refunded, false, "json: false is preserved, not dropped")

    v = json_decode('{"n":null,"after":7}')
    eq(v.n, nil, "json: null decodes to nil")
    eq(v.after, 7, "json: field after a null still parses")

    v = json_decode('{"s":"a\\"b\\\\c\\nd"}')
    eq(v.s, 'a"b\\c\nd', "json: escape sequences")

    v = json_decode('{"s":"\\u0041\\u00e9"}')
    eq(v.s, "A\u{e9}", "json: \\u escapes become utf8")

    v = json_decode('[1,2,3]')
    eq(#v, 3, "json: array length")
    eq(v[2], 2, "json: array element")

    v = json_decode('[1,null,3]')
    eq(v[3], 3, "json: null in an array does not shift later elements")

    v = json_decode('{"a":-1.5e3}')
    eq(v.a, -1500.0, "json: signed exponent number")

    v = json_decode('[]')
    eq(type(v), "table", "json: empty array")
    v = json_decode('{}')
    eq(type(v), "table", "json: empty object")

    ok(json_decode("") == nil, "json: empty input is an error")
    ok(json_decode("   ") == nil, "json: whitespace only is an error")
    ok(json_decode('{"a":1} trailing') == nil, "json: trailing data is an error")
    ok(json_decode('{"a":1') == nil, "json: truncated object is an error")
    ok(json_decode('{"a":"unterminated') == nil, "json: unterminated string is an error")
    ok(json_decode('{bad:1}') == nil, "json: unquoted key is an error")
    ok(json_decode(nil) == nil, "json: nil input is an error")
end

-- net.lua url encoding

do
    eq(net_url_encode("abc-._~"), "abc-._~", "net: unreserved characters pass through")
    eq(net_url_encode("a b"), "a%20b", "net: space is encoded")
    eq(net_url_encode('a"b&c=d'), "a%22b%26c%3Dd", "net: shell and form metacharacters encoded")
    eq(net_url_encode("K3Y-1234"), "K3Y-1234", "net: a typical licence key is untouched")
end

-- checksum, encode, decode

do
    local rec = { install = 100, last_seen = 200, key = "ABC",
                  activated = 150, checked = 180, fp = "deadbeef" }
    local blob = lic_encode(rec)
    local back = lic_decode(blob)
    ok(back ~= nil, "record: round trips")
    eq(back.install, 100, "record: install survives")
    eq(back.key, "ABC", "record: key survives")
    eq(back.fp, "deadbeef", "record: fingerprint survives")

    local _, why = lic_decode("")
    eq(why, "absent", "record: empty is absent, not tampered")
    _, why = lic_decode(nil)
    eq(why, "absent", "record: nil is absent")

    -- Flip a digit in the payload, leave the checksum alone.
    local bad = blob:gsub("^100|", "999|", 1)
    _, why = lic_decode(bad)
    eq(why, "tampered", "record: edited payload is detected")

    _, why = lic_decode("1|2|3")
    eq(why, "tampered", "record: wrong field count is tampered")

    _, why = lic_decode("a|b|c|d|e|f|g")
    eq(why, "tampered", "record: non-numeric install is tampered")

    -- An empty key and fp must survive, since that is the trial state.
    local trial = { install = 1, last_seen = 2, key = "", activated = 0,
                    checked = 0, fp = "" }
    local t2 = lic_decode(lic_encode(trial))
    ok(t2 ~= nil, "record: trial-shaped record round trips")
    eq(t2.key, "", "record: empty key survives")
end

-- trial arithmetic

do
    local rec = { install = 1000 * DAY, last_seen = 1000 * DAY }

    eq(lic_trial_days_left(rec, 1000 * DAY, 7), 7, "trial: day 0 leaves 7")
    eq(lic_trial_days_left(rec, 1000 * DAY + 1, 7), 7, "trial: one second in still leaves 7")
    eq(lic_trial_days_left(rec, 1001 * DAY, 7), 6, "trial: after one day, 6 left")
    eq(lic_trial_days_left(rec, 1006 * DAY + DAY - 1, 7), 1,
        "trial: a second before day 7 still leaves 1")
    eq(lic_trial_days_left(rec, 1007 * DAY, 7), 0, "trial: exactly 7 days is over")
    eq(lic_trial_days_left(rec, 1099 * DAY, 7), 0, "trial: long past is still 0, never negative")

    -- Clock wound back: the high-water mark is what counts.
    local used = { install = 1000 * DAY, last_seen = 1005 * DAY }
    eq(lic_effective_now(used, 1001 * DAY), 1005 * DAY,
        "trial: rolling the clock back does not rewind the effective clock")
    eq(lic_trial_days_left(used, 1000 * DAY, 7), 2,
        "trial: rolling back to install day still only leaves 2")
    eq(lic_trial_days_left(used, 1006 * DAY, 7), 1,
        "trial: moving forward past last_seen is honoured")
end

-- Gumroad response parsing

do
    local good = '{"success":true,"uses":2,"purchase":{"email":"a@b.c",' ..
                 '"product_name":"RenderSmith","refunded":false,' ..
                 '"chargebacked":false,"subscription_ended_at":null}}'
    local info, msg = lic_parse_gumroad(good)
    ok(info ~= nil, "gumroad: a valid response is accepted")
    eq(info and info.uses, 2, "gumroad: uses is read")
    eq(info and info.email, "a@b.c", "gumroad: email is read")

    info, msg = lic_parse_gumroad(
        '{"success":false,"message":"That license does not exist for the provided product"}')
    ok(info == nil, "gumroad: success=false is rejected")
    eq(msg, "That license does not exist for the provided product",
        "gumroad: the server message is passed through")

    info, msg = lic_parse_gumroad('{"success":true,"uses":1,"purchase":{"refunded":true}}')
    ok(info == nil, "gumroad: a refunded purchase is rejected")
    ok(msg ~= nil and msg:find("refunded") ~= nil, "gumroad: refund message mentions the refund")

    info, msg = lic_parse_gumroad('{"success":true,"uses":1,"purchase":{"chargebacked":true}}')
    ok(info == nil, "gumroad: a charged-back purchase is rejected")

    info = lic_parse_gumroad(
        '{"success":true,"uses":1,"purchase":{"subscription_ended_at":"2026-01-01"}}')
    ok(info == nil, "gumroad: an ended subscription is rejected")

    info = lic_parse_gumroad('{"success":true,"uses":1,"purchase":{"subscription_failed_at":"x"}}')
    ok(info == nil, "gumroad: a failed subscription is rejected")

    info, msg = lic_parse_gumroad("not json at all")
    ok(info == nil, "gumroad: a non-JSON body is rejected")
    ok(msg ~= nil and msg:find("unreadable") ~= nil, "gumroad: unreadable body says so")

    info = lic_parse_gumroad("")
    ok(info == nil, "gumroad: an empty body is rejected")

    info = lic_parse_gumroad('{"success":true}')
    ok(info ~= nil, "gumroad: success with no purchase block is still valid")

    info = lic_parse_gumroad('"just a string"')
    ok(info == nil, "gumroad: a bare JSON string is rejected")
end

-- Two stores: the merge rules

do
    reset_stores()
    local old = { install = 500 * DAY, last_seen = 500 * DAY, key = "",
                  activated = 0, checked = 0, fp = "" }
    local new = { install = 900 * DAY, last_seen = 950 * DAY, key = "",
                  activated = 0, checked = 0, fp = "" }

    -- ExtState holds the old install, the file holds a newer one.
    reaper.SetExtState(RC.LIC_SECTION, "rec", lic_encode(old), true)
    local f = io.open(store_file_path(), "w")
    f:write(lic_encode(new)); f:close()

    local rec = lic_load()
    ok(rec ~= nil, "stores: merge returns a record")
    eq(rec.install, 500 * DAY, "stores: the oldest install date wins")
    eq(rec.last_seen, 950 * DAY, "stores: the newest last_seen wins")

    -- Only ExtState.
    reset_stores()
    reaper.SetExtState(RC.LIC_SECTION, "rec", lic_encode(old), true)
    rec = lic_load()
    eq(rec and rec.install, 500 * DAY, "stores: ExtState alone is enough")

    -- Only the file.
    reset_stores()
    f = io.open(store_file_path(), "w")
    f:write(lic_encode(old)); f:close()
    rec = lic_load()
    eq(rec and rec.install, 500 * DAY, "stores: the file alone is enough")

    -- A key present in only one store is recovered.
    reset_stores()
    local keyed = { install = 600 * DAY, last_seen = 600 * DAY, key = "KEY-1",
                    activated = 601 * DAY, checked = 602 * DAY, fp = "aabbccdd" }
    local blank = { install = 600 * DAY, last_seen = 700 * DAY, key = "",
                    activated = 0, checked = 0, fp = "" }
    reaper.SetExtState(RC.LIC_SECTION, "rec", lic_encode(blank), true)
    f = io.open(store_file_path(), "w")
    f:write(lic_encode(keyed)); f:close()
    rec = lic_load()
    eq(rec and rec.key, "KEY-1", "stores: a key is recovered from the other store")
    eq(rec and rec.activated, 601 * DAY, "stores: activation data follows the key")

    -- Tampered plus absent must report tampered, not absent.
    reset_stores()
    reaper.SetExtState(RC.LIC_SECTION, "rec", "garbage|1|2", true)
    local _, why = lic_load()
    eq(why, "tampered", "stores: tampered beats absent")

    -- Both gone.
    reset_stores()
    local r2, why2 = lic_load()
    ok(r2 == nil, "stores: nothing stored returns nil")
    eq(why2, "absent", "stores: nothing stored is absent")
end

-- license_state and license_require

do
    -- First run records the trial start and reports a full trial.
    reset_stores()
    fake_time = 2000 * DAY
    local st = license_state(true)
    eq(st.status, "trial", "state: first run is a trial")
    eq(st.days_left, 7, "state: first run leaves 7 days")
    ok(reaper.GetExtState(RC.LIC_SECTION, "rec") ~= "",
        "state: first run writes the record immediately")

    -- Mid-trial.
    fake_time = 2003 * DAY
    st = license_state(true)
    eq(st.status, "trial", "state: still a trial on day 3")
    eq(st.days_left, 4, "state: day 3 leaves 4")

    -- Trial over.
    fake_time = 2007 * DAY
    st = license_state(true)
    eq(st.status, "expired", "state: the trial ends after 7 days")
    eq(st.reason, "trial_over", "state: the reason is the trial ending")
    local allowed, msg = license_require()
    ok(allowed == false, "require: an expired trial is blocked")
    ok(msg and msg:find("trial has ended"), "require: the message names the trial")

    -- A licensed record.
    reset_stores()
    fake_time = 2000 * DAY
    lic_save({ install = 1990 * DAY, last_seen = 2000 * DAY, key = "KEY-9",
               activated = 1995 * DAY, checked = 1999 * DAY, fp = "ff00ff00" })
    st = license_state(true)
    eq(st.status, "licensed", "state: an activated record is licensed")
    eq(st.key, "KEY-9", "state: the key is reported")
    ok(license_require() == true, "require: a licensed install is allowed")
    ok(not st.revalidate_due, "state: a recent check needs no revalidation")

    -- Past the re-check interval but inside the grace window.
    fake_time = 1999 * DAY + RC.REVALIDATE_DAYS * DAY + DAY
    st = license_state(true)
    eq(st.status, "licensed", "state: past the re-check interval it still works")
    ok(st.revalidate_due, "state: and it asks for a background re-check")
    ok(license_require() == true, "require: still allowed while only due a re-check")

    -- Past the offline grace window.
    fake_time = 1999 * DAY + RC.OFFLINE_GRACE_DAYS * DAY + 2 * DAY
    st = license_state(true)
    eq(st.status, "expired", "state: beyond the grace window it stops")
    eq(st.reason, "stale", "state: the reason is staleness, not the trial")
    allowed, msg = license_require()
    ok(allowed == false, "require: a stale licence is blocked")
    ok(msg and msg:find("offline too long"), "require: the message explains staleness")

    -- An expired trial must never silently become a fresh one.
    reset_stores()
    fake_time = 3000 * DAY
    license_state(true)
    fake_time = 3010 * DAY
    eq(license_state(true).status, "expired", "state: trial over at day 10")
    fake_time = 3011 * DAY
    eq(license_state(true).status, "expired", "state: and it stays over")

    -- Tampering is not rewarded with a new trial.
    reset_stores()
    reaper.SetExtState(RC.LIC_SECTION, "rec", "1|2|3|4", true)
    st = license_state(true)
    eq(st.status, "expired", "state: a tampered record is expired, not a new trial")
    eq(st.reason, "tampered", "state: and it says so")

    -- Deactivation returns the install to the trial clock it already had.
    reset_stores()
    fake_time = 4000 * DAY
    lic_save({ install = 3999 * DAY, last_seen = 4000 * DAY, key = "K",
               activated = 3999 * DAY, checked = 4000 * DAY, fp = "x" })
    eq(license_state(true).status, "licensed", "deactivate: licensed first")
    license_deactivate()
    st = license_state(true)
    eq(st.status, "trial", "deactivate: falls back to the remaining trial")
    eq(st.days_left, 6, "deactivate: the original install date still governs")
end

-- Activation and revalidation, with the network mocked out

do
    local real_post = net_post_form
    local captured

    local function respond(body, reason)
        net_post_form = function(_, fields, cb)
            captured = fields
            cb(body, reason)
        end
    end

    reset_stores()
    fake_time = 6000 * DAY
    license_state(true)

    respond('{"success":true,"uses":1,"purchase":{"email":"a@b.c"}}', nil)

    local got_ok
    license_activate("KEY-AAA", function(o) got_ok = o end)
    ok(got_ok == true, "activate: a valid key activates")
    eq(captured.license_key, "KEY-AAA", "activate: the key is sent")
    eq(captured.increment_uses_count, "true",
        "activate: a new machine bumps Gumroad's uses counter")
    eq(license_state(true).status, "licensed", "activate: the state becomes licensed")

    -- The seat guard: Gumroad's uses counts verifications and cannot be
    -- decremented, so re-activating this same install must not inflate it.
    license_activate("KEY-AAA", function() end)
    eq(captured.increment_uses_count, "false",
        "activate: re-activating the same machine does not bump the counter")

    license_activate("KEY-BBB", function() end)
    eq(captured.increment_uses_count, "true",
        "activate: a different key on this machine does bump the counter")

    -- An empty key must never reach the network.
    captured = nil
    local empty_ok
    license_activate("   ", function(o) empty_ok = o end)
    ok(empty_ok == false, "activate: an empty key is refused")
    ok(captured == nil, "activate: an empty key never hits the network")

    license_activate("  KEY-CCC  ", function() end)
    eq(captured.license_key, "KEY-CCC", "activate: surrounding whitespace is trimmed")

    -- A rejected key must leave the trial record untouched.
    reset_stores()
    fake_time = 6000 * DAY
    license_state(true)
    respond('{"success":false,"message":"nope"}', nil)
    local bad_ok
    license_activate("BAD", function(o) bad_ok = o end)
    ok(bad_ok == false, "activate: a rejected key reports failure")
    eq(license_state(true).status, "trial",
        "activate: a rejected key leaves the trial as it was")

    -- A network failure must not be reported as an invalid key.
    respond(nil, "timeout")
    local net_ok, net_msg
    license_activate("KEY-AAA", function(o, m) net_ok, net_msg = o, m end)
    ok(net_ok == false, "activate: a network failure fails")
    ok(net_msg ~= nil and net_msg:find("Could not reach") ~= nil,
        "activate: a network failure says so rather than blaming the key")

    -- Revalidation.
    local function licensed_record()
        reset_stores()
        fake_time = 6000 * DAY
        lic_save({ install = 5998 * DAY, last_seen = 6000 * DAY, key = "KEY-R",
                   activated = 5999 * DAY, checked = 5999 * DAY, fp = "zz" })
    end

    licensed_record()
    captured = nil
    respond('{"success":true,"uses":5,"purchase":{}}', nil)
    license_revalidate(nil)
    eq(captured.increment_uses_count, "false",
        "revalidate: never bumps the counter")
    eq(license_state(true).status, "licensed",
        "revalidate: a good check keeps it licensed")

    -- A key disabled in the Gumroad dashboard is the revocation path.
    respond('{"success":false,"message":"This license key has been disabled"}', nil)
    license_revalidate(nil)
    eq(license_state(true).status, "trial",
        "revalidate: a disabled key clears the licence")

    -- But a network failure must never clear it.
    licensed_record()
    respond(nil, "timeout")
    license_revalidate(nil)
    eq(license_state(true).status, "licensed",
        "revalidate: a network failure leaves the licence alone")

    -- A refund found during revalidation also revokes.
    licensed_record()
    respond('{"success":true,"uses":1,"purchase":{"refunded":true}}', nil)
    license_revalidate(nil)
    eq(license_state(true).status, "trial",
        "revalidate: a refund clears the licence")

    net_post_form = real_post
end

-- The 5 second cache

do
    reset_stores()
    fake_time = 5000 * DAY
    license_state(true)
    local first = license_state()
    fake_time = 5099 * DAY            -- would be expired if recomputed
    eq(license_state().status, first.status, "cache: a repeat call inside 5s is cached")
    fake_prec = fake_prec + 10
    eq(license_state().status, "expired", "cache: it recomputes once the window passes")
end

-- net.lua script generation, against a real filesystem
--
-- The bug this covers: the Windows branch built its filename with a single
-- backslash, so Lua read it as a carriage-return escape. The path then held
-- a control character, io.open failed, and activation could never have
-- worked on Windows at all.
--
-- None of the activation tests above could see it, because they replace
-- net_post_form wholesale. Platform-specific code has to be exercised for
-- real, against a real filesystem.

do
    local root = os.getenv("APPDATA")
    reaper.GetResourcePath = function() return root end

    local sep = package.config:sub(1, 1)
    local script = root .. sep .. "Scripts" .. sep ..
        (sep == "\\" and "rs_net.cmd" or "rs_net.sh")

    local execed
    reaper.ExecProcess = function(cmd) execed = cmd; return "" end

    os.remove(script)

    local started = net_post_form("https://api.gumroad.com/v2/licenses/verify", {
        license_key          = "RS-TEST-0001",
        product_id           = "WJ3xqLN8aPbnaTRsSrU8oA==",
        increment_uses_count = "false",
    }, function() end)

    ok(started == true, "net: the request starts, so the script file opened")
    ok(execed ~= nil, "net: a command was handed to ExecProcess")

    -- A control character in the path is exactly how the bug showed up.
    ok(not script:find("%c"), "net: the script path holds no control characters")

    local f = io.open(script, "r")
    ok(f ~= nil, "net: the script was written to disk")
    local body = f and f:read("*a") or ""
    if f then f:close() end

    ok(body:find("curl", 1, true) ~= nil, "net: the script calls curl")
    ok(body:find("WJ3xqLN8aPbnaTRsSrU8oA%3D%3D", 1, true) ~= nil,
        "net: the base64 product id is percent-encoded, so = survives the form body")
    ok(body:find("WJ3xqLN8aPbnaTRsSrU8oA==", 1, true) == nil,
        "net: and the raw = is not sent unencoded")
    ok(body:find("rs_net.txt.tmp", 1, true) ~= nil,
        "net: curl writes to a .tmp name")
    ok(body:find("increment_uses_count=false", 1, true) ~= nil,
        "net: the increment flag is sent as given")

    -- The rename must be conditional, or a failed curl would publish an
    -- empty body as if it were a real answer.
    if sep == "\\" then
        ok(body:find("if not errorlevel 1", 1, true) ~= nil,
            "net: the rename only happens when curl exited clean")
    else
        ok(body:find("if curl", 1, true) ~= nil,
            "net: the rename only happens when curl exited clean")
    end

    -- A second call while one is in flight must be refused, not allowed to
    -- fight over the same response file.
    local busy_reason
    net_post_form("https://example.invalid", { a = "1" },
        function(_, reason) busy_reason = reason end)
    eq(busy_reason, "busy", "net: an overlapping request is refused")

    os.remove(script)
end

os.time = real_os_time

print(string.format("\ntest_license: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
