MaintenanceWorkflow = MaintenanceWorkflow or {}

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function actionName(value)
    if type(value) ~= 'string' then return nil end
    local normalized = value:lower()
    local aliases = {
        accept_work_order = 'accept',
        travel_to_site = 'travel',
        arrive_on_site = 'arrive',
        start_diagnosis = 'diagnose',
        start_repair = 'begin',
        post_repair_verification = 'verify',
    }
    return aliases[normalized] or normalized
end

local function identifier(payload, preferSession)
    if preferSession and safeString(payload.sessionId, 96) then
        return payload.sessionId
    end
    if safeString(payload.workOrderId, 96) then return payload.workOrderId end
    if safeString(payload.sessionId, 96) then return payload.sessionId end
    if safeString(payload.incidentId, 64) then return payload.incidentId end
    return nil
end

local function resolveRepairSessionId(sourceId, payload)
    if safeString(payload.sessionId, 96) then return payload.sessionId end
    if safeString(payload.workOrderId, 96) then return payload.workOrderId end
    if not safeString(payload.incidentId, 64) then
        return nil, 'session_id_required'
    end
    local session = MaintenanceRepairs.GetSession(sourceId)
    if session and session.incidentId == payload.incidentId then
        return session.sessionId
    end
    return payload.incidentId
end

local function findIncidentForSource(sourceId, towerId)
    if not IncidentManager or type(IncidentManager.GetAll) ~= 'function' then
        return nil
    end
    local sourceNumber = tonumber(sourceId)
    local selected
    local selectedRank
    for _, incident in ipairs(IncidentManager.GetAll()) do
        if incident.towerId == towerId
            and incident.status ~= Enums.IncidentState.RESOLVED
            and incident.status ~= Enums.IncidentState.CLOSED then
            local rank = incident.assignedTo == nil and 1 or 2
            if sourceNumber and tonumber(incident.assignedTo) == sourceNumber then rank = 0 end
            local order = MaintenanceWorkOrders.GetForIncident(incident.id)
            if order and tonumber(order.assignedSource) == sourceNumber then rank = 0 end
            if selected == nil or rank < selectedRank
                or (rank == selectedRank and incident.id < selected.id) then
                selected = incident
                selectedRank = rank
            end
        end
    end
    return selected and selected.id or nil
end

local function executeTargetRequest(sourceId, payload)
    if payload.action ~= 'diagnose' and payload.action ~= 'begin'
        and payload.action ~= 'accept' and payload.action ~= 'arrive'
        and payload.action ~= 'verify' then
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

    local incidentId = findIncidentForSource(sourceId, payload.towerId)
    if not incidentId then return false, 'incident_not_found' end
    if payload.action == 'diagnose' then
        return MaintenanceDiagnostics.Begin(sourceId, incidentId)
    elseif payload.action == 'begin' then
        return MaintenanceRepairs.Begin(sourceId, incidentId)
    elseif payload.action == 'accept' then
        return MaintenanceWorkOrders.Accept(sourceId, incidentId)
    elseif payload.action == 'arrive' then
        local order = MaintenanceWorkOrders.GetForIncident(incidentId)
        if not order then return false, 'work_order_not_found' end
        return MaintenanceWorkOrders.Arrive(sourceId, order.id)
    end
    local order = MaintenanceWorkOrders.GetForIncident(incidentId)
    if not order then return false, 'work_order_not_found' end
    return MaintenanceRepairs.Verify(sourceId, order.id)
end

local function respond(sourceId, ok, result)
    if type(TriggerClientEvent) ~= 'function' then return end
    TriggerClientEvent(Constants.Events.MAINTENANCE_STATE, sourceId, {
        ok = ok,
        result = ok and Utils.DeepCopy(result) or nil,
        error = ok and nil or result,
    })
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
        local action = actionName(payload.action)
        local ok, result
        if action == 'accept' then
            local id = identifier(payload)
            if not id then ok, result = false, 'work_order_id_required'
            else ok, result = MaintenanceWorkOrders.Accept(sourceId, id) end
        elseif action == 'travel' then
            local id = identifier(payload)
            if not id then ok, result = false, 'work_order_id_required'
            else ok, result = MaintenanceWorkOrders.Travel(sourceId, id) end
        elseif action == 'arrive' then
            local id = identifier(payload)
            if not id then ok, result = false, 'work_order_id_required'
            else ok, result = MaintenanceWorkOrders.Arrive(sourceId, id) end
        elseif action == 'diagnose' or action == 'begin' then
            local id = identifier(payload)
            if not id then
                ok, result = false, 'incident_id_required'
            elseif action == 'diagnose' then
                ok, result = MaintenanceDiagnostics.Begin(sourceId, id)
            else
                ok, result = MaintenanceRepairs.Begin(sourceId, id)
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
            local id, sessionError = resolveRepairSessionId(sourceId, payload)
            if not id then ok, result = false, sessionError
            else ok, result = MaintenanceRepairs.Complete(sourceId, id) end
        elseif action == 'verify' then
            local id = identifier(payload)
            if not id then ok, result = false, 'work_order_id_required'
            else ok, result = MaintenanceRepairs.Verify(sourceId, id) end
        elseif action == 'cancel' then
            local id, sessionError = resolveRepairSessionId(sourceId, payload)
            if not id then
                ok, result = false, sessionError
            elseif payload.reason ~= nil and not safeString(payload.reason, 128) then
                ok, result = false, 'invalid_cancel_reason'
            else
                ok, result = MaintenanceRepairs.Cancel(sourceId, id, payload.reason)
            end
        else
            ok, result = false, 'unknown_maintenance_action'
        end
        respond(sourceId, ok, result)
    end)

    AddEventHandler(Constants.Events.MAINTENANCE_TARGET_REQUEST, function(payload)
        local sourceId = source
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'maintenance_target', 1000, 5)
        if not limited or type(payload) ~= 'table'
            or not TelecomSecurity.IsSafeTable(payload, 2, 8) then return end
        local request = {
            action = actionName(payload.action),
            towerId = payload.towerId,
        }
        local ok, result = executeTargetRequest(sourceId, request)
        respond(sourceId, ok, result)
    end)
end
