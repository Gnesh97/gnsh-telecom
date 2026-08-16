IncidentTickets = IncidentTickets or {}

local recordsById = {}
local orderedIds = {}
local sequence = 0

local transitions = {
    OPEN = { ACKNOWLEDGED = true, ASSIGNED = true, RESOLVED = true },
    ACKNOWLEDGED = { ASSIGNED = true, ON_ROUTE = true, RESOLVED = true },
    ASSIGNED = { ON_ROUTE = true, DIAGNOSING = true, RESOLVED = true },
    ON_ROUTE = { DIAGNOSING = true, ASSIGNED = true, RESOLVED = true },
    DIAGNOSING = { REPAIRING = true, ASSIGNED = true, RESOLVED = true },
    REPAIRING = { RESOLVED = true, DIAGNOSING = true },
    RESOLVED = { CLOSED = true },
    CLOSED = {},
}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function now()
    return type(os.time) == 'function' and os.time() or 0
end

local function nextId()
    repeat
        sequence = sequence + 1
    until recordsById[('INC-%06d'):format(sequence)] == nil
    return ('INC-%06d'):format(sequence)
end

local function validState(state)
    return type(state) == 'string' and transitions[state] ~= nil
end

function IncidentTickets.Create(data)
    if type(data) ~= 'table' then return nil, 'incident_required' end
    if type(data.failureId) ~= 'string' or data.failureId == '' then
        return nil, 'failure_id_required'
    end
    if type(data.towerId) ~= 'string' or data.towerId == '' then
        return nil, 'tower_id_required'
    end
    if not IncidentSeverity.IsValid(data.severity) then
        return nil, 'invalid_severity'
    end

    local id = data.id or nextId()
    if type(id) ~= 'string' or id == '' or #id > 64 or recordsById[id] then
        return nil, recordsById[id] and 'duplicate_incident_id' or 'invalid_incident_id'
    end

    local createdAt = tonumber(data.createdAt) or now()
    local record = {
        id = id,
        failureId = data.failureId,
        towerId = data.towerId,
        severity = data.severity,
        status = data.status or Enums.IncidentState.OPEN,
        assignedTo = data.assignedTo,
        createdAt = createdAt,
        acknowledgedAt = data.acknowledgedAt,
        resolvedAt = data.resolvedAt,
        closedAt = data.closedAt,
        updatedAt = data.updatedAt or createdAt,
        history = copy(data.history or {}),
        metadata = copy(data.metadata or {}),
    }
    if not validState(record.status) then return nil, 'invalid_incident_state' end
    recordsById[id] = record
    orderedIds[#orderedIds + 1] = id
    local suffix = id:match('^INC%-(%d+)$')
    if suffix and tonumber(suffix) > sequence then sequence = tonumber(suffix) end
    return copy(record)
end

function IncidentTickets.Get(id)
    return recordsById[id] and copy(recordsById[id]) or nil
end

function IncidentTickets.GetAll()
    local result = {}
    for _, id in ipairs(orderedIds) do
        if recordsById[id] then result[#result + 1] = copy(recordsById[id]) end
    end
    return result
end

function IncidentTickets.FindByFailure(failureId)
    for _, id in ipairs(orderedIds) do
        local record = recordsById[id]
        if record and record.failureId == failureId then return copy(record) end
    end
    return nil
end

function IncidentTickets.CanTransition(from, to)
    return validState(from) and validState(to) and transitions[from][to] == true
end

function IncidentTickets.Transition(id, nextState, actor, details)
    local record = recordsById[id]
    if not record then return false, 'incident_not_found' end
    if not IncidentTickets.CanTransition(record.status, nextState) then
        return false, 'invalid_incident_transition'
    end

    local timestamp = now()
    local next = copy(record)
    next.status = nextState
    next.updatedAt = timestamp
    next.history = next.history or {}
    next.history[#next.history + 1] = {
        from = record.status,
        to = nextState,
        actor = actor,
        timestamp = timestamp,
        details = copy(details or {}),
    }
    if nextState == Enums.IncidentState.ACKNOWLEDGED then next.acknowledgedAt = timestamp end
    if nextState == Enums.IncidentState.RESOLVED then next.resolvedAt = timestamp end
    if nextState == Enums.IncidentState.CLOSED then next.closedAt = timestamp end
    if type(details) == 'table' and details.unassigned == true then
        next.assignedTo = nil
    end
    recordsById[id] = next
    return true, copy(next)
end

function IncidentTickets.Assign(id, source, actor)
    local record = recordsById[id]
    if not record then return false, 'incident_not_found' end
    if record.status == Enums.IncidentState.OPEN then
        local acknowledged, errorCode = IncidentTickets.Transition(
            id,
            Enums.IncidentState.ACKNOWLEDGED,
            actor,
            { implicit = true }
        )
        if not acknowledged then return false, errorCode end
    end
    local current = recordsById[id]
    if current.status ~= Enums.IncidentState.ACKNOWLEDGED
        and current.status ~= Enums.IncidentState.ASSIGNED then
        return false, 'incident_not_assignable'
    end
    current.assignedTo = tonumber(source) or source
    current.updatedAt = now()
    if current.status == Enums.IncidentState.ACKNOWLEDGED then
        local transitioned, errorCode = IncidentTickets.Transition(
            id,
            Enums.IncidentState.ASSIGNED,
            actor,
            { assignedTo = current.assignedTo }
        )
        if not transitioned then return false, errorCode end
    end
    recordsById[id].assignedTo = current.assignedTo
    return true, copy(recordsById[id])
end

function IncidentTickets.Reset()
    recordsById = {}
    orderedIds = {}
    sequence = 0
end
