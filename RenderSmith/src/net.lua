-- net.lua
-- A single asynchronous HTTP POST, with no REAPER extension required.
--
-- REAPER exposes no HTTP API, so this shells out to curl and polls for a
-- response file, the same shape as the folder picker in gui.lua. Three
-- deliberate differences:
--
--   * curl writes to a .tmp name and the script renames it only after curl
--     exits clean, so the poll can never read a half-written body.
--   * the poll gives up on a deadline. The picker's poll defers forever if
--     its file never appears, which would leak a defer loop for the rest of
--     the session.
--   * curl is probed only after a timeout, never up front, so the happy path
--     stays free of blocking calls and the failure still gets a precise
--     message.
--
-- curl ships with Windows 10 1803 and later, with every macOS, and with
-- effectively every desktop Linux. There is no PowerShell fallback: it would
-- be forty lines of quoting to serve a vanishingly small population, and the
-- error message already says what to do.

local TIMEOUT_SEC  = 20
local CURL_MAX_SEC = 15   -- curl's own limit, below ours so it loses first

local _busy = false

local function paths()
    local sep = package.config:sub(1, 1)
    local dir = reaper.GetResourcePath() .. sep .. "Scripts"
    local out = dir .. sep .. "rs_net.txt"
    return sep, dir, out
end

-- Percent-encodes everything outside the unreserved set, which leaves the
-- value safe to drop into a shell script unquoted-adjacent.
function net_url_encode(value)
    return (tostring(value):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function form_body(fields)
    local parts = {}
    for key, value in pairs(fields) do
        parts[#parts + 1] = net_url_encode(key) .. "=" .. net_url_encode(value)
    end
    table.sort(parts)   -- stable order keeps the generated script diffable
    return table.concat(parts, "&")
end

-- One blocking probe, only ever reached after a request already failed.
local function curl_missing()
    local ret = reaper.ExecProcess("curl --version", 3000)
    if not ret or ret == "" then return true end
    return not ret:lower():find("curl")
end

-- Posts `fields` as application/x-www-form-urlencoded and calls
-- on_done(body, nil) or on_done(nil, reason), reason being "busy",
-- "no_curl", "timeout" or "write_failed". Returns false if it could not even
-- start. The callback always runs exactly once on the paths that start.
function net_post_form(url, fields, on_done)
    if _busy then
        on_done(nil, "busy")
        return false
    end

    local sep, dir, out = paths()
    local tmp  = out .. ".tmp"
    local body = form_body(fields)

    os.remove(out)
    os.remove(tmp)

    local script_file
    if sep == "\\" then
        -- cmd.exe expands % inside a batch file: %3 is the third argument, so
        -- a percent-encoded value loses every escape it has. A base64 product
        -- id ending in "==" encodes to "%3D%3D" and arrives as "DD", which the
        -- licence server then reports as an unknown product. Doubling every
        -- percent is how a batch file passes one through literally.
        local function batch_safe(text)
            return (text:gsub("%%", "%%%%"))
        end

        script_file = dir .. sep .. "rs_net.cmd"
        local f = io.open(script_file, "w")
        if not f then on_done(nil, "write_failed"); return false end
        f:write("@echo off\n")
        f:write(string.format(
            'curl.exe -s -m %d --data "%s" "%s" > "%s" 2>nul\n',
            CURL_MAX_SEC, batch_safe(body), batch_safe(url), batch_safe(tmp)))
        f:write(string.format('if not errorlevel 1 move /Y "%s" "%s" >nul\n',
            batch_safe(tmp), batch_safe(out)))
        f:write(string.format('del "%s" >nul 2>&1\n', batch_safe(tmp)))
        f:close()
        reaper.ExecProcess('cmd.exe /C "' .. script_file .. '"', -1)
    else
        script_file = dir .. sep .. "rs_net.sh"
        local f = io.open(script_file, "w")
        if not f then on_done(nil, "write_failed"); return false end
        f:write("#!/bin/sh\n")
        f:write(string.format(
            'if curl -s -m %d --data "%s" "%s" > "%s" 2>/dev/null; then\n',
            CURL_MAX_SEC, body, url, tmp))
        f:write(string.format('  mv -f "%s" "%s"\n', tmp, out))
        f:write("else\n")
        f:write(string.format('  rm -f "%s"\n', tmp))
        f:write("fi\n")
        f:close()
        reaper.ExecProcess('/bin/sh "' .. script_file .. '"', -1)
    end

    _busy = true
    local deadline = reaper.time_precise() + TIMEOUT_SEC

    local function finish(result, reason)
        _busy = false
        os.remove(script_file)
        on_done(result, reason)
    end

    local function poll()
        local f = io.open(out, "r")
        if f then
            local text = f:read("*a")
            f:close()
            os.remove(out)
            finish(text, nil)
            return
        end

        if reaper.time_precise() > deadline then
            os.remove(tmp)
            finish(nil, curl_missing() and "no_curl" or "timeout")
            return
        end

        reaper.defer(poll)
    end

    reaper.defer(poll)
    return true
end

-- Human-readable text for the reasons above, so callers do not each invent
-- their own wording.
function net_error_text(reason)
    if reason == "no_curl" then
        return "curl was not found on this system.\n\n" ..
               "curl ships with Windows 10 (1803 and later) and with macOS. " ..
               "On Linux, install it with your package manager."
    elseif reason == "timeout" then
        return "Could not reach the license server.\n\n" ..
               "Check your internet connection and try again."
    elseif reason == "busy" then
        return "A license check is already running. Wait a moment and retry."
    elseif reason == "write_failed" then
        return "Could not write to the REAPER Scripts folder.\n\n" ..
               "Check the folder's permissions."
    end
    return "Unexpected network error: " .. tostring(reason)
end
