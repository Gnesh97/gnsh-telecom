FailureEngine = FailureEngine or {}

local recordsById = {}
local orderedIds = {}
local sequence = 0

local function copy(value)
    return Utils.DeepCopy(value)
end

local function now()
    if type(os.time) == 'function' then return os.time() end
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return 0
end

local function enabled()
    return Config and Config.Features and Config.Features.Failures == true
end

local function neutralEffects()
    return {
        signalMultiplier = 1.0,
        capacityMultiplier = 1.0,
        coverageMultiplier = 1.0,
        serviceFailures = {},
        backhaulStatus = nil,
        healthDelta = 0,
        activeFailures = {},
    }
end

local function nextId()
    repeat
        sequence = sequence + 1
    until recordsById[('FAIL-%06d'):format(sequence)] == nil
    return ('FAIL-%06d'):format(sequence)
end

local function updateSequenceFromId(id)
    local suffix = type(id) == 'string' and id:match('^FAIL%-(%d+)$')
    local number = suffix and tonumber(suffix)
    if number and number > sequence then sequence = number end
end

local function addError(message)
    return false, message
end

local function recordSectorId(record)
    if type(record) ~= 'table' then return nil end
    if type(record.sectorId) == 'string' and record.sectorId ~= '' then
        return record.sectorId
    end
    local metadata = record.metadata
    if type(metadata) == 'table'
        and type(metadata.sectorId) == 'string'
        and metadata.sectorId ~= '' then
        return metadata.sectorId
    end
    return nil
end

local function isValidId(id)
    return type(id) == 'string' and id ~= '' and #id <= 64
end

local function removeOrderedId(id)
    for index, value in ipairs(orderedIds) do
        if value == id then
            table.remove(orderedIds, index)
            return index
        end
    end
    return nil
end

local function aggregate(towerId, excludedId, sectorId)
    local effects = neutralEffects()
    if not enabled() or type(towerId) ~= 'string' then return effects end

    for _, id in ipairs(orderedIds) do
        local record = recordsById[id]
        local recordSector = record and recordSectorId(record)
        local appliesToSector = recordSector == nil
            or (sectorId ~= nil and recordSector == sectorId)
        if record and record.id ~= excludedId
            and record.towerId == towerId and record.active ~= false
            and appliesToSector then
            local definition = FailureTypes.Get(record.type)
            if definition then
                effects.signalMultiplier = effects.signalMultiplier
                    * definition.signalMultiplier
                effects.capacityMultiplier = effects.capacityMultiplier
                    * definition.capacityMultiplier
                effects.coverageMultiplier = effects.coverageMultiplier
                    * (definition.coverageMultiplier or 1.0)
                if definition.backhaulStatus == Enums.BackhaulState.OFFLINE then
                    effects.backhaulStatus = Enums.BackhaulState.OFFLINE
                end
                effects.healthDelta = effects.healthDelta + (definition.healthDelta or 0)
                for service, blocked in pairs(definition.serviceFailures or {}) do
                    if blocked then effects.serviceFailures[service] = true end
                end
                effects.activeFailures[#effects.activeFailures + 1] = copy(record)
            end
        end
    end
    return effects
end

local function applyTower(towerId)
    if not TowerRegistry or not TowerRegistry.Exists
        or not TowerRegistry.Exists(towerId) then
        return false, 'unknown tower'
    end

    local effects = aggregate(towerId)
    local tower = TowerRegistry.Get and TowerRegistry.Get(towerId)
    local runtime = TowerState.Get(towerId)
    local baseBackhaul = tower and tower.backhaul and tower.backhaul.status
        or Enums.BackhaulState.ONLINE
    local health = runtime and runtime.health
        or tower and tower.hardware and tower.hardware.health
        or 100
    health = Utils.Clamp(health + (effects.healthDelta or 0), 0, 100)
    local updated = TowerState.Update(towerId, {
        activeFailures = effects.activeFailures,
        failureEffects = effects,
        capacityMultiplier = effects.capacityMultiplier,
        backhaulStatus = effects.backhaulStatus or baseBackhaul,
        health = health,
    })
    if not updated then return false, 'tower runtime update failed' end

    if Capacity and Capacity.RecalculateTower and Connections and Connections.GetAll then
        Capacity.RecalculateTower(towerId, Connections.GetAll())
    end
    if Connections and Connections.RefreshTower then
        Connections.RefreshTower(towerId)
    end

    if TowerSectors and TowerSectors.GetForTower and TowerSectors.UpdateRuntime then
        for _, sector in ipairs(TowerSectors.GetForTower(towerId)) do
            local sectorEffects = aggregate(towerId, nil, sector.id)
            local runtimeSector = TowerSectors.GetRuntime(towerId, sector.id) or {}
            local hasLocalizedFailure = false
            for _, failure in ipairs(sectorEffects.activeFailures or {}) do
                if recordSectorId(failure) == sector.id then
                    hasLocalizedFailure = true
                    break
                end
            end
            local nextState = runtimeSector.state or sector.state
            if hasLocalizedFailure and nextState == Enums.TowerState.OPERATIONAL then
                nextState = Enums.TowerState.DEGRADED
            elseif not hasLocalizedFailure then
                nextState = sector.state
            end
            TowerSectors.UpdateRuntime(towerId, sector.id, {
                activeFailures = sectorEffects.activeFailures,
                failureEffects = sectorEffects,
                capacityMultiplier = sectorEffects.capacityMultiplier,
                health = Utils.Clamp(
                    (sector.health or 100) + (sectorEffects.healthDelta or 0),
                    0,
                    100
                ),
                state = nextState,
                updatedAt = now(),
            })
        end
        if Connections and Connections.RefreshTower then
            Connections.RefreshTower(towerId)
        end
        if Capacity and Capacity.RecalculateTower and Connections and Connections.GetAll then
            Capacity.RecalculateTower(towerId, Connections.GetAll())
        end
    end
    return true, effects
end

function FailureEngine.GetEffects(towerId)
    return copy(aggregate(towerId))
end

function FailureEngine.GetSectorEffects(towerId, sectorId)
    if type(sectorId) ~= 'string' then return copy(aggregate(towerId)) end
    return copy(aggregate(towerId, nil, sectorId))
end

-- Read-only projection used by post-repair verification. The failure remains
-- active until verification succeeds, so this never mutates engine state.
function FailureEngine.GetEffectsAfterClear(failureId)
    local record = recordsById[failureId]
    if not record then return false, 'failure_not_found' end
    return true, copy(aggregate(record.towerId, failureId, recordSectorId(record)))
end

function FailureEngine.ApplySignal(signal, towerId, sectorId)
    local normalized = Utils.IsFiniteNumber(signal) and Utils.Clamp(signal, 0, 100) or 0
    local effects = aggregate(towerId, nil, sectorId)
    return Utils.Clamp(
        normalized * effects.signalMultiplier * (effects.coverageMultiplier or 1.0),
        0,
        100
    )
end

function FailureEngine.Create(towerId, failureType, options)
    if not enabled() then return addError('failures_disabled') end
    if type(towerId) ~= 'string' or not TowerRegistry.Exists(towerId) then
        return addError('unknown_tower')
    end
    if not FailureTypes.IsSupported(failureType) then
        return addError('unknown_failure_type')
    end

    options = type(options) == 'table' and options or {}
    local id = options.id or nextId()
    if not isValidId(id) then return addError('invalid_failure_id') end
    if recordsById[id] then return addError('duplicate_failure_id') end

    local createdAt = options.createdAt
    if type(createdAt) ~= 'number' or createdAt ~= createdAt
        or createdAt == math.huge or createdAt == -math.huge or createdAt < 0 then
        createdAt = now()
    end
    local record = {
        id = id,
        towerId = towerId,
        type = failureType,
        active = true,
        createdAt = createdAt,
        reason = type(options.reason) == 'string' and options.reason or nil,
        source = options.source,
        metadata = type(options.metadata) == 'table' and copy(options.metadata) or {},
    }
    local sectorId = type(options.sectorId) == 'string' and options.sectorId
        or type(record.metadata.sectorId) == 'string' and record.metadata.sectorId
        or nil
    if sectorId then
        if not TowerSectors or not TowerSectors.Get
            or not TowerSectors.Get(towerId, sectorId) then
            return addError('unknown_sector')
        end
        record.sectorId = sectorId
        record.metadata.sectorId = sectorId
    end
    local definition = FailureTypes.Get(failureType)
    record.component = type(options.component) == 'string'
        and options.component
        or definition and definition.component
    if TelecomPersistence and TelecomPersistence.IsEnabled
        and TelecomPersistence.IsEnabled()
        and PersistenceSerializers and PersistenceSerializers.SerializeFailure then
        local serializable, serializationError = PersistenceSerializers.SerializeFailure(record)
        if not serializable then return addError('failure_persistence_' .. serializationError) end
    end
    recordsById[id] = record
    orderedIds[#orderedIds + 1] = id

    local ok, effects = applyTower(towerId)
    if not ok then
        recordsById[id] = nil
        removeOrderedId(id)
        return addError(effects)
    end
    if TelecomPersistence and TelecomPersistence.SaveFailure then
        TelecomPersistence.SaveFailure(record)
    end
    if IncidentManager and IncidentManager.OnFailureCreated then
        IncidentManager.OnFailureCreated(record)
    end
    if TelecomStatistics and TelecomStatistics.RecordFailureCreated then
        TelecomStatistics.RecordFailureCreated(record)
    end
    return true, copy(record), copy(effects)
end

function FailureEngine.Restore(record)
    if not enabled() then return false, 'failures_disabled' end
    if type(record) ~= 'table' or not isValidId(record.id) then
        return false, 'invalid_failure_record'
    end
    if type(record.towerId) ~= 'string' or not TowerRegistry.Exists(record.towerId) then
        return false, 'unknown_tower'
    end
    if not FailureTypes.IsSupported(record.type) then
        return false, 'unknown_failure_type'
    end
    if record.active ~= true or recordsById[record.id] then
        return false, recordsById[record.id] and 'duplicate_failure_id' or 'inactive_failure'
    end
    if type(record.createdAt) ~= 'number' or record.createdAt ~= record.createdAt
        or record.createdAt == math.huge or record.createdAt == -math.huge
        or record.createdAt < 0 then
        return false, 'created_at_invalid'
    end
    local restored = {
        id = record.id,
        towerId = record.towerId,
        type = record.type,
        active = true,
        createdAt = record.createdAt,
        reason = type(record.reason) == 'string' and record.reason or nil,
        source = record.source,
        metadata = type(record.metadata) == 'table' and copy(record.metadata) or {},
        updatedAt = record.updatedAt,
        component = record.component,
    }
    local sectorId = recordSectorId(record)
    if sectorId then
        if not TowerSectors or not TowerSectors.Get
            or not TowerSectors.Get(restored.towerId, sectorId) then
            return false, 'unknown_sector'
        end
        restored.sectorId = sectorId
        restored.metadata.sectorId = sectorId
    end
    recordsById[restored.id] = restored
    orderedIds[#orderedIds + 1] = restored.id
    updateSequenceFromId(restored.id)
    if IncidentManager and IncidentManager.OnFailureCreated then
        IncidentManager.OnFailureCreated(restored, true)
    end
    return true, copy(restored)
end

function FailureEngine.Get(id)
    local record = recordsById[id]
    return record and copy(record) or nil
end

function FailureEngine.GetAll()
    local records = {}
    for _, id in ipairs(orderedIds) do
        if recordsById[id] then records[#records + 1] = copy(recordsById[id]) end
    end
    return records
end

function FailureEngine.GetTowerFailures(towerId)
    local records = {}
    for _, id in ipairs(orderedIds) do
        local record = recordsById[id]
        if record and record.towerId == towerId then records[#records + 1] = copy(record) end
    end
    return records
end

function FailureEngine.Clear(id, actorContext)
    local record = recordsById[id]
    if not record then return false, 'failure_not_found' end

    recordsById[id] = nil
    removeOrderedId(id)
    local ok, effects = applyTower(record.towerId)
    if not ok then
        recordsById[id] = record
        orderedIds[#orderedIds + 1] = id
        return false, effects
    end
    if TelecomPersistence and TelecomPersistence.DeleteFailure then
        TelecomPersistence.DeleteFailure(id)
    end
    if IncidentManager and IncidentManager.OnFailureCleared then
        IncidentManager.OnFailureCleared(record, actorContext)
    end
    if TelecomStatistics and TelecomStatistics.RecordFailureCleared then
        TelecomStatistics.RecordFailureCleared(record)
    end
    return true, copy(record), copy(effects)
end

function FailureEngine.ClearAll(towerId)
    if type(towerId) ~= 'string' or not TowerRegistry.Exists(towerId) then
        return false, 'unknown_tower'
    end

    local removed = 0
    local removedIds = {}
    local removedRecords = {}
    for index = #orderedIds, 1, -1 do
        local id = orderedIds[index]
        local record = recordsById[id]
        if record and record.towerId == towerId then
            recordsById[id] = nil
            table.remove(orderedIds, index)
            removedIds[#removedIds + 1] = id
            removedRecords[#removedRecords + 1] = copy(record)
            removed = removed + 1
        end
    end
    local ok, errorMessage = applyTower(towerId)
    if not ok then return false, errorMessage end
    if TelecomPersistence and TelecomPersistence.DeleteFailure then
        for _, id in ipairs(removedIds) do TelecomPersistence.DeleteFailure(id) end
    end
    for _, record in ipairs(removedRecords) do
        if IncidentManager and IncidentManager.OnFailureCleared then
            IncidentManager.OnFailureCleared(record)
        end
        if TelecomStatistics and TelecomStatistics.RecordFailureCleared then
            TelecomStatistics.RecordFailureCleared(record)
        end
    end
    return true, removed
end

function FailureEngine.ApplyTower(towerId)
    local ok, effects = applyTower(towerId)
    return ok, effects and copy(effects) or effects
end

function FailureEngine.Reset()
    recordsById = {}
    orderedIds = {}
    sequence = 0
    if TowerRegistry and TowerRegistry.GetAll then
        for _, tower in ipairs(TowerRegistry.GetAll()) do applyTower(tower.id) end
    end
    if IncidentManager and IncidentManager.Reset then IncidentManager.Reset() end
end
