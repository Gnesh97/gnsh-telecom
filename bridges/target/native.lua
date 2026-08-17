local function shallowCopy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

local function optionList(options)
    if type(options) ~= 'table' then return {} end
    if options[1] ~= nil then return options end
    return { options }
end

local function finitePoint(value)
    return Utils and Utils.IsPoint and Utils.IsPoint(value)
end

local function distance(left, right)
    if not finitePoint(left) or not finitePoint(right) then return nil end
    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function playerCoords()
    if type(PlayerPedId) ~= 'function' or type(GetEntityCoords) ~= 'function' then return nil end
    local ped = PlayerPedId()
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return finitePoint(coords) and coords or nil
end

local function entityCoords(entity)
    if type(GetEntityCoords) ~= 'function' then return nil end
    if type(DoesEntityExist) == 'function' and not DoesEntityExist(entity) then return nil end
    local coords = GetEntityCoords(entity)
    return finitePoint(coords) and coords or nil
end

local function showPrompt(text)
    if type(BeginTextCommandDisplayHelp) ~= 'function'
        or type(AddTextComponentSubstringPlayerName) ~= 'function'
        or type(EndTextCommandDisplayHelp) ~= 'function' then return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text or 'Interact')
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function interactionOptions(record)
    return optionList(record.options)
end

local function canUse(option, context)
    if type(option.canInteract) ~= 'function' then return true end
    local ok, result = pcall(option.canInteract, context)
    return ok and result == true
end

local function invoke(record, option, context)
    if not canUse(option, context) then return false end
    local callback = option.onSelect or option.action
    if type(callback) ~= 'function' then return false end
    local ok = pcall(callback, context)
    return ok
end

local records = {}
local running = false

local function findZone(record, origin)
    local zone = record.subject or {}
    local coords = zone.coords or zone.center
    local maximum = tonumber(zone.distance or zone.radius or 2.5) or 2.5
    local current = distance(origin, coords)
    return current and current <= maximum, current, coords
end

local function findEntity(record, origin)
    local coords = entityCoords(record.subject)
    local options = interactionOptions(record)
    local maximum = tonumber(options.distance) or 2.5
    local current = distance(origin, coords)
    return current and current <= maximum, current, coords
end

local function findModel(record, origin)
    if type(GetGamePool) ~= 'function' or type(GetEntityModel) ~= 'function' then
        return false
    end
    local models = {}
    for _, model in ipairs(record.subject or {}) do models[model] = true end
    for _, entity in ipairs(GetGamePool('CObject') or {}) do
        if models[GetEntityModel(entity)] then
            local coords = entityCoords(entity)
            local current = distance(origin, coords)
            if current and current <= 2.5 then return true, current, coords, entity end
        end
    end
    return false
end

local function findNearby(origin)
    for _, record in pairs(records) do
        local nearby, current, coords, entity
        if record.kind == 'zone' then
            nearby, current, coords = findZone(record, origin)
        elseif record.kind == 'entity' then
            nearby, current, coords = findEntity(record, origin)
            entity = record.subject
        else
            nearby, current, coords, entity = findModel(record, origin)
        end
        if nearby then
            local options = interactionOptions(record)
            for _, option in ipairs(options) do
                if type(option) == 'table' then
                    return record, option, {
                        id = record.id,
                        entity = entity,
                        coords = coords,
                        distance = current,
                    }
                end
            end
        end
    end
    return nil
end

local function startLoop()
    if running or type(CreateThread) ~= 'function' or type(Wait) ~= 'function'
        or type(PlayerPedId) ~= 'function' then
        return
    end
    running = true
    CreateThread(function()
        while running do
            local origin = playerCoords()
            local record, option, context = origin and findNearby(origin) or nil
            if record and option then
                showPrompt(option.label or option.prompt or 'Interact')
                local key = tonumber(option.key or record.key) or 38
                if type(IsControlJustReleased) == 'function' and IsControlJustReleased(0, key) then
                    invoke(record, option, context)
                end
                Wait(0)
            else
                Wait(250)
            end
        end
    end)
end

local adapter = {
    name = 'native',
    category = 'target',
    priority = 0,
    capabilities = {
        'AddEntityInteraction',
        'AddModelInteraction',
        'AddZoneInteraction',
        'RemoveInteraction',
    },
}

function adapter:Detect()
    return true
end

function adapter:Initialize()
    records = {}
    startLoop()
    return true
end

function adapter:Shutdown()
    records = {}
    running = false
    return true
end

function adapter:HealthCheck()
    return 'ACTIVE'
end

function adapter:AddEntityInteraction(id, entity, options)
    records[id] = {
        id = id,
        kind = 'entity',
        subject = entity,
        options = shallowCopy(options or {}),
    }
    return true, id
end

function adapter:AddModelInteraction(id, models, options)
    records[id] = {
        id = id,
        kind = 'model',
        subject = shallowCopy(models or {}),
        options = shallowCopy(options or {}),
    }
    return true, id
end

function adapter:AddZoneInteraction(id, zone, options)
    records[id] = {
        id = id,
        kind = 'zone',
        subject = shallowCopy(zone or {}),
        options = shallowCopy(options or {}),
    }
    return true, id
end

function adapter:RemoveInteraction(id)
    records[id] = nil
    return true
end

function adapter:GetInteractions()
    local result = {}
    for id, record in pairs(records) do result[id] = shallowCopy(record) end
    return result
end

if TargetBridge and type(TargetBridge.Register) == 'function' then
    TargetBridge.Register(adapter)
end
