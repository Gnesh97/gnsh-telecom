Jammers = Jammers or {}

local recordsById = {}
local orderedIds = {}
local sequence = 0

local function enabled()
    return Config and Config.Features and Config.Features.Jammers == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function nextId()
    repeat
        sequence = sequence + 1
    until not recordsById[('JAM-%06d'):format(sequence)]
    return ('JAM-%06d'):format(sequence)
end

local function hasTechnology(record, technologies)
    if type(record.technologies) ~= 'table' or type(technologies) ~= 'table' then return true end
    for _, left in ipairs(record.technologies) do
        for _, right in ipairs(technologies) do
            if left == right then return true end
        end
    end
    return false
end

local function expired(record, timestamp)
    return record.expiresAt ~= nil and timestamp >= record.expiresAt
end

local function normalizeTechnologies(requested, configured)
    local allowed = {}
    for _, technology in ipairs(configured or {}) do allowed[technology] = true end
    if type(requested) ~= 'table' then return copy(configured or {}) end
    local result = {}
    for _, technology in ipairs(requested) do
        if type(technology) ~= 'string' or not allowed[technology] then
            return nil, 'invalid_jammer_technology'
        end
        result[#result + 1] = technology
    end
    if #result == 0 then return copy(configured or {}) end
    return result
end

function Jammers.Cleanup(timestamp)
    timestamp = timestamp or now()
    local removed = 0
    for index = #orderedIds, 1, -1 do
        local id = orderedIds[index]
        if not recordsById[id] or expired(recordsById[id], timestamp) then
            recordsById[id] = nil
            table.remove(orderedIds, index)
            removed = removed + 1
        end
    end
    return removed
end

function Jammers.Create(owner, coords, options)
    if not enabled() then return false, 'jammers_disabled' end
    if not Utils.IsPoint(coords) then return false, 'invalid_jammer_position' end
    Jammers.Cleanup()
    local configured = Config.Jammers or {}
    if #orderedIds >= (tonumber(configured.maxActive) or 10) then
        return false, 'jammer_limit_reached'
    end

    options = type(options) == 'table' and options or {}
    local radius = tonumber(options.radius) or configured.defaultRadius or 250
    local strength = tonumber(options.strength) or configured.defaultStrength or 0.75
    local duration = tonumber(options.durationMs) or configured.defaultDurationMs or 600000
    if radius <= 0 or radius > 5000 then return false, 'invalid_jammer_radius' end
    if strength <= 0 or strength > 1 then return false, 'invalid_jammer_strength' end
    if duration <= 0 or duration > 86400000 then return false, 'invalid_jammer_duration' end
    local technologies, technologyError = normalizeTechnologies(
        options.technologies,
        configured.technologies
    )
    if not technologies then return false, technologyError end

    local source = tonumber(owner)
    if not source or source <= 0 then return false, 'owner_required' end
    local allowed, errorCode = TelecomRateLimit.Allow(
        source,
        'jammer',
        tonumber(configured.cooldownMs) or 30000,
        1
    )
    if not allowed then return false, errorCode end

    local record = {
        id = nextId(),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        radius = radius,
        strength = strength,
        technologies = technologies,
        owner = source,
        battery = 100,
        createdAt = now(),
        expiresAt = now() + duration,
    }
    recordsById[record.id] = record
    orderedIds[#orderedIds + 1] = record.id
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source, 'jammer_created', { jammerId = record.id })
    end
    if TelecomStatistics and TelecomStatistics.RecordJammer then TelecomStatistics.RecordJammer() end
    return true, copy(record)
end

function Jammers.Remove(id, source, force)
    Jammers.Cleanup()
    local record = recordsById[id]
    if not record then return false, 'jammer_not_found' end
    local owner = tonumber(source)
    if not force and owner ~= record.owner
        and not (TelecomPermissions and TelecomPermissions.IsAdmin and TelecomPermissions.IsAdmin(source)) then
        return false, 'not_authorized'
    end
    recordsById[id] = nil
    for index, value in ipairs(orderedIds) do
        if value == id then table.remove(orderedIds, index) break end
    end
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source or 0, 'jammer_removed', { jammerId = id })
    end
    return true, copy(record)
end

function Jammers.GetAll()
    Jammers.Cleanup()
    local result = {}
    for _, id in ipairs(orderedIds) do result[#result + 1] = copy(recordsById[id]) end
    return result
end

function Jammers.GetEffect(coords, technologies)
    if not enabled() or not Utils.IsPoint(coords) then
        return { multiplier = 1.0, active = false, jammers = {} }
    end
    Jammers.Cleanup()
    local multiplier = 1.0
    local active = {}
    for _, id in ipairs(orderedIds) do
        local record = recordsById[id]
        if record and hasTechnology(record, technologies) then
            local distance = Signal.CalculateDistance(coords, record.coords)
            if distance and distance <= record.radius then
                multiplier = multiplier * (1 - record.strength)
                active[#active + 1] = id
            end
        end
    end
    return { multiplier = Utils.Clamp(multiplier, 0, 1), active = #active > 0, jammers = active }
end

function Jammers.Reset()
    recordsById = {}
    orderedIds = {}
    sequence = 0
end

if type(RegisterNetEvent) == 'function' then RegisterNetEvent(Constants.Events.JAMMER_REQUEST) end
if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.JAMMER_REQUEST, function(payload)
        local sourceId = source
        if type(payload) ~= 'table' then return end
        local ok, result
        if payload.action == 'create' then
            local coords = payload.coords
            local maxDistance = Config.Jammers.maxPlacementDistance or 6.0
            local near, nearError = TelecomSecurity.IsNearPlayer(sourceId, coords, maxDistance)
            if not near then ok, result = false, nearError
            else ok, result = Jammers.Create(sourceId, coords, payload) end
        elseif payload.action == 'remove' then
            ok, result = Jammers.Remove(payload.id, sourceId, false)
        else
            ok, result = false, 'unknown_jammer_action'
        end
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent(Constants.Events.JAMMER_STATE, sourceId, {
                ok = ok,
                result = ok and copy(result) or nil,
                error = ok and nil or result,
            })
        end
    end)
    AddEventHandler('playerDropped', function()
        for _, record in ipairs(Jammers.GetAll()) do
            if record.owner == tonumber(source) then Jammers.Remove(record.id, source, true) end
        end
    end)
end

if enabled() and type(CreateThread) == 'function' and type(Wait) == 'function' then
    CreateThread(function()
        while true do
            Wait(1000)
            Jammers.Cleanup()
        end
    end)
end
