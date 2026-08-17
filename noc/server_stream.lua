NocStream = NocStream or {}
NocServer = NocServer or {}

local subscriptionsBySource = {}
local registeredEntitiesByKey = {}
local dynamicEntitiesByKey = {}
local entitiesByKey = {}
local providerByType = {}
local sequence = 0
local subscriptionSequence = 0
local publishedAt = 0
local publishedCount = 0
local streamLoopStarted = false

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

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and isFiniteNumber(value) then return value end
    end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function generatedAt()
    return type(os.time) == 'function' and os.time() or 0
end

local function configNumber(name, fallback, minimum)
    local value = Config and Config.NOC and tonumber(Config.NOC[name])
    if not value or not isFiniteNumber(value) then value = fallback end
    if minimum and value < minimum then value = minimum end
    return math.floor(value)
end

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= (maximumLength or 128)
end

local function safeData(value)
    if type(value) ~= 'table' then return false end
    if TelecomSecurity and TelecomSecurity.IsSafeTable then
        return TelecomSecurity.IsSafeTable(value, 4, 64)
    end
    return true
end

local function pointCopy(value)
    if type(value) ~= 'table' and type(value) ~= 'userdata'
        and type(value) ~= 'vector3' then return nil end
    if not isFiniteNumber(value.x) or not isFiniteNumber(value.y)
        or not isFiniteNumber(value.z) then return nil end
    return { x = value.x, y = value.y, z = value.z }
end

local function normalizeSource(source)
    local number = TelecomSecurity and TelecomSecurity.NormalizeSource
        and TelecomSecurity.NormalizeSource(source) or tonumber(source)
    if not isFiniteNumber(number) or number ~= math.floor(number) or number <= 0 then
        return nil
    end
    return number
end

local function normalizeEntity(value)
    if type(value) ~= 'table' then return nil, 'entity_required' end
    if not safeString(value.entityType, 32) then return nil, 'entity_type_required' end
    if not safeString(value.entityId, 96) then return nil, 'entity_id_required' end

    local state = value.state
    local metadata = value.metadata
    if state == nil then state = {} end
    if metadata == nil then metadata = {} end
    if not safeData(state) then return nil, 'entity_state_invalid' end
    if not safeData(metadata) then return nil, 'entity_metadata_invalid' end

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

local function normalizeEntityReference(entityType, entityId)
    if type(entityType) == 'table' then
        entityId = entityType.entityId
        entityType = entityType.entityType
    end
    if not safeString(entityType, 32) then return nil, 'entity_type_required' end
    if not safeString(entityId, 96) then return nil, 'entity_id_required' end
    return entityKey(entityType, entityId)
end

local function sortedEntities(entityMap)
    local result = {}
    for _, entity in pairs(entityMap) do result[#result + 1] = copy(entity) end
    table.sort(result, function(left, right)
        if left.entityType == right.entityType then
            return left.entityId < right.entityId
        end
        return left.entityType < right.entityType
    end)
    local limit = configNumber('maxEntities', 500, 1)
    while #result > limit do result[#result] = nil end
    return result
end

local function addEntity(entityMap, value)
    local entity = normalizeEntity(value)
    if not entity then return false end
    entityMap[entityKey(entity.entityType, entity.entityId)] = entity
    return true
end

local function addProviderResult(entityMap, result)
    if type(result) ~= 'table' then return end
    if result.entityType ~= nil then
        addEntity(entityMap, result)
        return
    end
    for _, value in ipairs(result) do addEntity(entityMap, value) end
end

local function addTowerEntity(entityMap, tower)
    if type(tower) ~= 'table' or not safeString(tower.id, 96) then return end
    local carriers = CarrierSelection and CarrierSelection.GetEffectiveCarrierIds
        and CarrierSelection.GetEffectiveCarrierIds(tower) or tower.carriers or {}
    local carrierDetails = CarrierSelection and CarrierSelection.GetEffectiveCarriers
        and CarrierSelection.GetEffectiveCarriers(tower) or {}
    addEntity(entityMap, {
        entityType = 'tower',
        entityId = tower.id,
        state = copy(tower.runtime or {}),
        metadata = {
            coords = pointCopy(tower.coords),
            coverage = copy(tower.coverage),
            technologies = copy(tower.technologies),
            carriers = copy(carriers),
            carrierDetails = copy(carrierDetails),
            capacity = copy(tower.capacity),
            backhaulStatus = tower.backhaulStatus,
        },
    })
end

local function addSectorEntities(entityMap, tower)
    if type(tower) ~= 'table' or not safeString(tower.id, 96)
        or not TowerSectors or not TowerSectors.GetForTower then return end

    for _, sector in ipairs(TowerSectors.GetForTower(tower)) do
        local runtime = TowerSectors.GetRuntime and TowerSectors.GetRuntime(
            tower.id, sector.id
        ) or {}
        local entityId = tower.id .. ':' .. sector.id
        if safeString(entityId, 96) then
            addEntity(entityMap, {
                entityType = 'sector',
                entityId = entityId,
                state = {
                    state = runtime.state or sector.state,
                    health = runtime.health or sector.health,
                    connectedClients = runtime.connectedClients or 0,
                    loadPercent = runtime.loadPercent or 0,
                    effectiveCapacity = runtime.effectiveCapacity or sector.capacity,
                    congestion = runtime.congestion or Enums.CongestionState.NORMAL,
                },
                metadata = {
                    towerId = tower.id,
                    sectorId = sector.id,
                    azimuth = sector.azimuth,
                    beamWidth = sector.beamWidth,
                    coverageRadius = sector.coverageRadius,
                    technologies = copy(sector.technologies),
                    carriers = CarrierSelection and CarrierSelection.GetEffectiveCarrierIds
                        and CarrierSelection.GetEffectiveCarrierIds({
                            tower = tower,
                            sector = sector,
                        }) or copy(sector.carriers or tower.carriers),
                    carrierDetails = CarrierSelection
                        and CarrierSelection.GetEffectiveCarriers
                        and CarrierSelection.GetEffectiveCarriers({
                            tower = tower,
                            sector = sector,
                        }) or {},
                    capacity = sector.capacity,
                },
            })
        end
    end
end

local function addIncidentEntity(entityMap, incident)
    if type(incident) ~= 'table' or not safeString(incident.id, 96) then return end
    addEntity(entityMap, {
        entityType = 'incident',
        entityId = incident.id,
        state = {
            status = incident.status,
            severity = incident.severity,
            assignedTo = incident.assignedTo,
            createdAt = incident.createdAt,
            updatedAt = incident.updatedAt,
        },
        metadata = {
            towerId = incident.towerId,
        },
    })
end

local function addBackhaulEntities(entityMap, backhaul)
    if type(backhaul) ~= 'table' then return end
    for towerId, status in pairs(backhaul) do
        if safeString(towerId, 96) then
            addEntity(entityMap, {
                entityType = 'backhaul',
                entityId = towerId,
                state = { status = status },
                metadata = { towerId = towerId },
            })
        end
    end
end

local function addBackhaulLoadEntities(entityMap, snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.links) ~= 'table' then return end
    for linkId, load in pairs(snapshot.links) do
        if safeString(linkId, 96) and isFiniteNumber(load) then
            local link = BackhaulLinks and BackhaulLinks.Get and BackhaulLinks.Get(linkId) or {}
            addEntity(entityMap, {
                entityType = 'backhaul_link',
                entityId = linkId,
                state = {
                    load = load,
                    state = link.state,
                    capacity = link.capacity,
                },
                metadata = {
                    linkId = linkId,
                    from = link.from,
                    to = link.to,
                    type = link.type,
                    capacity = link.capacity,
                },
            })
        end
    end
end

local function addJammerEntities(entityMap, jammers)
    if type(jammers) ~= 'table' then return end
    for _, jammer in ipairs(jammers) do
        if type(jammer) == 'table' and safeString(jammer.id, 96) then
            addEntity(entityMap, {
                entityType = 'jammer',
                entityId = jammer.id,
                state = {
                    coords = pointCopy(jammer.coords),
                    radius = jammer.radius,
                    strength = jammer.strength,
                    battery = jammer.battery,
                    expiresAt = jammer.expiresAt,
                },
                metadata = {
                    owner = jammer.owner,
                    technologies = copy(jammer.technologies),
                },
            })
        end
    end
end

local function addBackhaulNodeEntities(entityMap, nodes)
    if type(nodes) ~= 'table' then return end
    for _, node in ipairs(nodes) do
        if type(node) == 'table' and safeString(node.id, 96) then
            addEntity(entityMap, {
                entityType = 'backhaul',
                entityId = node.id,
                state = {
                    state = node.state,
                    nodeType = node.type,
                },
                metadata = copy(node.metadata or {}),
            })
        end
    end
end

local function addRegionEntities(entityMap, regions)
    if type(regions) ~= 'table' then return end
    for regionId, region in pairs(regions) do
        if safeString(regionId, 96) and type(region) == 'table' then
            addEntity(entityMap, {
                entityType = 'region',
                entityId = regionId,
                state = {
                    status = region.status,
                    onlineCount = region.onlineCount,
                    degradedCount = region.degradedCount,
                    offlineCount = region.offlineCount,
                    towerCount = region.towerCount,
                },
                metadata = {
                    popNode = region.popNode,
                },
            })
        end
    end
end

local function addSubscriberEntities(entityMap, subscribers)
    if type(subscribers) ~= 'table' then return end
    for _, subscriber in ipairs(subscribers) do
        if type(subscriber) == 'table'
            and safeString(subscriber.playerId, 128)
            and safeString(subscriber.simId, 64)
            and safeString(subscriber.carrierId, 64) then
            local source = SubscriberRegistry and SubscriberRegistry.GetSource
                and SubscriberRegistry.GetSource(subscriber.playerId)
            local network = source and CarrierSelection
                and CarrierSelection.ResolveSubscriberNetwork
                and CarrierSelection.ResolveSubscriberNetwork(source) or nil
            local currentCarrierId = network and network.carrierId or nil
            addEntity(entityMap, {
                entityType = 'subscriber',
                entityId = 'sim:' .. subscriber.simId,
                state = {
                    carrierId = subscriber.carrierId,
                    currentCarrierId = currentCarrierId,
                    roaming = network and network.roaming == true or false,
                    serviceClass = subscriber.serviceClass,
                },
                metadata = {
                    playerId = subscriber.playerId,
                    simId = subscriber.simId,
                    homeCarrierId = subscriber.carrierId,
                    roamingAllowed = subscriber.roamingAllowed,
                    networkReason = network and network.reason or 'unresolved',
                },
            })
        end
    end
end

function NocServer.BuildEntities(snapshot)
    if type(snapshot) ~= 'table' then return {} end
    local nextEntities = {}

    for _, tower in ipairs(snapshot.towers or {}) do
        addTowerEntity(nextEntities, tower)
        addSectorEntities(nextEntities, tower)
    end
    local incidentSnapshot = snapshot.incidents or {}
    for _, incident in ipairs(incidentSnapshot.incidents or {}) do
        addIncidentEntity(nextEntities, incident)
    end
    addBackhaulEntities(nextEntities, snapshot.backhaul)
    addBackhaulLoadEntities(nextEntities, snapshot.backhaulLoads)
    addBackhaulNodeEntities(nextEntities, snapshot.backhaulNodes)
    addRegionEntities(nextEntities, snapshot.regions)
    addJammerEntities(nextEntities, snapshot.jammers)
    addSubscriberEntities(nextEntities, snapshot.subscribers)

    for key, entity in pairs(registeredEntitiesByKey) do
        nextEntities[key] = copy(entity)
    end
    for entityType, provider in pairs(providerByType) do
        if type(provider) == 'function' then
            local ok, result = pcall(provider, copy(snapshot), entityType)
            if ok then addProviderResult(nextEntities, result) end
        end
    end
    for key, entity in pairs(dynamicEntitiesByKey) do
        nextEntities[key] = copy(entity)
    end

    entitiesByKey = nextEntities
    return sortedEntities(entitiesByKey)
end

function NocServer.RegisterEntity(entity)
    local normalized, errorCode = normalizeEntity(entity)
    if not normalized then return false, errorCode end
    local key = entityKey(normalized.entityType, normalized.entityId)
    registeredEntitiesByKey[key] = normalized
    dynamicEntitiesByKey[key] = nil
    entitiesByKey[key] = copy(normalized)
    return true, copy(normalized)
end

NocServer.UpsertEntity = NocServer.RegisterEntity

function NocServer.RegisterEntityProvider(entityType, provider)
    if not safeString(entityType, 32) then return false, 'entity_type_required' end
    if type(provider) ~= 'function' then return false, 'provider_required' end
    providerByType[entityType] = provider
    return true
end

function NocServer.UnregisterEntityProvider(entityType)
    if not safeString(entityType, 32) then return false, 'entity_type_required' end
    if not providerByType[entityType] then return false, 'provider_not_found' end
    providerByType[entityType] = nil
    return true
end

function NocServer.RemoveEntity(entityType, entityId)
    local key, errorCode = normalizeEntityReference(entityType, entityId)
    if not key then return false, errorCode end
    local existed = registeredEntitiesByKey[key] ~= nil or dynamicEntitiesByKey[key] ~= nil
        or entitiesByKey[key] ~= nil
    registeredEntitiesByKey[key] = nil
    dynamicEntitiesByKey[key] = nil
    entitiesByKey[key] = nil
    if not existed then return false, 'entity_not_found' end
    return true
end

local function emit(source, eventName, payload)
    if type(TriggerClientEvent) ~= 'function' then return true end
    local ok = pcall(TriggerClientEvent, eventName, source, payload)
    return ok
end

local function subscriptionCount()
    local count = 0
    for _ in pairs(subscriptionsBySource) do count = count + 1 end
    return count
end

local function nextSubscriptionId()
    subscriptionSequence = subscriptionSequence + 1
    return ('NOC-SUB-%06d'):format(subscriptionSequence)
end

function NocServer.GetSubscription(source)
    local sourceId = normalizeSource(source)
    local subscription = sourceId and subscriptionsBySource[sourceId]
    return subscription and copy(subscription) or nil
end

function NocServer.Subscribe(source)
    local sourceId = normalizeSource(source)
    if not sourceId then return false, 'source_required' end
    local allowed, errorCode = NocServer.HasAccess(sourceId)
    if not allowed then return false, errorCode end

    NocServer.CleanupStale()
    local existing = subscriptionsBySource[sourceId]
    if not existing and subscriptionCount() >= configNumber('maxSubscriptions', 64, 1) then
        return false, 'subscription_limit'
    end

    local snapshotOk, snapshot = NocServer.GetSnapshot(sourceId)
    if not snapshotOk then return false, snapshot end

    local timestamp = now()
    local subscription = existing or {
        source = sourceId,
        subscriptionId = nextSubscriptionId(),
    }
    subscription.cursor = sequence
    subscription.lastSeenAt = timestamp
    subscriptionsBySource[sourceId] = subscription

    local result = {
        mode = 'full',
        subscriptionId = subscription.subscriptionId,
        cursor = sequence,
        snapshot = copy(snapshot),
    }
    if not emit(sourceId, Constants.Events.NOC_STATE, { ok = true, mode = 'full',
        subscriptionId = result.subscriptionId, cursor = result.cursor,
        snapshot = copy(result.snapshot) }) then
        if not existing then subscriptionsBySource[sourceId] = nil end
        return false, 'delivery_failed'
    end
    return true, result
end

function NocServer.Unsubscribe(source)
    local sourceId = normalizeSource(source)
    if not sourceId then return false, 'source_required' end
    subscriptionsBySource[sourceId] = nil
    return true
end

function NocServer.Reconcile(source)
    local sourceId = normalizeSource(source)
    if not sourceId then return false, 'source_required' end
    local allowed, errorCode = NocServer.HasAccess(sourceId)
    if not allowed then return false, errorCode end
    local subscription = subscriptionsBySource[sourceId]
    if not subscription then return false, 'subscription_required' end

    local snapshotOk, snapshot = NocServer.GetSnapshot(sourceId)
    if not snapshotOk then return false, snapshot end
    local timestamp = now()
    subscription.cursor = sequence
    subscription.lastSeenAt = timestamp

    local result = {
        mode = 'reconcile',
        subscriptionId = subscription.subscriptionId,
        cursor = sequence,
        snapshot = copy(snapshot),
    }
    if not emit(sourceId, Constants.Events.NOC_STATE, { ok = true, mode = 'reconcile',
        subscriptionId = result.subscriptionId, cursor = result.cursor,
        snapshot = copy(result.snapshot) }) then
        subscriptionsBySource[sourceId] = nil
        return false, 'delivery_failed'
    end
    return true, result
end

function NocServer.CleanupStale(referenceTime)
    local timestamp = isFiniteNumber(referenceTime) and referenceTime or now()
    local ttl = configNumber('subscriptionTtlMs', 30000, 1)
    local removed = 0
    for sourceId, subscription in pairs(subscriptionsBySource) do
        if not isFiniteNumber(subscription.lastSeenAt)
            or timestamp - subscription.lastSeenAt > ttl then
            subscriptionsBySource[sourceId] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function normalizeChange(change)
    if type(change) ~= 'table' then return nil, 'change_required' end
    local operation = change.operation or change.op
    if type(operation) == 'string' then operation = operation:lower() end
    if operation == 'upsert' then
        local entity, errorCode = normalizeEntity(change.entity)
        if not entity then return nil, errorCode end
        return { operation = 'upsert', entity = entity }
    end
    if operation == 'remove' or operation == 'delete' then
        local reference = type(change.entity) == 'table' and change.entity or change
        local key, errorCode = normalizeEntityReference(reference)
        if not key then return nil, errorCode end
        return {
            operation = 'remove',
            entityType = reference.entityType,
            entityId = reference.entityId,
            key = key,
        }
    end
    return nil, 'change_operation_required'
end

local function publicationAllowed(timestamp)
    local limit = configNumber('maxDeltasPerSecond', 30, 1)
    if publishedAt == 0 or timestamp - publishedAt >= 1000 then
        publishedAt = timestamp
        publishedCount = 0
    end
    if publishedCount >= limit then return false end
    publishedCount = publishedCount + 1
    return true
end

function NocServer.PublishDelta(delta)
    if type(delta) ~= 'table' or type(delta.changes) ~= 'table' then
        return false, 'delta_required'
    end
    local maxChanges = configNumber('maxDeltaEntities', 100, 1)
    if #delta.changes == 0 then return false, 'delta_empty' end
    if #delta.changes > maxChanges then return false, 'delta_too_large' end

    local normalized = {}
    for _, change in ipairs(delta.changes) do
        local value, errorCode = normalizeChange(change)
        if not value then return false, errorCode end
        normalized[#normalized + 1] = value
    end

    local timestamp = now()
    if not publicationAllowed(timestamp) then return false, 'delta_rate_limited' end
    for _, change in ipairs(normalized) do
        if change.operation == 'upsert' then
            local key = entityKey(change.entity.entityType, change.entity.entityId)
            dynamicEntitiesByKey[key] = copy(change.entity)
            entitiesByKey[key] = copy(change.entity)
        else
            dynamicEntitiesByKey[change.key] = nil
            entitiesByKey[change.key] = nil
        end
    end

    sequence = sequence + 1
    local payload = {
        cursor = sequence,
        generatedAt = generatedAt(),
        changes = copy(normalized),
    }
    local delivered = 0
    for sourceId, subscription in pairs(subscriptionsBySource) do
        if emit(sourceId, Constants.Events.NOC_DELTA, { ok = true, delta = copy(payload) }) then
            subscription.cursor = sequence
            subscription.lastSeenAt = timestamp
            delivered = delivered + 1
        else
            subscriptionsBySource[sourceId] = nil
        end
    end
    return true, copy(payload), delivered
end

function NocServer.ResetStream()
    subscriptionsBySource = {}
    registeredEntitiesByKey = {}
    dynamicEntitiesByKey = {}
    entitiesByKey = {}
    providerByType = {}
    sequence = 0
    subscriptionSequence = 0
    publishedAt = 0
    publishedCount = 0
end

function NocServer.StartStream()
    if streamLoopStarted or type(CreateThread) ~= 'function' or type(Wait) ~= 'function' then
        return false
    end
    streamLoopStarted = true
    CreateThread(function()
        while streamLoopStarted do
            Wait(configNumber('reconcileIntervalMs', 10000, 1000))
            if streamLoopStarted then
                NocServer.CleanupStale()
                local sources = {}
                for sourceId in pairs(subscriptionsBySource) do sources[#sources + 1] = sourceId end
                table.sort(sources)
                for _, sourceId in ipairs(sources) do NocServer.Reconcile(sourceId) end
            end
        end
    end)
    return true
end

function NocServer.StopStream()
    streamLoopStarted = false
    NocServer.ResetStream()
    return true
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.NOC_RECONCILE)
    RegisterNetEvent(Constants.Events.NOC_UNSUBSCRIBE)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.NOC_RECONCILE, function()
        local sourceId = source
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'noc_reconcile', 1000, 4)
        if not limited then return end
        local ok, result = NocServer.Reconcile(sourceId)
        if not ok then emit(sourceId, Constants.Events.NOC_STATE, { ok = false, error = result }) end
    end)
    AddEventHandler(Constants.Events.NOC_UNSUBSCRIBE, function()
        NocServer.Unsubscribe(source)
    end)
    AddEventHandler('playerDropped', function()
        NocServer.Unsubscribe(source)
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        if type(GetCurrentResourceName) == 'function'
            and resourceName == GetCurrentResourceName() then
            NocServer.StopStream()
        end
    end)
end

NocServer.StartStream()
