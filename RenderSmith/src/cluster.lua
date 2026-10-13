-- cluster.lua
-- Gap clustering: turns a folder's items into one region per *sound*
-- instead of one region per folder.
--
-- A cluster is a run of items whose gaps stay under a threshold. Twenty
-- gunshots laid out in one folder become twenty regions, which is the
-- whole point of a batch SFX render.
--
-- No reaper.* calls in here on purpose: the algorithm is the part worth
-- unit-testing, and it needs nothing but a list of {pos, len}.

-- items: array of entries, any order. Two kinds:
--   { pos, len }                   a sound
--   { pos, switch = "Name", color} a NameSwitch marker (see nameswitch.lua)
--
-- Returns an array of { start, stop, index, name, color } in timeline
-- order. A marker closes whatever run is open, renames everything after
-- it, and restarts the numbering at 1 -- so `index` counts within the
-- current name, not across the whole folder.
function cluster_items(items, gap_length)
    local sorted = {}
    for i, it in ipairs(items) do sorted[i] = it end
    table.sort(sorted, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        -- A marker sharing a position with a sound must apply to it, so it
        -- sorts first.
        if (a.switch ~= nil) ~= (b.switch ~= nil) then return a.switch ~= nil end
        return (a.pos + (a.len or 0)) < (b.pos + (b.len or 0))
    end)

    local clusters    = {}
    local current     = nil
    local cluster_end = nil
    local name, color = nil, nil
    local index       = 1

    for _, it in ipairs(sorted) do
        if it.switch then
            -- Never merge across a marker, however small the gap.
            current, cluster_end = nil, nil
            name, color = it.switch, it.color
            index = 1

        else
            local stop = it.pos + it.len

            if not current or (it.pos - cluster_end) > gap_length then
                current = { start = it.pos, stop = stop, index = index,
                            name = name, color = color }
                index = index + 1
                clusters[#clusters + 1] = current
            end

            -- max, not "the last item we saw": a long item underneath
            -- several short ones extends the cluster even though it
            -- started earlier.
            current.stop = math.max(current.stop, stop)
            cluster_end  = current.stop
        end
    end

    return clusters
end

-- Zero-padded cluster number. `digits` follows REAPER's own autoincrsuffix
-- so tool-made names line up with names REAPER generates itself.
function format_cluster_number(number, digits)
    return string.format("%0" .. math.max(1, digits or 2) .. "d", number)
end

-- Splits REAPER's autoincrsuffix (e.g. "_01") into its prefix and digit
-- count. Anything that does not end in digits falls back to 2 digits.
function parse_autoincr_suffix(suffix)
    if not suffix or suffix == "" then return "_", 2 end
    local prefix, digits = suffix:match("^(.-)(%d+)$")
    if not digits then return "_", 2 end
    return prefix, #digits
end
