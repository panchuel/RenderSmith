-- json.lua
-- Minimal JSON decoder, read only.
--
-- Hand-written rather than vendored because the only JSON this tool ever
-- sees is a license-check response, and staying dependency-free keeps the
-- ReaPack manifest to files we own. No reaper.* calls in here, so the parser
-- is unit-testable without REAPER in the loop.
--
-- JSON null decodes to nil, so a null field and a missing field cannot be
-- told apart. Every null the license API returns means "not set", so that
-- distinction would carry no information anyway.

local ESCAPES = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

-- Every parser below returns `next_index, value` on success and `nil, errmsg`
-- on failure. The index comes first on purpose: a legitimate `false` or a
-- null decoded to nil would otherwise be indistinguishable from an error.
local parse_value

local function skip_ws(s, i)
    local _, stop = s:find("^[ \t\r\n]*", i)
    return stop + 1
end

local function parse_string(s, i)
    -- i points at the opening quote.
    local parts = {}
    local pos   = i + 1

    while true do
        local nxt = s:find('[\\"]', pos)
        if not nxt then return nil, "unterminated string" end

        if nxt > pos then parts[#parts + 1] = s:sub(pos, nxt - 1) end

        if s:sub(nxt, nxt) == '"' then
            return nxt + 1, table.concat(parts)
        end

        -- Backslash: one escape sequence follows.
        local esc = s:sub(nxt + 1, nxt + 1)
        if ESCAPES[esc] then
            parts[#parts + 1] = ESCAPES[esc]
            pos = nxt + 2
        elseif esc == "u" then
            local hex = s:sub(nxt + 2, nxt + 5)
            if not hex:match("^%x%x%x%x$") then return nil, "bad \\u escape" end
            -- Lone surrogates are passed through as-is; the license API never
            -- emits them, and guessing a pair would be worse than literal.
            parts[#parts + 1] = utf8.char(tonumber(hex, 16))
            pos = nxt + 6
        else
            return nil, "bad escape sequence"
        end
    end
end

local function parse_number(s, i)
    local text = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not text or text == "" then return nil, "bad number" end
    local value = tonumber(text)
    if not value then return nil, "bad number" end
    return i + #text, value
end

local function parse_array(s, i)
    local out = {}
    local pos = skip_ws(s, i + 1)

    if s:sub(pos, pos) == "]" then return pos + 1, out end

    -- Counted rather than `out[#out + 1]`: a null element decodes to nil, and
    -- appending by length would then silently shift every later element down.
    local n = 0

    while true do
        local ni, value = parse_value(s, pos)
        if not ni then return nil, value end
        n = n + 1
        out[n] = value

        pos = skip_ws(s, ni)
        local c = s:sub(pos, pos)
        if c == "]" then return pos + 1, out end
        if c ~= "," then return nil, "expected , or ] in array" end
        pos = skip_ws(s, pos + 1)
    end
end

local function parse_object(s, i)
    local out = {}
    local pos = skip_ws(s, i + 1)

    if s:sub(pos, pos) == "}" then return pos + 1, out end

    while true do
        if s:sub(pos, pos) ~= '"' then return nil, "expected object key" end
        local ni, key = parse_string(s, pos)
        if not ni then return nil, key end

        pos = skip_ws(s, ni)
        if s:sub(pos, pos) ~= ":" then return nil, "expected : after key" end

        pos = skip_ws(s, pos + 1)
        local nv, value = parse_value(s, pos)
        if not nv then return nil, value end
        out[key] = value

        pos = skip_ws(s, nv)
        local c = s:sub(pos, pos)
        if c == "}" then return pos + 1, out end
        if c ~= "," then return nil, "expected , or } in object" end
        pos = skip_ws(s, pos + 1)
    end
end

parse_value = function(s, i)
    local c = s:sub(i, i)
    if c == "" then return nil, "unexpected end of input" end

    if c == "{" then return parse_object(s, i) end
    if c == "[" then return parse_array(s, i)  end
    if c == '"' then return parse_string(s, i) end

    if s:sub(i, i + 3) == "true"  then return i + 4, true  end
    if s:sub(i, i + 4) == "false" then return i + 5, false end
    if s:sub(i, i + 3) == "null"  then return i + 4, nil   end

    if c:match("[%-%d]") then return parse_number(s, i) end

    return nil, "unexpected character " .. c
end

-- Returns the decoded value, or nil plus a message. An empty or whitespace
-- only input is an error rather than nil, so a truncated download cannot be
-- mistaken for a valid null response.
function json_decode(text)
    if type(text) ~= "string" then return nil, "not a string" end

    local pos = skip_ws(text, 1)
    if pos > #text then return nil, "empty input" end

    local ni, value = parse_value(text, pos)
    if not ni then return nil, value end

    -- Trailing garbage means the response was not what we think it is.
    if skip_ws(text, ni) <= #text then return nil, "trailing data" end

    return value
end
