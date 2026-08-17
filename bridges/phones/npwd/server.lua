local function resourceFor(adapter)
    return PhoneBridgeManager.FirstStarted(adapter.resourceNames)
end

local adapter = PhoneBridges.CreateResourceAdapter('npwd', {
    'npwd',
    'npwd_phone',
}, {
    supportLevel = PhoneBridgeContract.Levels.FUNCTIONAL,
    support = {
        signalUI = true,
        callGate = true,
        smsGate = true,
        dataGate = true,
        callLifecycle = false,
        networkChangeHooks = false,
    },
})

function adapter:CanStartCall(source)
    local available, state = PhoneBridgeManager.ServiceGate(source, 'voice')
    if not available then return false, state end

    local resourceName = resourceFor(self)
    local exportOk, busy, errorCode = PhoneBridgeManager.ExportCall(
        resourceName,
        'isPlayerBusy',
        source
    )
    if exportOk and busy == true then
        return false, {
            available = false,
            reason = 'phone_busy',
            blockedBy = 'provider',
        }
    end
    if not exportOk and errorCode ~= 'export_unavailable' then
        return false, {
            available = false,
            reason = 'provider_export_error',
            blockedBy = 'provider',
            export = 'isPlayerBusy',
        }
    end
    return true, state
end

function adapter:CanSendSMS(source)
    return PhoneBridgeManager.ServiceGate(source, 'sms')
end

function adapter:CanUseData(source)
    return PhoneBridgeManager.ServiceGate(source, 'data')
end

PhoneBridges.Register(adapter)
