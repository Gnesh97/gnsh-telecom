TechnicianClient = TechnicianClient or {}

local validActions = {
    accept = true,
    travel = true,
    arrive = true,
    diagnose = true,
    diagnose_complete = true,
    diagnose_cancel = true,
    begin = true,
    complete = true,
    verify = true,
    cancel = true,
}

local lastResponse

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function normalizeAction(value)
    return type(value) == 'string' and value:lower() or nil
end

function TechnicianClient.Request(action, identifier, reason)
    action = normalizeAction(action)
    if not Config or not Config.Features
        or Config.Features.Technician ~= true
        or Config.Features.Incidents ~= true then
        return false, 'technician_disabled'
    end
    if not validActions[action] then return false, 'unknown_maintenance_action' end
    local incidentAction = action == 'diagnose' or action == 'begin'
    local workOrderAction = action == 'accept' or action == 'travel'
        or action == 'arrive' or action == 'verify'
    if incidentAction and not safeString(identifier, 64) then
        return false, 'incident_id_required'
    elseif workOrderAction and not safeString(identifier, 96) then
        return false, 'work_order_id_required'
    elseif not incidentAction and not workOrderAction
        and not safeString(identifier, 96) then
        return false, 'session_id_required'
    end
    if reason ~= nil and not safeString(reason, 128) then
        return false, 'invalid_cancel_reason'
    end
    if action ~= 'cancel' then reason = nil end
    if type(TriggerServerEvent) ~= 'function' then
        return false, 'event_api_unavailable'
    end

    TriggerServerEvent(Constants.Events.MAINTENANCE_REQUEST, {
        action = action,
        incidentId = (incidentAction or action == 'accept') and identifier or nil,
        workOrderId = (action == 'accept' or action == 'travel' or action == 'arrive'
            or action == 'verify')
            and identifier or nil,
        sessionId = (action == 'complete' or action == 'cancel'
            or action == 'diagnose_complete' or action == 'diagnose_cancel')
            and identifier or nil,
        reason = reason,
    })
    return true
end

function TechnicianClient.RequestWorkOrder(action, workOrderId, reason)
    return TechnicianClient.Request(action, workOrderId, reason)
end

function TechnicianClient.RequestTower(action, towerId)
    action = normalizeAction(action)
    if not Config or not Config.Features
        or Config.Features.Technician ~= true
        or Config.Features.Incidents ~= true then
        return false, 'technician_disabled'
    end
    if action ~= 'diagnose' and action ~= 'begin'
        and action ~= 'accept' and action ~= 'arrive' and action ~= 'verify' then
        return false, 'unknown_target_action'
    end
    if not safeString(towerId, 64) then return false, 'tower_id_required' end
    if type(TriggerServerEvent) ~= 'function' then
        return false, 'event_api_unavailable'
    end

    TriggerServerEvent(Constants.Events.MAINTENANCE_TARGET_REQUEST, {
        action = action,
        towerId = towerId,
    })
    return true
end

function TechnicianClient.GetLastResponse()
    return copy(lastResponse)
end

function TechnicianClient.ClearLastResponse()
    lastResponse = nil
end

local function printResponse(payload)
    if type(print) ~= 'function' then return end
    if type(payload) ~= 'table' or type(payload.ok) ~= 'boolean' then return end
    if payload.ok ~= true then
        print(('[gnsh-telecom] technician request rejected: %s')
            :format(tostring(payload.error)))
        return
    end

    local result = type(payload.result) == 'table' and payload.result or {}
    local incident = result.incident or result
    print(('[gnsh-telecom] technician request ok incident=%s status=%s')
        :format(tostring(incident.id), tostring(incident.status)))
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.MAINTENANCE_STATE)
end
if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.MAINTENANCE_STATE, function(payload)
        if type(payload) ~= 'table' or type(payload.ok) ~= 'boolean' then return end
        if payload.ok == true and payload.result ~= nil
            and type(payload.result) ~= 'table' then return end
        if payload.ok ~= true and type(payload.error) ~= 'string' then return end
        lastResponse = {
            ok = payload.ok == true,
            result = payload.ok == true and copy(payload.result) or nil,
            error = payload.ok == true and nil or payload.error,
        }
        printResponse(lastResponse)
    end)
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('telecomtech', function(_, args)
        args = type(args) == 'table' and args or {}
        local reason
        if args[1] == 'cancel' and #args >= 3 then
            reason = table.concat(args, ' ', 3)
        end
        local ok, errorCode = TechnicianClient.Request(args[1], args[2], reason)
        if not ok and type(print) == 'function' then
            print(('[gnsh-telecom] technician request rejected: %s')
                :format(tostring(errorCode)))
        end
    end, false)
end
