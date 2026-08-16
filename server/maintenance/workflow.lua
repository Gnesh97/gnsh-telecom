MaintenanceWorkflow = MaintenanceWorkflow or {}

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.MAINTENANCE_REQUEST)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.MAINTENANCE_REQUEST, function(payload)
        local sourceId = source
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'maintenance', 1000, 5)
        if not limited or type(payload) ~= 'table'
            or not TelecomSecurity.IsSafeTable(payload, 2, 16) then return end
        local ok, result
        if payload.action == 'diagnose' then
            ok, result = MaintenanceDiagnostics.Inspect(sourceId, payload.incidentId)
        elseif payload.action == 'begin' then
            ok, result = MaintenanceRepairs.Begin(sourceId, payload.incidentId)
        elseif payload.action == 'complete' then
            ok, result = MaintenanceRepairs.Complete(sourceId, payload.incidentId)
        elseif payload.action == 'cancel' then
            ok, result = MaintenanceRepairs.Cancel(sourceId, payload.incidentId, payload.reason)
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
end
