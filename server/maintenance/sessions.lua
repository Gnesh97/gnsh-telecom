MaintenanceSessions = MaintenanceSessions or {}

local sessionsById = {}
local sessionIdBySource = {}
local sequence = 0

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function normalizeSource(source)
    if TelecomSecurity and TelecomSecurity.NormalizeSource then
        return TelecomSecurity.NormalizeSource(source)
    end
    local number = tonumber(source)
    if not number or number ~= math.floor(number) or number <= 0 then return nil end
    return number
end

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and type(value) == 'number'
            and value == value and value ~= math.huge and value ~= -math.huge then
            return math.floor(value)
        end
    end
    return os.time() * 1000
end

local function cleanup(session, reason)
    if not reason or type(session) ~= 'table' then return end
    if session.kind == 'REPAIR'
        and MaintenanceRepairs
        and type(MaintenanceRepairs.OnSessionCleanup) == 'function' then
        local ok, errorCode = pcall(MaintenanceRepairs.OnSessionCleanup, session, reason)
        if not ok and Log and Log.error then
            Log.error('maintenance session cleanup failed', {
                sessionId = session.sessionId,
                error = errorCode,
            })
        end
    elseif session.kind == 'DIAGNOSTIC'
        and MaintenanceDiagnostics
        and type(MaintenanceDiagnostics.OnSessionCleanup) == 'function' then
        local ok, errorCode = pcall(MaintenanceDiagnostics.OnSessionCleanup, session, reason)
        if not ok and Log and Log.error then
            Log.error('diagnostic session cleanup failed', {
                sessionId = session.sessionId,
                error = errorCode,
            })
        end
    end
end

local function remove(sessionId, reason)
    local session = sessionsById[sessionId]
    if not session then return nil end
    sessionsById[sessionId] = nil
    if sessionIdBySource[session.source] == sessionId then
        sessionIdBySource[session.source] = nil
    end
    cleanup(session, reason)
    return session
end

local function nextSessionId(kind, startedAt)
    sequence = sequence + 1
    return ('%s-%d-%d'):format(kind:upper(), startedAt, sequence)
end

function MaintenanceSessions.Now()
    return now()
end

function MaintenanceSessions.HasActive(source)
    local number = normalizeSource(source)
    return number ~= nil and sessionIdBySource[number] ~= nil
end

function MaintenanceSessions.Create(kind, source, actorId, incidentId, failureId, towerId, durationMs)
    local normalizedKind = type(kind) == 'string' and kind:upper() or kind
    if not safeString(normalizedKind, 32) then return false, 'session_kind_required' end
    local number = normalizeSource(source)
    if not number then return false, 'player_source_required' end
    if not safeString(actorId, 128) then return false, 'stable_identity_required' end
    if not safeString(incidentId, 64) then return false, 'incident_id_required' end
    if not safeString(failureId, 128) then return false, 'failure_id_required' end
    if not safeString(towerId, 128) then return false, 'tower_id_required' end
    if type(durationMs) ~= 'number' or durationMs ~= durationMs
        or durationMs == math.huge or durationMs == -math.huge
        or durationMs < 0 then
        return false, 'invalid_session_duration'
    end
    if MaintenanceSessions.HasActive(number) then
        return false, 'maintenance_session_exists'
    end

    local startedAt = now()
    local sessionId = nextSessionId(normalizedKind, startedAt)
    while sessionsById[sessionId] do
        sessionId = nextSessionId(normalizedKind, startedAt)
    end

    local session = {
        sessionId = sessionId,
        kind = normalizedKind,
        source = number,
        actorId = actorId,
        incidentId = incidentId,
        failureId = failureId,
        towerId = towerId,
        startedAt = startedAt,
        earliestCompleteAt = startedAt + math.floor(durationMs),
        state = 'ACTIVE',
    }
    sessionsById[sessionId] = session
    sessionIdBySource[number] = sessionId
    return true, copy(session)
end

function MaintenanceSessions.Get(sessionId)
    if not safeString(sessionId, 96) then return nil end
    local session = sessionsById[sessionId]
    return session and copy(session) or nil
end

function MaintenanceSessions.GetForSource(source)
    local number = normalizeSource(source)
    local sessionId = number and sessionIdBySource[number]
    return sessionId and MaintenanceSessions.Get(sessionId) or nil
end

function MaintenanceSessions.Validate(sessionId, kind, source)
    if not safeString(sessionId, 96) then return false, 'session_id_required' end
    local session = sessionsById[sessionId]
    if not session then return false, 'session_not_found' end
    if session.state ~= 'ACTIVE' then return false, 'session_replayed' end
    if kind ~= nil and session.kind ~= kind then return false, 'session_kind_mismatch' end
    local number = normalizeSource(source)
    if not number or session.source ~= number then return false, 'session_owner_mismatch' end
    return true, copy(session)
end

function MaintenanceSessions.IsElapsed(session)
    if type(session) ~= 'table' or type(session.earliestCompleteAt) ~= 'number' then
        return false, 'invalid_session'
    end
    local current = now()
    if current < session.earliestCompleteAt then
        return false, 'session_too_early', session.earliestCompleteAt - current
    end
    return true
end

function MaintenanceSessions.Finish(sessionId, state)
    if not safeString(sessionId, 96) then return false, 'session_id_required' end
    if state ~= 'COMPLETED' and state ~= 'CANCELLED' then
        return false, 'invalid_session_state'
    end
    local session = remove(sessionId)
    if not session then return false, 'session_not_found' end
    local finished = copy(session)
    finished.state = state
    finished.completedAt = now()
    return true, finished
end

function MaintenanceSessions.ClearSource(source)
    local number = normalizeSource(source)
    if not number then return 0 end
    local sessionId = sessionIdBySource[number]
    if not sessionId then return 0 end
    remove(sessionId, 'player_dropped')
    return 1
end

function MaintenanceSessions.ClearAll()
    local sessionIds = {}
    for sessionId in pairs(sessionsById) do
        sessionIds[#sessionIds + 1] = sessionId
    end

    local count = 0
    for _, sessionId in ipairs(sessionIds) do
        if remove(sessionId, 'resource_stop') then count = count + 1 end
    end
    return count
end

function MaintenanceSessions.Count()
    local count = 0
    for _ in pairs(sessionsById) do count = count + 1 end
    return count
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        MaintenanceSessions.ClearSource(source)
    end)

    AddEventHandler('onResourceStop', function(resourceName)
        local currentResource = type(GetCurrentResourceName) == 'function'
            and GetCurrentResourceName() or nil
        if not currentResource or resourceName == currentResource then
            MaintenanceSessions.ClearAll()
        end
    end)
end
