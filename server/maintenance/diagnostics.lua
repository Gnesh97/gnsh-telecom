MaintenanceDiagnostics = MaintenanceDiagnostics or {}

local function enabled()
    return Config and Config.Features and Config.Features.Technician == true
        and Config.Features.Incidents == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function authorizedTechnician(source)
    local configured = Config and Config.Technician or {}
    if configured.allowAdmin and TelecomPermissions and TelecomPermissions.IsAdmin
        and TelecomPermissions.IsAdmin(source) then
        return true, 'admin'
    end
    local allowed, job = FrameworkBridge.IsJobAllowed(source, configured.jobs)
    if not allowed then return false, 'technician_job_required' end
    return true, job
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

function MaintenanceDiagnostics.Inspect(source, incidentId)
    if not enabled() then return false, 'technician_disabled' end
    local allowed, actor = authorizedTechnician(source)
    if not allowed then return false, actor end
    local incident = IncidentManager.Get(incidentId)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.CLOSED then return false, 'incident_closed' end
    if incident.assignedTo and tonumber(incident.assignedTo) ~= tonumber(source)
        and actor ~= 'admin' then
        return false, 'incident_assigned_to_other' end

    local tower = TowerRegistry.Get(incident.towerId)
    local near, distance = TelecomSecurity.IsNearPlayer(
        source,
        tower and tower.coords,
        Config.Technician.interactionDistance or 5.0
    )
    if not near then return false, distance end

    local failure = FailureEngine.Get(incident.failureId)
    if not failure then return false, 'failure_not_found' end
    local symptoms = symptomByType[failure.type] or { 'unknown technical symptoms' }
    return true, {
        incident = copy(incident),
        failure = copy(failure),
        symptoms = copy(symptoms),
        probableCause = FailureTypes.Get(failure.type),
        component = failure.component,
        distance = distance,
    }
end
