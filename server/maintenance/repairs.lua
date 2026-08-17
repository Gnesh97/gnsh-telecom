MaintenanceRepairs = MaintenanceRepairs or {}

local function enabled()
    return Config and Config.Features and Config.Features.Technician == true
        and Config.Features.Incidents == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function resolveIncidentId(identifier)
    if not safeString(identifier, 96) then return nil end
    local order = MaintenanceWorkOrders and MaintenanceWorkOrders.Get
        and MaintenanceWorkOrders.Get(identifier)
    return order and order.incidentId or identifier
end

local function publicIncident(incident)
    local result = copy(incident)
    if type(result) ~= 'table' then return result end
    result.failureId = nil
    if type(result.metadata) == 'table' then
        result.metadata.failureId = nil
        result.metadata.failureType = nil
    end
    return result
end

local function publicSession(session)
    local result = copy(session)
    if type(result) ~= 'table' then return result end
    result.failureId = nil
    return result
end

local function getActorId(source)
    if not FrameworkBridge or type(FrameworkBridge.GetStablePlayerId) ~= 'function' then
        return nil
    end
    local actorId = FrameworkBridge.GetStablePlayerId(source)
    return safeString(actorId, 128) and actorId or nil
end

local function isAdmin(source)
    return TelecomPermissions
        and type(TelecomPermissions.IsAdmin) == 'function'
        and TelecomPermissions.IsAdmin(source) == true
end

local function actorDetails(actorId, details)
    local result = {}
    if type(details) == 'table' then
        for key, value in pairs(details) do result[key] = value end
    end
    result.actorId = actorId
    return result
end

local function technicianAllowed(source)
    local configured = Config and Config.Technician or {}
    if configured.allowAdmin and isAdmin(source) then return true end
    local allowed = FrameworkBridge.IsJobAllowed(source, configured.jobs)
    return allowed == true
end

local function requiredDefinition(failure)
    if MaintenanceComponents and MaintenanceComponents.RequiredForFailure then
        return MaintenanceComponents.RequiredForFailure(failure)
    end
    return { requiredPart = nil }
end

local function resolveRepairSessionId(source, identifier)
    if safeString(identifier, 96) then
        local session = MaintenanceSessions.Get(identifier)
        if session and session.kind == 'REPAIR' then return identifier end
    end
    local order = MaintenanceWorkOrders and MaintenanceWorkOrders.Get
        and MaintenanceWorkOrders.Get(identifier)
    if order and order.id == identifier and safeString(order.repairSessionId, 96) then
        return order.repairSessionId
    end
    return identifier
end

local function canRefundItem(source, item)
    if not item then return true end
    if InventoryBridge and type(InventoryBridge.CanCarry) == 'function' then
        return InventoryBridge.CanCarry(source, item, 1) == true
    end
    return InventoryBridge and type(InventoryBridge.CanAddItem) == 'function'
        and InventoryBridge.CanAddItem(source, item, 1) == true
end

local function validateIncident(source, incidentId, checkDistance)
    if not enabled() then return false, 'technician_disabled' end
    incidentId = resolveIncidentId(incidentId)
    if not safeString(incidentId, 64) then return false, 'incident_id_required' end
    if not technicianAllowed(source) then return false, 'technician_job_required' end

    local incident = IncidentManager.Get(incidentId)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.CLOSED
        or incident.status == Enums.IncidentState.RESOLVED then
        return false, 'incident_not_repairable'
    end
    if incident.assignedTo and tonumber(incident.assignedTo) ~= tonumber(source)
        and not isAdmin(source) then
        return false, 'incident_assigned_to_other'
    end

    local tower = TowerRegistry.Get(incident.towerId)
    if not tower then return false, 'tower_not_found' end
    local distance
    if checkDistance ~= false then
        local near
        near, distance = TelecomSecurity.IsNearPlayer(
            source,
            tower.coords,
            Config.Technician.interactionDistance or 5.0
        )
        if not near then return false, distance end
    end

    local failure = FailureEngine.Get(incident.failureId)
    if not failure then return false, 'failure_not_found' end
    local actorId = getActorId(source)
    if not actorId then return false, 'stable_identity_unavailable' end
    return true, incident, failure, tower, distance, actorId
end

local function validateSession(source, sessionId, requireElapsed, checkDistance)
    local ok, session = MaintenanceSessions.Validate(sessionId, 'REPAIR', source)
    if not ok then return false, session end

    local incidentOk, incident, failure, tower, distance, actorId = validateIncident(
        source,
        session.incidentId,
        checkDistance
    )
    if not incidentOk then return false, incident end
    if actorId ~= session.actorId then
        return false, 'actor_identity_mismatch', session
    end
    if failure.id ~= session.failureId then return false, 'failure_changed' end
    if tower.id ~= session.towerId then return false, 'tower_changed' end
    if requireElapsed then
        local elapsed, elapsedError = MaintenanceSessions.IsElapsed(session)
        if not elapsed then return false, elapsedError end
    end
    return true, session, incident, failure, tower, distance, actorId
end

local function abortStaleSession(session, reason)
    if type(session) ~= 'table' then return end
    if type(MaintenanceRepairs.OnSessionCleanup) == 'function' then
        pcall(MaintenanceRepairs.OnSessionCleanup, session, reason)
    end
    MaintenanceSessions.Finish(session.sessionId, 'CANCELLED')
end

function MaintenanceRepairs.Begin(source, incidentId)
    if MaintenanceSessions.HasActive(source) then
        return false, 'maintenance_session_exists'
    end
    local ok, incident, failure, tower, _, actorId = validateIncident(source, incidentId)
    if not ok then return false, incident end

    local requirementsOk, definitionOrError, definition =
        MaintenanceComponents.ValidateRequirements(source, failure)
    if not requirementsOk then return false, definitionOrError end
    local component = definition or definitionOrError
    local item = component and component.requiredPart
    if item and not canRefundItem(source, item) then
        return false, 'inventory_refund_unavailable'
    end

    local ready, workOrder = MaintenanceWorkOrders.EnsureForRepair(source, incident.id)
    if not ready then return false, workOrder end
    local started, startedResult = MaintenanceWorkOrders.StartRepair(source, workOrder.id)
    if not started then return false, startedResult end
    local current = IncidentManager.Get(incident.id)

    local created, session = MaintenanceSessions.Create(
        'REPAIR',
        source,
        actorId,
        current.id,
        failure.id,
        tower.id,
        Config.Technician.repairDurationMs or 0
    )
    if not created then return false, session end
    MaintenanceWorkOrders.MarkRepairSession(source, workOrder.id, session.sessionId)
    MaintenanceWorkOrders.MarkRepairPart(source, workOrder.id, item)
    workOrder = MaintenanceWorkOrders.Get(workOrder.id)
    return true, {
        session = publicSession(session),
        incident = publicIncident(current),
        workOrder = workOrder,
        requirements = {
            requiredTool = component and component.requiredTool,
            requiredPart = component and component.requiredPart,
        },
        earliestCompleteAt = session.earliestCompleteAt,
    }
end

function MaintenanceRepairs.Complete(source, sessionId)
    sessionId = resolveRepairSessionId(source, sessionId)
    local ok, session, incident, failure, _, _, actorId = validateSession(
        source,
        sessionId,
        true,
        true
    )
    if not ok then
        if session == 'actor_identity_mismatch' then abortStaleSession(incident, 'actor_identity_changed') end
        return false, session
    end
    if incident.status ~= Enums.IncidentState.DIAGNOSING
        and incident.status ~= Enums.IncidentState.REPAIRING then
        return false, 'incident_not_diagnosing'
    end

    local requirementsOk, definitionOrError, definition =
        MaintenanceComponents.ValidateRequirements(source, failure)
    if not requirementsOk then return false, definitionOrError end
    local component = definition or definitionOrError
    local item = component and component.requiredPart
    if item and not canRefundItem(source, item) then
        return false, 'inventory_refund_unavailable'
    end
    if incident.failureId ~= failure.id then return false, 'failure_changed' end

    if incident.status == Enums.IncidentState.DIAGNOSING then
        local transitioned, errorCode = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.REPAIRING,
            source,
            actorDetails(actorId)
        )
        if not transitioned then return false, errorCode end
    end

    if item then
        local removed, removeError = InventoryBridge.RemoveItem(source, item, 1)
        if not removed then
            IncidentManager.Transition(
                incident.id,
                Enums.IncidentState.DIAGNOSING,
                source,
                actorDetails(actorId, { repairItemRemovalFailed = true })
            )
        return false, removeError or 'required_item_remove_failed'
        end
    end
    if MaintenanceComponents.MarkRepaired then
        MaintenanceComponents.MarkRepaired(failure.id, {
            source = source,
            actorId = actorId,
        })
    end

    local verifying, verifyingError = IncidentManager.Transition(
        incident.id,
        Enums.IncidentState.VERIFYING,
        source,
        actorDetails(actorId, { physicalRepairComplete = true })
    )
    if not verifying then
        if item then InventoryBridge.AddItem(source, item, 1) end
        IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.DIAGNOSING,
            source,
            actorDetails(actorId, { verificationStartFailed = true })
        )
        MaintenanceWorkOrders.MarkRepairFailed(source, incident.id, {
            verificationStartFailed = true,
        })
        return false, verifyingError
    end

    local workOrderStarted, workOrderResult = MaintenanceWorkOrders.StartVerification(
        source,
        incident.id
    )
    if not workOrderStarted then
        if item then InventoryBridge.AddItem(source, item, 1) end
        IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.REPAIRING,
            source,
            actorDetails(actorId, { verificationStartFailed = true })
        )
        IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.DIAGNOSING,
            source,
            actorDetails(actorId, { verificationStartFailed = true })
        )
        return false, workOrderResult
    end

    local finished, finishedSession = MaintenanceSessions.Finish(session.sessionId, 'COMPLETED')
    if not finished then return false, finishedSession end
    local workOrder = MaintenanceWorkOrders.GetForIncident(incident.id)
    return true, {
        session = publicSession(finishedSession),
        incident = publicIncident(IncidentManager.Get(incident.id)),
        workOrder = workOrder,
        verification = { pending = true },
    }
end

function MaintenanceRepairs.Verify(source, identifier)
    local order = MaintenanceWorkOrders.Get(identifier)
    if not order then return false, 'work_order_not_found' end
    local ownerOk, ownerError = MaintenanceWorkOrders.Validate(identifier, source)
    if not ownerOk then return false, ownerError end
    if order.status ~= Enums.WorkOrderState.VERIFYING then
        return false, 'work_order_not_verifying'
    end

    local allowed, allowedError = technicianAllowed(source)
    if not allowed then return false, allowedError end
    local tower = TowerRegistry.Get(order.towerId)
    if not tower then return false, 'tower_not_found' end
    local near, distance = TelecomSecurity.IsNearPlayer(
        source,
        tower.coords,
        Config.Technician.interactionDistance or 5.0
    )
    if not near then return false, distance end

    local incident = IncidentManager.Get(order.incidentId)
    if not incident or incident.status ~= Enums.IncidentState.VERIFYING then
        return false, 'incident_not_verifying'
    end
    local failure = FailureEngine.Get(incident.failureId)
    if not failure then return false, 'failure_not_found' end
    local verificationOk, checksOrError, extraChecks = MaintenanceComponents.Verify(
        failure,
        order.towerId
    )
    if not verificationOk then
        local reason = type(checksOrError) == 'string' and checksOrError
            or 'verification_failed'
        if order.repairPart then
            local refunded = InventoryBridge.AddItem(source, order.repairPart, 1)
            if not refunded then
                return false, 'repair_rollback_failed', extraChecks or checksOrError
            end
        end
        local failed, failResult = MaintenanceWorkOrders.FailVerification(
            source,
            order.id,
            reason
        )
        if not failed then return false, failResult end
        return false, 'verification_failed', extraChecks or checksOrError
    end

    local completed, completedResult = MaintenanceWorkOrders.CompleteVerification(
        source,
        order.id,
        checksOrError
    )
    if not completed then return false, completedResult end
    local actorId = getActorId(source)
    local cleared, clearError = FailureEngine.Clear(failure.id, {
        source = source,
        actorId = actorId,
    })
    if not cleared then
        local reopened, reopenError = MaintenanceWorkOrders.ReopenVerification(
            source,
            order.id,
            clearError
        )
        if not reopened then return false, reopenError end
        return false, clearError
    end
    return true, {
        incident = publicIncident(IncidentManager.Get(order.incidentId)),
        workOrder = completedResult.workOrder,
        verification = copy(checksOrError),
        distance = distance,
    }
end

function MaintenanceRepairs.Cancel(source, sessionId, reason)
    sessionId = resolveRepairSessionId(source, sessionId)
    if reason ~= nil and not safeString(reason, 128) then
        return false, 'invalid_cancel_reason'
    end
    local ok, session, incident, _, _, actorId = validateSession(
        source,
        sessionId,
        false,
        false
    )
    if not ok then
        if session == 'actor_identity_mismatch' then abortStaleSession(incident, 'actor_identity_changed') end
        return false, session
    end
    if incident.status ~= Enums.IncidentState.DIAGNOSING
        and incident.status ~= Enums.IncidentState.REPAIRING
        and incident.status ~= Enums.IncidentState.VERIFYING then
        return false, 'incident_not_diagnosing'
    end
    local cancelled, cancelResult = MaintenanceWorkOrders.Cancel(
        source,
        incident.id,
        reason or 'cancelled'
    )
    if not cancelled then return false, cancelResult end
    local finished, finishedSession = MaintenanceSessions.Finish(
        session.sessionId,
        'CANCELLED'
    )
    if not finished then return false, finishedSession end
    return true, {
        session = publicSession(finishedSession),
        incident = publicIncident(cancelResult.incident),
        workOrder = cancelResult.workOrder,
    }
end

function MaintenanceRepairs.GetSession(source)
    return MaintenanceSessions.GetForSource(source)
end

function MaintenanceRepairs.OnSessionCleanup(session, reason)
    if type(session) ~= 'table' or session.kind ~= 'REPAIR' then return false end
    local incident = IncidentManager.Get(session.incidentId)
    if not incident then return true end

    local source = tonumber(session.source) or session.source
    local actorId = safeString(session.actorId, 128) and session.actorId or nil
    local workOrder = MaintenanceWorkOrders.GetForRepairSession(session.sessionId)
    if workOrder then
        local released, releaseError = MaintenanceWorkOrders.CancelForCleanup(
            workOrder.id,
            source,
            reason or 'session_cleanup'
        )
        if released then return true end
        if releaseError == 'work_order_replayed' then return true end
    end
    if incident.status == Enums.IncidentState.REPAIRING then
        local transitioned, errorCode = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.DIAGNOSING,
            source,
            actorDetails(actorId, { sessionCleanup = reason })
        )
        if not transitioned then return false, errorCode end
        incident = IncidentManager.Get(incident.id)
    end

    if incident and incident.status == Enums.IncidentState.DIAGNOSING
        and tonumber(incident.assignedTo) == tonumber(source) then
        return IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.ASSIGNED,
            source,
            actorDetails(actorId, {
                sessionCleanup = reason,
                unassigned = true,
            })
        )
    end
    return true
end
