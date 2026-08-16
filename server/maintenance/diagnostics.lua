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
    if not safeString(incidentId, 64) then return false, 'incident_id_required' end
    local allowed, actor = authorizedTechnician(source)
    if not allowed then return false, 'technician_job_required' end

    local incident = IncidentManager.Get(incidentId)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.CLOSED then return false, 'incident_closed' end
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

local function diagnosisResult(session, incident, failure, distance)
    local symptoms = symptomByType[failure.type] or { 'unknown technical symptoms' }
    return {
        session = copy(session),
        incident = copy(incident),
        failure = copy(failure),
        symptoms = copy(symptoms),
        probableCause = FailureTypes.Get(failure.type),
        component = failure.component,
        distance = distance,
    }
end

function MaintenanceDiagnostics.Begin(source, incidentId)
    local ok, incident, failure, tower, _, actorId = validateIncident(source, incidentId)
    if not ok then return false, incident end
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
    return true, {
        session = session,
        incident = copy(incident),
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
    local finished, finishedSession = MaintenanceSessions.Finish(
        session.sessionId,
        'COMPLETED'
    )
    if not finished then return false, finishedSession end
    local result = diagnosisResult(finishedSession, incident, failure, distance)
    result.session = finishedSession
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
    return true, {
        session = finishedSession,
        incident = copy(incident),
    }
end

-- Compatibility entrypoint: diagnosis now creates a server-owned session.
function MaintenanceDiagnostics.Inspect(source, incidentId)
    return MaintenanceDiagnostics.Begin(source, incidentId)
end
