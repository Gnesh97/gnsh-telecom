local function makeConnection(signal, towerId)
    return {
        source = 1,
        towerId = towerId or (signal > 0 and 'TOWER_A' or nil),
        signal = signal,
        signalLevel = Signal.GetLevel(signal),
        technology = signal > 0 and '4G' or nil,
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }
end

TEST('services allow voice while data is unavailable', function()
    local result = Services.Evaluate(makeConnection(30))

    ASSERT_TRUE(result.services.voice.available)
    ASSERT_FALSE(result.services.data.available)
    ASSERT_EQ(result.services.data.reason, 'signal')
end)

TEST('services are available at excellent and normal signal', function()
    local excellent = Services.Evaluate(makeConnection(95))
    local normal = Services.Evaluate(makeConnection(60))

    for _, service in ipairs(ServicePolicy.Names) do
        ASSERT_TRUE(excellent.services[service].available, service .. ' excellent')
        ASSERT_TRUE(normal.services[service].available, service .. ' normal')
    end
end)

TEST('weak signal applies each configured threshold independently', function()
    local result = Services.Evaluate(makeConnection(20))

    ASSERT_FALSE(result.services.voice.available)
    ASSERT_TRUE(result.services.sms.available)
    ASSERT_FALSE(result.services.data.available)
    ASSERT_TRUE(result.services.gps.available)
    ASSERT_TRUE(result.services.emergency.available)
end)

TEST('very weak signal and no service disable normal services', function()
    local veryWeak = Services.Evaluate(makeConnection(5))
    local noService = Services.Evaluate(makeConnection(0, nil))

    for _, service in ipairs(ServicePolicy.Names) do
        ASSERT_FALSE(veryWeak.services[service].available, service .. ' very weak')
        ASSERT_FALSE(noService.services[service].available, service .. ' no service')
        ASSERT_EQ(noService.services[service].reason, 'no_service')
    end
end)

TEST('service thresholds remain configurable', function()
    local previous = Config.Services.voice.minimumSignal
    Config.Services.voice.minimumSignal = 70

    local result = Services.Evaluate(makeConnection(60))
    ASSERT_FALSE(result.services.voice.available)
    ASSERT_EQ(result.services.voice.minimumSignal, 70)

    Config.Services.voice.minimumSignal = previous
end)

TEST('future backhaul state can block services with a structured reason', function()
    local result = Services.Evaluate(makeConnection(95), {
        backhaulStatus = Enums.BackhaulState.OFFLINE,
    })

    ASSERT_FALSE(result.services.voice.available)
    ASSERT_EQ(result.services.voice.reason, 'backhaul')
    ASSERT_EQ(result.services.voice.blockedBy, 'backhaul')
end)

TEST('CanUse returns service state for a connected player', function()
    Connections.Clear()
    local connection = makeConnection(30)
    connection.source = 99
    ASSERT_TRUE(Connections.Set(99, connection))

    local voice, voiceState = Services.CanUse(99, 'voice')
    local data, dataState = Services.CanUse(99, 'data')

    ASSERT_TRUE(voice)
    ASSERT_FALSE(data)
    ASSERT_EQ(voiceState.reason, 'available')
    ASSERT_EQ(dataState.reason, 'signal')
    Connections.Clear()
end)
