NocClient = NocClient or {}

local stream = {
    active = false,
    snapshot = nil,
    cursor = 0,
    subscriptionId = nil,
    needsReconcile = false,
    reconcilePending = false,
    lastReconcileRequestAt = 0,
}
NocClient.Stream = stream

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[copy(key)] = copy(item) end
    return result
end

local function isFiniteNumber(value)
    if Utils and Utils.IsFiniteNumber then return Utils.IsFiniteNumber(value) end
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function safeString(value, maximumLength)
    return type(value) == 'string' and value ~= ''
        and #value <= (maximumLength or 128)
end

local function safeData(value)
    if type(value) ~= 'table' then return false end
    if TelecomSecurity and TelecomSecurity.IsSafeTable then
        return TelecomSecurity.IsSafeTable(value, 4, 64)
    end
    return true
end

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and isFiniteNumber(value) then return value end
    end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function normalizeEntity(value)
    if type(value) ~= 'table'
        or not safeString(value.entityType, 32)
        or not safeString(value.entityId, 96) then
        return nil, 'invalid_entity'
    end
    local state = value.state or {}
    local metadata = value.metadata or {}
    if not safeData(state) or not safeData(metadata) then return nil, 'invalid_entity' end
    return {
        entityType = value.entityType,
        entityId = value.entityId,
        state = copy(state),
        metadata = copy(metadata),
    }
end

local function entityKey(entityType, entityId)
    return entityType .. ':' .. entityId
end

local function findEntityIndex(entities, key)
    for index, entity in ipairs(entities) do
        if entityKey(entity.entityType, entity.entityId) == key then return index end
    end
    return nil
end

local function sortEntities(entities)
    table.sort(entities, function(left, right)
        if left.entityType == right.entityType then
            return left.entityId < right.entityId
        end
        return left.entityType < right.entityType
    end)
end

local function towerFromEntity(entity, existing)
    local tower = copy(existing or { id = entity.entityId })
    tower.id = entity.entityId
    local runtime = copy(tower.runtime or {})
    for key, value in pairs(entity.state or {}) do runtime[key] = copy(value) end
    tower.runtime = runtime
    for key, value in pairs(entity.metadata or {}) do tower[key] = copy(value) end
    return tower
end

local function applyTowerUpsert(snapshot, entity)
    local towers = snapshot.towers or {}
    local index
    for candidateIndex, tower in ipairs(towers) do
        if tower.id == entity.entityId then index = candidateIndex break end
    end
    towers[index or (#towers + 1)] = towerFromEntity(entity, index and towers[index] or nil)
    snapshot.towers = towers
end

local function removeTower(snapshot, entityId)
    local towers = {}
    for _, tower in ipairs(snapshot.towers or {}) do
        if tower.id ~= entityId then towers[#towers + 1] = tower end
    end
    snapshot.towers = towers
end

local function refreshCounts(snapshot)
    local counts = copy(snapshot.counts or {})
    local operational, degraded, offline = 0, 0, 0
    local loadTotal = 0
    local towers = snapshot.towers or {}
    local critical = 0
    for _, tower in ipairs(towers) do
        local runtime = tower.runtime or {}
        local state = runtime.state
        if state == 'OFFLINE' or state == 'DESTROYED' then
            offline = offline + 1
        elseif state == 'DEGRADED' or state == 'MAINTENANCE' then
            degraded = degraded + 1
        else
            operational = operational + 1
        end
        loadTotal = loadTotal + (tonumber(runtime.loadPercent) or 0)
        if state == 'CRITICAL' or runtime.congestion == 'CRITICAL'
            or runtime.congestion == 'OVERLOADED' then
            critical = critical + 1
        end
    end
    counts.operational = operational
    counts.degraded = degraded
    counts.offline = offline
    counts.criticalCongestion = critical
    counts.averageLoad = #towers > 0 and loadTotal / #towers or 0
    snapshot.counts = counts
end

local function normalizeChange(change)
    if type(change) ~= 'table' then return nil, 'invalid_change' end
    local operation = change.operation or change.op
    if type(operation) == 'string' then operation = operation:lower() end
    if operation == 'upsert' then
        local entity, errorCode = normalizeEntity(change.entity)
        if not entity then return nil, errorCode end
        return { operation = 'upsert', entity = entity }
    end
    if operation == 'remove' or operation == 'delete' then
        local reference = type(change.entity) == 'table' and change.entity or change
        if not safeString(reference.entityType, 32)
            or not safeString(reference.entityId, 96) then
            return nil, 'invalid_change'
        end
        return {
            operation = 'remove',
            entityType = reference.entityType,
            entityId = reference.entityId,
        }
    end
    return nil, 'invalid_change'
end

local function sendDeltaToNui(delta)
    if type(SendNUIMessage) == 'function' then
        local ok = pcall(SendNUIMessage, {
            action = 'delta',
            view = 'noc',
            data = copy(delta),
        })
        return ok
    end
    return false
end

function NocClient.HandleState(payload)
    if type(payload) ~= 'table' then return false, 'invalid_payload' end
    if not payload.ok then return false, payload.error or 'request_rejected' end
    if type(payload.snapshot) ~= 'table' then return false, 'snapshot_required' end

    local nextSnapshot = copy(payload.snapshot)
    if type(nextSnapshot.entities) ~= 'table' then nextSnapshot.entities = {} end
    local entities = {}
    for _, value in ipairs(nextSnapshot.entities) do
        local entity = normalizeEntity(value)
        if entity then entities[#entities + 1] = entity end
    end
    nextSnapshot.entities = entities
    local cursor = tonumber(payload.cursor) or 0
    if not isFiniteNumber(cursor) or cursor < 0 or cursor ~= math.floor(cursor) then
        return false, 'invalid_cursor'
    end
    if payload.subscriptionId ~= nil
        and not safeString(payload.subscriptionId, 64) then
        return false, 'invalid_subscription'
    end

    stream.active = true
    stream.snapshot = nextSnapshot
    stream.cursor = cursor
    stream.subscriptionId = payload.subscriptionId
    stream.needsReconcile = false
    stream.reconcilePending = false
    stream.lastReconcileRequestAt = 0
    if TelecomNui and TelecomNui.Open then TelecomNui.Open('noc', copy(nextSnapshot)) end
    return true
end

function NocClient.HandleDelta(payload)
    if type(payload) ~= 'table' or type(payload.delta) ~= 'table' then
        return false, 'invalid_payload'
    end
    if not stream.active or type(stream.snapshot) ~= 'table' then
        return false, 'not_active'
    end
    local delta = payload.delta
    local cursor = tonumber(delta.cursor)
    if not isFiniteNumber(cursor) or cursor < 1 or cursor ~= math.floor(cursor) then
        return false, 'invalid_cursor'
    end
    if cursor <= stream.cursor then return true, 'duplicate' end
    if cursor ~= stream.cursor + 1 then
        stream.needsReconcile = true
        NocClient.RequestReconcile()
        return false, 'cursor_gap'
    end
    if type(delta.changes) ~= 'table' or #delta.changes == 0 then
        return false, 'invalid_changes'
    end

    local changes = {}
    for _, change in ipairs(delta.changes) do
        local normalized, errorCode = normalizeChange(change)
        if not normalized then return false, errorCode end
        changes[#changes + 1] = normalized
    end

    local nextSnapshot = copy(stream.snapshot)
    nextSnapshot.entities = copy(nextSnapshot.entities or {})
    for _, change in ipairs(changes) do
        local key = entityKey(change.entityType or change.entity.entityType,
            change.entityId or change.entity.entityId)
        local index = findEntityIndex(nextSnapshot.entities, key)
        if change.operation == 'upsert' then
            local entity = copy(change.entity)
            if index then nextSnapshot.entities[index] = entity
            else nextSnapshot.entities[#nextSnapshot.entities + 1] = entity end
            if entity.entityType == 'tower' then applyTowerUpsert(nextSnapshot, entity) end
        else
            if index then table.remove(nextSnapshot.entities, index) end
            if change.entityType == 'tower' then removeTower(nextSnapshot, change.entityId) end
        end
    end
    sortEntities(nextSnapshot.entities)
    refreshCounts(nextSnapshot)

    stream.snapshot = nextSnapshot
    stream.cursor = cursor
    stream.needsReconcile = false
    stream.reconcilePending = false
    stream.lastReconcileRequestAt = 0
    sendDeltaToNui(delta)
    return true
end

function NocClient.GetState()
    return stream.active and copy(stream.snapshot) or nil
end

function NocClient.GetCursor()
    return stream.cursor
end

function NocClient.RequestReconcile()
    if not stream.active then return false, 'not_active' end
    local interval = tonumber(Config.NOC and Config.NOC.reconcileIntervalMs) or 10000
    if stream.reconcilePending and now() - stream.lastReconcileRequestAt < interval then
        return false, 'reconcile_pending'
    end
    if type(TriggerServerEvent) ~= 'function' then return false, 'event_api_unavailable' end
    stream.reconcilePending = true
    stream.needsReconcile = true
    stream.lastReconcileRequestAt = now()
    TriggerServerEvent(Constants.Events.NOC_RECONCILE)
    return true
end

function NocClient.Unsubscribe()
    if stream.active and type(TriggerServerEvent) == 'function' then
        TriggerServerEvent(Constants.Events.NOC_UNSUBSCRIBE)
    end
    stream.active = false
    stream.snapshot = nil
    stream.cursor = 0
    stream.subscriptionId = nil
    stream.needsReconcile = false
    stream.reconcilePending = false
    stream.lastReconcileRequestAt = 0
    return true
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.NOC_DELTA)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.NOC_DELTA, function(payload)
        local ok, errorCode = NocClient.HandleDelta(payload)
        if not ok and errorCode ~= 'not_active' and type(print) == 'function' then
            print(('[gnsh-telecom] NOC delta rejected: %s'):format(tostring(errorCode)))
        end
    end)
end

if type(CreateThread) == 'function' and type(Wait) == 'function' then
    CreateThread(function()
        while true do
            Wait((Config.NOC and Config.NOC.reconcileIntervalMs) or 10000)
            if stream.active then NocClient.RequestReconcile() end
        end
    end)
end
