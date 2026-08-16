local function makeTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = {
            radius = 100,
            minimum = 10,
        },
        technologies = { '4G' },
        capacity = {
            maximum = 100,
        },
    }
end

TEST('environment defaults to open area with full multiplier', function()
    local result = Signal.ResolveEnvironment(vector3(0, 0, 0), nil)

    ASSERT_EQ(result.category, 'OPEN_AREA')
    ASSERT_EQ(result.zoneId, nil)
    ASSERT_EQ(result.multiplier, 1.0)
end)

TEST('environment accepts known categories but ignores client multipliers', function()
    local result = Signal.ResolveEnvironment(vector3(0, 0, 0), {
        category = 'TUNNEL',
        multiplier = 10.0,
    })
    local invalid = Signal.ResolveEnvironment(vector3(0, 0, 0), {
        category = 'CLIENT_SUPER_SIGNAL',
        multiplier = 0.0,
    })

    ASSERT_EQ(result.category, 'TUNNEL')
    ASSERT_EQ(result.multiplier, 0.45)
    ASSERT_EQ(invalid.category, 'OPEN_AREA')
    ASSERT_EQ(invalid.multiplier, 1.0)
end)

TEST('environment ignores an unknown configured zone id', function()
    local result = Signal.ResolveEnvironment(vector3(0, 0, 0), {
        zoneId = 'NOT_CONFIGURED',
    })

    ASSERT_EQ(result.category, 'OPEN_AREA')
    ASSERT_EQ(result.zoneId, nil)
    ASSERT_EQ(result.multiplier, 1.0)
end)

TEST('environment validation rejects signal gains and malformed zones', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.Environment.multipliers.TUNNEL = 1.1
    invalid.Environment.zones = {
        {
            id = 'BROKEN_ZONE',
            coords = vector3(0, 0, 0),
            radius = 0,
            category = 'UNKNOWN_ZONE_TYPE',
        },
    }

    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    local message = table.concat(errors, '; ')
    ASSERT_TRUE(message:find('between 0 and 1', 1, true) ~= nil)
    ASSERT_TRUE(message:find('greater than zero', 1, true) ~= nil)
    ASSERT_TRUE(message:find('allowed environment category', 1, true) ~= nil)
end)

TEST('configured environment zones require a matching position', function()
    local previousZones = Config.Environment.zones
    Config.Environment.zones = {
        {
            id = 'TEST_TUNNEL_ZONE',
            coords = vector3(10, 0, 0),
            radius = 20,
            category = 'TUNNEL',
        },
    }

    local inside = Signal.ResolveEnvironment(vector3(10, 0, 0), {
        zoneId = 'TEST_TUNNEL_ZONE',
        category = 'OPEN_AREA',
    })
    local outside = Signal.ResolveEnvironment(vector3(100, 0, 0), {
        zoneId = 'TEST_TUNNEL_ZONE',
    })
    local clientContext = Environment.GetContext(vector3(10, 0, 0))

    Config.Environment.zones = previousZones

    ASSERT_EQ(inside.category, 'TUNNEL')
    ASSERT_EQ(inside.zoneId, 'TEST_TUNNEL_ZONE')
    ASSERT_EQ(inside.multiplier, 0.45)
    ASSERT_EQ(outside.category, 'OPEN_AREA')
    ASSERT_EQ(outside.zoneId, nil)
    ASSERT_EQ(clientContext.category, 'TUNNEL')
    ASSERT_EQ(clientContext.zoneId, 'TEST_TUNNEL_ZONE')
end)

TEST('environment modifier changes signal and leaving the zone restores it', function()
    local tower = makeTower('ENVIRONMENT_TOWER')
    local openSignal = Signal.CalculateRaw(tower, vector3(0, 0, 0), {
        category = 'OPEN_AREA',
    })
    local tunnelSignal = Signal.CalculateRaw(tower, vector3(0, 0, 0), {
        category = 'TUNNEL',
    })

    ASSERT_EQ(openSignal, 100)
    ASSERT_EQ(tunnelSignal, 45)
end)

TEST('coverage and connections preserve validated environment context', function()
    local tower = makeTower('ENVIRONMENT_CONNECTION_TOWER')
    ASSERT_TRUE(TowerRegistry.Init({ tower }))
    ASSERT_TRUE(SpatialIndex.Rebuild({ tower }))
    Connections.Clear()

    local state = Connections.Reevaluate(1, vector3(0, 0, 0), {
        category = 'TUNNEL',
        multiplier = 99.0,
    })

    ASSERT_EQ(state.towerId, 'ENVIRONMENT_CONNECTION_TOWER')
    ASSERT_EQ(state.rawSignal, 45)
    ASSERT_EQ(state.environment.category, 'TUNNEL')
    ASSERT_EQ(state.environment.multiplier, 0.45)

    local restored = Connections.Reevaluate(1, vector3(0, 0, 0), {
        category = 'OPEN_AREA',
    })
    ASSERT_EQ(restored.rawSignal, 100)
    ASSERT_EQ(restored.environment.category, 'OPEN_AREA')

    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
end)

TEST('client position payload contains bounded environment context', function()
    local eventName
    local payload
    local previousTrigger = TriggerServerEvent
    TriggerServerEvent = function(name, value)
        eventName = name
        payload = value
    end

    ASSERT_TRUE(ClientState.ReportPosition(vector3(1, 2, 3)))
    ASSERT_EQ(eventName, Constants.Events.POSITION_UPDATE)
    ASSERT_EQ(payload.environment.category, 'OPEN_AREA')
    ASSERT_EQ(payload.environment.multiplier, nil)

    TriggerServerEvent = previousTrigger
end)
