local function makeTower(id, x, y, radius)
    return {
        id = id,
        coords = vector3(x, y, 0),
        coverage = {
            radius = radius or 100,
            minimum = 10,
        },
        technologies = { '4G' },
        capacity = {
            maximum = 100,
        },
    }
end

local function makeState(source, towerId, signal)
    return {
        source = source,
        towerId = towerId,
        signal = signal or 0,
        signalLevel = Signal.GetLevel(signal or 0),
        technology = towerId and '4G' or nil,
        congestion = Enums.CongestionState.NORMAL,
        services = {},
        updatedAt = 1,
    }
end

TEST('connections reject invalid player sources safely', function()
    Connections.Clear()

    ASSERT_FALSE(Connections.Set(0, makeState(0, nil, 0)))
    local state, changed = Connections.Reevaluate('invalid', vector3(0, 0, 0))
    ASSERT_EQ(state, nil)
    ASSERT_FALSE(changed)
    ASSERT_EQ(Connections.Count(), 0)
end)

TEST('connections store one defensive state per player', function()
    Connections.Clear()
    local input = makeState('1', 'TOWER_A', 80)

    local ok, changed = Connections.Set('1', input)
    ASSERT_TRUE(ok)
    ASSERT_TRUE(changed)

    input.signal = 0
    local stored = Connections.Get(1)
    ASSERT_EQ(stored.source, 1)
    ASSERT_EQ(stored.towerId, 'TOWER_A')
    ASSERT_EQ(stored.signal, 80)
    ASSERT_EQ(Connections.Count(), 1)
end)

TEST('connections compare meaningful state changes and preserve previous state', function()
    Connections.Clear()
    ASSERT_TRUE(Connections.Set(1, makeState(1, 'TOWER_A', 80)))

    local nextState = makeState(1, 'TOWER_A', 80)
    nextState.updatedAt = 2
    local ok, changed = Connections.Set(1, nextState)
    ASSERT_TRUE(ok)
    ASSERT_FALSE(changed)

    local previous = Connections.GetPrevious(1)
    ASSERT_EQ(previous.updatedAt, 1)
    ASSERT_FALSE(Connections.HasChanged(Connections.Get(1), Connections.Get(1)))
end)

TEST('connections reevaluate selects, changes and clears serving tower', function()
    Connections.Clear()
    ASSERT_TRUE(SpatialIndex.Rebuild({
        makeTower('TOWER_A', 0, 0),
        makeTower('TOWER_B', 200, 0),
    }))

    local state, changed = Connections.Reevaluate(1, vector3(0, 0, 0))
    ASSERT_TRUE(changed)
    ASSERT_EQ(state.towerId, 'TOWER_A')
    ASSERT_EQ(state.signal, 100)
    ASSERT_EQ(state.signalLevel, Enums.SignalLevel.EXCELLENT)
    ASSERT_EQ(state.technology, '4G')
    ASSERT_EQ(state.congestion, Enums.CongestionState.NORMAL)

    local sameState, sameChanged = Connections.Reevaluate(1, vector3(0, 0, 0))
    ASSERT_EQ(sameState.towerId, 'TOWER_A')
    ASSERT_FALSE(sameChanged)

    local movedState, movedChanged = Connections.Reevaluate(1, vector3(200, 0, 0))
    ASSERT_TRUE(movedChanged)
    ASSERT_EQ(movedState.towerId, 'TOWER_B')

    local noService, noServiceChanged = Connections.Reevaluate(1, vector3(500, 0, 0))
    ASSERT_TRUE(noServiceChanged)
    ASSERT_EQ(noService.towerId, nil)
    ASSERT_EQ(noService.signal, 0)
    ASSERT_EQ(noService.signalLevel, Enums.SignalLevel.NO_SERVICE)
end)

TEST('connections use dynamic selection instead of signal order alone', function()
    local towers = {
        makeTower('BUSY', 0, 0, 100),
        makeTower('AVAILABLE', 20, 0, 100),
    }

    TowerState.Initialize(towers)
    ASSERT_TRUE(TowerState.Update('BUSY', { loadPercent = 100 }))
    ASSERT_TRUE(TowerState.Update('AVAILABLE', { loadPercent = 0 }))
    ASSERT_TRUE(SpatialIndex.Rebuild(towers))

    local state = Connections.Reevaluate(1, vector3(0, 0, 0))
    ASSERT_EQ(state.towerId, 'AVAILABLE')

    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
end)

TEST('position updates validate payloads, rate-limit callers and prefer server coordinates', function()
    Connections.Clear()
    TelecomRateLimit.Clear(41)
    ASSERT_TRUE(SpatialIndex.Rebuild({
        makeTower('TOWER_A', 0, 0),
        makeTower('TOWER_B', 200, 0),
    }))

    local previousSource = rawget(_G, 'source')
    local previousTimer = rawget(_G, 'GetGameTimer')
    local previousGetPlayerPed = rawget(_G, 'GetPlayerPed')
    local previousGetEntityCoords = rawget(_G, 'GetEntityCoords')
    local serverCoords = vector3(0, 0, 0)

    rawset(_G, 'source', 41)
    rawset(_G, 'GetGameTimer', function() return 1000 end)
    rawset(_G, 'GetPlayerPed', function() return 1 end)
    rawset(_G, 'GetEntityCoords', function() return serverCoords end)

    local ok, errorMessage = pcall(function()
        TriggerTestEvent(Constants.Events.POSITION_UPDATE, {
            x = 200,
            y = 0,
            z = 0,
            environment = { category = 'TUNNEL' },
        })
        local state = Connections.Get(41)
        ASSERT_EQ(state.towerId, 'TOWER_A')
        ASSERT_EQ(state.environment.category, 'OPEN_AREA')

        TriggerTestEvent(Constants.Events.POSITION_UPDATE, {
            x = math.huge,
            y = 0,
            z = 0,
        })
        TriggerTestEvent(Constants.Events.POSITION_UPDATE, {
            x = 0,
            y = 0,
            z = 0,
            environment = { multiplier = 0.01 },
        })
        ASSERT_EQ(Connections.Get(41).towerId, 'TOWER_A')

        for _ = 1, 3 do
            TriggerTestEvent(Constants.Events.POSITION_UPDATE, {
                x = 200,
                y = 0,
                z = 0,
            })
        end

        serverCoords = vector3(200, 0, 0)
        TriggerTestEvent(Constants.Events.POSITION_UPDATE, {
            x = 0,
            y = 0,
            z = 0,
        })
        ASSERT_EQ(Connections.Get(41).towerId, 'TOWER_A')
    end)

    rawset(_G, 'source', previousSource)
    rawset(_G, 'GetGameTimer', previousTimer)
    rawset(_G, 'GetPlayerPed', previousGetPlayerPed)
    rawset(_G, 'GetEntityCoords', previousGetEntityCoords)
    Connections.Clear()
    SpatialIndex.Rebuild({})

    if not ok then error(errorMessage, 0) end
end)

TEST('connections remove player state and clear on restart', function()
    Connections.Clear()
    ASSERT_TRUE(Connections.Set(1, makeState(1, 'TOWER_A', 80)))
    ASSERT_TRUE(Connections.Set(2, makeState(2, 'TOWER_B', 70)))
    ASSERT_EQ(Connections.Count(), 2)

    ASSERT_TRUE(Connections.Remove('1'))
    ASSERT_EQ(Connections.Get(1), nil)
    ASSERT_EQ(Connections.Count(), 1)
    ASSERT_FALSE(Connections.Remove(1))

    Connections.Clear()
    ASSERT_EQ(Connections.Count(), 0)
    ASSERT_EQ(Connections.Get(2), nil)
end)
