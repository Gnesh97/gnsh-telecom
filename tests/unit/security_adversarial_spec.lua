TEST('security validation rejects malformed coordinates, distances, tables, and native failures', function()
    ASSERT_FALSE(TelecomSecurity.IsNearPlayer(1, vector3(0, 0, 0), -1))

    local previousPed = rawget(_G, 'GetPlayerPed')
    local previousCoords = rawget(_G, 'GetEntityCoords')
    GetPlayerPed = function() error('native failure') end
    GetEntityCoords = function() return vector3(0, 0, 0) end
    local near, nearError = TelecomSecurity.IsNearPlayer(1, vector3(0, 0, 0), 5)
    ASSERT_FALSE(near)
    ASSERT_EQ(nearError, 'player_ped_unavailable')
    rawset(_G, 'GetPlayerPed', previousPed)
    rawset(_G, 'GetEntityCoords', previousCoords)

    local cyclic = {}
    cyclic.self = cyclic
    ASSERT_FALSE(TelecomSecurity.IsSafeTable(cyclic, 4, 8))
    ASSERT_FALSE(TelecomSecurity.IsSafeTable(setmetatable({}, {}), 4, 8))

    local tooDeep = {}
    local cursor = tooDeep
    for _ = 1, 5 do
        cursor.next = {}
        cursor = cursor.next
    end
    ASSERT_FALSE(TelecomSecurity.IsSafeTable(tooDeep, 3, 8))
    ASSERT_FALSE(TelecomSecurity.IsSafeTable({}, '3', 8))
end)

TEST('security rate limits and audit records fail closed on malformed control input', function()
    TelecomRateLimit.Clear(902)
    local allowed, rateError = TelecomRateLimit.Allow(902, 'invalid', 0, 1)
    ASSERT_FALSE(allowed)
    ASSERT_EQ(rateError, 'invalid_rate_limit')

    allowed, rateError = TelecomRateLimit.Allow(902, 'invalid:name', 1000, 1)
    ASSERT_FALSE(allowed)
    ASSERT_EQ(rateError, 'invalid_rate_limit')

    TelecomAudit.Clear()
    ASSERT_EQ(TelecomAudit.Record(902, string.rep('x', 65), {}), nil)
    local cyclic = {}
    cyclic.self = cyclic
    ASSERT_EQ(TelecomAudit.Record(902, 'cyclic', cyclic), nil)
    ASSERT_EQ(TelecomAudit.Restore('not-a-list'), 0)
    ASSERT_TRUE(TelecomAudit.Record(902, 'safe', { requestId = 'security-test' }) ~= nil)
    TelecomAudit.Clear()
end)

local function securitySessionTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 10 },
    }
end

TEST('service sessions bind updates and completion to the creating resource', function()
    ServiceSessions.Reset()
    Connections.Clear()
    TelecomRateLimit.Clear(901)
    ASSERT_TRUE(TowerRegistry.Init({ securitySessionTower('SECURITY_SESSION_TOWER') }))
    ASSERT_TRUE(Connections.Set(901, {
        source = 901,
        towerId = 'SECURITY_SESSION_TOWER',
        signal = 90,
        rawSignal = 90,
        signalLevel = Signal.GetLevel(90),
        technology = '4G',
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }, { skipCapacity = true }))

    local previousInvoking = rawget(_G, 'GetInvokingResource')
    GetInvokingResource = function() return 'security-session-owner' end
    local ok, session = ServiceSessions.Begin(901, 'VOICE')
    ASSERT_TRUE(ok)
    ASSERT_TRUE(session ~= nil)

    GetInvokingResource = function() return 'untrusted-session-owner' end
    local updated, updateError = ServiceSessions.Update(session.id, {}, 901)
    ASSERT_FALSE(updated)
    ASSERT_EQ(updateError, 'session_resource_mismatch')

    GetInvokingResource = function() return 'security-session-owner' end
    ASSERT_TRUE(ServiceSessions.Update(session.id, { requestId = 'bound' }, 901))
    ASSERT_TRUE(ServiceSessions.End(session.id, 901))
    rawset(_G, 'GetInvokingResource', previousInvoking)
    Connections.Clear()
    ServiceSessions.Reset()
end)

TEST('sabotage rejects invalid sources and blocks re-entrant adapter execution', function()
    local previousEnabled = Config.Features.Sabotage
    local previousAlarm = Config.Sabotage.alarmProbability
    local previousMaxConcurrent = Config.Sabotage.maxConcurrent
    local previousAlert = DispatchBridge.Alert
    local previousPed = rawget(_G, 'GetPlayerPed')
    local previousCoords = rawget(_G, 'GetEntityCoords')

    Config.Features.Sabotage = true
    Config.Sabotage.alarmProbability = 1
    Config.Sabotage.maxConcurrent = 1
    local invalid, invalidError = Sabotage.Execute('spoofed-source', 'SECURITY_SABOTAGE_TOWER', 'antenna')
    ASSERT_FALSE(invalid)
    ASSERT_EQ(invalidError, 'invalid_source')

    ASSERT_TRUE(TowerRegistry.Init({ securitySessionTower('SECURITY_SABOTAGE_TOWER') }))
    GetPlayerPed = function() return 1 end
    GetEntityCoords = function() return vector3(0, 0, 0) end
    local nested, nestedError
    DispatchBridge.Alert = function()
        nested, nestedError = Sabotage.Execute(902, 'SECURITY_SABOTAGE_TOWER', 'antenna')
        return true
    end

    local ok, result = Sabotage.Execute(902, 'SECURITY_SABOTAGE_TOWER', 'antenna')
    ASSERT_TRUE(ok)
    ASSERT_FALSE(nested)
    ASSERT_EQ(nestedError, 'sabotage_in_progress')
    ASSERT_TRUE(result and result.failure and result.failure.id ~= nil)
    FailureEngine.Clear(result.failure.id)

    DispatchBridge.Alert = previousAlert
    rawset(_G, 'GetPlayerPed', previousPed)
    rawset(_G, 'GetEntityCoords', previousCoords)
    Config.Features.Sabotage = previousEnabled
    Config.Sabotage.alarmProbability = previousAlarm
    Config.Sabotage.maxConcurrent = previousMaxConcurrent
    TelecomRateLimit.Clear(902)
end)

TEST('incident network requests reject spoofed identifiers and assignees', function()
    local previousRequireAdmin = TelecomPermissions.RequireAdmin
    local previousSource = rawget(_G, 'source')
    local previousTrigger = rawget(_G, 'TriggerClientEvent')
    local response

    TelecomPermissions.RequireAdmin = function() return true end
    TriggerClientEvent = function(_, _, payload) response = payload end
    source = 903
    TelecomRateLimit.Clear(903)
    TriggerTestEvent(Constants.Events.INCIDENT_REQUEST, {
        action = 'assign',
        id = 'INC-SECURITY-001',
        assignedTo = 'not-a-player-source',
    })
    ASSERT_TRUE(response ~= nil)
    ASSERT_EQ(response.error, 'invalid_incident_assignment')

    response = nil
    TelecomRateLimit.Clear(903)
    TriggerTestEvent(Constants.Events.INCIDENT_REQUEST, {
        action = 'transition',
        id = string.rep('x', 97),
        state = 'CLOSED',
    })
    ASSERT_TRUE(response ~= nil)
    ASSERT_EQ(response.error, 'invalid_incident_payload')

    TelecomPermissions.RequireAdmin = previousRequireAdmin
    rawset(_G, 'TriggerClientEvent', previousTrigger)
    rawset(_G, 'source', previousSource)
    TelecomRateLimit.Clear(903)
end)

TEST('custom bridge callbacks cannot escape lifecycle error handling', function()
    local previousInvoking = rawget(_G, 'GetInvokingResource')
    local previousState = rawget(_G, 'GetResourceState')
    local owner = 'security-sdk-owner'
    GetInvokingResource = function() return owner end
    GetResourceState = function(resourceName)
        return resourceName == owner and 'started' or 'stopped'
    end

    local provider = {
        name = 'security-throwing-dispatch',
        priority = 999,
        Detect = function() return true end,
        Initialize = function() return true end,
        Shutdown = function() return true end,
        HealthCheck = function() return 'ACTIVE' end,
        Alert = function() error('untrusted adapter') end,
    }
    local ok = BridgeSDK.RegisterBridge('dispatch', provider)
    ASSERT_TRUE(ok)
    local callOk = BridgeManager.Call('dispatch', 'Alert', { source = 904 })
    ASSERT_FALSE(callOk)
    ASSERT_TRUE(BridgeSDK.UnregisterBridge('dispatch', provider.name))

    rawset(_G, 'GetInvokingResource', previousInvoking)
    rawset(_G, 'GetResourceState', previousState)
end)

TEST('NOC snapshot access fails closed for non-privileged sources', function()
    local previousIsAdmin = TelecomPermissions.IsAdmin
    local previousAce = rawget(_G, 'IsPlayerAceAllowed')
    TelecomPermissions.IsAdmin = function() return false end
    IsPlayerAceAllowed = function() return false end
    local allowed, errorCode = NocServer.GetSnapshot(905)
    ASSERT_FALSE(allowed)
    ASSERT_EQ(errorCode, 'not_authorized')
    TelecomPermissions.IsAdmin = previousIsAdmin
    rawset(_G, 'IsPlayerAceAllowed', previousAce)
end)
