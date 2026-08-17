PhoneBridgeManager = PhoneBridgeManager or {}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function unavailable(reason, blockedBy, extra)
    local state = {
        available = false,
        reason = reason or 'connection_unavailable',
        blockedBy = blockedBy or 'connection',
    }
    for key, value in pairs(extra or {}) do state[key] = value end
    return state
end

function PhoneBridgeManager.ResourceStarted(resourceName)
    if type(resourceName) ~= 'string' or resourceName == ''
        or type(GetResourceState) ~= 'function' then
        return false
    end
    local ok, state = pcall(GetResourceState, resourceName)
    return ok and state == 'started'
end

function PhoneBridgeManager.FirstStarted(resources)
    for _, resourceName in ipairs(resources or {}) do
        if PhoneBridgeManager.ResourceStarted(resourceName) then
            return resourceName
        end
    end
    return nil
end

local function resolveExport(resourceName, exportName)
    local exportRegistry = rawget(_G, 'exports')
    if type(exportRegistry) ~= 'table' and type(exportRegistry) ~= 'userdata' then
        return nil
    end

    local ok, resourceExports = pcall(function()
        return exportRegistry[resourceName]
    end)
    if not ok or resourceExports == nil then return nil end

    local resolved, exportFunction = pcall(function()
        return resourceExports[exportName]
    end)
    if not resolved or type(exportFunction) ~= 'function' then return nil end
    return resourceExports, exportFunction
end

function PhoneBridgeManager.HasExport(resourceName, exportName)
    return resolveExport(resourceName, exportName) ~= nil
end

function PhoneBridgeManager.ExportCall(resourceName, exportName, ...)
    local resourceExports, exportFunction = resolveExport(resourceName, exportName)
    if not resourceExports then return false, nil, 'export_unavailable' end

    local arguments = { ... }
    local results = { pcall(function()
        return exportFunction(resourceExports, table.unpack(arguments))
    end) }
    local ok = table.remove(results, 1)
    if not ok then return false, nil, 'export_error', tostring(results[1]) end
    return true, table.unpack(results)
end

function PhoneBridgeManager.ServiceGate(source, service)
    local api = rawget(_G, 'TelecomAPI')
    if api and type(api.CanUseService) == 'function' then
        local ok, available, state = pcall(api.CanUseService, source, service)
        if ok then
            return available == true, copy(state or unavailable())
        end
        return false, unavailable('provider_api_error', 'provider')
    end

    local clientState = rawget(_G, 'ClientState')
    if clientState and type(clientState.Get) == 'function' then
        local state = clientState.Get()
        local serviceState = state and state.services and state.services[service]
        if type(serviceState) == 'table' then
            return serviceState.available == true, copy(serviceState)
        end
        if type(serviceState) == 'boolean' then
            return serviceState, {
                available = serviceState,
                reason = serviceState and 'available' or 'service_unavailable',
                blockedBy = serviceState and nil or 'connection',
            }
        end
    end

    return false, unavailable('connection_unavailable', 'connection')
end

function PhoneBridgeManager.OptionalBooleanExportGate(
    resourceName,
    exportName,
    blockedReason,
    ...
)
    local ok, value, errorCode = PhoneBridgeManager.ExportCall(
        resourceName,
        exportName,
        ...
    )
    if not ok and errorCode == 'export_unavailable' then
        return true, nil
    end
    if not ok then
        return false, unavailable('provider_export_error', 'provider', {
            export = exportName,
        })
    end
    if value ~= true then
        return false, unavailable(blockedReason or 'provider_rejected', 'provider', {
            export = exportName,
        })
    end
    return true, nil
end
