FailureEngine = FailureEngine or {}

local recordsById = {}
local orderedIds = {}
local sequence = 0

local function copy(value)
    return Utils.DeepCopy(value)
end

local function now()
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
        serviceFailures = {},
        activeFailures = {},
    }
end

local function nextId()
    repeat
        sequence = sequence + 1
    until recordsById[('FAIL-%06d'):format(sequence)] == nil
    return ('FAIL-%06d'):format(sequence)
end

local function addError(message)
    return false, message
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

local function aggregate(towerId)
    local effects = neutralEffects()
    if not enabled() or type(towerId) ~= 'string' then return effects end

    for _, id in ipairs(orderedIds) do
        local record = recordsById[id]
        if record and record.towerId == towerId and record.active ~= false then
            local definition = FailureTypes.Get(record.type)
            if definition then
                effects.signalMultiplier = effects.signalMultiplier
                    * definition.signalMultiplier
                effects.capacityMultiplier = effects.capacityMultiplier
                    * definition.capacityMultiplier
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
    local updated = TowerState.Update(towerId, {
        activeFailures = effects.activeFailures,
        failureEffects = effects,
        capacityMultiplier = effects.capacityMultiplier,
    })
    if not updated then return false, 'tower runtime update failed' end

    if Capacity and Capacity.RecalculateTower and Connections and Connections.GetAll then
        Capacity.RecalculateTower(towerId, Connections.GetAll())
    end
    if Connections and Connections.RefreshTower then
        Connections.RefreshTower(towerId)
    end
    return true, effects
end

function FailureEngine.GetEffects(towerId)
    return copy(aggregate(towerId))
end

function FailureEngine.ApplySignal(signal, towerId)
    local normalized = Utils.IsFiniteNumber(signal) and Utils.Clamp(signal, 0, 100) or 0
    local effects = aggregate(towerId)
    return Utils.Clamp(normalized * effects.signalMultiplier, 0, 100)
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

    local record = {
        id = id,
        towerId = towerId,
        type = failureType,
        active = true,
        createdAt = now(),
        reason = type(options.reason) == 'string' and options.reason or nil,
        source = options.source,
        metadata = type(options.metadata) == 'table' and copy(options.metadata) or {},
    }
    recordsById[id] = record
    orderedIds[#orderedIds + 1] = id

    local ok, effects = applyTower(towerId)
    if not ok then
        recordsById[id] = nil
        removeOrderedId(id)
        return addError(effects)
    end
    return true, copy(record), copy(effects)
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

function FailureEngine.Clear(id)
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
    return true, copy(record), copy(effects)
end

function FailureEngine.ClearAll(towerId)
    if type(towerId) ~= 'string' or not TowerRegistry.Exists(towerId) then
        return false, 'unknown_tower'
    end

    local removed = 0
    for index = #orderedIds, 1, -1 do
        local id = orderedIds[index]
        local record = recordsById[id]
        if record and record.towerId == towerId then
            recordsById[id] = nil
            table.remove(orderedIds, index)
            removed = removed + 1
        end
    end
    local ok, errorMessage = applyTower(towerId)
    if not ok then return false, errorMessage end
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
end
