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
        networkChangeHooks = true,
    },
})

function adapter:Initialize()
    self.api = PhoneBridges.GetTelecomAPI()
    self.initialized = true

    if ClientState and type(ClientState.Get) == 'function' then
        local state = ClientState.Get()
        if state then self:OnNetworkState(state) end
    end
    return true
end

function adapter:Shutdown()
    self.initialized = false
    return true
end

function adapter:CanStartCall()
    return PhoneBridgeManager.ServiceGate(nil, 'voice')
end

function adapter:CanSendSMS()
    return PhoneBridgeManager.ServiceGate(nil, 'sms')
end

function adapter:CanUseData()
    return PhoneBridgeManager.ServiceGate(nil, 'data')
end

function adapter:OnNetworkState(state)
    if type(state) ~= 'table' or type(TriggerEvent) ~= 'function' then
        return false
    end
    TriggerEvent('qb-phone:client:UpdateTelecomNetwork', state)
    return true
end

PhoneBridges.Register(adapter)
