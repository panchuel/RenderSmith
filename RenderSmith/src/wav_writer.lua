-- wav_writer.lua
-- Pure-Lua WAV file writer. No reaper.* calls: this module must stay
-- host-agnostic so it can be reused outside REAPER (future plugin port).
-- Requires Lua 5.3+ (string.pack). Supports 16/24-bit PCM and 32-bit float.
--
-- Usage:
--   local wav = wav_open(path, srate, nch, bit_depth)  -- bit_depth: 16|24|32
--   wav_write(wav, samples, num_frames)  -- samples: interleaved Lua table
--   wav_close(wav)

local WAV_FMT_PCM        = 1
local WAV_FMT_IEEE_FLOAT = 3
local PACK_CHUNK         = 128   -- values per string.pack call

function wav_open(path, srate, nch, bit_depth)
    if bit_depth ~= 16 and bit_depth ~= 24 and bit_depth ~= 32 then
        return nil, "unsupported bit depth: " .. tostring(bit_depth)
    end

    local f, err = io.open(path, "wb")
    if not f then
        return nil, err
    end

    local is_float    = (bit_depth == 32)
    local bytes_per   = bit_depth // 8
    local block_align = nch * bytes_per
    local byte_rate   = srate * block_align

    -- RIFF/data sizes are unknown until close; write zeros and patch later.
    f:write("RIFF")
    local riff_size_pos = f:seek()
    f:write(string.pack("<I4", 0))
    f:write("WAVE")

    if is_float then
        -- Non-PCM formats need an 18-byte fmt chunk (cbSize=0) plus a fact chunk.
        f:write("fmt ", string.pack("<I4I2I2I4I4I2I2I2",
            18, WAV_FMT_IEEE_FLOAT, nch, srate, byte_rate, block_align, bit_depth, 0))
        f:write("fact")
        f:write(string.pack("<I4", 4))
    else
        f:write("fmt ", string.pack("<I4I2I2I4I4I2I2",
            16, WAV_FMT_PCM, nch, srate, byte_rate, block_align, bit_depth))
    end

    local fact_frames_pos = nil
    if is_float then
        fact_frames_pos = f:seek()
        f:write(string.pack("<I4", 0))
    end

    f:write("data")
    local data_size_pos = f:seek()
    f:write(string.pack("<I4", 0))

    return {
        f               = f,
        path            = path,
        nch             = nch,
        bit_depth       = bit_depth,
        is_float        = is_float,
        frames_written  = 0,
        data_bytes      = 0,
        riff_size_pos   = riff_size_pos,
        fact_frames_pos = fact_frames_pos,
        data_size_pos   = data_size_pos,
    }
end

-- Packs values[1..n] with the given single-value format, PACK_CHUNK values
-- per string.pack call (orders of magnitude faster than one call per value).
local function pack_values(fmt_char, values, n)
    local chunk_fmt = "<" .. fmt_char:rep(PACK_CHUNK)
    local out, i = {}, 1
    while i + PACK_CHUNK - 1 <= n do
        out[#out + 1] = string.pack(chunk_fmt, table.unpack(values, i, i + PACK_CHUNK - 1))
        i = i + PACK_CHUNK
    end
    if i <= n then
        out[#out + 1] = string.pack("<" .. fmt_char:rep(n - i + 1), table.unpack(values, i, n))
    end
    return table.concat(out)
end

-- samples: interleaved Lua table (1-based), num_frames frames of handle.nch channels
function wav_write(handle, samples, num_frames)
    local n = num_frames * handle.nch
    local data

    if handle.is_float then
        data = pack_values("f", samples, n)
    else
        local scale = handle.bit_depth == 24 and 8388607.0 or 32767.0
        local ints  = {}
        for j = 1, n do
            local s = samples[j]
            if s > 1.0 then s = 1.0 elseif s < -1.0 then s = -1.0 end
            ints[j] = math.floor(s * scale + 0.5)
        end
        data = pack_values(handle.bit_depth == 24 and "i3" or "i2", ints, n)
    end

    handle.f:write(data)
    handle.frames_written = handle.frames_written + num_frames
    handle.data_bytes     = handle.data_bytes + n * (handle.bit_depth // 8)
end

function wav_close(handle)
    if not handle or not handle.f then return end
    local f = handle.f

    local data_end = handle.data_size_pos + 4 + handle.data_bytes
    f:seek("set", handle.riff_size_pos)
    f:write(string.pack("<I4", data_end - 8))

    if handle.fact_frames_pos then
        f:seek("set", handle.fact_frames_pos)
        f:write(string.pack("<I4", handle.frames_written))
    end

    f:seek("set", handle.data_size_pos)
    f:write(string.pack("<I4", handle.data_bytes))

    f:close()
    handle.f = nil
end
