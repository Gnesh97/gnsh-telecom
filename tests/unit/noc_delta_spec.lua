local function makeNocTower(id, maximum)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = maximum or 100 },
    }
end

TEST('logical tower topology does not require visual prop metadata', function()
    local tower = makeNocTower('NOC_LOGICAL_ONLY')
    ASSERT_EQ(tower.visual, nil)
    ASSERT_EQ(tower.entity, nil)

    local ok, errors, normalized = TowerValidation.Validate(tower)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_TRUE(TowerRegistry.Init({ normalized }))

    local registered = TowerRegistry.Get('NOC_LOGICAL_ONLY')
    ASSERT_TRUE(registered ~= nil)
    ASSERT_EQ(registered.visual, nil)
    ASSERT_EQ(registered.entity, nil)

    local entities = NocServer.BuildEntities({ towers = { registered } })
    local logicalEntity
    for _, entity in ipairs(entities) do
        if entity.entityType == 'tower' and entity.entityId == 'NOC_LOGICAL_ONLY' then
            logicalEntity = entity
            break
        end
    end

    ASSERT_TRUE(logicalEntity ~= nil)
    ASSERT_EQ(logicalEntity.metadata.coords.x, 0)
    ASSERT_EQ(logicalEntity.metadata.coverage.radius, 100)
end)

local function withNocState(fn, maximum)
    local previous = {
        noc = Config.Features.NOC,
        backhaul = Config.Features.Backhaul,
        jammers = Config.Features.Jammers,
        statistics = Config.Features.Statistics,
        serviceSessions = Config.Features.ServiceSessions,
        qos = Config.Features.QoS,
        ace = rawget(_G, 'IsPlayerAceAllowed'),
        triggerClient = rawget(_G, 'TriggerClientEvent'),
        maxDeltaEntities = Config.NOC.maxDeltaEntities,
        maxSubscriptions = Config.NOC.maxSubscriptions,
    }
    local events = {}

    Config.Features.NOC = true
    Config.Features.Backhaul = true
    Config.Features.Jammers = true
    Config.Features.Statistics = false
    Config.Features.ServiceSessions = true
    Config.Features.QoS = true
    IsPlayerAceAllowed = function(source, ace)
        return (source == 7 or source == 8) and ace == Config.NOC.ace
    end
    TriggerClientEvent = function(name, source, payload)
        events[#events + 1] = { name = name, source = source, payload = payload }
    end
    Connections.Clear()
    ServiceSessions.Reset()
    TowerRegistry.Init({ makeNocTower('NOC_TEST_TOWER', maximum) })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    NocServer.ResetStream()
    ServiceSessions.Reset()

    local ok, err = pcall(fn, events)

    NocServer.ResetStream()
    Config.Features.NOC = previous.noc
    Config.Features.Backhaul = previous.backhaul
    Config.Features.Jammers = previous.jammers
    Config.Features.Statistics = previous.statistics
    Config.Features.ServiceSessions = previous.serviceSessions
    Config.Features.QoS = previous.qos
    Config.NOC.maxDeltaEntities = previous.maxDeltaEntities
    Config.NOC.maxSubscriptions = previous.maxSubscriptions
    rawset(_G, 'IsPlayerAceAllowed', previous.ace)
    rawset(_G, 'TriggerClientEvent', previous.triggerClient)
    if not ok then error(err, 0) end
end

TEST('NOC stream sends an initial full snapshot with extensible entities', function()
    withNocState(function(events)
        ASSERT_TRUE(Connections.Set(601, {
            source = 601,
            towerId = 'NOC_TEST_TOWER',
            signal = 90,
            rawSignal = 90,
            signalLevel = Signal.GetLevel(90),
            technology = '4G',
            services = {},
        }, { skipCapacity = true }))
        TelecomRateLimit.Clear(601)
        local sessionOk, session = ServiceSessions.Begin(601, 'BACKGROUND_DATA', {
            dashboard = 'noc',
            intensity = 4,
        })
        ASSERT_TRUE(sessionOk)
        while #events > 0 do table.remove(events) end
        local ok, result = NocServer.Subscribe(7)
        ASSERT_TRUE(ok)
        ASSERT_EQ(result.mode, 'full')
        ASSERT_EQ(result.cursor, 0)
        ASSERT_TRUE(type(result.subscriptionId) == 'string')
        ASSERT_EQ(events[1].name, Constants.Events.NOC_STATE)
        ASSERT_EQ(events[1].payload.mode, 'full')
        local towerFound = false
        for _, entity in ipairs(result.snapshot.entities) do
            if entity.entityType == 'tower' and entity.entityId == 'NOC_TEST_TOWER' then
                towerFound = true
            end
        end
        ASSERT_TRUE(towerFound)
        local sessionFound = false
        for _, entity in ipairs(result.snapshot.entities) do
            if entity.entityType == 'service_session'
                and entity.entityId == session.id then
                sessionFound = true
                ASSERT_EQ(entity.state.service, 'BACKGROUND_DATA')
                ASSERT_EQ(entity.state.qos.degraded, true)
            end
        end
        ASSERT_TRUE(sessionFound)
        ASSERT_TRUE(ServiceSessions.End(session.id, 601))
    end, 4)
end)

TEST('NOC stream publishes bounded delta events and updates the entity cache', function()
    withNocState(function(events)
        ASSERT_TRUE(NocServer.Subscribe(7))
        events[1] = nil

        local ok, delta = NocServer.PublishDelta({
            changes = {
                {
                    operation = 'upsert',
                    entity = {
                        entityType = 'sector',
                        entityId = 'NOC-SECTOR-1',
                        state = { status = 'DEGRADED' },
                        metadata = { towerId = 'NOC_TEST_TOWER' },
                    },
                },
            },
        })
        ASSERT_TRUE(ok)
        ASSERT_EQ(delta.cursor, 1)
        ASSERT_EQ(events[1].name, Constants.Events.NOC_DELTA)
        ASSERT_EQ(events[1].payload.delta.changes[1].entity.entityType, 'sector')

        local snapshotOk, snapshot = NocServer.GetSnapshot(7)
        ASSERT_TRUE(snapshotOk)
        local found = false
        for _, entity in ipairs(snapshot.entities) do
            if entity.entityId == 'NOC-SECTOR-1' then found = true end
        end
        ASSERT_TRUE(found)
    end)
end)

TEST('NOC stream reconciles an active subscription with a full snapshot', function()
    withNocState(function(events)
        ASSERT_TRUE(NocServer.RegisterEntity({
            entityType = 'carrier',
            entityId = 'NOC-CARRIER-1',
            state = { status = 'ONLINE' },
            metadata = {},
        }))
        ASSERT_TRUE(NocServer.Subscribe(7))
        events[1] = nil

        local ok, result = NocServer.Reconcile(7)
        ASSERT_TRUE(ok)
        ASSERT_EQ(result.mode, 'reconcile')
        ASSERT_EQ(events[1].payload.mode, 'reconcile')
        local carrierFound = false
        for _, entity in ipairs(result.snapshot.entities) do
            if entity.entityType == 'carrier' then carrierFound = true end
        end
        ASSERT_TRUE(carrierFound)
    end)
end)

TEST('NOC stream enforces access and remains safe when optional modules are disabled', function()
    withNocState(function()
        local denied, errorCode = NocServer.Subscribe(99)
        ASSERT_FALSE(denied)
        ASSERT_EQ(errorCode, 'not_authorized')

        Config.Features.Backhaul = false
        Config.Features.Jammers = false
        Config.Features.Statistics = false
        local ok, snapshot = NocServer.GetSnapshot(7)
        ASSERT_TRUE(ok)
        ASSERT_TRUE(type(snapshot.entities) == 'table')
        ASSERT_EQ(#snapshot.jammers, 0)
        ASSERT_EQ(next(snapshot.backhaul), nil)
    end)
end)

TEST('NOC stream supports provider extensions and message volume limits', function()
    withNocState(function()
        ASSERT_TRUE(NocServer.RegisterEntityProvider('carrier', function()
            return {
                {
                    entityType = 'carrier',
                    entityId = 'NOC-CARRIER-1',
                    state = {},
                    metadata = {},
                },
            }
        end))
        local providerOk, snapshot = NocServer.GetSnapshot(7)
        ASSERT_TRUE(providerOk)
        local carrierFound = false
        for _, entity in ipairs(snapshot.entities) do
            if entity.entityType == 'carrier' then carrierFound = true end
        end
        ASSERT_TRUE(carrierFound)

        Config.NOC.maxDeltaEntities = 1
        local deltaOk, errorCode = NocServer.PublishDelta({
            changes = {
                { operation = 'remove', entityType = 'carrier', entityId = 'NOC-CARRIER-1' },
                { operation = 'remove', entityType = 'sector', entityId = 'NOC-SECTOR-1' },
            },
        })
        ASSERT_FALSE(deltaOk)
        ASSERT_EQ(errorCode, 'delta_too_large')
    end)
end)

TEST('NOC stream cleans stale subscriptions and requires a live subscription to reconcile', function()
    withNocState(function()
        ASSERT_TRUE(NocServer.Subscribe(7))
        local subscription = NocServer.GetSubscription(7)
        ASSERT_TRUE(subscription ~= nil)
        local removed = NocServer.CleanupStale(
            subscription.lastSeenAt + (Config.NOC.subscriptionTtlMs or 30000) + 1
        )
        ASSERT_EQ(removed, 1)
        ASSERT_EQ(NocServer.GetSubscription(7), nil)
        local ok, errorCode = NocServer.Reconcile(7)
        ASSERT_FALSE(ok)
        ASSERT_EQ(errorCode, 'subscription_required')
    end)
end)

local function withNocClientState(fn)
    local previousTriggerServer = rawget(_G, 'TriggerServerEvent')
    local previousSendNui = rawget(_G, 'SendNUIMessage')
    local events = {}
    TriggerServerEvent = function(name, payload)
        events[#events + 1] = { name = name, payload = payload }
    end
    SendNUIMessage = function(payload) events[#events + 1] = payload end
    NocClient.Unsubscribe()

    local ok, err = pcall(fn, events)

    NocClient.Unsubscribe()
    rawset(_G, 'TriggerServerEvent', previousTriggerServer)
    rawset(_G, 'SendNUIMessage', previousSendNui)
    if not ok then error(err, 0) end
end

TEST('NOC client applies sequential deltas and forwards only the delta to NUI', function()
    withNocClientState(function(events)
        ASSERT_TRUE(NocClient.HandleState({
            ok = true,
            mode = 'full',
            cursor = 0,
            subscriptionId = 'NOC-SUB-1',
            snapshot = {
                counts = {},
                towers = {},
                entities = {},
            },
        }))
        events[1] = nil
        ASSERT_TRUE(NocClient.HandleDelta({
            ok = true,
            delta = {
                cursor = 1,
                changes = {
                    {
                        operation = 'upsert',
                        entity = {
                            entityType = 'sector',
                            entityId = 'CLIENT-SECTOR-1',
                            state = { status = 'ONLINE' },
                            metadata = {},
                        },
                    },
                },
            },
        }))
        ASSERT_EQ(NocClient.GetCursor(), 1)
        ASSERT_EQ(events[1].action, 'delta')
        local state = NocClient.GetState()
        ASSERT_EQ(state.entities[1].entityId, 'CLIENT-SECTOR-1')
    end)
end)

TEST('NOC client requests reconciliation when a delta cursor has a gap', function()
    withNocClientState(function(events)
        ASSERT_TRUE(NocClient.HandleState({
            ok = true,
            cursor = 0,
            subscriptionId = 'NOC-SUB-2',
            snapshot = { counts = {}, towers = {}, entities = {} },
        }))
        events[1] = nil
        local ok, errorCode = NocClient.HandleDelta({
            ok = true,
            delta = { cursor = 2, changes = {
                { operation = 'remove', entityType = 'sector', entityId = 'MISSING' },
            } },
        })
        ASSERT_FALSE(ok)
        ASSERT_EQ(errorCode, 'cursor_gap')
        ASSERT_EQ(events[1].name, Constants.Events.NOC_RECONCILE)
        ASSERT_TRUE(NocClient.Stream.needsReconcile)
    end)
end)
