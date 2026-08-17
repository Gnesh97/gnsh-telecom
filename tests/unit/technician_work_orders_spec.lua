local function workOrderTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function configureWorkOrderPlayer()
    local previous = {
        technician = Config.Features.Technician,
        incidents = Config.Features.Incidents,
        components = Config.Technician.components,
        requiredItems = Config.Technician.requiredItems,
        ace = rawget(_G, 'IsPlayerAceAllowed'),
        getPlayerPed = rawget(_G, 'GetPlayerPed'),
        getEntityCoords = rawget(_G, 'GetEntityCoords'),
        getIdentifier = rawget(_G, 'GetPlayerIdentifierByType'),
        getGameTimer = rawget(_G, 'GetGameTimer'),
    }
    local now = 200000

    Config.Features.Technician = true
    Config.Features.Incidents = true
    Config.Technician.components = {}
    Config.Technician.requiredItems = {}
    IsPlayerAceAllowed = function() return true end
    GetPlayerPed = function() return 1 end
    GetEntityCoords = function() return vector3(0, 0, 0) end
    GetPlayerIdentifierByType = function(source, identifierType)
        return identifierType .. ':work-order-' .. tostring(source)
    end
    GetGameTimer = function() return now end

    return previous, function(milliseconds)
        now = now + milliseconds
    end
end

local function restoreWorkOrderPlayer(previous)
    Config.Features.Technician = previous.technician
    Config.Features.Incidents = previous.incidents
    Config.Technician.components = previous.components
    Config.Technician.requiredItems = previous.requiredItems
    rawset(_G, 'IsPlayerAceAllowed', previous.ace)
    rawset(_G, 'GetPlayerPed', previous.getPlayerPed)
    rawset(_G, 'GetEntityCoords', previous.getEntityCoords)
    rawset(_G, 'GetPlayerIdentifierByType', previous.getIdentifier)
    rawset(_G, 'GetGameTimer', previous.getGameTimer)
    if MaintenanceWorkOrders then MaintenanceWorkOrders.Reset() end
    MaintenanceSessions.ClearAll()
end

local function resetWorkOrderState()
    Connections.Clear()
    FailureEngine.Reset()
    IncidentManager.Reset()
    MaintenanceSessions.ClearAll()
    MaintenanceWorkOrders.Reset()
    TowerRegistry.Init({ workOrderTower('WORK_ORDER_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
end

TEST('technician work order completes physical repair only after verification', function()
    local previous, advance = configureWorkOrderPlayer()
    resetWorkOrderState()
    local created, failure = FailureEngine.Create('WORK_ORDER_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]

    local accepted, acceptedResult = MaintenanceWorkOrders.Accept(7, incident.id)
    ASSERT_TRUE(accepted)
    ASSERT_EQ(acceptedResult.workOrder.status, Enums.WorkOrderState.ACCEPTED)
    ASSERT_EQ(acceptedResult.incident.failureId, nil)
    local workOrderId = acceptedResult.workOrder.id

    local travelling = MaintenanceWorkOrders.Travel(7, workOrderId)
    ASSERT_TRUE(travelling)
    local arrived, arrivedResult = MaintenanceWorkOrders.Arrive(7, workOrderId)
    ASSERT_TRUE(arrived)
    ASSERT_EQ(arrivedResult.workOrder.status, Enums.WorkOrderState.ON_SITE)

    local diagnosing, diagnosisSession = MaintenanceDiagnostics.Begin(7, workOrderId)
    ASSERT_TRUE(diagnosing)
    ASSERT_EQ(diagnosisSession.session.failureId, nil)
    advance(Config.Technician.diagnosticDurationMs)
    local diagnosed, diagnosis = MaintenanceDiagnostics.Complete(
        7,
        diagnosisSession.session.sessionId
    )
    ASSERT_TRUE(diagnosed)
    ASSERT_TRUE(diagnosis.diagnosis ~= nil)
    ASSERT_EQ(diagnosis.session.failureId, nil)
    ASSERT_EQ(diagnosis.failure, nil)
    ASSERT_EQ(diagnosis.incident.failureId, nil)
    ASSERT_EQ(diagnosis.workOrder.status, Enums.WorkOrderState.READY_FOR_REPAIR)

    local repairing, repairSession = MaintenanceRepairs.Begin(7, workOrderId)
    ASSERT_TRUE(repairing)
    ASSERT_EQ(repairSession.session.failureId, nil)
    advance(Config.Technician.repairDurationMs)
    local physicallyRepaired, repairResult = MaintenanceRepairs.Complete(
        7,
        workOrderId
    )
    ASSERT_TRUE(physicallyRepaired)
    ASSERT_EQ(repairResult.session.failureId, nil)
    ASSERT_EQ(repairResult.incident.status, Enums.IncidentState.VERIFYING)
    ASSERT_EQ(repairResult.workOrder.status, Enums.WorkOrderState.VERIFYING)
    ASSERT_TRUE(FailureEngine.Get(failure.id) ~= nil)

    local verified, verifiedResult = MaintenanceRepairs.Verify(7, workOrderId)
    ASSERT_TRUE(verified)
    ASSERT_EQ(verifiedResult.incident.status, Enums.IncidentState.RESOLVED)
    ASSERT_EQ(verifiedResult.workOrder.status, Enums.WorkOrderState.COMPLETED)
    ASSERT_EQ(FailureEngine.Get(failure.id), nil)

    local terminalAccept, terminalError = MaintenanceWorkOrders.Accept(7, incident.id)
    ASSERT_FALSE(terminalAccept)
    ASSERT_EQ(terminalError, 'incident_terminal')

    local replayed, replayError = MaintenanceRepairs.Verify(7, workOrderId)
    ASSERT_FALSE(replayed)
    ASSERT_EQ(replayError, 'work_order_not_verifying')
    restoreWorkOrderPlayer(previous)
end)

TEST('diagnostic session cleanup releases its work order on disconnect', function()
    local previous, _ = configureWorkOrderPlayer()
    local previousJobCheck = FrameworkBridge.IsJobAllowed
    local previousAce = IsPlayerAceAllowed
    resetWorkOrderState()
    local created = FailureEngine.Create('WORK_ORDER_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceDiagnostics.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    local workOrderId = beginResult.workOrder.id

    FrameworkBridge.IsJobAllowed = function() return false end
    IsPlayerAceAllowed = function() return false end
    rawset(_G, 'source', 7)
    TriggerTestEvent('playerDropped')
    rawset(_G, 'source', nil)
    ASSERT_EQ(MaintenanceSessions.Get(beginResult.session.sessionId), nil)
    ASSERT_EQ(MaintenanceWorkOrders.Get(workOrderId).status, Enums.WorkOrderState.CANCELLED)
    ASSERT_EQ(IncidentManager.Get(incident.id).assignedTo, nil)
    FrameworkBridge.IsJobAllowed = previousJobCheck
    IsPlayerAceAllowed = previousAce
    restoreWorkOrderPlayer(previous)
end)

TEST('technician diagnostics expose observations without exact failure details', function()
    local previous, advance = configureWorkOrderPlayer()
    resetWorkOrderState()
    local created = FailureEngine.Create('WORK_ORDER_TOWER', 'BACKHAUL_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceDiagnostics.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    advance(Config.Technician.diagnosticDurationMs)
    local complete, result = MaintenanceDiagnostics.Complete(
        7,
        beginResult.session.sessionId
    )
    ASSERT_TRUE(complete)
    ASSERT_TRUE(result.diagnosis.observations ~= nil)
    ASSERT_TRUE(result.diagnosis.indicators ~= nil)
    ASSERT_EQ(result.failure, nil)
    ASSERT_EQ(result.incident.failureId, nil)
    ASSERT_EQ(result.incident.metadata.failureType, nil)
    ASSERT_EQ(result.diagnosis.probableCause, nil)
    restoreWorkOrderPlayer(previous)
end)

TEST('component tool and part requirements fail closed before repair ownership', function()
    local previous, _ = configureWorkOrderPlayer()
    local inventory = { rf_meter = false, radio_replacement = false }
    Config.Technician.components = {
        RADIO_UNIT = {
            requiredTool = 'rf_meter',
            requiredPart = 'radio_replacement',
        },
    }
    InventoryBridge.SetAdapter({
        HasItem = function(_, _, item) return inventory[item] == true end,
        RemoveItem = function() return true end,
        AddItem = function() return true end,
        CanCarry = function() return true end,
    })
    resetWorkOrderState()
    local created = FailureEngine.Create('WORK_ORDER_TOWER', 'RADIO_UNIT_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]

    local missing, missingError = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_FALSE(missing)
    ASSERT_EQ(missingError, 'required_tool_missing')
    ASSERT_EQ(IncidentManager.Get(incident.id).assignedTo, nil)

    inventory.rf_meter = true
    inventory.radio_replacement = true
    local begun = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    InventoryBridge.SetAdapter(nil)
    restoreWorkOrderPlayer(previous)
end)

TEST('failed verification refunds a consumed configured part', function()
    local previous, advance = configureWorkOrderPlayer()
    local inventory = { rf_meter = true, radio_replacement = true }
    Config.Technician.components = {
        RADIO_UNIT = {
            requiredTool = 'rf_meter',
            requiredPart = 'radio_replacement',
        },
    }
    InventoryBridge.SetAdapter({
        HasItem = function(_, _, item) return inventory[item] == true end,
        RemoveItem = function(_, _, item)
            inventory[item] = false
            return true
        end,
        AddItem = function(_, _, item)
            inventory[item] = true
            return true
        end,
        CanCarry = function() return true end,
    })
    resetWorkOrderState()
    local created = FailureEngine.Create('WORK_ORDER_TOWER', 'RADIO_UNIT_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    advance(Config.Technician.repairDurationMs)
    local complete, completeResult = MaintenanceRepairs.Complete(
        7,
        beginResult.session.sessionId
    )
    ASSERT_TRUE(complete)
    ASSERT_FALSE(inventory.radio_replacement)

    local previousVerify = MaintenanceComponents.Verify
    MaintenanceComponents.Verify = function() return false, 'component_not_operational' end
    local verified, verifyError = MaintenanceRepairs.Verify(7, completeResult.workOrder.id)
    ASSERT_FALSE(verified)
    ASSERT_EQ(verifyError, 'verification_failed')
    ASSERT_TRUE(inventory.radio_replacement)
    ASSERT_EQ(IncidentManager.Get(incident.id).status, Enums.IncidentState.REPAIRING)
    MaintenanceComponents.Verify = previousVerify
    InventoryBridge.SetAdapter(nil)
    restoreWorkOrderPlayer(previous)
end)

TEST('failed post-repair verification leaves incident and failure active', function()
    local previous, advance = configureWorkOrderPlayer()
    resetWorkOrderState()
    local created, failure = FailureEngine.Create('WORK_ORDER_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local begun, beginResult = MaintenanceRepairs.Begin(7, incident.id)
    ASSERT_TRUE(begun)
    advance(Config.Technician.repairDurationMs)
    local complete, result = MaintenanceRepairs.Complete(
        7,
        beginResult.session.sessionId
    )
    ASSERT_TRUE(complete)
    ASSERT_EQ(result.incident.status, Enums.IncidentState.VERIFYING)

    local previousVerify = MaintenanceComponents.Verify
    MaintenanceComponents.Verify = function() return false, 'backhaul_unreachable' end
    local verified, verifyError = MaintenanceRepairs.Verify(7, result.workOrder.id)
    ASSERT_FALSE(verified)
    ASSERT_EQ(verifyError, 'verification_failed')
    ASSERT_EQ(IncidentManager.Get(incident.id).status, Enums.IncidentState.REPAIRING)
    ASSERT_TRUE(FailureEngine.Get(failure.id) ~= nil)
    MaintenanceComponents.Verify = previousVerify
    local retry, retrySession = MaintenanceRepairs.Begin(7, result.workOrder.id)
    ASSERT_TRUE(retry)
    advance(Config.Technician.repairDurationMs)
    local retryComplete, retryResult = MaintenanceRepairs.Complete(
        7,
        retrySession.session.sessionId
    )
    ASSERT_TRUE(retryComplete)
    local retryVerified, retryVerification = MaintenanceRepairs.Verify(
        7,
        retryResult.workOrder.id
    )
    ASSERT_TRUE(retryVerified)
    ASSERT_EQ(retryVerification.incident.status, Enums.IncidentState.RESOLVED)
    restoreWorkOrderPlayer(previous)
end)

TEST('work orders enforce distance, reassignment, job changes and disconnect cleanup', function()
    local previous, _ = configureWorkOrderPlayer()
    local previousJobCheck = FrameworkBridge.IsJobAllowed
    local previousAce = IsPlayerAceAllowed
    FrameworkBridge.IsJobAllowed = function(source)
        return (tonumber(source) == 7 or tonumber(source) == 8), 'technician'
    end
    IsPlayerAceAllowed = function() return false end
    resetWorkOrderState()
    local created = FailureEngine.Create('WORK_ORDER_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(created)
    local incident = IncidentManager.GetSnapshot().incidents[1]
    local accepted, acceptedResult = MaintenanceWorkOrders.Accept(7, incident.id)
    ASSERT_TRUE(accepted)
    local orderId = acceptedResult.workOrder.id
    ASSERT_TRUE(MaintenanceWorkOrders.Travel(7, orderId))

    GetEntityCoords = function() return vector3(1000, 1000, 0) end
    local tooFar, tooFarError = MaintenanceWorkOrders.Arrive(7, orderId)
    ASSERT_FALSE(tooFar)
    ASSERT_EQ(tooFarError, 'too_far')
    GetEntityCoords = function() return vector3(0, 0, 0) end

    local reassigned, reassignedResult = MaintenanceWorkOrders.Reassign(7, orderId, 8)
    ASSERT_TRUE(reassigned)
    ASSERT_EQ(reassignedResult.workOrder.assignedSource, 8)
    local oldOwner, oldOwnerError = MaintenanceWorkOrders.Arrive(7, orderId)
    ASSERT_FALSE(oldOwner)
    ASSERT_EQ(oldOwnerError, 'work_order_assigned_to_other')
    ASSERT_TRUE(MaintenanceWorkOrders.Arrive(8, orderId))

    FrameworkBridge.IsJobAllowed = function() return false end
    local jobChanged, jobError = MaintenanceWorkOrders.StartDiagnosis(8, orderId)
    ASSERT_FALSE(jobChanged)
    ASSERT_EQ(jobError, 'technician_job_required')
    FrameworkBridge.IsJobAllowed = function(source)
        return (tonumber(source) == 7 or tonumber(source) == 8), 'technician'
    end

    rawset(_G, 'source', 8)
    TriggerTestEvent('playerDropped')
    rawset(_G, 'source', nil)
    ASSERT_EQ(MaintenanceWorkOrders.Get(orderId).status, Enums.WorkOrderState.CANCELLED)
    ASSERT_EQ(IncidentManager.Get(incident.id).assignedTo, nil)

    FrameworkBridge.IsJobAllowed = previousJobCheck
    IsPlayerAceAllowed = previousAce
    restoreWorkOrderPlayer(previous)
end)
