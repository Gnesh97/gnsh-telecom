local function resourceStarted(name)
    if type(GetResourceState) ~= 'function' then return false end
    local ok, state = pcall(GetResourceState, name)
    return ok and state == 'started'
end

local function targetExports()
    local allExports = rawget(_G, 'exports')
    if allExports == nil then return nil end
    local ok, api = pcall(function() return allExports.ox_target end)
    return ok and api or nil
end

local function exportFunction(api, method)
    if api == nil then return nil end
    local ok, fn = pcall(function() return api[method] end)
    return ok and type(fn) == 'function' and fn or nil
end

local function hasRequiredExports()
    local api = targetExports()
    return exportFunction(api, 'addEntity') ~= nil
        and exportFunction(api, 'addModel') ~= nil
        and exportFunction(api, 'addBoxZone') ~= nil
end

local function copyZone(zone, id, options)
    local data = {}
    for key, value in pairs(zone or {}) do data[key] = value end
    data.name = data.name or id
    data.options = options or {}
    if data.size == nil and tonumber(data.radius) then
        local diameter = tonumber(data.radius) * 2.0
        data.size = { x = diameter, y = diameter, z = diameter }
    end
    return data
end

local function callExport(method, ...)
    local api = targetExports()
    local fn = exportFunction(api, method)
    if type(fn) ~= 'function' then return false, nil, 'ox_target_export_unavailable' end
    local args = { ... }
    local ok, first, second = pcall(function()
        return fn(api, table.unpack(args))
    end)
    if not ok then return false, nil, 'ox_target_export_error' end
    return true, first, second
end

local handles = {}

local adapter = {
    name = 'ox',
    category = 'target',
    priority = 300,
    resources = { 'ox_target' },
    capabilities = {
        'AddEntityInteraction',
        'AddModelInteraction',
        'AddZoneInteraction',
        'RemoveInteraction',
    },
}

function adapter:Detect()
    local configured = Config and Config.TargetBridge or 'auto'
    return (configured == 'auto' or configured == 'ox')
        and resourceStarted('ox_target')
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
    local ok, handle, errorMessage = callExport('addEntity', entity, options or {})
    if not ok then return false, errorMessage end
    handles[id] = { kind = 'entity', value = handle or entity }
    return true, handle or id
end

function adapter:AddModelInteraction(id, models, options)
    local ok, handle, errorMessage = callExport('addModel', models, options or {})
    if not ok then return false, errorMessage end
    handles[id] = { kind = 'model', value = handle or models }
    return true, handle or id
end

function adapter:AddZoneInteraction(id, zone, options)
    local ok, handle, errorMessage = callExport(
        'addBoxZone',
        copyZone(zone, id, options)
    )
    if not ok then return false, errorMessage end
    handles[id] = { kind = 'zone', value = handle or id }
    return true, handle or id
end

function adapter:RemoveInteraction(id, explicitHandle)
    local entry = handles[id]
    local kind = entry and entry.kind or 'zone'
    local value = explicitHandle or (entry and entry.value) or id
    local method = kind == 'entity' and 'removeEntity'
        or kind == 'model' and 'removeModel'
        or 'removeZone'
    local ok, _, errorMessage = callExport(method, value)
    if not ok and kind == 'entity' then
        ok, _, errorMessage = callExport('removeLocalEntity', value)
    end
    handles[id] = nil
    return ok, errorMessage
end

if TargetBridge and type(TargetBridge.Register) == 'function' then
    TargetBridge.Register(adapter)
end
