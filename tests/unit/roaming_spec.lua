local function makeCarrier(id, partners, priority)
    return {
        id = id,
        name = id:upper(),
        technologies = { '4G' },
        roamingPartners = partners or {},
        priority = priority or 0,
    }
end

local function makeTower(id, carriers)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
        carriers = carriers,
    }
end

local function withCarriers(definitions, fn, persistenceEnabled)
    local previousEnabled = Config.Features.Carriers
    local previousDefinitions = Config.Carriers
    local previousPersistence = Config.Persistence.enabled
    local previousAdapter = Config.Persistence.adapter
    Config.Features.Carriers = true
    Config.Carriers = Utils.DeepCopy(definitions)
    Config.Persistence.enabled = persistenceEnabled == true
    Config.Persistence.adapter = 'memory'
    SubscriberRegistry.Reset()
    TelecomPersistence.Reset()
    ASSERT_TRUE(CarrierRegistry.Initialize(definitions))

    local ok, err = pcall(fn)

    SubscriberRegistry.Reset()
    TelecomPersistence.Reset()
    CarrierRegistry.Reset()
    Config.Carriers = previousDefinitions
    Config.Features.Carriers = previousEnabled
    Config.Persistence.enabled = previousPersistence
    Config.Persistence.adapter = previousAdapter
    Connections.Clear()
    TowerRegistry.Init({})
    SpatialIndex.Rebuild({})
    if not ok then error(err, 0) end
end

local function subscriber(playerId, simId, carrierId, roamingAllowed)
    return {
        playerId = playerId,
        simId = simId,
        carrierId = carrierId,
        roamingAllowed = roamingAllowed,
        serviceClass = 'standard',
    }
end

TEST('subscriber resolves on its home carrier', function()
    withCarriers({
        makeCarrier('carrier_a', { 'carrier_b' }, 10),
        makeCarrier('carrier_b', {}, 20),
    }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(501,
            subscriber('license:home', 'sim-home', 'carrier_a', true)))
        local result = CarrierSelection.ResolveSubscriberNetwork(501, { technology = '4G' })
        ASSERT_TRUE(result.available)
        ASSERT_FALSE(result.roaming)
        ASSERT_EQ(result.reason, 'home')
        ASSERT_EQ(result.carrierId, 'carrier_a')
        ASSERT_EQ(result.homeCarrierId, 'carrier_a')
    end)
end)

TEST('subscriber roams to an available partner when home is unavailable', function()
    withCarriers({
        makeCarrier('carrier_a', { 'carrier_b' }, 10),
        makeCarrier('carrier_b', {}, 20),
    }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(502,
            subscriber('license:roaming', 'sim-roaming', 'carrier_a', true)))
        ASSERT_TRUE(CarrierRegistry.SetAvailability('carrier_a', false))
        local result = CarrierSelection.ResolveSubscriberNetwork(502, { technology = '4G' })
        ASSERT_TRUE(result.available)
        ASSERT_TRUE(result.roaming)
        ASSERT_EQ(result.reason, 'roaming')
        ASSERT_EQ(result.carrierId, 'carrier_b')
    end)
end)

TEST('subscriber with roaming disabled fails closed on home outage', function()
    withCarriers({
        makeCarrier('carrier_a', { 'carrier_b' }, 10),
        makeCarrier('carrier_b', {}, 20),
    }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(503,
            subscriber('license:no-roaming', 'sim-no-roaming', 'carrier_a', false)))
        ASSERT_TRUE(CarrierRegistry.SetAvailability('carrier_a', false))
        local result = CarrierSelection.ResolveSubscriberNetwork(503, { technology = '4G' })
        ASSERT_FALSE(result.available)
        ASSERT_EQ(result.reason, 'roaming_disabled')
        ASSERT_EQ(result.carrierId, nil)
    end)
end)

TEST('subscriber reports no partner when roaming has no configured fallback', function()
    withCarriers({ makeCarrier('carrier_a', {}, 10) }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(504,
            subscriber('license:no-partner', 'sim-no-partner', 'carrier_a', true)))
        ASSERT_TRUE(CarrierRegistry.SetAvailability('carrier_a', false))
        local result = CarrierSelection.ResolveSubscriberNetwork(504, { technology = '4G' })
        ASSERT_FALSE(result.available)
        ASSERT_EQ(result.reason, 'no_partner')
    end)
end)

TEST('player cleanup removes active subscriber binding but preserves durable identity', function()
    withCarriers({ makeCarrier('carrier_a', {}, 10) }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(505,
            subscriber('license:cleanup', 'sim-cleanup', 'carrier_a', true)))
        ASSERT_TRUE(SubscriberRegistry.Remove(505))
        ASSERT_EQ(SubscriberRegistry.Get(505), nil)
        ASSERT_EQ(SubscriberRegistry.GetPersisted()[1].playerId, 'license:cleanup')
    end)
end)

TEST('subscriber registry rejects persisted SIM collisions and cleans replaced identities', function()
    withCarriers({ makeCarrier('carrier_a', {}, 10) }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(512,
            subscriber('license:offline', 'sim-unique', 'carrier_a', true)))
        ASSERT_TRUE(SubscriberRegistry.Remove(512))
        local collision, collisionError = SubscriberRegistry.Set(513,
            subscriber('license:collision', 'sim-unique', 'carrier_a', true))
        ASSERT_FALSE(collision)
        ASSERT_EQ(collisionError, 'sim_id_in_use')

        ASSERT_TRUE(SubscriberRegistry.Set(514,
            subscriber('license:old', 'sim-old', 'carrier_a', true)))
        ASSERT_TRUE(SubscriberRegistry.Set(514,
            subscriber('license:new', 'sim-new', 'carrier_a', true)))
        local persisted = SubscriberRegistry.GetPersisted()
        ASSERT_EQ(#persisted, 2)
        ASSERT_EQ(persisted[1].playerId, 'license:new')
        ASSERT_EQ(persisted[2].playerId, 'license:offline')
    end)
end)

TEST('subscriber records persist and rebind through a stable player identity', function()
    withCarriers({ makeCarrier('carrier_a', {}, 10) }, function()
        local repository = MemoryRepository.New()
        ASSERT_TRUE(repository:Initialize())
        TelecomPersistence.SetRepository(repository)
        ASSERT_TRUE(TelecomPersistence.Initialize())
        ASSERT_TRUE(SubscriberRegistry.Set(506,
            subscriber('license:persisted', 'sim-persisted', 'carrier_a', true)))

        local loadOk, rows = repository:LoadSubscribers()
        ASSERT_TRUE(loadOk)
        ASSERT_EQ(#rows, 1)
        ASSERT_EQ(rows[1].player_id, 'license:persisted')

        SubscriberRegistry.Reset()
        TelecomPersistence.Reset()
        TelecomPersistence.SetRepository(repository)
        ASSERT_TRUE(TelecomPersistence.Initialize())
        local previousStableId = FrameworkBridge.GetStablePlayerId
        FrameworkBridge.GetStablePlayerId = function() return 'license:persisted' end
        local bound, bindError = SubscriberRegistry.Bind(507)
        FrameworkBridge.GetStablePlayerId = previousStableId
        ASSERT_TRUE(bound, bindError)
        ASSERT_EQ(SubscriberRegistry.Get(507).simId, 'sim-persisted')
    end, true)
end)

TEST('deferred subscriber writes are discarded by a persistence reset', function()
    local previousEnabled = Config.Features.Carriers
    local previousDefinitions = Config.Carriers
    local previousPersistence = Config.Persistence.enabled
    local previousAdapter = Config.Persistence.adapter
    Config.Features.Carriers = true
    Config.Carriers = { makeCarrier('carrier_a', {}, 10) }
    Config.Persistence.enabled = true
    Config.Persistence.adapter = 'auto'
    CarrierRegistry.Initialize(Config.Carriers)
    SubscriberRegistry.Reset()
    TelecomPersistence.Reset()
    ASSERT_TRUE(SubscriberRegistry.Set(507,
        subscriber('license:deferred', 'sim-deferred', 'carrier_a', true)))
    ASSERT_TRUE(TelecomPersistence.GetStatus().pendingWrites >= 1)
    TelecomPersistence.Reset()
    ASSERT_EQ(TelecomPersistence.GetStatus().pendingWrites, 0)
    SubscriberRegistry.Reset()
    CarrierRegistry.Reset()
    Config.Carriers = previousDefinitions
    Config.Features.Carriers = previousEnabled
    Config.Persistence.enabled = previousPersistence
    Config.Persistence.adapter = previousAdapter
end)

TEST('subscriber roaming is integrated into live connection selection', function()
    withCarriers({
        makeCarrier('carrier_a', { 'carrier_b' }, 10),
        makeCarrier('carrier_b', {}, 20),
    }, function()
        ASSERT_TRUE(TowerRegistry.Init({
            makeTower('ROAMING_TOWER', { 'carrier_a', 'carrier_b' }),
        }))
        ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
        ASSERT_TRUE(SubscriberRegistry.Set(508,
            subscriber('license:connection', 'sim-connection', 'carrier_a', true)))
        ASSERT_TRUE(CarrierRegistry.SetAvailability('carrier_a', false))
        local state = Connections.Reevaluate(508, vector3(0, 0, 0))
        ASSERT_EQ(state.towerId, 'ROAMING_TOWER')
        ASSERT_EQ(state.carrierId, 'carrier_b')
    end)
end)

TEST('availability changes reevaluate an active roaming subscriber immediately', function()
    withCarriers({
        makeCarrier('carrier_a', { 'carrier_b' }, 10),
        makeCarrier('carrier_b', {}, 20),
    }, function()
        ASSERT_TRUE(TowerRegistry.Init({
            makeTower('LIVE_ROAMING_TOWER', { 'carrier_a', 'carrier_b' }),
        }))
        ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
        ASSERT_TRUE(SubscriberRegistry.Set(511,
            subscriber('license:live-roaming', 'sim-live-roaming', 'carrier_a', true)))
        local initial = Connections.Reevaluate(511, vector3(0, 0, 0))
        ASSERT_EQ(initial.carrierId, 'carrier_a')
        ASSERT_TRUE(CarrierRegistry.SetAvailability('carrier_a', false))
        ASSERT_EQ(Connections.Get(511).carrierId, 'carrier_b')
    end)
end)

TEST('carrier-disabled servers keep subscriber APIs inert', function()
    local previousEnabled = Config.Features.Carriers
    Config.Features.Carriers = false
    SubscriberRegistry.Reset()
    local ok, errorCode = SubscriberRegistry.Set(509,
        subscriber('license:disabled', 'sim-disabled', 'carrier_a', true))
    ASSERT_FALSE(ok)
    ASSERT_EQ(errorCode, 'carriers_disabled')
    local result = CarrierSelection.ResolveSubscriberNetwork(509)
    ASSERT_TRUE(result.available)
    ASSERT_EQ(result.reason, 'disabled')
    Config.Features.Carriers = previousEnabled
end)

TEST('NOC exposes active subscriber carrier state', function()
    withCarriers({ makeCarrier('carrier_a', {}, 10) }, function()
        ASSERT_TRUE(SubscriberRegistry.Set(510,
            subscriber('license:noc', 'sim-noc', 'carrier_a', true)))
        local entities = NocServer.BuildEntities({
            subscribers = SubscriberRegistry.GetAll(),
        })
        local entity
        for _, candidate in ipairs(entities) do
            if candidate.entityType == 'subscriber' and candidate.entityId == 'sim:sim-noc' then
                entity = candidate
                break
            end
        end
        ASSERT_TRUE(entity ~= nil)
        ASSERT_EQ(entity.state.carrierId, 'carrier_a')
        ASSERT_EQ(entity.state.currentCarrierId, 'carrier_a')
        ASSERT_EQ(entity.metadata.playerId, 'license:noc')
    end)
end)
