MaintenanceRepairs = MaintenanceRepairs or {}

local sessionsBySource = {}

local function enabled()
    return Config and Config.Features and Config.Features.Technician == true
        and Config.Features.Incidents == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function technicianAllowed(source)
    local configured = Config and Config.Technician or {}
    if configured.allowAdmin and TelecomPermissions and TelecomPermissions.IsAdmin
        and TelecomPermissions.IsAdmin(source) then return true end
    local allowed = FrameworkBridge.IsJobAllowed(source, configured.jobs)
    return allowed == true
end

local function validateIncident(source, incidentId)
    if not enabled() then return false, 'technician_disabled' end
    if not technicianAllowed(source) then return false, 'technician_job_required' end
    local incident = IncidentManager.Get(incidentId)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.CLOSED then return false, 'incident_closed' end
    if incident.assignedTo and tonumber(incident.assignedTo) ~= tonumber(source)
        and not TelecomPermissions.IsAdmin(source) then
        return false, 'incident_assigned_to_other'
    end
    local tower = TowerRegistry.Get(incident.towerId)
    local near, distance = TelecomSecurity.IsNearPlayer(
        source,
        tower and tower.coords,
        Config.Technician.interactionDistance or 5.0
    )
    if not near then return false, distance end
    local failure = FailureEngine.Get(incident.failureId)
    if not failure then return false, 'failure_not_found' end
    return true, incident, failure, distance
end

local function requiredItem(failure)
    local configured = Config and Config.Technician and Config.Technician.requiredItems or {}
    return configured[failure.type] or configured.default
end

function MaintenanceRepairs.Begin(source, incidentId)
    local ok, incident, failure, distance = validateIncident(source, incidentId)
    if not ok then return false, incident end
    if sessionsBySource[source] then return false, 'repair_session_exists' end
    local current = incident
    if current.status == Enums.IncidentState.OPEN then
        local transitioned, errorCode = IncidentManager.Transition(
            current.id, Enums.IncidentState.ACKNOWLEDGED, source
        )
        if not transitioned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    if current.status == Enums.IncidentState.ACKNOWLEDGED then
        local assigned, errorCode = IncidentManager.Assign(current.id, source, source)
        if not assigned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    local item = requiredItem(failure)
    local hasItem, itemError = InventoryBridge.HasItem(source, item, 1)
    if not hasItem then return false, itemError or 'required_item_missing' end
    local transitioned, errorCode = IncidentManager.Transition(
        current.id, Enums.IncidentState.ON_ROUTE, source
    )
    if not transitioned and current.status ~= Enums.IncidentState.ASSIGNED then
        return false, errorCode end
    sessionsBySource[source] = {
        source = tonumber(source),
        incidentId = current.id,
        startedAt = type(GetGameTimer) == 'function' and GetGameTimer() or os.time() * 1000,
        failureType = failure.type,
    }
    local nextIncident = IncidentManager.Get(current.id)
    if nextIncident and nextIncident.status == Enums.IncidentState.ON_ROUTE then
        IncidentManager.Transition(current.id, Enums.IncidentState.DIAGNOSING, source)
    end
    return true, { session = copy(sessionsBySource[source]), incident = IncidentManager.Get(current.id) }
end

function MaintenanceRepairs.Complete(source, incidentId)
    local session = sessionsBySource[source]
    if not session or session.incidentId ~= incidentId then return false, 'repair_session_not_found' end
    local ok, incident, failure = validateIncident(source, incidentId)
    if not ok then return false, incident end
    if incident.status == Enums.IncidentState.DIAGNOSING then
        local transitioned, errorCode = IncidentManager.Transition(
            incident.id, Enums.IncidentState.REPAIRING, source
        )
        if not transitioned then return false, errorCode end
    end
    local item = requiredItem(failure)
    local hasItem, itemError = InventoryBridge.HasItem(source, item, 1)
    if not hasItem then return false, itemError or 'required_item_missing' end
    if item then
        local removed, removeError = InventoryBridge.RemoveItem(source, item, 1)
        if not removed then return false, removeError or 'required_item_remove_failed' end
    end
    local cleared, clearError = FailureEngine.Clear(failure.id)
    if not cleared then return false, clearError end
    sessionsBySource[source] = nil
    return true, {
        incident = IncidentManager.Get(incident.id),
        failure = copy(failure),
    }
end

function MaintenanceRepairs.Cancel(source, incidentId, reason)
    local session = sessionsBySource[source]
    if not session or session.incidentId ~= incidentId then return false, 'repair_session_not_found' end
    sessionsBySource[source] = nil
    local incident = IncidentManager.Get(incidentId)
    if incident and incident.status == Enums.IncidentState.DIAGNOSING then
        IncidentManager.Transition(incidentId, Enums.IncidentState.ASSIGNED, source, {
            cancelled = reason or 'cancelled',
        })
    end
    return true, incident and IncidentManager.Get(incidentId) or nil
end

function MaintenanceRepairs.GetSession(source)
    return sessionsBySource[source] and copy(sessionsBySource[source]) or nil
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        sessionsBySource[source] = nil
    end)
end
