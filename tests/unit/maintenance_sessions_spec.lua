local function makeMaintenanceTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetMaintenanceState()
    Connections.Clear()
    FailureEngine.Reset()
    IncidentManager.Reset()
    MaintenanceSessions.ClearAll()
    TowerRegistry.Init({ makeMaintenanceTower('MAINTENANCE_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
end

local function configureMaintenancePlayer()
    local previous = {
        technician = Config.Features.Technician,
        incidents = Config.Features.Incidents,
        ace = rawget(_G, 'IsPlayerAceAllowed'),
        getPlayerPed = rawget(_G, 'GetPlayerPed'),
        getEntityCoords = rawget(_G, 'GetEntityCoords'),
        getIdentifier = rawget(_G, 'GetPlayerIdentifierByType'),
        getGameTimer = rawget(_G, 'GetGameTimer'),
    }
    local now = 100000

    Config.Features.Technician = true
    Config.Features.Incidents = true
    IsPlayerAceAllowed = function() return true end
    GetPlayerPed = function() return 1 end
    GetEntityCoords = function() return vector3(0, 0, 0) end
    GetPlayerIdentifierByType = function(source, identifierType)
        return identifierType .. ':maintenance-' .. tostring(source)
    end
    GetGameTimer = function() return now end

    return previous, function(milliseconds)
        now = now + milliseconds
    end
end

local function restoreMaintenancePlayer(previous)
    Config.Features.Technician = previous.technician
    Config.Features.Incidents = previous.incidents
    rawset(_G, 'IsPlayerAceAllowed', previous.ace)
    rawset(_G, 'GetPlayerPed', previous.getPlayerPed)
    rawset(_G, 'GetEntityCoords', previous.getEntityCoords)
    rawset(_G, 'GetPlayerIdentifierByType', previous.getIdentifier)
    rawset(_G, 'GetGameTimer', previous.getGameTimer)
    MaintenanceSessions.ClearAll()
end

TEST('maintenance sessions reject early, wrong-owner and replayed completion', function()
    local previous, advance = configureMaintenancePlayer()
    resetMaintenanceState()
    local created, failure = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]

    local begun, beginResult = MaintenanceDiagnostics.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    local sessionId = beginResult.session.sessionId

    local early, earlyError = MaintenanceDiagnostics.Complete(7, sessionId)
    ASSERT_FALSE(early)
    ASSERT_EQ(earlyError, 'session_too_early')

    local wrongOwner, wrongOwnerError = MaintenanceDiagnostics.Complete(8, sessionId)
    ASSERT_FALSE(wrongOwner)
    ASSERT_EQ(wrongOwnerError, 'session_owner_mismatch')

    local wrongSession, wrongSessionError = MaintenanceDiagnostics.Complete(
        7,
        'DIAGNOSTIC-NOT-A-SESSION'
    )
    ASSERT_FALSE(wrongSession)
    ASSERT_EQ(wrongSessionError, 'session_not_found')

    local wrongKind, wrongKindError = MaintenanceRepairs.Complete(7, sessionId)
    ASSERT_FALSE(wrongKind)
    ASSERT_EQ(wrongKindError, 'session_kind_mismatch')

    GetPlayerIdentifierByType = function() return 'license:changed-actor' end
    advance(Config.Technician.diagnosticDurationMs)
    local changedActor, changedActorError = MaintenanceDiagnostics.Complete(7, sessionId)
    ASSERT_FALSE(changedActor)
    ASSERT_EQ(changedActorError, 'actor_identity_mismatch')
    GetPlayerIdentifierByType = function(source, identifierType)
        return identifierType .. ':maintenance-' .. tostring(source)
    end

    local staleCompletion, staleCompletionError = MaintenanceDiagnostics.Complete(7, sessionId)
    ASSERT_FALSE(staleCompletion)
    ASSERT_EQ(staleCompletionError, 'session_not_found')

    local restarted, restartedResult = MaintenanceDiagnostics.Begin(7, incident.id)
    ASSERT_TRUE(restarted)
    advance(Config.Technician.diagnosticDurationMs)
    local completed, result = MaintenanceDiagnostics.Complete(
        7,
        restartedResult.session.sessionId
    )
    ASSERT_TRUE(completed)
    ASSERT_TRUE(result.diagnosis ~= nil)
    ASSERT_EQ(result.failure, nil)

    local replayed, replayError = MaintenanceDiagnostics.Complete(7, sessionId)
    ASSERT_FALSE(replayed)
    ASSERT_EQ(replayError, 'session_not_found')
    restoreMaintenancePlayer(previous)
end)

TEST('repair completion requires server session and elapsed duration', function()
    local previous, advance = configureMaintenancePlayer()
    resetMaintenanceState()
    local created, failure = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]

    local begun, beginResult = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    ASSERT_EQ(beginResult.incident.status, Enums.IncidentState.DIAGNOSING)

    local early, earlyError = MaintenanceRepairs.Complete(7, beginResult.session.sessionId)
    ASSERT_FALSE(early)
    ASSERT_EQ(earlyError, 'session_too_early')

    local incidentAsSession, incidentAsSessionError = MaintenanceRepairs.Complete(7, incident.id)
    ASSERT_FALSE(incidentAsSession)
    ASSERT_EQ(incidentAsSessionError, 'session_not_found')

    advance(Config.Technician.repairDurationMs)
    local completed, result = MaintenanceRepairs.Complete(7, beginResult.session.sessionId)
    ASSERT_TRUE(completed)
    ASSERT_EQ(result.incident.status, Enums.IncidentState.VERIFYING)
    ASSERT_TRUE(FailureEngine.Get(failure.id) ~= nil)
    local verified, verifyResult = MaintenanceRepairs.Verify(7, result.workOrder.id)
    ASSERT_TRUE(verified)
    ASSERT_EQ(verifyResult.incident.status, Enums.IncidentState.RESOLVED)

    local replayed, replayError = MaintenanceRepairs.Complete(7, beginResult.session.sessionId)
    ASSERT_FALSE(replayed)
    ASSERT_EQ(replayError, 'session_not_found')
    restoreMaintenancePlayer(previous)
end)

TEST('repair completion rolls back the incident state when item removal fails', function()
    local previous, advance = configureMaintenancePlayer()
    local previousItems = Config.Technician.requiredItems
    Config.Technician.requiredItems = { RADIO_FAILURE = 'repair_kit' }
    InventoryBridge.SetAdapter({
        HasItem = function() return true end,
        RemoveItem = function() return false end,
        AddItem = function() return true end,
    })

    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)

    advance(Config.Technician.repairDurationMs)
    local completed, errorCode = MaintenanceRepairs.Complete(7, beginResult.session.sessionId)
    ASSERT_FALSE(completed)
    ASSERT_EQ(errorCode, 'required_item_remove_failed')
    ASSERT_EQ(IncidentManager.Get(incident.id).status, Enums.IncidentState.DIAGNOSING)
    ASSERT_TRUE(MaintenanceSessions.Get(beginResult.session.sessionId) ~= nil)

    Config.Technician.requiredItems = previousItems
    InventoryBridge.SetAdapter(nil)
    restoreMaintenancePlayer(previous)
end)

TEST('repair begin does not claim an incident without its required item', function()
    local previous, _ = configureMaintenancePlayer()
    local previousItems = Config.Technician.requiredItems
    Config.Technician.requiredItems = { RADIO_FAILURE = 'repair_kit' }
    InventoryBridge.SetAdapter({
        HasItem = function() return false end,
        AddItem = function() return true end,
    })

    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, errorCode = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_FALSE(begun)
    ASSERT_EQ(errorCode, 'required_item_missing')
    local unchanged = IncidentManager.Get(incident.id)
    ASSERT_EQ(unchanged.status, Enums.IncidentState.OPEN)
    ASSERT_EQ(unchanged.assignedTo, nil)

    Config.Technician.requiredItems = previousItems
    InventoryBridge.SetAdapter(nil)
    restoreMaintenancePlayer(previous)
end)

TEST('repair completion refunds the item when failure clearing fails', function()
    local previous, advance = configureMaintenancePlayer()
    local previousItems = Config.Technician.requiredItems
    local previousClear = FailureEngine.Clear
    local refundCount = 0
    Config.Technician.requiredItems = { RADIO_FAILURE = 'repair_kit' }
    InventoryBridge.SetAdapter({
        HasItem = function() return true end,
        RemoveItem = function() return true end,
        AddItem = function() refundCount = refundCount + 1; return true end,
    })

    resetMaintenanceState()
    local created, failure = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)

    advance(Config.Technician.repairDurationMs)
    local completed, completeResult = MaintenanceRepairs.Complete(7, beginResult.session.sessionId)
    ASSERT_TRUE(completed)
    FailureEngine.Clear = function() return false, 'failure_clear_failed' end
    local verified, errorCode = MaintenanceRepairs.Verify(7, completeResult.workOrder.id)
    ASSERT_FALSE(verified)
    ASSERT_EQ(errorCode, 'failure_clear_failed')
    ASSERT_EQ(refundCount, 0)
    ASSERT_EQ(IncidentManager.Get(incident.id).status, Enums.IncidentState.VERIFYING)
    ASSERT_TRUE(FailureEngine.Get(failure.id) ~= nil)

    FailureEngine.Clear = previousClear
    Config.Technician.requiredItems = previousItems
    InventoryBridge.SetAdapter(nil)
    restoreMaintenancePlayer(previous)
end)

TEST('repair session cleanup releases an incident for reassignment', function()
    local previous = configureMaintenancePlayer()
    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)

    rawset(_G, 'source', 7)
    TriggerTestEvent('playerDropped')
    rawset(_G, 'source', nil)
    local released = IncidentManager.Get(incident.id)
    ASSERT_EQ(released.status, Enums.IncidentState.ASSIGNED)
    ASSERT_EQ(released.assignedTo, nil)

    local reassigned, reassignedResult = MaintenanceRepairs.Begin(8, incident.id)
    ASSERT_TRUE(reassigned)
    ASSERT_EQ(reassignedResult.incident.status, Enums.IncidentState.DIAGNOSING)
    ASSERT_EQ(reassignedResult.incident.assignedTo, 8)
    TriggerTestEvent('onResourceStop', 'gnsh-telecom')
    local releasedAfterStop = IncidentManager.Get(incident.id)
    ASSERT_EQ(releasedAfterStop.status, Enums.IncidentState.ASSIGNED)
    ASSERT_EQ(releasedAfterStop.assignedTo, nil)
    restoreMaintenancePlayer(previous)
end)

TEST('maintenance cancellation is allowed after leaving the tower', function()
    local previous = configureMaintenancePlayer()
    local previousGetEntityCoords = rawget(_G, 'GetEntityCoords')
    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)

    GetEntityCoords = function() return vector3(1000, 1000, 0) end
    local cancelled, cancelResult = MaintenanceRepairs.Cancel(
        7,
        beginResult.session.sessionId,
        'left site'
    )
    ASSERT_TRUE(cancelled)
    ASSERT_EQ(cancelResult.incident.status, Enums.IncidentState.ASSIGNED)
    ASSERT_EQ(cancelResult.incident.assignedTo, nil)

    rawset(_G, 'GetEntityCoords', previousGetEntityCoords)
    restoreMaintenancePlayer(previous)
end)

TEST('inventory adapter destructive calls require explicit success', function()
    InventoryBridge.SetAdapter({ RemoveItem = function() end, AddItem = function() end })
    local removed = InventoryBridge.RemoveItem(7, 'repair_kit', 1)
    local added = InventoryBridge.AddItem(7, 'repair_kit', 1)
    ASSERT_FALSE(removed)
    ASSERT_FALSE(added)

    InventoryBridge.SetAdapter({
        RemoveItem = function() error('adapter failure') end,
        AddItem = function() error('adapter failure') end,
    })
    local removedWithError, removeError = InventoryBridge.RemoveItem(7, 'repair_kit', 1)
    local addedWithError, addError = InventoryBridge.AddItem(7, 'repair_kit', 1)
    ASSERT_FALSE(removedWithError)
    ASSERT_EQ(removeError, 'inventory_adapter_error')
    ASSERT_FALSE(addedWithError)
    ASSERT_EQ(addError, 'inventory_adapter_error')
    InventoryBridge.SetAdapter(nil)
end)

TEST('maintenance wire handler returns session results and supports legacy incident ids', function()
    local previous, advance = configureMaintenancePlayer()
    local previousTriggerClient = rawget(_G, 'TriggerClientEvent')
    local response
    TriggerClientEvent = function(_, _, payload) response = payload end
    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]

    rawset(_G, 'source', 7)
    TriggerTestEvent(Constants.Events.MAINTENANCE_REQUEST, {
        action = 'BEGIN',
        incidentId = incident.id,
    })
    ASSERT_TRUE(response.ok)
    local sessionId = response.result.session.sessionId
    ASSERT_TRUE(sessionId ~= nil)

    advance(Config.Technician.repairDurationMs)
    TriggerTestEvent(Constants.Events.MAINTENANCE_REQUEST, {
        action = 'complete',
        incidentId = incident.id,
    })
    ASSERT_TRUE(response.ok)
    ASSERT_EQ(response.result.session.sessionId, sessionId)
    ASSERT_EQ(response.result.incident.status, Enums.IncidentState.VERIFYING)
    TriggerTestEvent(Constants.Events.MAINTENANCE_REQUEST, {
        action = 'verify',
        workOrderId = response.result.workOrder.id,
    })
    ASSERT_TRUE(response.ok)
    ASSERT_EQ(response.result.incident.status, Enums.IncidentState.RESOLVED)
    rawset(_G, 'source', nil)

    TriggerClientEvent = previousTriggerClient
    restoreMaintenancePlayer(previous)
end)

TEST('target maintenance wire rejects spoofed and remote tower intents', function()
    local previous = configureMaintenancePlayer()
    local previousTriggerClient = rawget(_G, 'TriggerClientEvent')
    local response
    TriggerClientEvent = function(_, _, payload) response = payload end
    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]

    rawset(_G, 'source', 7)
    TriggerTestEvent(Constants.Events.MAINTENANCE_TARGET_REQUEST, {
        action = 'begin',
        towerId = 'SPOOFED_TOWER',
    })
    ASSERT_FALSE(response.ok)
    ASSERT_EQ(response.error, 'unknown_tower')
    ASSERT_EQ(IncidentManager.Get(incident.id).status, Enums.IncidentState.OPEN)

    GetEntityCoords = function() return vector3(1000, 1000, 1000) end
    TriggerTestEvent(Constants.Events.MAINTENANCE_TARGET_REQUEST, {
        action = 'begin',
        towerId = 'MAINTENANCE_TOWER',
    })
    ASSERT_FALSE(response.ok)
    ASSERT_EQ(response.error, 'too_far')
    ASSERT_EQ(IncidentManager.Get(incident.id).status, Enums.IncidentState.OPEN)
    rawset(_G, 'source', nil)

    TriggerClientEvent = previousTriggerClient
    restoreMaintenancePlayer(previous)
end)

TEST('valid target maintenance intent resolves one deterministic incident', function()
    local previous = configureMaintenancePlayer()
    local previousTriggerClient = rawget(_G, 'TriggerClientEvent')
    local response
    TriggerClientEvent = function(_, _, payload) response = payload end
    resetMaintenanceState()
    local created = FailureEngine.Create('MAINTENANCE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)

    rawset(_G, 'source', 7)
    TriggerTestEvent(Constants.Events.MAINTENANCE_TARGET_REQUEST, {
        action = 'diagnose',
        towerId = 'MAINTENANCE_TOWER',
    })
    ASSERT_TRUE(response.ok)
    ASSERT_TRUE(response.result.session.sessionId ~= nil)
    ASSERT_EQ(response.result.incident.towerId, 'MAINTENANCE_TOWER')

    local cancelled = MaintenanceDiagnostics.Cancel(7, response.result.session.sessionId)
    ASSERT_TRUE(cancelled)
    rawset(_G, 'source', nil)
    TriggerClientEvent = previousTriggerClient
    restoreMaintenancePlayer(previous)
end)

TEST('maintenance sessions clean up on disconnect and resource stop', function()
    local previous = configureMaintenancePlayer()
    MaintenanceSessions.ClearAll()

    local created = MaintenanceSessions.Create(
        'REPAIR',
        7,
        'license:cleanup-7',
        'INC-CLEANUP-1',
        'FAIL-CLEANUP-1',
        'TOWER-CLEANUP-1',
        1000
    )
    ASSERT_TRUE(created)
    local createdAnother = MaintenanceSessions.Create(
        'REPAIR',
        8,
        'license:cleanup-8',
        'INC-CLEANUP-2',
        'FAIL-CLEANUP-2',
        'TOWER-CLEANUP-1',
        1000
    )
    ASSERT_TRUE(createdAnother)
    ASSERT_EQ(MaintenanceSessions.Count(), 2)

    rawset(_G, 'source', 7)
    TriggerTestEvent('playerDropped')
    rawset(_G, 'source', nil)
    ASSERT_EQ(MaintenanceSessions.Count(), 1)

    local recreated = MaintenanceSessions.Create(
        'DIAGNOSTIC',
        7,
        'license:cleanup-7',
        'INC-CLEANUP-3',
        'FAIL-CLEANUP-3',
        'TOWER-CLEANUP-2',
        1000
    )
    ASSERT_TRUE(recreated)
    TriggerTestEvent('onResourceStop', 'gnsh-telecom')
    ASSERT_EQ(MaintenanceSessions.Count(), 0)
    restoreMaintenancePlayer(previous)
end)
