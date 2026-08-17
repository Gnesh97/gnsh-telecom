ServiceSessions = ServiceSessions or {}

ServiceSessions.Classes = {
    VOICE = 'VOICE',
    SMS = 'SMS',
    DATA = 'DATA',
    GPS = 'GPS',
    EMERGENCY = 'EMERGENCY',
    BACKGROUND_DATA = 'BACKGROUND_DATA',
}

local policyByClass = {
    VOICE = 'voice',
    SMS = 'sms',
    DATA = 'data',
    GPS = 'gps',
    EMERGENCY = 'emergency',
    BACKGROUND_DATA = 'data',
}

local fallbackDemandByClass = {
    VOICE = 2.0,
    SMS = 0.5,
    DATA = 5.0,
    GPS = 0.75,
    EMERGENCY = 3.0,
    BACKGROUND_DATA = 1.0,
}

local reservedMetadataKeys = {
    id = true,
    sessionId = true,
    source = true,
    ownerSource = true,
    service = true,
    towerId = true,
    sectorId = true,
    carrierId = true,
    demand = true,
    createdAt = true,
    updatedAt = true,
    expiresAt = true,
}

local sessionsById = {}
local idsBySource = {}
local endedById = {}
local endedOrder = {}
local sequence = tonumber(ServiceSessions._nextSequence) or 0
local purging = false
local instanceId = ServiceSessions._instanceId
if type(instanceId) ~= 'string' or instanceId == '' then
    instanceId = tostring({}):gsub('[^%w]', '')
    ServiceSessions._instanceId = instanceId
end

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

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and isFiniteNumber(value) then return value end
    end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function enabled()
    return not (Config and Config.Features)
        or Config.Features.ServiceSessions ~= false
end

local function configNumber(name, fallback, minimum)
    local configured = Config and Config.ServiceSessions
        and tonumber(Config.ServiceSessions[name])
    if not isFiniteNumber(configured) then configured = fallback end
    if minimum and configured < minimum then configured = minimum end
    return math.floor(configured)
end

local function normalizeSource(source)
    local normalized = TelecomSecurity and TelecomSecurity.NormalizeSource
        and TelecomSecurity.NormalizeSource(source) or tonumber(source)
    if not isFiniteNumber(normalized) or normalized ~= math.floor(normalized)
        or normalized <= 0 then
        return nil
    end
    return normalized
end

local function normalizeService(service)
    if type(service) ~= 'string' or service == '' or #service > 32 then
        return nil
    end
    local normalized = service:upper()
    return policyByClass[normalized] and normalized or nil
end

local function normalizeMetadata(metadata)
    if metadata == nil then return {} end
    if type(metadata) ~= 'table' then return nil, 'metadata_invalid' end

    local maximumDepth = configNumber('maxMetadataDepth', 3, 1)
    local maximumFields = configNumber('maxMetadataFields', 16, 1)
    if TelecomSecurity and TelecomSecurity.IsSafeTable
        and not TelecomSecurity.IsSafeTable(metadata, maximumDepth, maximumFields) then
        return nil, 'metadata_invalid'
    end

    local normalized = copy(metadata)
    for key in pairs(normalized) do
        if reservedMetadataKeys[key] then return nil, 'metadata_reserved_field' end
    end
    return normalized
end

local function mergeMetadata(previous, patch)
    local merged = copy(previous or {})
    for key, value in pairs(patch or {}) do merged[key] = copy(value) end
    return merged
end

local function demandMultiplier(metadata)
    local multiplier = metadata and (metadata.demandMultiplier or metadata.intensity)
    if multiplier == nil then return 1.0 end
    if not isFiniteNumber(multiplier) or multiplier < 0.25 or multiplier > 4.0 then
        return nil
    end
    return multiplier
end

local function baseDemand(service)
    local configured = Config and Config.ServiceSessions
        and Config.ServiceSessions.demands
        and tonumber(Config.ServiceSessions.demands[service])
    if isFiniteNumber(configured) and configured >= 0 then return configured end
    return fallbackDemandByClass[service] or 1.0
end

local function sessionDemand(service, metadata)
    local multiplier = demandMultiplier(metadata)
    if not multiplier then return nil end
    return baseDemand(service) * multiplier
end

local function allow(source, operation, maximum)
    if not TelecomRateLimit or not TelecomRateLimit.Allow then return true end
    return TelecomRateLimit.Allow(
        source,
        'service_session_' .. operation,
        1000,
        maximum
    )
end

local function refreshTowers(affected)
    if type(affected) ~= 'table' or next(affected) == nil then return end
    local states = Connections and Connections.GetAll and Connections.GetAll() or {}
    if Capacity and Capacity.RecalculateTowers then
        pcall(Capacity.RecalculateTowers, affected, states)
    elseif Capacity and Capacity.RecalculateTower then
        for towerId in pairs(affected) do
            pcall(Capacity.RecalculateTower, towerId, states)
        end
    end
    if Connections and Connections.RefreshCapacity then
        pcall(Connections.RefreshCapacity, affected)
    end
end

local function rememberEnded(sessionId)
    endedById[sessionId] = true
    endedOrder[#endedOrder + 1] = sessionId
    local maximum = configNumber('maxEndedIds', 1024, 64)
    while #endedOrder > maximum do
        local oldest = table.remove(endedOrder, 1)
        endedById[oldest] = nil
    end
end

local function removeInternal(sessionId, reason)
    local session = sessionsById[sessionId]
    if not session then return nil, {} end

    sessionsById[sessionId] = nil
    local sourceSessions = idsBySource[session.source]
    if sourceSessions then
        sourceSessions[sessionId] = nil
        if next(sourceSessions) == nil then idsBySource[session.source] = nil end
    end

    if reason then session.endReason = reason end
    session.endedAt = now()
    rememberEnded(sessionId)
    return session, { [session.towerId] = true }
end

local function purgeExpired()
    if purging then return 0 end
    purging = true
    local timestamp = now()
    local affected = {}
    local removed = 0
    for sessionId, session in pairs(sessionsById) do
        if isFiniteNumber(session.expiresAt) and timestamp >= session.expiresAt then
            local expired, towers = removeInternal(sessionId, 'expired')
            if expired then
                removed = removed + 1
                for towerId in pairs(towers) do affected[towerId] = true end
            end
        end
    end
    purging = false
    refreshTowers(affected)
    return removed
end

local function validateOwner(session, ownerSource)
    if ownerSource == nil then
        ownerSource = rawget(_G, 'source')
        if ownerSource == nil then return false, 'owner_required' end
    end
    local normalized = normalizeSource(ownerSource)
    if not normalized then return false, 'invalid_owner' end
    if normalized ~= session.source then return false, 'session_owner_mismatch' end
    return true
end

local function activeCountForSource(source)
    local entries = idsBySource[source]
    if not entries then return 0 end
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

function ServiceSessions.Begin(source, service, metadata)
    if not enabled() then return false, 'service_sessions_disabled' end
    local normalizedSource = normalizeSource(source)
    if not normalizedSource then return false, 'invalid_source' end
    local normalizedService = normalizeService(service)
    if not normalizedService then return false, 'unknown_service_class' end

    purgeExpired()
    if not allow(
        normalizedSource,
        'begin',
        configNumber('maxBeginsPerSecond', 8, 1)
    ) then
        return false, 'rate_limited'
    end

    local activeTotal = 0
    for _ in pairs(sessionsById) do activeTotal = activeTotal + 1 end
    if activeTotal >= configNumber('maxActive', 256, 1) then
        return false, 'session_capacity_reached'
    end
    if activeCountForSource(normalizedSource)
        >= configNumber('maxActivePerSource', 4, 1) then
        return false, 'source_session_limit_reached'
    end

    local normalizedMetadata, metadataError = normalizeMetadata(metadata)
    if not normalizedMetadata then return false, metadataError end
    local demand = sessionDemand(normalizedService, normalizedMetadata)
    if not demand then return false, 'metadata_invalid' end

    local connection = Connections and Connections.Get and Connections.Get(normalizedSource)
    if type(connection) ~= 'table' then return false, 'player_not_connected' end
    if type(connection.towerId) ~= 'string' or connection.towerId == '' then
        return false, 'no_serving_tower'
    end

    local policyService = policyByClass[normalizedService]
    if Services and Services.CanUse then
        local available, state = Services.CanUse(normalizedSource, policyService)
        if not available then
            return false, state and state.reason or 'service_unavailable'
        end
    end

    sequence = sequence + 1
    local sessionId = ('service:%s:%08d'):format(instanceId, sequence)
    ServiceSessions._nextSequence = sequence
    local timestamp = now()
    local duration = configNumber('maxDurationMs', 1800000, 1000)
    local session = {
        id = sessionId,
        sessionId = sessionId,
        source = normalizedSource,
        ownerSource = normalizedSource,
        service = normalizedService,
        policyService = policyService,
        towerId = connection.towerId,
        sectorId = connection.sectorId,
        carrierId = connection.carrierId,
        technology = connection.technology,
        demand = demand,
        metadata = normalizedMetadata,
        createdAt = timestamp,
        updatedAt = timestamp,
        expiresAt = timestamp + duration,
    }

    sessionsById[sessionId] = session
    idsBySource[normalizedSource] = idsBySource[normalizedSource] or {}
    idsBySource[normalizedSource][sessionId] = true
    refreshTowers({ [connection.towerId] = true })
    return true, copy(session)
end

function ServiceSessions.Get(sessionId)
    if type(sessionId) ~= 'string' then return nil end
    purgeExpired()
    local session = sessionsById[sessionId]
    return session and copy(session) or nil
end

function ServiceSessions.GetAll(limit)
    purgeExpired()
    local sessions = {}
    for _, session in pairs(sessionsById) do sessions[#sessions + 1] = copy(session) end
    table.sort(sessions, function(left, right) return left.id < right.id end)
    local maximum = tonumber(limit) or configNumber('maxActive', 256, 1)
    if not isFiniteNumber(maximum) or maximum < 1 then maximum = 1 end
    maximum = math.floor(maximum)
    while #sessions > maximum do sessions[#sessions] = nil end
    return sessions
end

function ServiceSessions.GetForSource(source)
    purgeExpired()
    local normalizedSource = normalizeSource(source)
    if not normalizedSource then return {} end
    local result = {}
    for sessionId in pairs(idsBySource[normalizedSource] or {}) do
        local session = sessionsById[sessionId]
        if session then result[#result + 1] = copy(session) end
    end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

function ServiceSessions.GetDemand(towerId, sectorId)
    purgeExpired()
    if type(towerId) ~= 'string' then return { count = 0, demand = 0, byService = {} } end
    local result = { count = 0, demand = 0, byService = {} }
    for _, session in pairs(sessionsById) do
        if session.towerId == towerId
            and (sectorId == nil or session.sectorId == sectorId) then
            result.count = result.count + 1
            result.demand = result.demand + session.demand
            result.byService[session.service] = (result.byService[session.service] or 0)
                + session.demand
        end
    end
    return result
end

ServiceSessions.GetTowerDemand = ServiceSessions.GetDemand

function ServiceSessions.Update(sessionId, metadata, ownerSource)
    if not enabled() then return false, 'service_sessions_disabled' end
    if type(sessionId) ~= 'string' or sessionId == '' then return false, 'session_id_required' end
    purgeExpired()
    if endedById[sessionId] then return false, 'session_replayed' end
    local session = sessionsById[sessionId]
    if not session then return false, 'session_not_found' end

    local ownerOk, ownerError = validateOwner(session, ownerSource)
    if not ownerOk then return false, ownerError end
    if not allow(
        session.source,
        'update',
        configNumber('maxUpdatesPerSecond', 20, 1)
    ) then
        return false, 'rate_limited'
    end

    local normalizedMetadata, metadataError = normalizeMetadata(metadata)
    if not normalizedMetadata then return false, metadataError end
    local merged = mergeMetadata(session.metadata, normalizedMetadata)
    local demand = sessionDemand(session.service, merged)
    if not demand then return false, 'metadata_invalid' end

    local demandChanged = demand ~= session.demand
    session.metadata = merged
    session.demand = demand
    session.updatedAt = now()
    if demandChanged then refreshTowers({ [session.towerId] = true }) end
    return true, copy(session)
end

function ServiceSessions.End(sessionId, ownerSource)
    if type(sessionId) ~= 'string' or sessionId == '' then return false, 'session_id_required' end
    purgeExpired()
    if endedById[sessionId] then return false, 'session_replayed' end
    local session = sessionsById[sessionId]
    if not session then return false, 'session_not_found' end

    local ownerOk, ownerError = validateOwner(session, ownerSource)
    if not ownerOk then return false, ownerError end
    if not allow(
        session.source,
        'end',
        configNumber('maxEndsPerSecond', 20, 1)
    ) then
        return false, 'rate_limited'
    end

    local ended, affected = removeInternal(sessionId, 'ended')
    refreshTowers(affected)
    return true, copy(ended)
end

function ServiceSessions.ClearSource(source)
    local normalizedSource = normalizeSource(source)
    if not normalizedSource then return 0 end
    local affected = {}
    local removed = 0
    local sourceSessions = copy(idsBySource[normalizedSource] or {})
    for sessionId in pairs(sourceSessions) do
        local session, towers = removeInternal(sessionId, 'disconnect')
        if session then
            removed = removed + 1
            for towerId in pairs(towers) do affected[towerId] = true end
        end
    end
    refreshTowers(affected)
    return removed
end

function ServiceSessions.Count()
    purgeExpired()
    local count = 0
    for _ in pairs(sessionsById) do count = count + 1 end
    return count
end

function ServiceSessions.Reset()
    sessionsById = {}
    idsBySource = {}
    endedById = {}
    endedOrder = {}
    purging = false
end

ServiceSessions.BeginServiceSession = ServiceSessions.Begin
ServiceSessions.UpdateServiceSession = ServiceSessions.Update
ServiceSessions.EndServiceSession = ServiceSessions.End

function BeginServiceSession(source, service, metadata)
    return ServiceSessions.Begin(source, service, metadata)
end

function UpdateServiceSession(sessionId, metadata, ownerSource)
    return ServiceSessions.Update(sessionId, metadata, ownerSource)
end

function EndServiceSession(sessionId, ownerSource)
    return ServiceSessions.End(sessionId, ownerSource)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        ServiceSessions.ClearSource(source)
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        if type(GetCurrentResourceName) == 'function'
            and resourceName == GetCurrentResourceName() then
            ServiceSessions.Reset()
        end
    end)
end
