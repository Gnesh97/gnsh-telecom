IncidentSeverity = IncidentSeverity or {}

local order = {
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4,
}

function IncidentSeverity.IsValid(value)
    return type(value) == 'string' and order[value] ~= nil
end

function IncidentSeverity.GetForFailure(failure)
    local configured = Config and Config.Incidents
        and Config.Incidents.severityByFailure
        and failure and Config.Incidents.severityByFailure[failure.type]
    if IncidentSeverity.IsValid(configured) then return configured end

    local fallback = Config and Config.Incidents and Config.Incidents.defaultSeverity
    if IncidentSeverity.IsValid(fallback) then return fallback end
    return Enums.IncidentSeverity.MEDIUM
end

function IncidentSeverity.Rank(value)
    return order[value] or 0
end

function IncidentSeverity.Compare(left, right)
    return IncidentSeverity.Rank(left) - IncidentSeverity.Rank(right)
end
