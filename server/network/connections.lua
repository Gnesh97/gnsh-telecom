Connections = Connections or {}

local statesBySource = {}
local previousBySource = {}

local meaningfulFields = {
    'towerId',
    'signal',
    'signalLevel',
    'technology',
    'congestion',
}

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number <= 0 or number % 1 ~= 0 then
        return nil, nil
    end
    number = math.floor(number)
    return tostring(number), number
end

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return 0
end

local function servicesChanged(left, right)
    local leftServices = left.services or {}
    local rightServices = right.services or {}

    for name, enabled in pairs(leftServices) do
        if rightServices[name] ~= enabled then return true end
    end
    for name, enabled in pairs(rightServices) do
        if leftServices[name] ~= enabled then return true end
    end
    return false
end

local function emptyState(source)
    return {
        source = source,
        towerId = nil,
        signal = 0,
        signalLevel = Signal.GetLevel(0),
        technology = nil,
        congestion = Enums.CongestionState.NORMAL,
        services = {},
        updatedAt = now(),
    }
end

local function normalizeState(source, state)
    if type(state) ~= 'table' then return nil, 'state must be a table' end

    local normalized = Utils.DeepCopy(state)
    if normalized.source ~= nil then
        local _, declaredSource = normalizeSource(normalized.source)
        if declaredSource ~= source then return nil, 'state source does not match key' end
    end
    if normalized.towerId ~= nil and type(normalized.towerId) ~= 'string' then
        return nil, 'towerId must be a string or nil'
    end
    if type(normalized.signal) ~= 'number' or normalized.signal ~= normalized.signal
        or normalized.signal < 0 or normalized.signal > 100 then
        return nil, 'signal must be between 0 and 100'
    end
    if normalized.services ~= nil and type(normalized.services) ~= 'table' then
        return nil, 'services must be a table'
    end

    normalized.source = source
    normalized.signalLevel = normalized.signalLevel or Signal.GetLevel(normalized.signal)
    normalized.congestion = normalized.congestion or Enums.CongestionState.NORMAL
    normalized.services = normalized.services or {}
    normalized.updatedAt = normalized.updatedAt or now()
    return normalized
end

local function resolveServerCoords(source)
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return nil
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return Utils.IsPoint(coords) and coords or nil
end

local function sendState(source, state)
    if type(TriggerClientEvent) == 'function' then
        TriggerClientEvent(Constants.Events.CONNECTION_STATE, source, state)
    end
end

function Connections.HasChanged(previous, current)
    if previous == nil or current == nil then return previous ~= current end
    for _, field in ipairs(meaningfulFields) do
        if previous[field] ~= current[field] then return true end
    end
    return servicesChanged(previous, current)
end

function Connections.Get(source)
    local key = normalizeSource(source)
    if not key or not statesBySource[key] then return nil end
    return Utils.DeepCopy(statesBySource[key])
end

function Connections.GetPrevious(source)
    local key = normalizeSource(source)
    if not key or not previousBySource[key] then return nil end
    return Utils.DeepCopy(previousBySource[key])
end

function Connections.GetAll()
    local states = {}
    for _, state in pairs(statesBySource) do
        states[#states + 1] = Utils.DeepCopy(state)
    end
    table.sort(states, function(left, right)
        return left.source < right.source
    end)
    return states
end

function Connections.Set(source, state)
    local key, number = normalizeSource(source)
    if not key then return false, 'invalid player source' end

    local normalized, errorMessage = normalizeState(number, state)
    if not normalized then return false, errorMessage end

    local previous = statesBySource[key]
    previousBySource[key] = previous and Utils.DeepCopy(previous) or nil
    statesBySource[key] = normalized
    return true, Connections.HasChanged(previous, normalized)
end

function Connections.Remove(source)
    local key = normalizeSource(source)
    if not key or not statesBySource[key] then return false end
    previousBySource[key] = Utils.DeepCopy(statesBySource[key])
    statesBySource[key] = nil
    return true
end

function Connections.Clear()
    statesBySource = {}
    previousBySource = {}
end

function Connections.Count()
    local count = 0
    for _ in pairs(statesBySource) do count = count + 1 end
    return count
end

function Connections.Reevaluate(source, coords)
    local key, number = normalizeSource(source)
    if not key then return nil, false, 'invalid player source' end

    if not Utils.IsPoint(coords) then
        coords = resolveServerCoords(number)
    end
    if not Utils.IsPoint(coords) then
        return Connections.Get(number), false, 'player position unavailable'
    end

    local candidates = Coverage.GetCandidates(coords)
    local ranked = Selection.Rank(candidates)
    local best = ranked[1]
    local state = emptyState(number)
    if best then
        state.towerId = best.towerId
        state.signal = best.signal
        state.signalLevel = Signal.GetLevel(best.signal)
        state.technology = best.tower.technologies[1]
    end

    local ok, changed = Connections.Set(number, state)
    if not ok then return nil, false, 'connection state rejected' end

    local updated = Connections.Get(number)
    if changed then
        sendState(number, updated)
        if Config.Debug.enabled and Log and Log.debug and best then
            Log.debug('connection selection', {
                source = number,
                towerId = best.towerId,
                score = best.score,
                signal = best.signal,
                loadPercent = best.scoreDetails.loadPercent,
                health = best.scoreDetails.health,
            })
        end
    end
    return updated, changed
end

local function handlePlayerJoining()
    local _, number = normalizeSource(source)
    if number then Connections.Set(number, emptyState(number)) end
end

local function handlePlayerDropped()
    Connections.Remove(source)
end

local function handlePositionUpdate(coords)
    Connections.Reevaluate(source, coords)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerJoining', handlePlayerJoining)
    AddEventHandler('playerDropped', handlePlayerDropped)
    AddEventHandler(Constants.Events.POSITION_UPDATE, handlePositionUpdate)
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then Connections.Clear() end
    end)
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.POSITION_UPDATE)
end
