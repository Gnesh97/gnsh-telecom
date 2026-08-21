local adapter = PhoneBridges.CreateResourceAdapter('qbphone', {
    'qb-phone',
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
    return PhoneBridgeManager.ServiceGate(source, 'voice')
end

function adapter:CanSendSMS(source)
    return PhoneBridgeManager.ServiceGate(source, 'sms')
end

function adapter:CanUseData(source)
    return PhoneBridgeManager.ServiceGate(source, 'data')
end

PhoneBridges.Register(adapter)
