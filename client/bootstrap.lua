local started = false

local function boot()
    if started then return end
    started = true
    if PhoneBridges and type(PhoneBridges.Initialize) == 'function' then
        PhoneBridges.Initialize()
    end
    print(('[gnsh-telecom] %s'):format(Locale.Translate(Config.Locale, 'startup.ready')))
end

local function shutdown()
    if not started then return end
    started = false
    print(('[gnsh-telecom] %s'):format(Locale.Translate(Config.Locale, 'startup.stopped')))
end

ClientBootstrap = {
    Boot = boot,
    Shutdown = shutdown,
    IsStarted = function() return started end,
}

if type(AddEventHandler) == 'function' then
    AddEventHandler('onClientResourceStart', function(resourceName)
        if resourceName == GetCurrentResourceName() then boot() end
    end)

    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then shutdown() end
    end)
end

if type(GetCurrentResourceName) == 'function' then boot() end
