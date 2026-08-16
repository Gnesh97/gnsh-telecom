BridgeLifecycle = BridgeLifecycle or {}

local function resourceStarted(resourceName)
    if type(resourceName) ~= 'string' or resourceName == ''
        or type(GetResourceState) ~= 'function' then
        return false
    end
    local ok, state = pcall(GetResourceState, resourceName)
    return ok and state == 'started'
end

function BridgeLifecycle.ResourcesAvailable(provider)
    local resources = provider and provider.resources or {}
    if #resources == 0 then return true end

    local mode = provider.resourceMode == 'all' and 'all' or 'any'
    if mode == 'all' then
        for _, resourceName in ipairs(resources) do
            if not resourceStarted(resourceName) then return false end
        end
        return true
    end

    for _, resourceName in ipairs(resources) do
        if resourceStarted(resourceName) then return true end
    end
    return false
end

function BridgeLifecycle.Call(provider, method, ...)
    local fn = provider and provider[method]
    if type(fn) ~= 'function' then return true, nil end

    local args = { ... }
    local ok, first, second, third = pcall(function()
        return fn(provider, table.unpack(args))
    end)
    if not ok then return false, nil, tostring(first) end
    return true, first, second, third
end

function BridgeLifecycle.Detect(provider)
    if not BridgeLifecycle.ResourcesAvailable(provider) then
        return false, 'resources_unavailable'
    end

    local ok, detected, errorMessage = BridgeLifecycle.Call(provider, 'Detect')
    if not ok then return false, errorMessage or 'provider_detection_failed' end
    return detected == true, detected == true and nil or 'provider_not_detected'
end

function BridgeLifecycle.Initialize(provider)
    if not BridgeLifecycle.ResourcesAvailable(provider) then
        return false, 'resources_unavailable'
    end

    local ok, initialized, errorMessage = BridgeLifecycle.Call(provider, 'Initialize')
    if not ok then return false, errorMessage or 'provider_initialization_failed' end
    if initialized == false then
        return false, errorMessage or 'provider_rejected_initialization'
    end
    return true
end

function BridgeLifecycle.Shutdown(provider)
    local ok, stopped, errorMessage = BridgeLifecycle.Call(provider, 'Shutdown')
    if not ok then return false, errorMessage or 'provider_shutdown_failed' end
    if stopped == false then
        return false, errorMessage or 'provider_rejected_shutdown'
    end
    return true
end

function BridgeLifecycle.HealthCheck(provider)
    local ok, health, errorMessage = BridgeLifecycle.Call(provider, 'HealthCheck')
    if not ok then return false, nil, errorMessage or 'provider_health_check_failed' end
    return true, health
end
