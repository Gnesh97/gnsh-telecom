local function makeSessionTower(id, maximum)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = maximum or 10 },
    }
end

local function makeSessionConnection(source, towerId)
    return {
        source = source,
        towerId = towerId,
        sectorId = nil,
        signal = 90,
        rawSignal = 90,
        signalLevel = Signal.GetLevel(90),
        technology = '4G',
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }
end

local function resetSessionState(towerId)
    ServiceSessions.Reset()
    TelecomRateLimit.Clear(501)
    TelecomRateLimit.Clear(502)
    TelecomRateLimit.Clear(503)
    TelecomRateLimit.Clear(504)
    TelecomRateLimit.Clear(505)
    TelecomRateLimit.Clear(506)
    TelecomRateLimit.Clear(507)
    Connections.Clear()
    TowerRegistry.Init({ makeSessionTower(towerId, 10) })
end

TEST('service sessions add voice and data demand to tower load', function()
    resetSessionState('SESSION_TOWER_LOAD')
    ASSERT_TRUE(Connections.Set(501, makeSessionConnection(501, 'SESSION_TOWER_LOAD'), {
        skipCapacity = true,
    }))

    local baseline = Capacity.RecalculateTower('SESSION_TOWER_LOAD', Connections.GetAll())
    ASSERT_EQ(baseline.connectedClients, 1)
    ASSERT_EQ(baseline.serviceDemand, 0)

    local ok, voice = ServiceSessions.Begin(501, 'VOICE')
    ASSERT_TRUE(ok)
    ASSERT_EQ(voice.service, 'VOICE')
    local withVoice = TowerRegistry.GetRuntimeState('SESSION_TOWER_LOAD')
    ASSERT_EQ(withVoice.serviceSessionCount, 1)
    ASSERT_EQ(withVoice.serviceDemand, 2)
    ASSERT_EQ(withVoice.loadPercent, 30)

    local dataOk, data = ServiceSessions.Begin(501, 'DATA')
    ASSERT_TRUE(dataOk)
    ASSERT_EQ(data.service, 'DATA')
    local withData = TowerRegistry.GetRuntimeState('SESSION_TOWER_LOAD')
    ASSERT_EQ(withData.serviceSessionCount, 2)
    ASSERT_EQ(withData.serviceDemand, 7)
    ASSERT_EQ(withData.loadPercent, 80)

    ASSERT_TRUE(ServiceSessions.End(voice.id, 501))
    ASSERT_TRUE(ServiceSessions.End(data.id, 501))
    Connections.Clear()
end)

TEST('idle connections do not add service demand', function()
    resetSessionState('SESSION_TOWER_IDLE')
    ASSERT_TRUE(Connections.Set(502, makeSessionConnection(502, 'SESSION_TOWER_IDLE'), {
        skipCapacity = true,
    }))
    local idle = Capacity.RecalculateTower('SESSION_TOWER_IDLE', Connections.GetAll())
    ASSERT_EQ(idle.loadPercent, 10)
    ASSERT_EQ(ServiceSessions.GetDemand('SESSION_TOWER_IDLE').demand, 0)
    Connections.Clear()
end)

TEST('service sessions enforce owner validation and replay protection', function()
    resetSessionState('SESSION_TOWER_OWNER')
    ASSERT_TRUE(Connections.Set(503, makeSessionConnection(503, 'SESSION_TOWER_OWNER'), {
        skipCapacity = true,
    }))
    local ok, session = ServiceSessions.Begin(503, 'VOICE')
    ASSERT_TRUE(ok)

    local previousSource = rawget(_G, 'source')
    rawset(_G, 'source', nil)
    local noOwnerUpdate, noOwnerUpdateError = ServiceSessions.Update(session.id, {})
    ASSERT_FALSE(noOwnerUpdate)
    ASSERT_EQ(noOwnerUpdateError, 'owner_required')
    local noOwnerEnd, noOwnerEndError = ServiceSessions.End(session.id)
    ASSERT_FALSE(noOwnerEnd)
    ASSERT_EQ(noOwnerEndError, 'owner_required')
    rawset(_G, 'source', previousSource)

    local updated, updateError = ServiceSessions.Update(session.id, { quality = 'HD' }, 999)
    ASSERT_FALSE(updated)
    ASSERT_EQ(updateError, 'session_owner_mismatch')

    local ended, endError = ServiceSessions.End(session.id, 999)
    ASSERT_FALSE(ended)
    ASSERT_EQ(endError, 'session_owner_mismatch')
    ASSERT_TRUE(ServiceSessions.End(session.id, 503))

    local replayed, replayError = ServiceSessions.End(session.id, 503)
    ASSERT_FALSE(replayed)
    ASSERT_EQ(replayError, 'session_replayed')
    local replayUpdate, replayUpdateError = ServiceSessions.Update(session.id, {}, 503)
    ASSERT_FALSE(replayUpdate)
    ASSERT_EQ(replayUpdateError, 'session_replayed')
    Connections.Clear()
end)

TEST('service sessions rate limit begins and clean up on disconnect', function()
    resetSessionState('SESSION_TOWER_LIMIT')
    ASSERT_TRUE(Connections.Set(506, makeSessionConnection(506, 'SESSION_TOWER_LIMIT'), {
        skipCapacity = true,
    }))
    local lastSession
    local allowedCount = 0
    for _ = 1, 9 do
        local ok, session = ServiceSessions.Begin(506, 'SMS')
        if ok then
            allowedCount = allowedCount + 1
            lastSession = session
            ASSERT_TRUE(ServiceSessions.End(session.id, 506))
        end
    end
    ASSERT_EQ(allowedCount, 8)
    ASSERT_TRUE(lastSession ~= nil)

    ASSERT_TRUE(Connections.Set(507, makeSessionConnection(507, 'SESSION_TOWER_LIMIT'), {
        skipCapacity = true,
    }))
    local cleanupOk, cleanupSession = ServiceSessions.Begin(507, 'DATA')
    ASSERT_TRUE(cleanupOk)
    local previousSource = rawget(_G, 'source')
    source = 507
    TriggerTestEvent('playerDropped')
    rawset(_G, 'source', previousSource)
    ASSERT_EQ(ServiceSessions.Get(cleanupSession.id), nil)
    ASSERT_EQ(ServiceSessions.Count(), 0)
    Connections.Clear()
end)

TEST('service session metadata updates demand without changing ownership', function()
    resetSessionState('SESSION_TOWER_UPDATE')
    ASSERT_TRUE(Connections.Set(504, makeSessionConnection(504, 'SESSION_TOWER_UPDATE'), {
        skipCapacity = true,
    }))
    local ok, session = ServiceSessions.Begin(504, 'DATA')
    ASSERT_TRUE(ok)
    local updated, result = ServiceSessions.Update(session.id, {
        intensity = 2,
        requestId = 'server-request',
    }, 504)
    ASSERT_TRUE(updated)
    ASSERT_EQ(result.demand, 10)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('SESSION_TOWER_UPDATE').serviceDemand, 10)
    ASSERT_TRUE(ServiceSessions.End(session.id, 504))
    Connections.Clear()
end)

TEST('service session updates are rate limited and feature flags fail closed', function()
    resetSessionState('SESSION_TOWER_UPDATE_LIMIT')
    ASSERT_TRUE(Connections.Set(505, makeSessionConnection(505, 'SESSION_TOWER_UPDATE_LIMIT'), {
        skipCapacity = true,
    }))
    local previousMaximum = Config.ServiceSessions.maxUpdatesPerSecond
    Config.ServiceSessions.maxUpdatesPerSecond = 1
    TelecomRateLimit.Clear(505)
    local ok, session = ServiceSessions.Begin(505, 'VOICE')
    ASSERT_TRUE(ok)
    ASSERT_TRUE(ServiceSessions.Update(session.id, { sequence = 1 }, 505))
    local limited, limitError = ServiceSessions.Update(session.id, { sequence = 2 }, 505)
    ASSERT_FALSE(limited)
    ASSERT_EQ(limitError, 'rate_limited')
    ASSERT_TRUE(ServiceSessions.End(session.id, 505))
    Config.ServiceSessions.maxUpdatesPerSecond = previousMaximum

    local previousEnabled = Config.Features.ServiceSessions
    Config.Features.ServiceSessions = false
    local disabled, disabledError = ServiceSessions.Begin(505, 'VOICE')
    ASSERT_FALSE(disabled)
    ASSERT_EQ(disabledError, 'service_sessions_disabled')
    Config.Features.ServiceSessions = previousEnabled
    Connections.Clear()
end)

TEST('service sessions clear on resource stop', function()
    resetSessionState('SESSION_TOWER_STOP')
    ASSERT_TRUE(Connections.Set(509, makeSessionConnection(509, 'SESSION_TOWER_STOP'), {
        skipCapacity = true,
    }))
    TelecomRateLimit.Clear(509)
    local ok = ServiceSessions.Begin(509, 'BACKGROUND_DATA')
    ASSERT_TRUE(ok)
    ASSERT_EQ(ServiceSessions.Count(), 1)

    local previousSource = rawget(_G, 'source')
    rawset(_G, 'source', nil)
    TriggerTestEvent('onResourceStop', 'gnsh-telecom')
    rawset(_G, 'source', previousSource)
    ASSERT_EQ(ServiceSessions.Count(), 0)
    Connections.Clear()
end)
