local function resourceStarted(name)
    if type(GetResourceState) ~= 'function' then return false end
    local ok, state = pcall(GetResourceState, name)
    return ok and state == 'started'
end

local function targetExports()
    local allExports = rawget(_G, 'exports')
    if allExports == nil then return nil end
    local ok, api = pcall(function() return allExports['qb-target'] end)
    return ok and api or nil
end

local function exportFunction(api, method)
    if api == nil then return nil end
    local ok, fn = pcall(function() return api[method] end)
    return ok and type(fn) == 'function' and fn or nil
end

local function hasRequiredExports()
    local api = targetExports()
    return exportFunction(api, 'AddTargetEntity') ~= nil
        and exportFunction(api, 'AddTargetModel') ~= nil
        and exportFunction(api, 'AddBoxZone') ~= nil
end

local function optionList(options)
    if type(options) ~= 'table' then return {} end
    if options[1] ~= nil then return options end
    return { options }
end

local function adaptOptions(options)
    local result = {}
    for _, option in ipairs(optionList(options)) do
        if type(option) == 'table' then
            local adapted = {}
            for key, value in pairs(option) do
                if key ~= 'onSelect' then adapted[key] = value end
            end
            adapted.type = adapted.type or 'client'
            adapted.action = function(entity)
                if type(option.onSelect) ~= 'function' then return false end
                return option.onSelect({ entity = entity, option = option.name })
            end
            result[#result + 1] = adapted
        end
    end
    return result
end

local function zoneOptions(zone)
    local result = {
        name = zone.name,
        heading = zone.heading or 0.0,
    }
    if zone.minZ ~= nil then result.minZ = zone.minZ end
    if zone.maxZ ~= nil then result.maxZ = zone.maxZ end
    return result
end

local function callExport(method, ...)
    local api = targetExports()
    local fn = exportFunction(api, method)
    if type(fn) ~= 'function' then return false, nil, 'qb_target_export_unavailable' end
    local args = { ... }
    local ok, first, second = pcall(function()
        return fn(api, table.unpack(args))
    end)
    if not ok then return false, nil, 'qb_target_export_error' end
    return true, first, second
end

local handles = {}

local adapter = {
    name = 'qb',
    category = 'target',
    priority = 200,
    resources = { 'qb-target' },
    capabilities = {
        'AddEntityInteraction',
        'AddModelInteraction',
        'AddZoneInteraction',
        'RemoveInteraction',
    },
}

function adapter:Detect()
    local configured = Config and Config.TargetBridge or 'auto'
    return (configured == 'auto' or configured == 'qb')
        and resourceStarted('qb-target')
        and hasRequiredExports()
end

function adapter:Initialize()
    handles = {}
    return true
end

function adapter:Shutdown()
    handles = {}
    return true
end

function adapter:HealthCheck()
    return hasRequiredExports() and 'ACTIVE' or 'UNAVAILABLE'
end

function adapter:AddEntityInteraction(id, entity, options)
    local params = {
        options = adaptOptions(options),
        distance = tonumber(options and options.distance) or 2.5,
    }
    local ok, result, errorMessage = callExport('AddTargetEntity', entity, params)
    if not ok then return false, errorMessage end
    handles[id] = { kind = 'entity', value = entity }
    return result ~= false, id
end

function adapter:AddModelInteraction(id, models, options)
    local params = {
        options = adaptOptions(options),
        distance = tonumber(options and options.distance) or 2.5,
    }
    local ok, result, errorMessage = callExport('AddTargetModel', models, params)
    if not ok then return false, errorMessage end
    handles[id] = { kind = 'model', value = models }
    return result ~= false, id
end

function adapter:AddZoneInteraction(id, zone, options)
    zone = zone or {}
    local length = tonumber(zone.length) or (tonumber(zone.radius) or 1.5) * 2.0
    local width = tonumber(zone.width) or length
    local targetOptions = {
        options = adaptOptions(options),
        distance = tonumber(zone.distance) or 2.5,
    }
    local ok, result, errorMessage = callExport(
        'AddBoxZone',
        zone.name or id,
        zone.coords,
        length,
        width,
        zoneOptions({
            name = zone.name or id,
            heading = zone.heading,
            minZ = zone.minZ,
            maxZ = zone.maxZ,
        }),
        targetOptions
    )
    if not ok then return false, errorMessage end
    handles[id] = { kind = 'zone', value = zone.name or id }
    return result ~= false, id
end

function adapter:RemoveInteraction(id)
    local entry = handles[id]
    if not entry then return true end
    local method = entry.kind == 'entity' and 'RemoveTargetEntity'
        or entry.kind == 'model' and 'RemoveTargetModel'
        or 'RemoveZone'
    local ok, result, errorMessage = callExport(method, entry.value)
    handles[id] = nil
    if not ok then return false, errorMessage end
    return result ~= false
end

if TargetBridge and type(TargetBridge.Register) == 'function' then
    TargetBridge.Register(adapter)
end
