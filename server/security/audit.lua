TelecomAudit = TelecomAudit or {}

local entries = {}
local maxEntries = 200

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= math.floor(number) or number < 0 then return nil end
    return number
end

local function append(entry)
    local nextEntries = {}
    local start = math.max(1, #entries - maxEntries + 2)
    for index = start, #entries do
        nextEntries[#nextEntries + 1] = entries[index]
    end
    nextEntries[#nextEntries + 1] = entry
    entries = nextEntries
end

function TelecomAudit.Record(source, action, details)
    local number = normalizeSource(source)
    if not number or type(action) ~= 'string' or action == '' then return nil end

    local record = {
        source = number,
        action = action,
        details = type(details) == 'table' and copy(details) or {},
        timestamp = type(os.time) == 'function' and os.time() or 0,
    }
    append(record)

    if Log and Log.info then
        Log.info('admin debug action', {
            source = record.source,
            action = record.action,
        })
    end
    return copy(record)
end

function TelecomAudit.GetAll()
    return copy(entries)
end

function TelecomAudit.Clear()
    entries = {}
end
