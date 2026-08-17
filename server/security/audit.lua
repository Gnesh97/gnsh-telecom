TelecomAudit = TelecomAudit or {}

local entries = {}
local maxEntries = 200
local sequence = 0

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= math.floor(number) or number < 0 then return nil end
    return number
end

local function retention()
    local configured = Config and Config.Persistence and Config.Persistence.auditRetention
    if type(configured) == 'number' and configured >= 1 then return math.floor(configured) end
    return maxEntries
end

local function nextId()
    repeat
        sequence = sequence + 1
    until not (function()
        for _, entry in ipairs(entries) do
            if entry.id == ('AUDIT-%06d'):format(sequence) then return true end
        end
        return false
    end)()
    return ('AUDIT-%06d'):format(sequence)
end

local function updateSequenceFromId(id)
    local suffix = type(id) == 'string' and id:match('^AUDIT%-(%d+)$')
    local number = suffix and tonumber(suffix)
    if number and number > sequence then sequence = number end
end

local function append(entry)
    local nextEntries = {}
    local start = math.max(1, #entries - retention() + 2)
    for index = start, #entries do
        nextEntries[#nextEntries + 1] = entries[index]
    end
    nextEntries[#nextEntries + 1] = entry
    entries = nextEntries
end

function TelecomAudit.Record(source, action, details)
    local number = normalizeSource(source)
    if not number or type(action) ~= 'string' or action == '' or #action > 64 then
        return nil
    end
    if details ~= nil and type(details) ~= 'table' then return nil end
    if TelecomSecurity and TelecomSecurity.IsSafeTable
        and details ~= nil
        and not TelecomSecurity.IsSafeTable(details, 4, 64) then
        return nil
    end

    local record = {
        id = nextId(),
        source = number,
        action = action,
        details = type(details) == 'table' and copy(details) or {},
        timestamp = type(os.time) == 'function' and os.time() or 0,
    }
    if TelecomPersistence and TelecomPersistence.IsEnabled
        and TelecomPersistence.IsEnabled()
        and PersistenceSerializers and PersistenceSerializers.SerializeAudit then
        local serializable = PersistenceSerializers.SerializeAudit(record)
        if not serializable then return nil end
    end
    append(record)

    if TelecomPersistence and TelecomPersistence.AppendAudit then
        TelecomPersistence.AppendAudit(record)
    end

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
    sequence = 0
end

function TelecomAudit.Restore(records, merge)
    if type(records) ~= 'table' then return 0 end
    local restored = {}
    local existing = {}
    if merge then
        for _, entry in ipairs(entries) do existing[entry.id] = true end
    else
        sequence = 0
    end
    for _, record in ipairs(records or {}) do
        if type(record) == 'table' and type(record.id) == 'string'
            and normalizeSource(record.source) ~= nil
            and type(record.action) == 'string' and #record.action > 0
            and #record.action <= 64
            and type(record.timestamp) == 'number'
            and type(record.details) == 'table'
            and (not TelecomSecurity or not TelecomSecurity.IsSafeTable
                or TelecomSecurity.IsSafeTable(record.details, 4, 64))
            and not existing[record.id] then
            restored[#restored + 1] = copy(record)
            updateSequenceFromId(record.id)
        end
    end
    if not merge then entries = {} end
    for _, record in ipairs(restored) do append(record) end
    return #restored
end
