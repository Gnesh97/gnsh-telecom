MaintenanceWorkflow = MaintenanceWorkflow or {}

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function resolveRepairSessionId(sourceId, payload)
    if payload.sessionId ~= nil then
        if not safeString(payload.sessionId, 96) then
            return nil, 'session_id_required'
        end
        return payload.sessionId
    end
    if not safeString(payload.incidentId, 64) then
        return nil, 'session_id_required'
    end
    if not MaintenanceRepairs or type(MaintenanceRepairs.GetSession) ~= 'function' then
        return nil, 'session_not_found'
    end
    local session = MaintenanceRepairs.GetSession(sourceId)
    if not session or session.incidentId ~= payload.incidentId then
        return nil, 'session_not_found'
    end
    return session.sessionId
end

local function findIncidentForTower(towerId)
    if not IncidentManager or type(IncidentManager.GetAll) ~= 'function' then
        return nil
    end
    for _, incident in ipairs(IncidentManager.GetAll()) do
        if incident.towerId == towerId
            and incident.status ~= Enums.IncidentState.RESOLVED
            and incident.status ~= Enums.IncidentState.CLOSED then
            return incident.id
        end
    end
    return nil
end

local function executeTargetRequest(sourceId, payload)
    if payload.action ~= 'diagnose' and payload.action ~= 'begin' then
        return false, 'unknown_target_action'
    end
    if type(payload.towerId) ~= 'string' or #payload.towerId == 0
        or #payload.towerId > 64 then
        return false, 'tower_id_required'
    end
    local maximumDistance = Config and Config.Technician
        and Config.Technician.interactionDistance or 5.0
    local near, towerOrError = TelecomSecurity.ValidateTower(
        sourceId,
        payload.towerId,
        maximumDistance
    )
    if not near then return false, towerOrError end

    local incidentId = findIncidentForTower(payload.towerId)
    if not incidentId then return false, 'incident_not_found' end
    if payload.action == 'diagnose' then
        return MaintenanceDiagnostics.Begin(sourceId, incidentId)
    end
    return MaintenanceRepairs.Begin(sourceId, incidentId)
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.MAINTENANCE_REQUEST)
    RegisterNetEvent(Constants.Events.MAINTENANCE_TARGET_REQUEST)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.MAINTENANCE_REQUEST, function(payload)
        local sourceId = source
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'maintenance', 1000, 5)
        if not limited or type(payload) ~= 'table'
            or not TelecomSecurity.IsSafeTable(payload, 2, 16) then return end
        local action = type(payload.action) == 'string' and payload.action:lower() or nil
        local ok, result
        if action == 'diagnose' or action == 'begin' then
            if not safeString(payload.incidentId, 64) then
                ok, result = false, 'incident_id_required'
            elseif action == 'diagnose' then
                ok, result = MaintenanceDiagnostics.Begin(sourceId, payload.incidentId)
            else
                ok, result = MaintenanceRepairs.Begin(sourceId, payload.incidentId)
            end
        elseif action == 'diagnose_complete' then
            if not safeString(payload.sessionId, 96) then
                ok, result = false, 'session_id_required'
            else
                ok, result = MaintenanceDiagnostics.Complete(sourceId, payload.sessionId)
            end
        elseif action == 'diagnose_cancel' then
            if not safeString(payload.sessionId, 96) then
                ok, result = false, 'session_id_required'
            else
                ok, result = MaintenanceDiagnostics.Cancel(sourceId, payload.sessionId)
            end
        elseif action == 'complete' then
            local sessionId, sessionError = resolveRepairSessionId(sourceId, payload)
            if not sessionId then
                ok, result = false, sessionError
            else
                ok, result = MaintenanceRepairs.Complete(sourceId, sessionId)
            end
        elseif action == 'cancel' then
            local sessionId, sessionError = resolveRepairSessionId(sourceId, payload)
            if not sessionId then
                ok, result = false, sessionError
            elseif payload.reason ~= nil and not safeString(payload.reason, 128) then
                ok, result = false, 'invalid_cancel_reason'
            else
                ok, result = MaintenanceRepairs.Cancel(
                    sourceId,
                    sessionId,
                    payload.reason
                )
            end
        else
            ok, result = false, 'unknown_maintenance_action'
        end
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent(Constants.Events.MAINTENANCE_STATE, sourceId, {
                ok = ok,
                result = ok and Utils.DeepCopy(result) or nil,
                error = ok and nil or result,
            })
        end
    end)
    AddEventHandler(Constants.Events.MAINTENANCE_TARGET_REQUEST, function(payload)
        local sourceId = source
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'maintenance_target', 1000, 5)
        if not limited or type(payload) ~= 'table'
            or not TelecomSecurity.IsSafeTable(payload, 2, 8) then return end
        local action = type(payload.action) == 'string' and payload.action:lower() or nil
        local request = {
            action = action,
            towerId = payload.towerId,
        }
        local ok, result = executeTargetRequest(sourceId, request)
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent(Constants.Events.MAINTENANCE_STATE, sourceId, {
                ok = ok,
                result = ok and Utils.DeepCopy(result) or nil,
                error = ok and nil or result,
            })
        end
    end)
end
