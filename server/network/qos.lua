QosEngine = QosEngine or {}

QosEngine.Classes = {
    EMERGENCY = 'EMERGENCY',
    VOICE = 'VOICE',
    SMS = 'SMS',
    DATA_HIGH = 'DATA_HIGH',
    DATA_NORMAL = 'DATA_NORMAL',
    BACKGROUND = 'BACKGROUND',
}

local fallbackPriorities = {
    EMERGENCY = 100,
    VOICE = 90,
    SMS = 70,
    DATA_HIGH = 50,
    DATA_NORMAL = 30,
    BACKGROUND = 10,
}

local policyByClass = {
    EMERGENCY = 'emergency',
    VOICE = 'voice',
    SMS = 'sms',
    DATA_HIGH = 'data',
    DATA_NORMAL = 'data',
    BACKGROUND = 'data',
}

local validClasses = {
    EMERGENCY = true,
    VOICE = true,
    SMS = true,
    DATA_HIGH = true,
    DATA_NORMAL = true,
    BACKGROUND = true,
}

local resultsBySession = {}
local resultsByTower = {}

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function isFiniteNumber(value)
    if TelecomSecurity and TelecomSecurity.IsFiniteNumber then
        return TelecomSecurity.IsFiniteNumber(value)
    end
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function enabled()
    return not (Config and Config.Features) or Config.Features.QoS ~= false
end

local function normalizeService(service)
    if type(service) ~= 'string' or service == '' then return nil end
    return service:upper()
end

local function normalizeClass(value)
    if type(value) ~= 'string' then return nil end
    local normalized = value:upper()
    local aliases = {
        HIGH = 'DATA_HIGH',
        NORMAL = 'DATA_NORMAL',
        BACKGROUND_DATA = 'BACKGROUND',
    }
    normalized = aliases[normalized] or normalized
    return validClasses[normalized] and normalized or nil
end

local function dataClass(metadata)
    if type(metadata) ~= 'table' then return 'DATA_NORMAL' end
    local requested = metadata.qosClass or metadata.priorityClass
        or metadata.dataClass or metadata.priority
    return normalizeClass(requested) or 'DATA_NORMAL'
end

local function resolveClass(service, metadata)
    local normalized = normalizeService(service)
    if normalized == 'EMERGENCY' then return 'EMERGENCY' end
    if normalized == 'VOICE' then return 'VOICE' end
    if normalized == 'SMS' then return 'SMS' end
    if normalized == 'DATA_HIGH' or normalized == 'DATA_NORMAL' then
        return normalized
    end
    if normalized == 'BACKGROUND' then return 'BACKGROUND' end
    if normalized == 'BACKGROUND_DATA' then return 'BACKGROUND' end
    if normalized == 'DATA' then
        local class = dataClass(metadata)
        if class == 'EMERGENCY' or class == 'VOICE' or class == 'SMS' then
            return 'DATA_NORMAL'
        end
        return class
    end
    if normalized == 'GPS' then return 'DATA_NORMAL' end
    return 'DATA_NORMAL'
end

local function priorityFor(class)
    local configured = Config and Config.QoS and Config.QoS.priorities
        and tonumber(Config.QoS.priorities[class])
    if isFiniteNumber(configured) and configured >= 0 then return configured end
    return fallbackPriorities[class] or fallbackPriorities.DATA_NORMAL
end

function QosEngine.GetPriority(service, metadata)
    local class = resolveClass(service, metadata)
    local priority = priorityFor(class)
    return priority, {
        class = class,
        priority = priority,
        policyService = policyByClass[class],
        preemptible = class ~= 'EMERGENCY' and class ~= 'VOICE',
    }
end

function QosEngine.GetClass(service, metadata)
    local _, details = QosEngine.GetPriority(service, metadata)
    return details.class
end

local function normalizeCapacity(capacity, sessions)
    if type(capacity) == 'table' then
        capacity = capacity.serviceCapacity or capacity.effectiveCapacity
            or capacity.capacity or capacity.maximum
    end
    if not isFiniteNumber(capacity) then
        capacity = 0
        for _, session in ipairs(sessions or {}) do
            local demand = session and tonumber(session.demand)
            if isFiniteNumber(demand) and demand > 0 then capacity = capacity + demand end
        end
    end
    return math.max(0, capacity)
end

local function sessionDemand(session)
    local demand = session and tonumber(session.demand)
    return isFiniteNumber(demand) and math.max(0, demand) or 0
end

local function orderedSessions(sessions)
    local ordered = {}
    local seen = {}
    for _, session in ipairs(sessions or {}) do
        local sessionId = type(session) == 'table' and (session.id or session.sessionId)
        if type(sessionId) == 'string' and sessionId ~= '' and not seen[sessionId] then
            seen[sessionId] = true
            local priority, details = QosEngine.GetPriority(
                session.service,
                session.metadata
            )
            ordered[#ordered + 1] = {
                session = session,
                sessionId = sessionId,
                priority = priority,
                details = details,
                demand = sessionDemand(session),
            }
        end
    end
    table.sort(ordered, function(left, right)
        if left.priority ~= right.priority then return left.priority > right.priority end
        local leftCreated = tonumber(left.session.createdAt) or 0
        local rightCreated = tonumber(right.session.createdAt) or 0
        if leftCreated ~= rightCreated then return leftCreated < rightCreated end
        return left.sessionId < right.sessionId
    end)
    return ordered
end

local function clearTowerResults(towerId)
    local previous = resultsByTower[towerId]
    if not previous then return end
    for sessionId in pairs(previous.allocations or {}) do
        resultsBySession[sessionId] = nil
    end
end

function QosEngine.Allocate(towerId, sessions, capacity)
    if type(towerId) ~= 'string' or towerId == '' then
        return nil, 'tower_required'
    end

    clearTowerResults(towerId)
    local available = normalizeCapacity(capacity, sessions)
    if not enabled() then
        resultsByTower[towerId] = nil
        return {
            towerId = towerId,
            capacity = available,
            requested = 0,
            used = 0,
            remaining = available,
            degradedCount = 0,
            blockedCount = 0,
            overloaded = false,
            allocations = {},
            ordered = {},
            enabled = false,
        }
    end
    local ordered = orderedSessions(sessions)
    local requestedTotal = 0
    local used = 0
    local degradedCount = 0
    local blockedCount = 0
    local allocations = {}
    local orderedAllocations = {}

    for _, item in ipairs(ordered) do
        requestedTotal = requestedTotal + item.demand
        local allocated = math.min(item.demand, available)
        available = available - allocated
        used = used + allocated
        local degraded = allocated + 0.000001 < item.demand
        local blocked = item.demand > 0 and allocated <= 0
        if degraded then degradedCount = degradedCount + 1 end
        if blocked then blockedCount = blockedCount + 1 end
        local ratio = item.demand > 0 and allocated / item.demand or 1.0
        local allocation = {
            sessionId = item.sessionId,
            source = item.session.source,
            towerId = towerId,
            service = item.session.service,
            policyService = item.details.policyService,
            class = item.details.class,
            priority = item.priority,
            requested = item.demand,
            allocated = allocated,
            ratio = ratio,
            available = item.demand <= 0 or allocated > 0,
            degraded = degraded,
            blocked = blocked,
            reason = blocked and 'qos_capacity'
                or degraded and 'qos_degraded'
                or 'qos_allocated',
        }
        allocations[item.sessionId] = allocation
        orderedAllocations[#orderedAllocations + 1] = allocation
        resultsBySession[item.sessionId] = copy(allocation)
    end

    local result = {
        towerId = towerId,
        capacity = normalizeCapacity(capacity, sessions),
        requested = requestedTotal,
        used = used,
        remaining = math.max(0, available),
        degradedCount = degradedCount,
        blockedCount = blockedCount,
        overloaded = requestedTotal > normalizeCapacity(capacity, sessions),
        allocations = allocations,
        ordered = orderedAllocations,
    }
    resultsByTower[towerId] = copy(result)
    return copy(result)
end

function QosEngine.GetServiceResult(sessionId)
    if type(sessionId) ~= 'string' then return nil end
    if not enabled() then return nil end
    local result = resultsBySession[sessionId]
    return result and copy(result) or nil
end

function QosEngine.GetTowerResult(towerId)
    if type(towerId) ~= 'string' then return nil end
    if not enabled() then return nil end
    local result = resultsByTower[towerId]
    return result and copy(result) or nil
end

function QosEngine.GetSourceServiceStates(source)
    if not enabled() then return {} end
    local normalizedSource = tonumber(source)
    if not isFiniteNumber(normalizedSource) then return {} end
    local states = {}
    for _, result in pairs(resultsBySession) do
        if tonumber(result.source) == normalizedSource then
            local service = result.policyService
            if service then
                local state = states[service] or {
                    available = false,
                    degraded = false,
                    blocked = false,
                    requested = 0,
                    allocated = 0,
                    ratio = 1.0,
                }
                state.requested = state.requested + result.requested
                state.allocated = state.allocated + result.allocated
                state.degraded = state.degraded or result.degraded
                state.blocked = state.blocked or result.blocked
                state.available = state.available or result.available
                states[service] = state
            end
        end
    end
    for _, state in pairs(states) do
        state.ratio = state.requested > 0 and state.allocated / state.requested or 1.0
        state.available = state.requested <= 0 or state.allocated > 0
        state.blocked = state.requested > 0 and state.allocated <= 0
    end
    return states
end

function QosEngine.ClearTower(towerId)
    if type(towerId) ~= 'string' then return false end
    clearTowerResults(towerId)
    resultsByTower[towerId] = nil
    return true
end

function QosEngine.Clear(sessionId)
    if type(sessionId) ~= 'string' then return false end
    local result = resultsBySession[sessionId]
    if not result then return false end
    resultsBySession[sessionId] = nil
    local towerResult = resultsByTower[result.towerId]
    if towerResult and towerResult.allocations then
        towerResult.allocations[sessionId] = nil
        for index, allocation in ipairs(towerResult.ordered or {}) do
            if allocation.sessionId == sessionId then
                table.remove(towerResult.ordered, index)
                break
            end
        end
    end
    return true
end

function QosEngine.Reset()
    resultsBySession = {}
    resultsByTower = {}
end
