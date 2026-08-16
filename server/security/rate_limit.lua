TelecomRateLimit = TelecomRateLimit or {}

local buckets = {}

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

function TelecomRateLimit.Allow(source, name, intervalMs, maximum)
    local key = ('%s:%s'):format(tostring(source), tostring(name))
    local timestamp = now()
    local bucket = buckets[key] or { startedAt = timestamp, count = 0 }
    if timestamp - bucket.startedAt >= intervalMs then
        bucket = { startedAt = timestamp, count = 0 }
    end
    if bucket.count >= maximum then
        buckets[key] = bucket
        return false, 'rate_limited'
    end
    bucket.count = bucket.count + 1
    buckets[key] = bucket
    return true
end

function TelecomRateLimit.Clear(source)
    local prefix = tostring(source) .. ':'
    for key in pairs(buckets) do
        if key:sub(1, #prefix) == prefix then buckets[key] = nil end
    end
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        TelecomRateLimit.Clear(source)
    end)
end
