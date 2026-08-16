local function makeTower(id, maximum)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = {
            radius = 100,
            minimum = 10,
        },
        technologies = { '4G' },
        capacity = {
            maximum = maximum or 100,
        },
    }
end

local function makeConnection(source, towerId, signal)
    return {
        source = source,
        towerId = towerId,
        signal = signal or 80,
        rawSignal = signal or 80,
        signalLevel = Signal.GetLevel(signal or 80),
        technology = '4G',
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }
end

TEST('capacity calculates load and normal congestion', function()
    local result = Capacity.Calculate(0, 100)

    ASSERT_EQ(result.connectedClients, 0)
    ASSERT_EQ(result.effectiveCapacity, 100)
    ASSERT_EQ(result.loadPercent, 0)
    ASSERT_EQ(result.congestion, Enums.CongestionState.NORMAL)
end)

TEST('capacity uses deterministic congestion threshold boundaries', function()
    ASSERT_EQ(Capacity.GetCongestionState(59.99), Enums.CongestionState.NORMAL)
    ASSERT_EQ(Capacity.GetCongestionState(60), Enums.CongestionState.BUSY)
    ASSERT_EQ(Capacity.GetCongestionState(80), Enums.CongestionState.CONGESTED)
    ASSERT_EQ(Capacity.GetCongestionState(95), Enums.CongestionState.CRITICAL)
    ASSERT_EQ(Capacity.GetCongestionState(100), Enums.CongestionState.CRITICAL)
    ASSERT_EQ(Capacity.GetCongestionState(125), Enums.CongestionState.OVERLOADED)
end)

TEST('capacity calculates more than one hundred percent without clamping overload', function()
    local result = Capacity.Calculate(125, 100)

    ASSERT_EQ(result.loadPercent, 125)
    ASSERT_EQ(result.congestion, Enums.CongestionState.OVERLOADED)
    ASSERT_EQ(result.effects.dataPerformance, 'UNAVAILABLE')
end)

TEST('capacity respects a runtime effective capacity multiplier', function()
    TowerRegistry.Init({ makeTower('CAPACITY_HALF', 100) })
    ASSERT_TRUE(TowerState.Update('CAPACITY_HALF', { capacityMultiplier = 0.5 }))

    local result = Capacity.RecalculateTower('CAPACITY_HALF', {
        makeConnection(1, 'CAPACITY_HALF'),
    })

    ASSERT_EQ(result.effectiveCapacity, 50)
    ASSERT_EQ(result.connectedClients, 1)
    ASSERT_EQ(result.loadPercent, 2)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_HALF').effectiveCapacity, 50)
end)

TEST('capacity recalculates affected tower counters when connections move', function()
    TowerRegistry.Init({
        makeTower('CAPACITY_A', 2),
        makeTower('CAPACITY_B', 2),
    })
    Connections.Clear()

    ASSERT_TRUE(Connections.Set(1, makeConnection(1, 'CAPACITY_A')))
    ASSERT_TRUE(Connections.Set(2, makeConnection(2, 'CAPACITY_A')))
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_A').connectedClients, 2)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_A').loadPercent, 100)

    ASSERT_TRUE(Connections.Set(1, makeConnection(1, 'CAPACITY_B')))
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_A').connectedClients, 1)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_B').connectedClients, 1)

    ASSERT_TRUE(Connections.Remove(2))
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_A').connectedClients, 0)

    Connections.Clear()
    TowerState.Initialize({})
end)

TEST('overload changes effective signal and degrades data service', function()
    local state = makeConnection(80, 'CAPACITY_OVERLOADED')
    local result = Capacity.ApplyToConnection(state, {
        towerId = 'CAPACITY_OVERLOADED',
        connectedClients = 2,
        effectiveCapacity = 1,
        loadPercent = 200,
        congestion = Enums.CongestionState.OVERLOADED,
        capacityEffects = Capacity.GetEffects(Enums.CongestionState.OVERLOADED),
    })

    ASSERT_EQ(result.rawSignal, 80)
    ASSERT_EQ(result.signal, 52)
    ASSERT_EQ(result.congestion, Enums.CongestionState.OVERLOADED)
    ASSERT_EQ(result.services.data.available, false)
    ASSERT_EQ(result.services.data.reason, 'congestion')
    ASSERT_EQ(result.services.data.dataPerformance, 'UNAVAILABLE')
    ASSERT_EQ(result.services.voice.callSetupReliability, 0.5)
    ASSERT_EQ(result.services.sms.smsDelayMs, 3000)
end)

TEST('connection reevaluation applies overload without losing the serving tower', function()
    TowerRegistry.Init({
        {
            id = 'CAPACITY_LIVE_A',
            coords = vector3(0, 0, 0),
            coverage = { radius = 100, minimum = 10 },
            technologies = { '4G' },
            capacity = { maximum = 1 },
        },
        {
            id = 'CAPACITY_LIVE_B',
            coords = vector3(200, 0, 0),
            coverage = { radius = 100, minimum = 10 },
            technologies = { '4G' },
            capacity = { maximum = 1 },
        },
    })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    Connections.Clear()

    local previousTrigger = rawget(_G, 'TriggerClientEvent')
    local eventCount = 0
    TriggerClientEvent = function() eventCount = eventCount + 1 end

    local first = Connections.Reevaluate(1, vector3(0, 0, 0))
    ASSERT_EQ(first.towerId, 'CAPACITY_LIVE_A')
    ASSERT_EQ(first.congestion, Enums.CongestionState.CRITICAL)
    ASSERT_EQ(first.signal, 82)
    ASSERT_TRUE(first.services.data.available)

    local firstEventCount = eventCount
    local repeated, repeatedChanged = Connections.Reevaluate(1, vector3(0, 0, 0))
    ASSERT_EQ(repeated.towerId, 'CAPACITY_LIVE_A')
    ASSERT_FALSE(repeatedChanged)
    ASSERT_EQ(eventCount, firstEventCount)

    local second = Connections.Reevaluate(2, vector3(0, 0, 0))
    ASSERT_EQ(second.towerId, 'CAPACITY_LIVE_A')
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_LIVE_A').connectedClients, 2)
    ASSERT_EQ(Connections.Get(1).towerId, 'CAPACITY_LIVE_A')
    ASSERT_EQ(Connections.Get(1).congestion, Enums.CongestionState.OVERLOADED)
    ASSERT_FALSE(Connections.Get(1).services.data.available)

    local moved = Connections.Reevaluate(1, vector3(200, 0, 0))
    ASSERT_EQ(moved.towerId, 'CAPACITY_LIVE_B')
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_LIVE_A').connectedClients, 1)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('CAPACITY_LIVE_B').connectedClients, 1)

    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
    rawset(_G, 'TriggerClientEvent', previousTrigger)
end)

TEST('capacity effects remain configurable without random behavior', function()
    local previous = Config.Capacity.effects.BUSY.signalMultiplier
    Config.Capacity.effects.BUSY.signalMultiplier = 0.5

    ASSERT_EQ(Capacity.ApplySignal(80, Enums.CongestionState.BUSY), 40)

    Config.Capacity.effects.BUSY.signalMultiplier = previous
end)
