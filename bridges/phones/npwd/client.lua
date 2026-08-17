local adapter = PhoneBridges.CreateResourceAdapter('npwd', {
    'npwd',
    'npwd_phone',
}, {
    supportLevel = PhoneBridgeContract.Levels.DISPLAY,
    support = {
        signalUI = true,
        callGate = false,
        smsGate = false,
        dataGate = false,
        callLifecycle = false,
        networkChangeHooks = false,
    },
})

local function unsupported()
    return false, {
        available = false,
        reason = 'provider_gate_unsupported',
        blockedBy = 'provider',
    }
end

function adapter:CanStartCall()
    return unsupported()
end

function adapter:CanSendSMS()
    return unsupported()
end

function adapter:CanUseData()
    return unsupported()
end

PhoneBridges.Register(adapter)
