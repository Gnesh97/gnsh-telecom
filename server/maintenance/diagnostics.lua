MaintenanceDiagnostics = MaintenanceDiagnostics or {}

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

local function authorizedTechnician(source)
    local configured = Config and Config.Technician or {}
    if configured.allowAdmin and TelecomPermissions
        and type(TelecomPermissions.IsAdmin) == 'function'
        and TelecomPermissions.IsAdmin(source) then
        return true, 'admin'
    end
    local allowed, job = FrameworkBridge.IsJobAllowed(source, configured.jobs)
    if not allowed then return false, 'technician_job_required' end
    return true, job
end

local function getActorId(source)
    if not FrameworkBridge or type(FrameworkBridge.GetStablePlayerId) ~= 'function' then
        return nil
    end
    local actorId = FrameworkBridge.GetStablePlayerId(source)
    return safeString(actorId, 128) and actorId or nil
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

local symptomByType = {
    ANTENNA_FAILURE = { 'coverage reduced', 'signal instability' },
    RADIO_FAILURE = { 'data unavailable', 'radio chain degraded' },
    SECTOR_FAILURE = { 'localized coverage loss', 'capacity reduced' },
    RADIO_UNIT_FAILURE = { 'very weak signal', 'radio unit offline' },
    COOLING_FAILURE = { 'thermal alarm', 'hardware health declining' },
    FIBER_FAILURE = { 'radio bars present', 'services unavailable' },
    BACKHAUL_FAILURE = { 'radio bars present', 'core path unreachable' },
    CONTROLLER_FAILURE = { 'multiple services unavailable', 'tower control degraded' },
    SOFTWARE_FAILURE = { 'data service unavailable', 'software alarms' },
}

local function validateIncident(source, incidentId, checkDistance)
    if not enabled() then return false, 'technician_disabled' end
    incidentId = resolveIncidentId(incidentId)
    if not safeString(incidentId, 64) then return false, 'incident_id_required' end
    local allowed, actor = authorizedTechnician(source)
    if not allowed then return false, 'technician_job_required' end

    local incident = IncidentManager.Get(incidentId)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.CLOSED
        or incident.status == Enums.IncidentState.RESOLVED then
        return false, 'incident_terminal'
    end
    if incident.assignedTo and tonumber(incident.assignedTo) ~= tonumber(source)
        and actor ~= 'admin' then
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
    local ok, session = MaintenanceSessions.Validate(sessionId, 'DIAGNOSTIC', source)
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
    return true, session, incident, failure, distance
end

local function abortStaleSession(session)
    if type(session) == 'table' then
        MaintenanceSessions.Finish(session.sessionId, 'CANCELLED')
    end
end

local function diagnosisObservations(failure)
    local observations = {
        ['RF Output'] = 'NORMAL',
        ['Sector B'] = 'NORMAL',
        ['Backhaul RX'] = 'NORMAL',
        ['Controller'] = 'NORMAL',
        ['Temperature'] = 'NORMAL',
    }
    local indicators = {}
    local typeName = failure.type
    if typeName == 'ANTENNA_FAILURE' then
        observations['RF Output'] = 'DEGRADED'
        indicators[#indicators + 1] = 'coverage footprint unstable'
    elseif typeName == 'SECTOR_FAILURE' then
        observations['Sector B'] = 'DEGRADED'
        indicators[#indicators + 1] = 'localized sector alarm'
    elseif typeName == 'RADIO_FAILURE' or typeName == 'RADIO_UNIT_FAILURE' then
        observations['RF Output'] = 'DEGRADED'
        indicators[#indicators + 1] = 'radio chain alarm'
    elseif typeName == 'FIBER_FAILURE' or typeName == 'BACKHAUL_FAILURE' then
        observations['Backhaul RX'] = 'FAILED'
        indicators[#indicators + 1] = 'transport path unreachable'
    elseif typeName == 'CONTROLLER_FAILURE' then
        observations['Controller'] = 'DEGRADED'
        indicators[#indicators + 1] = 'control plane alarm'
    elseif typeName == 'COOLING_FAILURE' then
        observations['Temperature'] = 'HIGH'
        indicators[#indicators + 1] = 'thermal alarm'
    elseif typeName == 'SOFTWARE_FAILURE' then
        observations['Controller'] = 'DEGRADED'
        indicators[#indicators + 1] = 'service policy alarm'
    else
        indicators[#indicators + 1] = 'intermittent telecom alarm'
    end
    return observations, indicators
end

local function diagnosisResult(session, incident, failure, distance, workOrder)
    local symptoms = symptomByType[failure.type] or { 'unknown technical symptoms' }
    local observations, indicators = diagnosisObservations(failure)
    return {
        session = publicSession(session),
        incident = publicIncident(incident),
        symptoms = copy(symptoms),
        diagnosis = {
            observations = observations,
            indicators = indicators,
            confidence = 'LOW',
            nextAction = 'inspect_component',
        },
        distance = distance,
        workOrder = copy(workOrder),
    }
end

function MaintenanceDiagnostics.Begin(source, incidentId)
    local ok, incident, failure, tower, _, actorId = validateIncident(source, incidentId)
    if not ok then return false, incident end
    local workOrderOk, workOrder = MaintenanceWorkOrders.EnsureForDiagnosis(
        source,
        incident.id
    )
    if not workOrderOk then return false, workOrder end
    local workOrderOwner, ownerError = MaintenanceWorkOrders.Validate(workOrder.id, source)
    if not workOrderOwner then return false, ownerError end
    if workOrder.status ~= Enums.WorkOrderState.DIAGNOSING then
        return false, 'work_order_not_diagnosing'
    end
    local created, session = MaintenanceSessions.Create(
        'DIAGNOSTIC',
        source,
        actorId,
        incident.id,
        failure.id,
        tower.id,
        Config.Technician.diagnosticDurationMs or 0
    )
    if not created then return false, session end
    MaintenanceWorkOrders.MarkDiagnosisSession(source, workOrder.id, session.sessionId)
    workOrder = MaintenanceWorkOrders.Get(workOrder.id)
    return true, {
        session = publicSession(session),
        incident = publicIncident(incident),
        workOrder = copy(workOrder),
        earliestCompleteAt = session.earliestCompleteAt,
    }
end

function MaintenanceDiagnostics.Complete(source, sessionId)
    local ok, session, incident, failure, distance = validateSession(
        source,
        sessionId,
        true,
        true
    )
    if not ok then
        if session == 'actor_identity_mismatch' then abortStaleSession(incident) end
        return false, session
    end
    local workOrder = MaintenanceWorkOrders.GetForIncident(incident.id)
    local finished, finishedSession = MaintenanceSessions.Finish(
        session.sessionId,
        'COMPLETED'
    )
    if not finished then return false, finishedSession end
    local completedOrder, orderResult = MaintenanceWorkOrders.CompleteDiagnosis(
        source,
        incident.id,
        { observations = diagnosisObservations(failure) }
    )
    if not completedOrder then return false, orderResult end
    workOrder = orderResult.workOrder
    local result = diagnosisResult(finishedSession, incident, failure, distance, workOrder)
    result.session = publicSession(finishedSession)
    return true, result
end

function MaintenanceDiagnostics.Cancel(source, sessionId)
    local ok, session, incident = validateSession(source, sessionId, false, false)
    if not ok then
        if session == 'actor_identity_mismatch' then abortStaleSession(incident) end
        return false, session
    end
    local finished, finishedSession = MaintenanceSessions.Finish(
        session.sessionId,
        'CANCELLED'
    )
    if not finished then return false, finishedSession end
    local cancelled, cancelResult = MaintenanceWorkOrders.Cancel(
        source,
        incident.id,
        'diagnostic_cancelled'
    )
    if not cancelled then return false, cancelResult end
    return true, {
        session = publicSession(finishedSession),
        incident = publicIncident(cancelResult.incident),
        workOrder = cancelResult.workOrder,
    }
end

function MaintenanceDiagnostics.OnSessionCleanup(session, reason)
    if type(session) ~= 'table' or session.kind ~= 'DIAGNOSTIC' then return false end
    local workOrder = MaintenanceWorkOrders.GetForIncident(session.incidentId)
    if not workOrder then return true end
    local released, errorCode = MaintenanceWorkOrders.CancelForCleanup(
        workOrder.id,
        session.source,
        reason or 'session_cleanup'
    )
    if not released and errorCode ~= 'work_order_replayed' then
        return false, errorCode
    end
    return true
end

-- Compatibility entrypoint: diagnosis now creates a server-owned session.
function MaintenanceDiagnostics.Inspect(source, incidentId)
    return MaintenanceDiagnostics.Begin(source, incidentId)
end
