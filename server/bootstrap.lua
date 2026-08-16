local started = false

local function stopAfterInvalidConfig()
    if type(StopResource) == 'function' and type(GetCurrentResourceName) == 'function' then
        StopResource(GetCurrentResourceName())
    end
end

local function validateConfig()
    local ok, errors, warnings = Config.Validate()
    if not ok then
        Log.error(Locale.Translate(Config.Locale, 'startup.invalidConfig'))
        for _, message in ipairs(errors) do Log.error(message) end
        Log.event(Constants.LogEvent.CONFIG_INVALID, { errorCount = #errors })
        stopAfterInvalidConfig()
        return false
    end

    for _, message in ipairs(warnings or {}) do Log.warn(message) end
    return true
end

local function boot()
    if started then return true end
    if not validateConfig() then return false end

    local registryOk, registryErrors, registryWarnings = TowerRegistry.Init()
    if not registryOk then
        Log.error('tower registry validation failed')
        for _, message in ipairs(registryErrors or {}) do Log.error(message) end
        stopAfterInvalidConfig()
        return false
    end
    for _, message in ipairs(registryWarnings or {}) do Log.warn(message) end

    local spatialOk, spatialErrors, spatialWarnings, spatialStats = SpatialIndex.Rebuild()
    if not spatialOk then
        Log.error('spatial index build failed')
        for _, message in ipairs(spatialErrors or {}) do Log.error(message) end
        stopAfterInvalidConfig()
        return false
    end
    for _, message in ipairs(spatialWarnings or {}) do Log.warn(message) end
    Log.info('spatial index built', spatialStats)

    if BackhaulGraph and BackhaulGraph.Initialize then
        local backhaulOk, backhaulStats = BackhaulGraph.Initialize()
        if not backhaulOk then Log.warn('backhaul graph initialization degraded', backhaulStats) end
        if BackhaulRouting and BackhaulRouting.Initialize then BackhaulRouting.Initialize() end
    end

    if TelecomStatistics and TelecomStatistics.Initialize then TelecomStatistics.Initialize() end

    if TelecomPersistence and TelecomPersistence.Initialize then
        local persistenceOk, persistenceStatus = TelecomPersistence.Initialize()
        if not persistenceOk or (persistenceStatus and persistenceStatus.mode == 'degraded') then
            Log.warn('persistence initialization degraded', persistenceStatus)
        end
    end

    started = true
    Log.info(Locale.Translate(Config.Locale, 'startup.ready'), {
        version = Config.Version,
        apiVersion = Constants.ApiVersion,
    })
    Log.event(Constants.LogEvent.CONFIG_OK)
    Log.event(Constants.LogEvent.RESOURCE_STARTED)
    return true
end

local function shutdown()
    if not started then return end
    if TelecomPersistence and TelecomPersistence.Shutdown then
        TelecomPersistence.Shutdown()
    elseif TelecomPersistence and TelecomPersistence.Flush then
        TelecomPersistence.Flush()
    end
    if TelecomStatistics and TelecomStatistics.Shutdown then TelecomStatistics.Shutdown() end
    if Jammers and Jammers.Reset then Jammers.Reset() end
    started = false
    Log.event(Constants.LogEvent.RESOURCE_STOPPED)
    Log.info(Locale.Translate(Config.Locale, 'startup.stopped'))
end

Bootstrap = {
    Boot = boot,
    Shutdown = shutdown,
    IsStarted = function() return started end,
}

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == GetCurrentResourceName() then boot() end
    end)

    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then shutdown() end
    end)
end

if type(GetCurrentResourceName) == 'function'
    and type(GetResourceState) == 'function'
    and GetResourceState(GetCurrentResourceName()) == 'started' then
    boot()
end
