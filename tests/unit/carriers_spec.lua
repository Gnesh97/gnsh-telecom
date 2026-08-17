local function makeCarrier(id, priority, technologies)
    return {
        id = id,
        name = id:upper(),
        technologies = technologies or { '4G' },
        roamingPartners = {},
        priority = priority or 0,
        branding = { color = id },
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

local function withCarriers(definitions, fn)
    local previousEnabled = Config.Features.Carriers
    local previousDefinitions = Config.Carriers
    Config.Features.Carriers = true
    Config.Carriers = Utils.DeepCopy(definitions)
    ASSERT_TRUE(CarrierRegistry.Initialize(definitions))

    local ok, err = pcall(fn)

    CarrierRegistry.Reset()
    Config.Carriers = previousDefinitions
    Config.Features.Carriers = previousEnabled
    Connections.Clear()
    TowerRegistry.Init({})
    SpatialIndex.Rebuild({})
    if not ok then error(err, 0) end
end

TEST('multi-carrier feature defaults disabled', function()
    ASSERT_FALSE(Config.Features.Carriers)
end)

TEST('disabled carrier selection preserves the single-carrier path', function()
    local previousEnabled = Config.Features.Carriers
    Config.Features.Carriers = false
    CarrierRegistry.Reset()

    local result = CarrierSelection.Resolve({
        id = 'LEGACY_CARRIER_TOWER',
        carriers = { 'UNKNOWN_CARRIER' },
    }, {})
    ASSERT_TRUE(result.available)
    ASSERT_EQ(result.carrierId, nil)
    ASSERT_EQ(result.reason, 'disabled')

    local score = Selection.Score({
        towerId = 'LEGACY_CARRIER_TOWER',
        tower = makeTower('LEGACY_CARRIER_TOWER', { 'UNKNOWN_CARRIER' }),
        signal = 80,
    })
    ASSERT_TRUE(score ~= nil)
    Config.Features.Carriers = previousEnabled
end)

TEST('single carrier is selected and projected through ranking', function()
    withCarriers({ makeCarrier('carrier_a', 10) }, function()
        local result = CarrierSelection.Resolve(
            makeTower('SINGLE_CARRIER_TOWER', { 'carrier_a' }),
            { technology = '4G' }
        )
        ASSERT_TRUE(result.available)
        ASSERT_EQ(result.carrierId, 'carrier_a')
        ASSERT_EQ(result.carrier.name, 'CARRIER_A')

        local ranked = Selection.Rank({
            {
                towerId = 'SINGLE_CARRIER_TOWER',
                tower = makeTower('SINGLE_CARRIER_TOWER', { 'carrier_a' }),
                signal = 80,
            },
        })
        ASSERT_EQ(#ranked, 1)
        ASSERT_EQ(ranked[1].carrierId, 'carrier_a')
        ASSERT_EQ(ranked[1].scoreDetails.carrierPriority, 10)
    end)
end)

TEST('multiple carriers select the highest priority operator', function()
    withCarriers({
        makeCarrier('carrier_a', 10),
        makeCarrier('carrier_b', 20),
    }, function()
        local result = CarrierSelection.Resolve(
            makeTower('MULTI_CARRIER_TOWER', { 'carrier_a', 'carrier_b' }),
            { technology = '4G' }
        )
        ASSERT_TRUE(result.available)
        ASSERT_EQ(result.carrierId, 'carrier_b')
    end)
end)

TEST('carrier priority breaks equal serving-candidate scores', function()
    withCarriers({
        makeCarrier('carrier_a', 10),
        makeCarrier('carrier_b', 20),
    }, function()
        local ranked = Selection.Rank({
            {
                towerId = 'CARRIER_TOWER_A',
                tower = makeTower('CARRIER_TOWER_A', { 'carrier_a' }),
                signal = 80,
            },
            {
                towerId = 'CARRIER_TOWER_B',
                tower = makeTower('CARRIER_TOWER_B', { 'carrier_b' }),
                signal = 80,
            },
        })
        ASSERT_EQ(#ranked, 2)
        ASSERT_EQ(ranked[1].towerId, 'CARRIER_TOWER_B')
        ASSERT_EQ(ranked[1].carrierId, 'carrier_b')
    end)
end)

TEST('unavailable carrier fails closed when no advertised operator remains', function()
    withCarriers({ makeCarrier('carrier_a', 10) }, function()
        ASSERT_TRUE(CarrierRegistry.SetAvailability('carrier_a', false))
        local result = CarrierSelection.Resolve(
            makeTower('UNAVAILABLE_CARRIER_TOWER', { 'carrier_a' }),
            { technology = '4G' }
        )
        ASSERT_FALSE(result.available)
        ASSERT_EQ(result.reason, 'unavailable_carrier')
    end)
end)

TEST('equal carrier priorities use deterministic id ordering', function()
    withCarriers({
        makeCarrier('carrier_b', 10),
        makeCarrier('carrier_a', 10),
    }, function()
        local result = CarrierSelection.Resolve(
            makeTower('TIE_CARRIER_TOWER', { 'carrier_b', 'carrier_a' }),
            { technology = '4G' }
        )
        ASSERT_TRUE(result.available)
        ASSERT_EQ(result.carrierId, 'carrier_a')
    end)
end)

TEST('invalid carrier references fall back to a valid registered operator', function()
    withCarriers({ makeCarrier('carrier_a', 10) }, function()
        local result = CarrierSelection.Resolve(
            makeTower('INVALID_CARRIER_TOWER', { 'UNKNOWN_CARRIER' }),
            { technology = '4G' }
        )
        ASSERT_TRUE(result.available)
        ASSERT_EQ(result.carrierId, 'carrier_a')
        ASSERT_EQ(result.reason, 'fallback')
    end)
end)

TEST('carrier metadata is exposed in NOC tower entities', function()
    withCarriers({ makeCarrier('carrier_a', 10) }, function()
        local entities = NocServer.BuildEntities({
            towers = { makeTower('NOC_CARRIER_TOWER', { 'carrier_a' }) },
        })
        local towerEntity
        for _, entity in ipairs(entities) do
            if entity.entityType == 'tower' and entity.entityId == 'NOC_CARRIER_TOWER' then
                towerEntity = entity
                break
            end
        end
        ASSERT_TRUE(towerEntity ~= nil)
        ASSERT_EQ(towerEntity.metadata.carriers[1], 'carrier_a')
    end)
end)

TEST('connection state carries the selected operator identity', function()
    withCarriers({ makeCarrier('carrier_a', 10) }, function()
        ASSERT_TRUE(TowerRegistry.Init({
            makeTower('LIVE_CARRIER_TOWER', { 'carrier_a' }),
        }))
        ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
        local state = Connections.Reevaluate(301, vector3(0, 0, 0))
        ASSERT_EQ(state.towerId, 'LIVE_CARRIER_TOWER')
        ASSERT_EQ(state.carrierId, 'carrier_a')
    end)
end)
