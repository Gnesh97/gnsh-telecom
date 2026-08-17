SubscriberRegistry = SubscriberRegistry or {}

local activeBySource = {}
local sourceByPlayerId = {}
local sourceBySimId = {}
local persistedByPlayerId = {}

local maxPlayerIdLength = 128
local maxSimIdLength = 64
local maxServiceClassLength = 32

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

local function enabled()
    return Config and Config.Features and Config.Features.Carriers == true
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number ~= math.floor(number) or number <= 0 then
        return nil, nil
    end
    return tostring(number), math.floor(number)
end

local function safeIdentifier(value, maximumLength)
    return type(value) == 'string'
        and #value > 0
        and #value <= maximumLength
        and value:match('^[%w_.:%-]+$') ~= nil
end

local function stablePlayerId(source)
    if not FrameworkBridge or type(FrameworkBridge.GetStablePlayerId) ~= 'function' then
        return nil
    end
    local ok, identifier = pcall(FrameworkBridge.GetStablePlayerId, source)
    if ok and safeIdentifier(identifier, maxPlayerIdLength) then return identifier end
    return nil
end

local function normalizeRecord(source, value)
    if type(value) ~= 'table' then return nil, 'subscriber_required' end

    local playerId = value.playerId
    local stableId = source and stablePlayerId(source)
    if playerId == nil then playerId = stableId end
    if not safeIdentifier(playerId, maxPlayerIdLength) then
        return nil, 'player_id_invalid'
    end
    if stableId and stableId ~= playerId then
        return nil, 'player_id_mismatch'
    end

    if not safeIdentifier(value.simId, maxSimIdLength) then
        return nil, 'sim_id_invalid'
    end
    if not safeIdentifier(value.carrierId, 64) then
        return nil, 'carrier_id_invalid'
    end
    if CarrierRegistry and CarrierRegistry.Exists
        and not CarrierRegistry.Exists(value.carrierId) then
        return nil, 'unknown_carrier'
    end

    local roamingAllowed = value.roamingAllowed
    if roamingAllowed == nil then roamingAllowed = true end
    if type(roamingAllowed) ~= 'boolean' then
        return nil, 'roaming_allowed_invalid'
    end

    local serviceClass = value.serviceClass
    if serviceClass == nil then serviceClass = 'standard' end
    if type(serviceClass) ~= 'string' or serviceClass == ''
        or #serviceClass > maxServiceClassLength then
        return nil, 'service_class_invalid'
    end

    return {
        playerId = playerId,
        simId = value.simId,
        carrierId = value.carrierId,
        roamingAllowed = roamingAllowed,
        serviceClass = serviceClass,
    }
end

local function activeRecord(sourceKey)
    local record = activeBySource[sourceKey]
    return record and copy(record) or nil
end

local function clearActive(sourceKey)
    local record = activeBySource[sourceKey]
    if not record then return nil end
    activeBySource[sourceKey] = nil
    if sourceByPlayerId[record.playerId] == sourceKey then
        sourceByPlayerId[record.playerId] = nil
    end
    if sourceBySimId[record.simId] == sourceKey then
        sourceBySimId[record.simId] = nil
    end
    return record
end

local function persist(record)
    if not TelecomPersistence or type(TelecomPersistence.SaveSubscriber) ~= 'function' then
        return
    end
    local ok, saved, errorCode = pcall(TelecomPersistence.SaveSubscriber, record)
    if (not ok or saved == false) and Log and Log.warn then
        Log.warn('subscriber persistence deferred', {
            error = ok and errorCode or tostring(saved),
            playerId = record.playerId,
        })
    end
end

local function activate(sourceKey, source, record, shouldPersist)
    local playerSource = sourceByPlayerId[record.playerId]
    if playerSource and playerSource ~= sourceKey then
        return false, 'player_id_in_use'
    end
    local simSource = sourceBySimId[record.simId]
    if simSource and simSource ~= sourceKey then
        return false, 'sim_id_in_use'
    end
    for playerId, persisted in pairs(persistedByPlayerId) do
        if playerId ~= record.playerId and persisted.simId == record.simId then
            return false, 'sim_id_in_use'
        end
    end

    local previous = clearActive(sourceKey)
    if previous and previous.playerId ~= record.playerId then
        persistedByPlayerId[previous.playerId] = nil
        if shouldPersist and TelecomPersistence
            and type(TelecomPersistence.DeleteSubscriber) == 'function' then
            TelecomPersistence.DeleteSubscriber(previous.playerId)
        end
    end

    activeBySource[sourceKey] = copy(record)
    sourceByPlayerId[record.playerId] = sourceKey
    sourceBySimId[record.simId] = sourceKey
    persistedByPlayerId[record.playerId] = copy(record)
    if shouldPersist then persist(record) end
    return true, copy(record)
end

function SubscriberRegistry.Get(source)
    if not enabled() then return nil end
    local sourceKey = normalizeSource(source)
    return sourceKey and activeRecord(sourceKey) or nil
end

function SubscriberRegistry.Set(source, subscriber)
    if not enabled() then return false, 'carriers_disabled' end
    local sourceKey, sourceNumber = normalizeSource(source)
    if not sourceKey then return false, 'invalid_player_source' end
    local record, errorCode = normalizeRecord(sourceNumber, subscriber)
    if not record then return false, errorCode end
    return activate(sourceKey, sourceNumber, record, true)
end

function SubscriberRegistry.Bind(source)
    if not enabled() then return false, 'carriers_disabled' end
    local sourceKey, sourceNumber = normalizeSource(source)
    if not sourceKey then return false, 'invalid_player_source' end
    local playerId = stablePlayerId(sourceNumber)
    if not playerId then return false, 'player_id_unavailable' end
    local record = persistedByPlayerId[playerId]
    if not record then return false, 'subscriber_not_found' end
    return activate(sourceKey, sourceNumber, record, false)
end

function SubscriberRegistry.Remove(source)
    local sourceKey = normalizeSource(source)
    if not sourceKey then return false, 'invalid_player_source' end
    local record = clearActive(sourceKey)
    if not record then return false, 'subscriber_not_found' end
    return true, copy(record)
end

function SubscriberRegistry.Delete(sourceOrPlayerId)
    local sourceKey, sourceNumber = normalizeSource(sourceOrPlayerId)
    local playerId = sourceKey and activeBySource[sourceKey]
        and activeBySource[sourceKey].playerId
        or (not sourceKey and sourceOrPlayerId)
    if sourceKey then clearActive(sourceKey) end
    if not safeIdentifier(playerId, maxPlayerIdLength) then
        return false, 'player_id_invalid'
    end

    local ownerSource = sourceByPlayerId[playerId]
    if ownerSource then clearActive(ownerSource) end
    persistedByPlayerId[playerId] = nil
    if TelecomPersistence and type(TelecomPersistence.DeleteSubscriber) == 'function' then
        TelecomPersistence.DeleteSubscriber(playerId)
    end
    return true, sourceNumber or playerId
end

function SubscriberRegistry.GetAll(limit)
    if not enabled() then return {} end
    local sources = {}
    for sourceKey in pairs(activeBySource) do sources[#sources + 1] = sourceKey end
    table.sort(sources, function(left, right) return tonumber(left) < tonumber(right) end)
    local maximum = tonumber(limit)
    if maximum and maximum >= 0 then
        maximum = math.floor(maximum)
        while #sources > maximum do sources[#sources] = nil end
    end
    local result = {}
    for _, sourceKey in ipairs(sources) do result[#result + 1] = activeRecord(sourceKey) end
    return result
end

function SubscriberRegistry.GetPersisted()
    if not enabled() then return {} end
    local playerIds = {}
    for playerId in pairs(persistedByPlayerId) do playerIds[#playerIds + 1] = playerId end
    table.sort(playerIds)
    local result = {}
    for _, playerId in ipairs(playerIds) do result[#result + 1] = copy(persistedByPlayerId[playerId]) end
    return result
end

function SubscriberRegistry.GetSource(playerId)
    local sourceKey = sourceByPlayerId[playerId]
    return sourceKey and tonumber(sourceKey) or nil
end

function SubscriberRegistry.Restore(rows, mergeLocalState)
    if not enabled() then return false, 0, 0, 'carriers_disabled' end
    if not mergeLocalState then
        activeBySource = {}
        sourceByPlayerId = {}
        sourceBySimId = {}
        persistedByPlayerId = {}
    end

    local restored, skipped = 0, 0
    for _, row in ipairs(rows or {}) do
        local record, errorCode = normalizeRecord(nil, row)
        local simInUse = false
        if record then
            for _, existing in pairs(persistedByPlayerId) do
                if existing.simId == record.simId then simInUse = true break end
            end
        end
        if not record or persistedByPlayerId[record.playerId] or simInUse
            or sourceBySimId[record.simId] then
            skipped = skipped + 1
        else
            persistedByPlayerId[record.playerId] = copy(record)
            restored = restored + 1
        end
    end
    return true, restored, skipped
end

function SubscriberRegistry.Count()
    local count = 0
    for _ in pairs(activeBySource) do count = count + 1 end
    return count
end

function SubscriberRegistry.Clear()
    activeBySource = {}
    sourceByPlayerId = {}
    sourceBySimId = {}
end

function SubscriberRegistry.Reset()
    SubscriberRegistry.Clear()
    persistedByPlayerId = {}
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerJoining', function(sourceId)
        SubscriberRegistry.Bind(sourceId or source)
    end)
    AddEventHandler('playerDropped', function(sourceId)
        SubscriberRegistry.Remove(sourceId or source)
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        if type(GetCurrentResourceName) == 'function'
            and resourceName == GetCurrentResourceName() then
            SubscriberRegistry.Reset()
        end
    end)
end
