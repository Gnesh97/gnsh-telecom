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

local function requiredItem(failure)
    local configured = Config and Config.Technician and Config.Technician.requiredItems or {}
    return configured[failure.type] or configured.default
end

local function validateIncident(source, incidentId, checkDistance)
    if not enabled() then return false, 'technician_disabled' end
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

    local current = incident
    local item = requiredItem(failure)
    local hasItem, itemError = InventoryBridge.HasItem(source, item, 1)
    if not hasItem then return false, itemError or 'required_item_missing' end
    if item and not InventoryBridge.CanAddItem(source, item) then
        return false, 'inventory_refund_unavailable'
    end

    if current.status == Enums.IncidentState.OPEN then
        local transitioned, errorCode = IncidentManager.Transition(
            current.id,
            Enums.IncidentState.ACKNOWLEDGED,
            source,
            actorDetails(actorId)
        )
        if not transitioned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    if current.status == Enums.IncidentState.ACKNOWLEDGED
        or (current.status == Enums.IncidentState.ASSIGNED and current.assignedTo == nil) then
        local assigned, errorCode = IncidentManager.Assign(
            current.id,
            source,
            source,
            actorDetails(actorId)
        )
        if not assigned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    if current.status ~= Enums.IncidentState.ASSIGNED
        and current.status ~= Enums.IncidentState.ON_ROUTE
        and current.status ~= Enums.IncidentState.DIAGNOSING then
        return false, 'incident_not_assignable'
    end

    if current.status == Enums.IncidentState.ASSIGNED then
        local transitioned, errorCode = IncidentManager.Transition(
            current.id,
            Enums.IncidentState.ON_ROUTE,
            source,
            actorDetails(actorId)
        )
        if not transitioned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    if current.status == Enums.IncidentState.ON_ROUTE then
        local transitioned, errorCode = IncidentManager.Transition(
            current.id,
            Enums.IncidentState.DIAGNOSING,
            source,
            actorDetails(actorId)
        )
        if not transitioned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    if current.status ~= Enums.IncidentState.DIAGNOSING then
        return false, 'incident_not_diagnosing'
    end

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
    return true, {
        session = session,
        incident = copy(current),
        earliestCompleteAt = session.earliestCompleteAt,
    }
end

function MaintenanceRepairs.Complete(source, sessionId)
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
    if incident.status ~= Enums.IncidentState.DIAGNOSING then
        return false, 'incident_not_diagnosing'
    end

    local item = requiredItem(failure)
    local hasItem, itemError = InventoryBridge.HasItem(source, item, 1)
    if not hasItem then return false, itemError or 'required_item_missing' end
    if item and not InventoryBridge.CanAddItem(source, item) then
        return false, 'inventory_refund_unavailable'
    end
    if incident.failureId ~= failure.id then return false, 'failure_changed' end

    local transitioned, errorCode = IncidentManager.Transition(
        incident.id,
        Enums.IncidentState.REPAIRING,
        source,
        actorDetails(actorId)
    )
    if not transitioned then return false, errorCode end

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
    local cleared, clearError = FailureEngine.Clear(failure.id, {
        source = source,
        actorId = actorId,
    })
    if not cleared then
        local refunded, refundError = true, nil
        if item then
            refunded, refundError = InventoryBridge.AddItem(source, item, 1)
        end
        IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.DIAGNOSING,
            source,
            actorDetails(actorId, {
                repairClearFailed = true,
                repairRefunded = refunded,
            })
        )
        if not refunded then return false, 'repair_rollback_failed' end
        return false, clearError
    end

    local finished, finishedSession = MaintenanceSessions.Finish(
        session.sessionId,
        'COMPLETED'
    )
    if not finished then return false, finishedSession end
    return true, {
        session = finishedSession,
        incident = IncidentManager.Get(incident.id),
        failure = copy(failure),
    }
end

function MaintenanceRepairs.Cancel(source, sessionId, reason)
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
    if incident.status ~= Enums.IncidentState.DIAGNOSING then
        return false, 'incident_not_diagnosing'
    end

    local transitioned, errorCode = IncidentManager.Transition(
        incident.id,
        Enums.IncidentState.ASSIGNED,
        source,
        actorDetails(actorId, {
            cancelled = reason or 'cancelled',
            unassigned = true,
        })
    )
    if not transitioned then return false, errorCode end
    local finished, finishedSession = MaintenanceSessions.Finish(
        session.sessionId,
        'CANCELLED'
    )
    if not finished then return false, finishedSession end
    return true, {
        session = finishedSession,
        incident = IncidentManager.Get(incident.id),
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
