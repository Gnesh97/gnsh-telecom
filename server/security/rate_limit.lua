TelecomRateLimit = TelecomRateLimit or {}

local buckets = {}

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, timestamp = pcall(GetGameTimer)
        if ok and type(timestamp) == 'number'
            and timestamp == timestamp
            and timestamp ~= math.huge
            and timestamp ~= -math.huge then
            return timestamp
        end
    end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function keyPart(value, maximumLength)
    if type(value) == 'number' then
        if value ~= value or value == math.huge or value == -math.huge
            or value ~= math.floor(value) or value < 0 then
            return nil
        end
        return tostring(value)
    end
    if type(value) ~= 'string' or value == '' or #value > maximumLength then
        return nil
    end
    return value
end

function TelecomRateLimit.Allow(source, name, intervalMs, maximum)
    local sourceKey = keyPart(source, 32)
    local nameKey = keyPart(name, 64)
    if not sourceKey or not nameKey
        or nameKey:find(':', 1, true) then
        return false, 'invalid_rate_limit'
    end
    if type(intervalMs) ~= 'number' or intervalMs ~= intervalMs
        or intervalMs == math.huge or intervalMs == -math.huge
        or intervalMs < 1 or intervalMs ~= math.floor(intervalMs)
        or type(maximum) ~= 'number' or maximum ~= maximum
        or maximum == math.huge or maximum == -math.huge
        or maximum < 1 or maximum ~= math.floor(maximum) then
        return false, 'invalid_rate_limit'
    end

    local key = sourceKey .. ':' .. nameKey
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
    local sourceKey = keyPart(source, 32)
    if not sourceKey then return end
    local prefix = sourceKey .. ':'
    for key in pairs(buckets) do
        if key:sub(1, #prefix) == prefix then buckets[key] = nil end
    end
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        TelecomRateLimit.Clear(source)
    end)
end
