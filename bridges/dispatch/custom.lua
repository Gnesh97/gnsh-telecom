local function customAdapter(configured)
    if type(configured) ~= 'table' then return nil, 'invalid_custom_dispatch' end
    if configured.Alert ~= nil and type(configured.Alert) ~= 'function' then
        return nil, 'custom_dispatch_alert_invalid'
    end
    if configured.CreateAlert ~= nil and type(configured.CreateAlert) ~= 'function' then
        return nil, 'custom_dispatch_create_alert_invalid'
    end
    if type(configured.Alert) ~= 'function' and type(configured.CreateAlert) ~= 'function' then
        return nil, 'custom_dispatch_requires_alert'
    end

    local adapter = {}
    for _, key in ipairs({
        'priority',
        'resources',
        'capabilities',
        'Detect',
        'Initialize',
        'Shutdown',
        'HealthCheck',
        'Alert',
        'CreateAlert',
    }) do
        if configured[key] ~= nil then adapter[key] = configured[key] end
    end
    adapter.name = type(configured.name) == 'string' and configured.name ~= ''
        and configured.name or 'custom-dispatch'
    return adapter
end

function DispatchBridge.CreateCustomAdapter(configured)
    return customAdapter(configured)
end

function DispatchBridge.SetCustomAdapter(configured)
    local adapter, errorMessage = customAdapter(configured)
    if not adapter then return false, errorMessage end
    return DispatchBridge.SetAdapter(adapter)
end

DispatchBridge.ConfigureCustom = DispatchBridge.SetCustomAdapter

if Config and type(Config.CustomDispatch) == 'table' then
    DispatchBridge.SetCustomAdapter(Config.CustomDispatch)
end
