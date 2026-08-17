MaintenanceWorkOrders = MaintenanceWorkOrders or {}
WorkOrders = MaintenanceWorkOrders

local ordersById = {}
local activeByIncident = {}
local activeBySource = {}
local sequence = 0

local transitions = {
    OFFERED = { ACCEPTED = true, CANCELLED = true },
    ACCEPTED = { EN_ROUTE = true, CANCELLED = true },
    EN_ROUTE = { ON_SITE = true, CANCELLED = true },
    ON_SITE = { DIAGNOSING = true, CANCELLED = true },
    DIAGNOSING = { READY_FOR_REPAIR = true, CANCELLED = true },
    READY_FOR_REPAIR = { REPAIRING = true, CANCELLED = true },
    REPAIRING = { VERIFYING = true, READY_FOR_REPAIR = true, CANCELLED = true },
    VERIFYING = { COMPLETED = true, REPAIRING = true, DIAGNOSING = true, CANCELLED = true },
    COMPLETED = {},
    CANCELLED = {},
}

local timestampByState = {
    ACCEPTED = 'acceptedAt',
    ON_SITE = 'arrivedAt',
    DIAGNOSING = 'diagnosisStartedAt',
    REPAIRING = 'repairStartedAt',
    VERIFYING = 'verificationStartedAt',
    COMPLETED = 'completedAt',
}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function now()
    if MaintenanceSessions and type(MaintenanceSessions.Now) == 'function' then
        return MaintenanceSessions.Now()
    end
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and type(value) == 'number' then return math.floor(value) end
    end
    return os.time() * 1000
end

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function sourceNumber(source)
    if TelecomSecurity and type(TelecomSecurity.NormalizeSource) == 'function' then
        return TelecomSecurity.NormalizeSource(source)
    end
    local number = tonumber(source)
    if not number or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function actorId(source)
    if not FrameworkBridge or type(FrameworkBridge.GetStablePlayerId) ~= 'function' then
        return nil
    end
    local value = FrameworkBridge.GetStablePlayerId(source)
    return safeString(value, 128) and value or nil
end

local function admin(source)
    return TelecomPermissions
        and type(TelecomPermissions.IsAdmin) == 'function'
        and TelecomPermissions.IsAdmin(source) == true
end

local function authorized(source)
    local configured = Config and Config.Technician or {}
    if configured.allowAdmin and admin(source) then return true, 'admin' end
    if not FrameworkBridge or type(FrameworkBridge.IsJobAllowed) ~= 'function' then
        return false, 'technician_job_required'
    end
    local allowed, job = FrameworkBridge.IsJobAllowed(source, configured.jobs)
    if not allowed then return false, 'technician_job_required' end
    return true, job
end

local function nextId()
    repeat
        sequence = sequence + 1
    until ordersById[('WO-%06d'):format(sequence)] == nil
    return ('WO-%06d'):format(sequence)
end

local function terminal(order)
    return order and (order.status == Enums.WorkOrderState.COMPLETED
        or order.status == Enums.WorkOrderState.CANCELLED)
end

local function currentForIncident(incidentId)
    local id = activeByIncident[incidentId]
    return id and ordersById[id] or nil
end

local function currentForSource(source)
    local number = sourceNumber(source)
    local id = number and activeBySource[number]
    return id and ordersById[id] or nil
end

local function find(identifier)
    if not safeString(identifier, 96) then return nil end
    if ordersById[identifier] then return ordersById[identifier] end
    if activeByIncident[identifier] then return ordersById[activeByIncident[identifier]] end
    if activeBySource[tonumber(identifier)] then
        return ordersById[activeBySource[tonumber(identifier)]]
    end
    for index = #ordersById, 1, -1 do
        local order = ordersById[index]
        if order and (order.incidentId == identifier or order.repairSessionId == identifier
            or order.diagnosticSessionId == identifier) then
            return order
        end
    end
    for _, order in pairs(ordersById) do
        if order.incidentId == identifier or order.repairSessionId == identifier
            or order.diagnosticSessionId == identifier then
            return order
        end
    end
    return nil
end

local function incidentFor(order)
    return order and IncidentManager and IncidentManager.Get
        and IncidentManager.Get(order.incidentId) or nil
end

local function publicIncident(incident)
    local result = copy(incident)
    if type(result) ~= 'table' then return result end
    result.failureId = nil
    if type(result.metadata) == 'table' then
        result.metadata.failureId = nil
        result.metadata.failureType = nil
    end
    return result
end

local function result(order, incident)
    return {
        workOrder = copy(order),
        incident = incident and publicIncident(incident) or nil,
    }
end

local function releaseIndexes(order)
    if not order then return end
    if activeByIncident[order.incidentId] == order.id then
        activeByIncident[order.incidentId] = nil
    end
    if order.assignedSource and activeBySource[order.assignedSource] == order.id then
        activeBySource[order.assignedSource] = nil
    end
end

local function indexOrder(order)
    if order.status == Enums.WorkOrderState.COMPLETED
        or order.status == Enums.WorkOrderState.CANCELLED then
        releaseIndexes(order)
        return
    end
    activeByIncident[order.incidentId] = order.id
    if order.assignedSource then activeBySource[order.assignedSource] = order.id end
end

local function transition(order, nextState, details)
    if not order or not transitions[order.status] then
        return false, 'work_order_not_found'
    end
    if order.status ~= nextState and not transitions[order.status][nextState] then
        return false, 'invalid_work_order_transition'
    end
    local updated = copy(order)
    updated.status = nextState
    updated.updatedAt = now()
    local timestampField = timestampByState[nextState]
    if timestampField then updated[timestampField] = updated.updatedAt end
    if type(details) == 'table' then
        updated.lastAction = copy(details)
    end
    ordersById[updated.id] = updated
    indexOrder(updated)
    return true, updated
end

local function setAssignment(order, source, stableActor)
    local updated = copy(order)
    local previousSource = updated.assignedSource
    updated.assignedSource = sourceNumber(source) or source
    updated.assignedActorId = stableActor or updated.assignedActorId
    updated.updatedAt = now()
    ordersById[updated.id] = updated
    if previousSource and activeBySource[previousSource] == updated.id then
        activeBySource[previousSource] = nil
    end
    indexOrder(updated)
    return updated
end

local function assignIncident(incident, source, actor)
    if not incident then return false, 'incident_not_found' end
    local sourceValue = sourceNumber(source) or source
    if incident.assignedTo
        and tonumber(incident.assignedTo) ~= tonumber(sourceValue)
        and actor ~= 'admin' then
        return false, 'incident_assigned_to_other'
    end
    local current = incident
    if current.status == Enums.IncidentState.OPEN then
        local acknowledged, errorCode = IncidentManager.Transition(
            current.id,
            Enums.IncidentState.ACKNOWLEDGED,
            sourceValue,
            { workOrder = true }
        )
        if not acknowledged then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    if current.status == Enums.IncidentState.ACKNOWLEDGED
        or (current.status == Enums.IncidentState.ASSIGNED and current.assignedTo == nil) then
        local assigned, errorCode = IncidentManager.Assign(
            current.id,
            sourceValue,
            sourceValue,
            { workOrder = true }
        )
        if not assigned then return false, errorCode end
        current = IncidentManager.Get(current.id)
    end
    return true, current
end

local function nearTower(source, order)
    local tower = TowerRegistry and TowerRegistry.Get and TowerRegistry.Get(order.towerId)
    if not tower then return false, 'tower_not_found' end
    local maximum = Config and Config.Technician
        and Config.Technician.interactionDistance or 5.0
    local near, distance = TelecomSecurity.IsNearPlayer(source, tower.coords, maximum)
    if not near then return false, distance end
    return true, tower, distance
end

local function validateOwner(source, order)
    if not order then return false, 'work_order_not_found' end
    local allowed, actor = authorized(source)
    if not allowed then return false, actor end
    local number = sourceNumber(source)
    if order.assignedSource and tonumber(order.assignedSource) ~= tonumber(number)
        and actor ~= 'admin' then
        return false, 'work_order_assigned_to_other'
    end
    local stable = actorId(source)
    if order.assignedActorId and stable ~= order.assignedActorId and actor ~= 'admin' then
        return false, 'actor_identity_mismatch'
    end
    return true, actor, stable
end

function MaintenanceWorkOrders.Validate(identifier, source)
    local order = find(identifier)
    local valid, actor, stable = validateOwner(source, order)
    if not valid then return false, actor end
    return true, copy(order), actor, stable
end

local function createForIncident(incident, source)
    local existing = currentForIncident(incident.id)
    if existing then return true, existing end
    local number = sourceNumber(source)
    local stable = actorId(source)
    local id = nextId()
    local createdAt = now()
    local order = {
        id = id,
        incidentId = incident.id,
        towerId = incident.towerId,
        assignedActorId = stable,
        assignedSource = number,
        status = Enums.WorkOrderState.OFFERED,
        createdAt = createdAt,
        acceptedAt = nil,
        arrivedAt = nil,
        diagnosisStartedAt = nil,
        repairStartedAt = nil,
        verificationStartedAt = nil,
        completedAt = nil,
        updatedAt = createdAt,
    }
    ordersById[id] = order
    activeByIncident[incident.id] = id
    if number then activeBySource[number] = id end
    return true, order
end

function MaintenanceWorkOrders.Create(incidentId, source, stableActor, options)
    if not safeString(incidentId, 64) then return false, 'incident_id_required' end
    local incident = IncidentManager and IncidentManager.Get and IncidentManager.Get(incidentId)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.RESOLVED
        or incident.status == Enums.IncidentState.CLOSED then
        return false, 'incident_terminal'
    end
    local existing = currentForIncident(incidentId)
    if existing then return false, 'work_order_exists', copy(existing) end

    options = type(options) == 'table' and options or {}
    local number = sourceNumber(source)
    local id = safeString(options.id, 96) and options.id or nextId()
    if ordersById[id] then return false, 'work_order_id_exists' end
    local createdAt = tonumber(options.createdAt) or now()
    local order = {
        id = id,
        incidentId = incidentId,
        towerId = incident.towerId,
        assignedActorId = safeString(stableActor, 128) and stableActor
            or actorId(source),
        assignedSource = number,
        status = Enums.WorkOrderState.OFFERED,
        createdAt = createdAt,
        acceptedAt = nil,
        arrivedAt = nil,
        diagnosisStartedAt = nil,
        repairStartedAt = nil,
        verificationStartedAt = nil,
        completedAt = nil,
        updatedAt = createdAt,
    }
    ordersById[id] = order
    activeByIncident[incidentId] = id
    if number then activeBySource[number] = id end
    local suffix = id:match('^WO%-(%d+)$')
    if suffix and tonumber(suffix) > sequence then sequence = tonumber(suffix) end
    return true, copy(order)
end

function MaintenanceWorkOrders.Get(identifier)
    local order = find(identifier)
    return order and copy(order) or nil
end

function MaintenanceWorkOrders.GetForIncident(incidentId)
    local order = currentForIncident(incidentId)
    return order and copy(order) or nil
end

function MaintenanceWorkOrders.GetForSource(source)
    local order = currentForSource(source)
    return order and copy(order) or nil
end

function MaintenanceWorkOrders.GetForRepairSession(sessionId)
    for _, order in pairs(ordersById) do
        if order.repairSessionId == sessionId then return copy(order) end
    end
    return nil
end

function MaintenanceWorkOrders.List()
    local result = {}
    for _, order in pairs(ordersById) do result[#result + 1] = copy(order) end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

function MaintenanceWorkOrders.Count()
    local count = 0
    for _ in pairs(ordersById) do count = count + 1 end
    return count
end

function MaintenanceWorkOrders.Accept(source, identifier)
    local allowed, actor = authorized(source)
    if not allowed then return false, actor end
    local order = find(identifier)
    local incident = order and incidentFor(order) or IncidentManager.Get(identifier)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.RESOLVED
        or incident.status == Enums.IncidentState.CLOSED then
        return false, 'incident_terminal'
    end
    if not order then
        local created, createdOrder = createForIncident(incident, source)
        if not created then return false, createdOrder end
        order = createdOrder
    end
    local ownerOk, ownerError = validateOwner(source, order)
    if not ownerOk and actor ~= 'admin' then return false, ownerError end
    if terminal(order) then return false, 'work_order_replayed' end
    if order.status ~= Enums.WorkOrderState.OFFERED
        and order.status ~= Enums.WorkOrderState.ACCEPTED then
        return false, 'work_order_not_offered'
    end
    local assigned, assignedIncident = assignIncident(incident, source, actor)
    if not assigned then return false, assignedIncident end
    order = setAssignment(order, source, actorId(source))
    local transitioned, nextOrder = transition(
        order,
        Enums.WorkOrderState.ACCEPTED,
        { action = 'accept' }
    )
    if not transitioned then return false, nextOrder end
    return true, result(nextOrder, assignedIncident)
end

function MaintenanceWorkOrders.Travel(source, identifier)
    local order = find(identifier)
    local ownerOk, actor, stable = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status == Enums.WorkOrderState.EN_ROUTE then
        return true, result(order, incidentFor(order))
    end
    if order.status ~= Enums.WorkOrderState.ACCEPTED then
        return false, 'work_order_not_accepted'
    end
    local incident = incidentFor(order)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.ASSIGNED then
        local moved, errorCode = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.ON_ROUTE,
            source,
            { workOrder = order.id, actorId = stable }
        )
        if not moved then return false, errorCode end
        incident = IncidentManager.Get(incident.id)
    end
    local moved, nextOrder = transition(order, Enums.WorkOrderState.EN_ROUTE, {
        action = 'travel',
    })
    if not moved then return false, nextOrder end
    return true, result(nextOrder, incident)
end

function MaintenanceWorkOrders.Arrive(source, identifier)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status == Enums.WorkOrderState.ON_SITE then
        return true, result(order, incidentFor(order))
    end
    if order.status ~= Enums.WorkOrderState.EN_ROUTE then
        return false, 'work_order_not_en_route'
    end
    local near, towerOrError, distance = nearTower(source, order)
    if not near then return false, towerOrError end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.ON_SITE, {
        action = 'arrive',
        distance = distance,
    })
    if not transitioned then return false, nextOrder end
    return true, result(nextOrder, incidentFor(nextOrder))
end

function MaintenanceWorkOrders.StartDiagnosis(source, identifier)
    local order = find(identifier)
    local ownerOk, actor, stable = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status == Enums.WorkOrderState.DIAGNOSING
        or order.status == Enums.WorkOrderState.READY_FOR_REPAIR then
        return true, result(order, incidentFor(order))
    end
    if order.status ~= Enums.WorkOrderState.ON_SITE then
        return false, 'work_order_not_on_site'
    end
    local incident = incidentFor(order)
    if not incident then return false, 'incident_not_found' end
    if incident.status == Enums.IncidentState.ON_ROUTE then
        local diagnosing, errorCode = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.DIAGNOSING,
            source,
            { workOrder = order.id, actorId = stable }
        )
        if not diagnosing then return false, errorCode end
        incident = IncidentManager.Get(incident.id)
    end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.DIAGNOSING, {
        action = 'diagnose_start',
    })
    if not transitioned then return false, nextOrder end
    return true, result(nextOrder, incident)
end

function MaintenanceWorkOrders.CompleteDiagnosis(source, identifier, diagnosis)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status == Enums.WorkOrderState.READY_FOR_REPAIR then
        return true, result(order, incidentFor(order))
    end
    if order.status ~= Enums.WorkOrderState.DIAGNOSING then
        return false, 'work_order_not_diagnosing'
    end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.READY_FOR_REPAIR, {
        action = 'diagnose_complete',
        actorId = actor,
    })
    if not transitioned then return false, nextOrder end
    nextOrder = copy(nextOrder)
    nextOrder.diagnosis = copy(diagnosis or {})
    ordersById[nextOrder.id] = nextOrder
    return true, result(nextOrder, incidentFor(nextOrder))
end

function MaintenanceWorkOrders.StartRepair(source, identifier)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status == Enums.WorkOrderState.REPAIRING then
        return true, result(order, incidentFor(order))
    end
    if order.status ~= Enums.WorkOrderState.READY_FOR_REPAIR then
        return false, 'work_order_not_ready_for_repair'
    end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.REPAIRING, {
        action = 'repair_start',
        actorId = actor,
    })
    if not transitioned then return false, nextOrder end
    return true, result(nextOrder, incidentFor(nextOrder))
end

MaintenanceWorkOrders.BeginRepair = MaintenanceWorkOrders.StartRepair
MaintenanceWorkOrders.MarkRepairStarted = MaintenanceWorkOrders.StartRepair

function MaintenanceWorkOrders.MarkDiagnosisSession(source, identifier, sessionId)
    local order = find(identifier)
    local ownerOk, errorCode = validateOwner(source, order)
    if not ownerOk then return false, errorCode end
    local updated = copy(order)
    updated.diagnosticSessionId = sessionId
    ordersById[updated.id] = updated
    return true, copy(updated)
end

function MaintenanceWorkOrders.MarkRepairSession(source, identifier, sessionId)
    local order = find(identifier)
    local ownerOk, errorCode = validateOwner(source, order)
    if not ownerOk then return false, errorCode end
    local updated = copy(order)
    updated.repairSessionId = sessionId
    ordersById[updated.id] = updated
    return true, copy(updated)
end

function MaintenanceWorkOrders.MarkRepairPart(source, identifier, item)
    local order = find(identifier)
    local ownerOk, errorCode = validateOwner(source, order)
    if not ownerOk then return false, errorCode end
    local updated = copy(order)
    updated.repairPart = item
    ordersById[updated.id] = updated
    return true, copy(updated)
end

function MaintenanceWorkOrders.MarkRepairFailed(source, identifier, details)
    local order = find(identifier)
    local ownerOk, errorCode = validateOwner(source, order)
    if not ownerOk then return false, errorCode end
    if order.status ~= Enums.WorkOrderState.REPAIRING then
        return false, 'work_order_not_repairing'
    end
    return transition(order, Enums.WorkOrderState.READY_FOR_REPAIR, details)
end

function MaintenanceWorkOrders.StartVerification(source, identifier)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status == Enums.WorkOrderState.VERIFYING then
        return true, result(order, incidentFor(order))
    end
    if order.status ~= Enums.WorkOrderState.REPAIRING then
        return false, 'work_order_not_repairing'
    end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.VERIFYING, {
        action = 'verify_start',
        actorId = actor,
    })
    if not transitioned then return false, nextOrder end
    return true, result(nextOrder, incidentFor(nextOrder))
end

function MaintenanceWorkOrders.FailVerification(source, identifier, reason)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status ~= Enums.WorkOrderState.VERIFYING then
        return false, 'work_order_not_verifying'
    end
    local incident = incidentFor(order)
    if incident and incident.status == Enums.IncidentState.VERIFYING then
        local moved, errorCode = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.REPAIRING,
            source,
            { verificationFailed = reason or true, actorId = actor }
        )
        if not moved then return false, errorCode end
        incident = IncidentManager.Get(incident.id)
    end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.REPAIRING, {
        action = 'verify_failed',
        reason = reason or 'verification_failed',
    })
    if not transitioned then return false, nextOrder end
    return true, result(nextOrder, incident)
end

function MaintenanceWorkOrders.CompleteVerification(source, identifier, checks)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    if order.status ~= Enums.WorkOrderState.VERIFYING then
        return false, 'work_order_not_verifying'
    end
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.COMPLETED, {
        action = 'verify_complete',
        actorId = actor,
    })
    if not transitioned then return false, nextOrder end
    nextOrder = copy(nextOrder)
    nextOrder.verification = copy(checks or {})
    ordersById[nextOrder.id] = nextOrder
    return true, result(nextOrder, incidentFor(nextOrder))
end

function MaintenanceWorkOrders.ReopenVerification(source, identifier, reason)
    local order = find(identifier)
    local ownerOk, errorCode = validateOwner(source, order)
    if not ownerOk then return false, errorCode end
    if order.status ~= Enums.WorkOrderState.COMPLETED then
        return false, 'work_order_not_completed'
    end
    local reopened = copy(order)
    reopened.status = Enums.WorkOrderState.VERIFYING
    reopened.completedAt = nil
    reopened.updatedAt = now()
    reopened.lastAction = {
        action = 'verification_reopened',
        reason = reason or 'verification_commit_failed',
    }
    ordersById[reopened.id] = reopened
    indexOrder(reopened)
    return true, result(reopened, incidentFor(reopened))
end

local function unassignIncident(incident, source, actor, reason)
    if not incident then return true end
    local current = incident
    local actorValue = actor or source
    local function move(state)
        local ok, value = IncidentManager.Transition(
            current.id,
            state,
            source,
            { workOrderCancelled = reason or true, unassigned = state == Enums.IncidentState.ASSIGNED }
        )
        if not ok then return false, value end
        current = value
        return true
    end
    if current.status == Enums.IncidentState.VERIFYING then
        local ok, errorCode = move(Enums.IncidentState.REPAIRING)
        if not ok then return false, errorCode end
    end
    if current.status == Enums.IncidentState.REPAIRING then
        local ok, errorCode = move(Enums.IncidentState.DIAGNOSING)
        if not ok then return false, errorCode end
    end
    if current.status == Enums.IncidentState.DIAGNOSING
        or current.status == Enums.IncidentState.ON_ROUTE then
        local ok, errorCode = move(Enums.IncidentState.ASSIGNED)
        if not ok then return false, errorCode end
    end
    if current.status == Enums.IncidentState.ASSIGNED
        and tonumber(current.assignedTo) == tonumber(sourceNumber(source) or source) then
        local updated, errorCode = IncidentManager.Assign(
            current.id,
            nil,
            actorValue,
            { workOrderCancelled = reason or true, unassigned = true }
        )
        if not updated then return false, errorCode or 'incident_unassign_failed' end
    end
    return true
end

local function cancelOrder(order, source, reason, actorValue)
    if not order or terminal(order) then return false, 'work_order_replayed' end
    local incident = incidentFor(order)
    local transitioned, nextOrder = transition(order, Enums.WorkOrderState.CANCELLED, {
        action = 'cancel',
        reason = reason or 'cancelled',
    })
    if not transitioned then return false, nextOrder end
    local released, releaseError = unassignIncident(
        incident,
        source,
        actorValue or source,
        reason
    )
    if not released then return false, releaseError end
    return true, result(nextOrder, IncidentManager.Get(order.incidentId))
end

function MaintenanceWorkOrders.Cancel(source, identifier, reason)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk then return false, actor end
    return cancelOrder(order, source, reason, actor)
end

function MaintenanceWorkOrders.CancelForCleanup(identifier, source, reason)
    local order = find(identifier)
    if not order then return false, 'work_order_not_found' end
    if order.assignedSource and tonumber(order.assignedSource) ~= tonumber(source) then
        return false, 'work_order_assigned_to_other'
    end
    return cancelOrder(order, source, reason or 'session_cleanup', source)
end

function MaintenanceWorkOrders.ReleaseSource(source, reason)
    local order = currentForSource(source)
    if not order then return 0 end
    local ok = cancelOrder(order, source, reason or 'player_dropped', source)
    return ok and 1 or 0
end

function MaintenanceWorkOrders.Reassign(source, identifier, newSource)
    local order = find(identifier)
    local ownerOk, actor = validateOwner(source, order)
    if not ownerOk and actor ~= 'admin' then return false, actor end
    local target = sourceNumber(newSource)
    if not target then return false, 'player_source_required' end
    if terminal(order) then return false, 'work_order_replayed' end
    local targetAllowed, targetError = authorized(target)
    if not targetAllowed then return false, targetError end
    if activeBySource[target] and activeBySource[target] ~= order.id then
        return false, 'work_order_source_busy'
    end
    local stable = actorId(target)
    local updated = setAssignment(order, target, stable)
    local incident = incidentFor(updated)
    if incident and (incident.status == Enums.IncidentState.ASSIGNED
        or incident.status == Enums.IncidentState.ACKNOWLEDGED) then
        local assigned, errorCode = IncidentManager.Assign(
            incident.id,
            target,
            source,
            { reassigned = true }
        )
        if not assigned then return false, errorCode end
        incident = IncidentManager.Get(incident.id)
    elseif incident and incident.status == Enums.IncidentState.ON_ROUTE then
        local reset, resetError = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.ASSIGNED,
            source,
            { reassigned = true, unassigned = true }
        )
        if not reset then return false, resetError end
        local assigned, assignedError = IncidentManager.Assign(
            incident.id,
            target,
            source,
            { reassigned = true }
        )
        if not assigned then return false, assignedError end
        local resumed, resumedError = IncidentManager.Transition(
            incident.id,
            Enums.IncidentState.ON_ROUTE,
            source,
            { reassigned = true }
        )
        if not resumed then return false, resumedError end
        incident = IncidentManager.Get(incident.id)
    end
    return true, result(updated, incident)
end

local function ensureDiagnosis(source, identifier)
    local order = ordersById[identifier] or currentForIncident(identifier)
    local incident = order and incidentFor(order) or IncidentManager.Get(identifier)
    if not incident then return false, 'incident_not_found' end
    if not order then
        local created, createdOrder = createForIncident(incident, source)
        if not created then return false, createdOrder end
        order = createdOrder
    end
    local steps = {
        { Enums.WorkOrderState.OFFERED, MaintenanceWorkOrders.Accept },
        { Enums.WorkOrderState.ACCEPTED, MaintenanceWorkOrders.Travel },
        { Enums.WorkOrderState.EN_ROUTE, MaintenanceWorkOrders.Arrive },
        { Enums.WorkOrderState.ON_SITE, MaintenanceWorkOrders.StartDiagnosis },
    }
    for _, step in ipairs(steps) do
        local current = ordersById[order.id]
        if current.status == step[1] then
            local moved, value = step[2](source, order.id)
            if not moved then return false, value end
            order = ordersById[order.id]
        end
    end
    return true, copy(ordersById[order.id])
end

function MaintenanceWorkOrders.EnsureForDiagnosis(source, identifier)
    return ensureDiagnosis(source, identifier)
end

function MaintenanceWorkOrders.EnsureForRepair(source, identifier)
    local ok, order = ensureDiagnosis(source, identifier)
    if not ok then return false, order end
    if order.status == Enums.WorkOrderState.DIAGNOSING then
        local completed, completedOrder = MaintenanceWorkOrders.CompleteDiagnosis(
            source,
            order.id,
            { compatibility = true }
        )
        if not completed then return false, completedOrder end
        order = ordersById[order.id]
    end
    if order.status ~= Enums.WorkOrderState.READY_FOR_REPAIR
        and order.status ~= Enums.WorkOrderState.REPAIRING then
        return false, 'work_order_not_ready_for_repair'
    end
    return true, copy(order)
end

function MaintenanceWorkOrders.ClearSource(source, reason)
    return MaintenanceWorkOrders.ReleaseSource(source, reason)
end

function MaintenanceWorkOrders.Reset()
    ordersById = {}
    activeByIncident = {}
    activeBySource = {}
    sequence = 0
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        MaintenanceWorkOrders.ClearSource(source, 'player_dropped')
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        local currentResource = type(GetCurrentResourceName) == 'function'
            and GetCurrentResourceName() or nil
        if not currentResource or resourceName == currentResource then
            local ids = {}
            for id, order in pairs(ordersById) do
                if not terminal(order) then ids[#ids + 1] = id end
            end
            for _, id in ipairs(ids) do
                local order = ordersById[id]
                if order and order.assignedSource then
                    MaintenanceWorkOrders.CancelForCleanup(id, order.assignedSource, 'resource_stop')
                end
            end
        end
    end)
end
