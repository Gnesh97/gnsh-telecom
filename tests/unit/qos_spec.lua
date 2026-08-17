local function makeQosTower(id, maximum)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = maximum or 10 },
    }
end

local function makeQosConnection(source, towerId)
    return {
        source = source,
        towerId = towerId,
        signal = 90,
        rawSignal = 90,
        signalLevel = Signal.GetLevel(90),
        technology = '4G',
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }
end

TEST('qos exposes the configured class priority order', function()
    local emergencyPriority, emergency = QosEngine.GetPriority('EMERGENCY')
    local voicePriority, voice = QosEngine.GetPriority('VOICE')
    local backgroundPriority, background = QosEngine.GetPriority('BACKGROUND_DATA')

    ASSERT_EQ(emergency.class, 'EMERGENCY')
    ASSERT_EQ(voice.class, 'VOICE')
    ASSERT_EQ(background.class, 'BACKGROUND')
    ASSERT_TRUE(emergencyPriority > voicePriority)
    ASSERT_TRUE(voicePriority > backgroundPriority)
    ASSERT_EQ(emergencyPriority, Config.QoS.priorities.EMERGENCY)
end)

TEST('service session limits are validated before startup', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.ServiceSessions.maxActive = 0
    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('ServiceSessions.maxActive', 1, true) ~= nil)
end)

TEST('disabled optional qos modules do not require their configuration tables', function()
    local disabled = Utils.DeepCopy(Config)
    disabled.Features.ServiceSessions = false
    disabled.Features.QoS = false
    disabled.ServiceSessions = nil
    disabled.QoS = nil
    local ok, errors = Config.Validate(disabled)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
end)

TEST('qos allocates voice before degrading background traffic', function()
    QosEngine.Reset()
    local result = QosEngine.Allocate('QOS_PRIORITY_TOWER', {
        { id = 'background-1', service = 'BACKGROUND_DATA', demand = 4, createdAt = 1 },
        { id = 'voice-1', service = 'VOICE', demand = 2, createdAt = 2 },
    }, 3)

    ASSERT_EQ(result.allocations['voice-1'].allocated, 2)
    ASSERT_EQ(result.allocations['voice-1'].available, true)
    ASSERT_EQ(result.allocations['background-1'].allocated, 1)
    ASSERT_EQ(result.allocations['background-1'].degraded, true)
    ASSERT_EQ(result.degradedCount, 1)
end)

TEST('qos gives emergency traffic precedence over normal data', function()
    QosEngine.Reset()
    local result = QosEngine.Allocate('QOS_EMERGENCY_TOWER', {
        { id = 'data-1', service = 'DATA', demand = 4, createdAt = 1 },
        { id = 'emergency-1', service = 'EMERGENCY', demand = 3, createdAt = 2 },
    }, 3)

    ASSERT_EQ(result.allocations['emergency-1'].allocated, 3)
    ASSERT_EQ(result.allocations['emergency-1'].available, true)
    ASSERT_EQ(result.allocations['data-1'].allocated, 0)
    ASSERT_EQ(result.allocations['data-1'].blocked, true)
end)

TEST('qos priorities remain configurable without changing allocation determinism', function()
    local previous = Config.QoS.priorities.BACKGROUND
    Config.QoS.priorities.BACKGROUND = 120
    QosEngine.Reset()

    local result = QosEngine.Allocate('QOS_CONFIG_TOWER', {
        { id = 'voice-2', service = 'VOICE', demand = 2, createdAt = 1 },
        { id = 'background-2', service = 'BACKGROUND_DATA', demand = 2, createdAt = 2 },
    }, 2)

    ASSERT_EQ(result.allocations['background-2'].allocated, 2)
    ASSERT_EQ(result.allocations['voice-2'].allocated, 0)
    Config.QoS.priorities.BACKGROUND = previous
    QosEngine.Reset()
end)

TEST('qos service results are queryable and cleared with a session', function()
    QosEngine.Reset()
    local result = QosEngine.Allocate('QOS_RESULT_TOWER', {
        { id = 'result-1', source = 901, service = 'DATA', demand = 2 },
    }, 1)
    ASSERT_EQ(result.allocations['result-1'].degraded, true)
    ASSERT_EQ(QosEngine.GetServiceResult('result-1').towerId, 'QOS_RESULT_TOWER')
    ASSERT_TRUE(QosEngine.Clear('result-1'))
    ASSERT_EQ(QosEngine.GetServiceResult('result-1'), nil)
end)

TEST('qos feature disable clears stale allocations from service decisions', function()
    QosEngine.Reset()
    ServiceSessions.Reset()
    TelecomRateLimit.Clear(802)
    Connections.Clear()
    TowerRegistry.Init({ makeQosTower('QOS_DISABLED_TOWER', 10) })
    ASSERT_TRUE(Connections.Set(802, makeQosConnection(802, 'QOS_DISABLED_TOWER'), {
        skipCapacity = true,
    }))
    local started, session = ServiceSessions.Begin(802, 'VOICE')
    ASSERT_TRUE(started)
    local stateWithQos = Connections.Get(802)
    ASSERT_TRUE(type(stateWithQos.services.voice.qos) == 'table')

    local previous = Config.Features.QoS
    Config.Features.QoS = false
    ASSERT_EQ(QosEngine.GetServiceResult(session.id), nil)
    local evaluation = Services.Evaluate(stateWithQos)
    ASSERT_EQ(evaluation.qos, nil)
    ASSERT_EQ(evaluation.services.voice.qos, nil)
    local disabledAllocation = QosEngine.Allocate('QOS_DISABLED_TOWER', {
        session,
    }, 1)
    ASSERT_EQ(disabledAllocation.enabled, false)
    Config.Features.QoS = previous

    ASSERT_TRUE(ServiceSessions.End(session.id, 802))
    Connections.Clear()
    QosEngine.Reset()
end)

TEST('qos allocation integrates with active sessions and capacity state', function()
    QosEngine.Reset()
    ServiceSessions.Reset()
    TelecomRateLimit.Clear(801)
    Connections.Clear()
    TowerRegistry.Init({ makeQosTower('QOS_CAPACITY_TOWER', 4) })
    ASSERT_TRUE(Connections.Set(801, makeQosConnection(801, 'QOS_CAPACITY_TOWER'), {
        skipCapacity = true,
    }))

    local backgroundOk, background = ServiceSessions.Begin(801, 'BACKGROUND_DATA', {
        intensity = 4,
    })
    ASSERT_TRUE(backgroundOk)
    local voiceOk, voice = ServiceSessions.Begin(801, 'VOICE')
    ASSERT_TRUE(voiceOk)

    local backgroundResult = QosEngine.GetServiceResult(background.id)
    local voiceResult = QosEngine.GetServiceResult(voice.id)
    ASSERT_TRUE(backgroundResult.degraded)
    ASSERT_EQ(voiceResult.available, true)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('QOS_CAPACITY_TOWER').qosSummary.degradedCount, 1)
    ASSERT_TRUE(type(Connections.Get(801).services.voice.qos) == 'table')

    ASSERT_TRUE(ServiceSessions.End(background.id, 801))
    ASSERT_TRUE(ServiceSessions.End(voice.id, 801))
    Connections.Clear()
    QosEngine.Reset()
end)
