IncidentManager = IncidentManager or {}

local function enabled()
    return Config and Config.Features and Config.Features.Incidents == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function audit(source, action, details)
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source or 0, action, details)
    end
end

local function notify(record, previous)
    if TelecomAPI and TelecomAPI.EmitIncidentEvent then
        TelecomAPI.EmitIncidentEvent(record and record.towerId, record, previous)
    end
end

function IncidentManager.CreateForFailure(failure, restored)
    if not enabled() then return false, 'incidents_disabled' end
    if type(failure) ~= 'table' then return false, 'failure_required' end
    if IncidentTickets.FindByFailure(failure.id) then
        return false, 'incident_exists'
    end

    local created, errorCode = IncidentTickets.Create({
        failureId = failure.id,
        towerId = failure.towerId,
        severity = IncidentSeverity.GetForFailure(failure),
        metadata = {
            failureType = failure.type,
            restored = restored == true,
        },
    })
    if not created then return false, errorCode end
    if not restored then
        audit(failure.source or 0, 'incident_created', {
            incidentId = created.id,
            failureId = failure.id,
            towerId = failure.towerId,
        })
    end
    if TelecomStatistics and TelecomStatistics.RecordIncidentCreated then
        TelecomStatistics.RecordIncidentCreated()
    end
    notify(created, nil)
    return true, created
end

function IncidentManager.OnFailureCreated(failure, restored)
    if not enabled() then return false, 'incidents_disabled' end
    return IncidentManager.CreateForFailure(failure, restored)
end

function IncidentManager.OnFailureCleared(failure, actorContext)
    if not enabled() or type(failure) ~= 'table' then return false end
    local incident = IncidentTickets.FindByFailure(failure.id)
    if not incident or incident.status == Enums.IncidentState.CLOSED then return false end
    local actorSource = 0
    local actorId
    if type(actorContext) == 'table' then
        actorSource = tonumber(actorContext.source) or 0
        actorId = actorContext.actorId
    elseif type(actorContext) == 'number' then
        actorSource = actorContext
    end
    local details = { failureCleared = true }
    if type(actorId) == 'string' and actorId ~= '' then
        details.actorId = actorId
    end
    local previous = incident
    local ok, updated = IncidentTickets.Transition(
        incident.id,
        Enums.IncidentState.RESOLVED,
        actorSource,
        details
    )
    if not ok then return false, updated end
    audit(actorSource, 'incident_resolved', {
        incidentId = updated.id,
        failureId = failure.id,
        actorId = actorId,
    })
    if TelecomStatistics and TelecomStatistics.RecordIncidentResolved then
        TelecomStatistics.RecordIncidentResolved()
    end
    notify(updated, previous)
    return true, updated
end

function IncidentManager.Get(id)
    if not enabled() then return nil, 'incidents_disabled' end
    return IncidentTickets.Get(id)
end

function IncidentManager.GetAll()
    if not enabled() then return {} end
    return IncidentTickets.GetAll()
end

function IncidentManager.Transition(id, state, actor, details)
    if not enabled() then return false, 'incidents_disabled' end
    local previous = IncidentTickets.Get(id)
    if not previous then return false, 'incident_not_found' end
    local ok, updated = IncidentTickets.Transition(id, state, actor, details)
    if not ok then return false, updated end
    local auditDetails = {
        incidentId = id,
        from = previous.status,
        to = state,
    }
    if type(details) == 'table' then
        for key, value in pairs(details) do auditDetails[key] = copy(value) end
    end
    audit(actor or 0, 'incident_transition', auditDetails)
    notify(updated, previous)
    return true, updated
end

function IncidentManager.Assign(id, source, actor, details)
    if not enabled() then return false, 'incidents_disabled' end
    local previous = IncidentTickets.Get(id)
    if not previous then return false, 'incident_not_found' end
    local ok, updated = IncidentTickets.Assign(id, source, actor)
    if not ok then return false, updated end
    local auditDetails = {
        incidentId = id,
        assignedTo = updated.assignedTo,
    }
    if type(details) == 'table' then
        for key, value in pairs(details) do auditDetails[key] = copy(value) end
    end
    audit(actor or 0, 'incident_assigned', auditDetails)
    notify(updated, previous)
    return true, updated
end

function IncidentManager.Reset()
    if IncidentTickets and IncidentTickets.Reset then IncidentTickets.Reset() end
    if MaintenanceWorkOrders and MaintenanceWorkOrders.Reset then
        MaintenanceWorkOrders.Reset()
    end
end

function IncidentManager.GetSnapshot()
    local incidents = IncidentManager.GetAll()
    local counts = {}
    for _, incident in ipairs(incidents) do
        counts[incident.status] = (counts[incident.status] or 0) + 1
    end
    return { incidents = copy(incidents), counts = counts }
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.INCIDENT_REQUEST)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.INCIDENT_REQUEST, function(payload)
        local sourceId = source
        if not TelecomPermissions or not TelecomPermissions.RequireAdmin then return end
        local authorized = TelecomPermissions.RequireAdmin(sourceId)
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'incident', 1000, 10)
        if not authorized or not limited or type(payload) ~= 'table'
            or not TelecomSecurity.IsSafeTable(payload, 3, 32) then return end
        local action = payload.action
        local ok, result
        if action == 'transition' then
            ok, result = IncidentManager.Transition(payload.id, payload.state, sourceId, payload.details)
        elseif action == 'assign' then
            ok, result = IncidentManager.Assign(payload.id, payload.assignedTo, sourceId)
        else
            ok, result = false, 'unknown_incident_action'
        end
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent(Constants.Events.INCIDENT_STATE, sourceId, {
                ok = ok,
                result = ok and copy(result) or nil,
                error = ok and nil or result,
            })
        end
    end)
end
