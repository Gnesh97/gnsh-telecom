local function makeOperationsTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetOperationsState()
    Connections.Clear()
    FailureEngine.Reset()
    IncidentManager.Reset()
    TowerRegistry.Init({ makeOperationsTower('OPERATIONS_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
end

TEST('failure lifecycle creates and resolves an incident', function()
    local previousIncidents = Config.Features.Incidents
    Config.Features.Incidents = true
    resetOperationsState()

    local ok, failure = FailureEngine.Create('OPERATIONS_TOWER', 'RADIO_FAILURE')
    local snapshot = IncidentManager.GetSnapshot()

    ASSERT_TRUE(ok)
    ASSERT_EQ(#snapshot.incidents, 1)
    ASSERT_EQ(snapshot.incidents[1].failureId, failure.id)
    ASSERT_EQ(snapshot.incidents[1].status, Enums.IncidentState.OPEN)
    ASSERT_EQ(snapshot.incidents[1].severity, 'HIGH')

    ASSERT_TRUE(FailureEngine.Clear(failure.id))
    local resolved = IncidentManager.Get(snapshot.incidents[1].id)
    ASSERT_EQ(resolved.status, Enums.IncidentState.RESOLVED)

    Config.Features.Incidents = previousIncidents
end)

TEST('technician workflow validates distance and completes a repair', function()
    local previousTechnician = Config.Features.Technician
    local previousIncidents = Config.Features.Incidents
    local previousAce = rawget(_G, 'IsPlayerAceAllowed')
    local previousGetPlayerPed = rawget(_G, 'GetPlayerPed')
    local previousGetEntityCoords = rawget(_G, 'GetEntityCoords')
    local previousGetPlayerIdentifierByType = rawget(_G, 'GetPlayerIdentifierByType')
    local previousGetGameTimer = rawget(_G, 'GetGameTimer')
    local now = 100000

    Config.Features.Technician = true
    Config.Features.Incidents = true
    IsPlayerAceAllowed = function() return true end
    GetPlayerPed = function() return 1 end
    GetEntityCoords = function() return vector3(0, 0, 0) end
    GetPlayerIdentifierByType = function(source, identifierType)
        return identifierType .. ':operations-' .. tostring(source)
    end
    GetGameTimer = function() return now end
    resetOperationsState()

    local created, failure = FailureEngine.Create('OPERATIONS_TOWER', 'RADIO_FAILURE')
    local incidents = IncidentManager.GetSnapshot()
    local incident = incidents.incidents[1]
    ASSERT_TRUE(created)

    local diagnosed, _, diagnosis = TelecomDebug.Execute(7, {
        'technician', 'diagnose', incident.id,
    })
    ASSERT_TRUE(diagnosed)
    ASSERT_TRUE(diagnosis.session.sessionId ~= nil)

    now = now + Config.Technician.diagnosticDurationMs
    local diagnosisCompleted, _, diagnosisResult = TelecomDebug.Execute(7, {
        'technician', 'diagnose_complete', diagnosis.session.sessionId,
    })
    ASSERT_TRUE(diagnosisCompleted)
    ASSERT_TRUE(diagnosisResult.diagnosis ~= nil)
    ASSERT_EQ(diagnosisResult.failure, nil)

    local begun, _, beginResult = TelecomDebug.Execute(7, {
        'technician', 'begin', incident.id,
    })
    ASSERT_TRUE(begun)
    ASSERT_EQ(beginResult.incident.status, Enums.IncidentState.DIAGNOSING)
    local beginHistory = beginResult.incident.history[#beginResult.incident.history]
    ASSERT_EQ(beginHistory.details.actorId, 'license:operations-7')

    now = now + Config.Technician.repairDurationMs
    local completed, _, completeResult = TelecomDebug.Execute(7, {
        'technician', 'complete', beginResult.session.sessionId,
    })
    ASSERT_TRUE(completed)
    ASSERT_EQ(completeResult.incident.status, Enums.IncidentState.VERIFYING)
    ASSERT_TRUE(FailureEngine.Get(failure.id) ~= nil)
    local verified, _, verifiedResult = TelecomDebug.Execute(7, {
        'technician', 'verify', completeResult.workOrder.id,
    })
    ASSERT_TRUE(verified)
    ASSERT_EQ(verifiedResult.incident.status, Enums.IncidentState.RESOLVED)
    local completionHistory = completeResult.incident.history[#completeResult.incident.history]
    ASSERT_EQ(completionHistory.details.actorId, 'license:operations-7')
    ASSERT_EQ(#FailureEngine.GetTowerFailures('OPERATIONS_TOWER'), 0)

    Config.Features.Technician = previousTechnician
    Config.Features.Incidents = previousIncidents
    rawset(_G, 'IsPlayerAceAllowed', previousAce)
    rawset(_G, 'GetPlayerPed', previousGetPlayerPed)
    rawset(_G, 'GetEntityCoords', previousGetEntityCoords)
    rawset(_G, 'GetPlayerIdentifierByType', previousGetPlayerIdentifierByType)
    rawset(_G, 'GetGameTimer', previousGetGameTimer)
end)

TEST('NOC snapshot requires access and returns defensive operational data', function()
    local previousNoc = Config.Features.NOC
    local previousAce = rawget(_G, 'IsPlayerAceAllowed')
    Config.Features.NOC = true
    IsPlayerAceAllowed = function() return true end
    resetOperationsState()
    ASSERT_TRUE(Connections.Reevaluate(7, vector3(0, 0, 0)))

    local ok, snapshot = NocServer.GetSnapshot(7)
    ASSERT_TRUE(ok)
    ASSERT_EQ(snapshot.counts.connectedClients, 1)
    ASSERT_EQ(#snapshot.towers, 1)
    ASSERT_EQ(snapshot.towers[1].id, 'OPERATIONS_TOWER')

    snapshot.towers[1].id = 'MUTATED'
    local nextOk, nextSnapshot = NocServer.GetSnapshot(7)
    ASSERT_TRUE(nextOk)
    ASSERT_EQ(nextSnapshot.towers[1].id, 'OPERATIONS_TOWER')

    IsPlayerAceAllowed = function() return false end
    local denied, errorCode = NocServer.GetSnapshot(7)
    ASSERT_FALSE(denied)
    ASSERT_EQ(errorCode, 'not_authorized')

    Config.Features.NOC = previousNoc
    rawset(_G, 'IsPlayerAceAllowed', previousAce)
end)
