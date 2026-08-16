local function makeApiState(source)
    return {
        source = source,
        towerId = 'API_TOWER_A',
        signal = 75,
        rawSignal = 75,
        signalLevel = 'GOOD',
        technology = '4G',
        congestion = 'NORMAL',
        loadPercent = 0,
        effectiveCapacity = 100,
        capacityEffects = {},
        services = {},
        environment = {
            category = 'OPEN_AREA',
            multiplier = 1.0,
        },
    }
end

TEST('public API registers required server exports', function()
    local required = {
        'HasSignal',
        'GetSignalStrength',
        'GetSignalLevel',
        'GetNetworkType',
        'GetConnectedTower',
        'GetNetworkState',
        'CanCall',
        'CanSendSMS',
        'HasDataConnection',
        'CanUseService',
    }

    for _, name in ipairs(required) do
        ASSERT_TRUE(type(registeredExports[name]) == 'function', name .. ' export missing')
    end
    ASSERT_EQ(TelecomAPI.ApiVersion, Constants.ApiVersion)
end)

TEST('public API returns safe values for invalid or disconnected sources', function()
    Connections.Clear()

    ASSERT_FALSE(TelecomAPI.HasSignal('invalid'))
    ASSERT_EQ(TelecomAPI.GetSignalStrength('invalid'), 0)
    ASSERT_EQ(TelecomAPI.GetSignalLevel('invalid'), 'NO_SERVICE')
    ASSERT_EQ(TelecomAPI.GetNetworkType('invalid'), nil)
    ASSERT_EQ(TelecomAPI.GetConnectedTower('invalid'), nil)
    ASSERT_EQ(TelecomAPI.GetNetworkState('invalid'), nil)

    local canCall, callState = TelecomAPI.CanCall('invalid')
    ASSERT_FALSE(canCall)
    ASSERT_EQ(callState.reason, 'player_not_connected')
end)

TEST('public API exposes defensive network state and service queries', function()
    Connections.Clear()
    local state = makeApiState(10)
    ASSERT_TRUE(Connections.Set(10, state, { skipCapacity = true }))

    ASSERT_TRUE(TelecomAPI.HasSignal(10))
    ASSERT_EQ(TelecomAPI.GetSignalStrength(10), 75)
    ASSERT_EQ(TelecomAPI.GetSignalLevel(10), 'GOOD')
    ASSERT_EQ(TelecomAPI.GetNetworkType(10), '4G')
    ASSERT_EQ(TelecomAPI.GetConnectedTower(10), 'API_TOWER_A')

    local snapshot = TelecomAPI.GetNetworkState(10)
    ASSERT_EQ(snapshot.apiVersion, Constants.ApiVersion)
    snapshot.towerId = 'MUTATED'
    snapshot.environment.category = 'TUNNEL'
    ASSERT_EQ(TelecomAPI.GetConnectedTower(10), 'API_TOWER_A')
    ASSERT_EQ(TelecomAPI.GetNetworkState(10).environment.category, 'OPEN_AREA')

    local canCall, callState = TelecomAPI.CanCall(10)
    local canSms = TelecomAPI.CanSendSMS(10)
    local hasData = TelecomAPI.HasDataConnection(10)
    ASSERT_TRUE(canCall)
    ASSERT_TRUE(callState.available)
    ASSERT_TRUE(canSms)
    ASSERT_TRUE(hasData)

    local unknown, unknownState = TelecomAPI.CanUseService(10, 'fax')
    ASSERT_FALSE(unknown)
    ASSERT_EQ(unknownState.reason, 'unknown_service')

    Connections.Clear()
end)

TEST('public API emits stable connection and service change events', function()
    triggeredEvents = {}
    local previous = makeApiState(10)
    local current = Utils.DeepCopy(previous)
    current.towerId = 'API_TOWER_B'
    current.signal = 60
    current.rawSignal = 60
    current.signalLevel = 'NORMAL'
    current.technology = '5G'
    current.services = {
        voice = { available = true },
        data = { available = false },
    }

    TelecomAPI.EmitStateEvents(previous, current)

    local names = {}
    for _, event in ipairs(triggeredEvents) do names[event[1]] = true end
    ASSERT_TRUE(names[Constants.ApiEvents.CONNECTION_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.SIGNAL_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.SIGNAL_LEVEL_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.TOWER_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.NETWORK_TYPE_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.SERVICE_CHANGED])

    local connectionEvent = triggeredEvents[1]
    ASSERT_EQ(connectionEvent[2], 10)
    ASSERT_EQ(connectionEvent[3].towerId, 'API_TOWER_B')
    ASSERT_EQ(connectionEvent[4].towerId, 'API_TOWER_A')
end)

TEST('connection reevaluation routes state changes through public events', function()
    TowerRegistry.Init({
        {
            id = 'API_RUNTIME_TOWER',
            coords = vector3(0, 0, 0),
            coverage = { radius = 100, minimum = 10 },
            technologies = { '4G' },
            capacity = { maximum = 100 },
        },
    })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    Connections.Clear()
    triggeredEvents = {}

    local state = Connections.Reevaluate(21, vector3(0, 0, 0))
    ASSERT_EQ(state.towerId, 'API_RUNTIME_TOWER')

    local names = {}
    for _, event in ipairs(triggeredEvents) do names[event[1]] = true end
    ASSERT_TRUE(names[Constants.ApiEvents.CONNECTION_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.TOWER_CHANGED])
    ASSERT_TRUE(names[Constants.ApiEvents.SIGNAL_CHANGED])

    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
end)
