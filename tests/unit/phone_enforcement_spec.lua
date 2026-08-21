local function makePhoneState(source, overrides)
    local state = {
        source = source,
        towerId = 'PHONE_TOWER',
        signal = 80,
        rawSignal = 80,
        signalLevel = Enums.SignalLevel.GOOD,
        technology = '4G',
        backhaulStatus = Enums.BackhaulState.ONLINE,
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }
    for key, value in pairs(overrides or {}) do state[key] = value end
    return state
end

local function setPhoneState(source, overrides)
    Connections.Clear()
    ASSERT_TRUE(Connections.Set(
        source,
        makePhoneState(source, overrides),
        { skipCapacity = true }
    ))
end

TEST('phone contract exposes honest support levels and downgrades incomplete providers', function()
    ASSERT_EQ(PhoneBridgeContract.Levels.FULL, 'FULL')
    ASSERT_EQ(PhoneBridgeContract.Levels.FUNCTIONAL, 'FUNCTIONAL')
    ASSERT_EQ(PhoneBridgeContract.Levels.DISPLAY, 'DISPLAY')

    local normalized = PhoneBridgeContract.Normalize({
        name = 'incomplete',
        category = 'phone',
        supportLevel = PhoneBridgeContract.Levels.FULL,
        support = {
            signalUI = true,
            callGate = true,
            smsGate = true,
            dataGate = true,
            callLifecycle = false,
            networkChangeHooks = false,
        },
        GetSignalStrength = function() return 100 end,
        CanStartCall = function() return true end,
        CanSendSMS = function() return true end,
        CanUseData = function() return true end,
        GetNetworkState = function() return {} end,
    })

    ASSERT_EQ(normalized.supportLevel, PhoneBridgeContract.Levels.FUNCTIONAL)
    ASSERT_TRUE(normalized.support.callGate)
    ASSERT_FALSE(normalized.support.callLifecycle)
end)

TEST('generic phone gates reject no service and offline backhaul', function()
    local previous = Config.PhoneBridge
    Config.PhoneBridge = 'generic'
    PhoneBridges.Shutdown()
    ASSERT_TRUE(PhoneBridges.Initialize())

    setPhoneState(71)
    local canCall, callState = PhoneBridges.CanStartCall(71)
    local canSms, smsState = PhoneBridges.CanSendSMS(71)
    local canData, dataState = PhoneBridges.CanUseData(71)
    ASSERT_TRUE(canCall)
    ASSERT_TRUE(canSms)
    ASSERT_TRUE(canData)

    setPhoneState(71, { towerId = nil, signal = 0, rawSignal = 0 })
    canCall, callState = PhoneBridges.CanStartCall(71)
    canSms, smsState = PhoneBridges.CanSendSMS(71)
    canData, dataState = PhoneBridges.CanUseData(71)
    ASSERT_FALSE(canCall)
    ASSERT_FALSE(canSms)
    ASSERT_FALSE(canData)
    ASSERT_EQ(callState.blockedBy, 'signal')
    ASSERT_EQ(smsState.blockedBy, 'signal')
    ASSERT_EQ(dataState.blockedBy, 'signal')

    setPhoneState(71, { backhaulStatus = Enums.BackhaulState.OFFLINE })
    canCall, callState = PhoneBridges.CanStartCall(71)
    ASSERT_FALSE(canCall)
    ASSERT_EQ(callState.blockedBy, 'backhaul')
    ASSERT_EQ(callState.reason, 'backhaul')

    PhoneBridges.Shutdown()
    Config.PhoneBridge = previous
    Connections.Clear()
end)

TEST('qb phone adapter enforces telecom service gates', function()
    local previousConfig = Config.PhoneBridge
    local previousGetResourceState = GetResourceState

    Config.PhoneBridge = 'qbphone'
    GetResourceState = function(name)
        return name == 'qb-phone' and 'started' or 'stopped'
    end

    setPhoneState(76)
    PhoneBridges.Shutdown()
    local ok, active = PhoneBridges.Initialize()
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'qbphone')
    ASSERT_EQ(PhoneBridges.GetStatus().supportLevel, PhoneBridgeContract.Levels.FUNCTIONAL)
    ASSERT_TRUE(PhoneBridges.CanStartCall(76))
    ASSERT_TRUE(PhoneBridges.CanSendSMS(76))
    ASSERT_TRUE(PhoneBridges.CanUseData(76))

    setPhoneState(76, { towerId = nil, signal = 0, rawSignal = 0 })
    local canCall, callState = PhoneBridges.CanStartCall(76)
    local canSms, smsState = PhoneBridges.CanSendSMS(76)
    local canData, dataState = PhoneBridges.CanUseData(76)
    ASSERT_FALSE(canCall)
    ASSERT_FALSE(canSms)
    ASSERT_FALSE(canData)
    ASSERT_EQ(callState.blockedBy, 'signal')
    ASSERT_EQ(smsState.blockedBy, 'signal')
    ASSERT_EQ(dataState.blockedBy, 'signal')

    PhoneBridges.Shutdown()
    Connections.Clear()
    GetResourceState = previousGetResourceState
    Config.PhoneBridge = previousConfig
end)

TEST('lb phone adapter enforces service, phone item, and call state gates', function()
    local previousConfig = Config.PhoneBridge
    local previousGetResourceState = GetResourceState
    local previousExports = exports
    local phoneItem = true
    local inCall = false

    Config.PhoneBridge = 'auto'
    GetResourceState = function(name)
        return name == 'lb-phone' and 'started' or 'stopped'
    end
    exports = {
        ['lb-phone'] = {
            GetEquippedPhoneNumber = function(_, source) return '555-0100', source end,
            HasPhoneItem = function(_, source, number)
                return phoneItem and number == '555-0100', source
            end,
            IsInCall = function(_, source) return inCall, source end,
        },
    }

    setPhoneState(72)
    PhoneBridges.Shutdown()
    local ok, active = PhoneBridges.Initialize()
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'lbphone')
    ASSERT_EQ(PhoneBridges.GetStatus().supportLevel, PhoneBridgeContract.Levels.FUNCTIONAL)
    ASSERT_TRUE(PhoneBridges.CanStartCall(72))

    phoneItem = false
    local canCall, state = PhoneBridges.CanStartCall(72)
    ASSERT_FALSE(canCall)
    ASSERT_EQ(state.reason, 'phone_item')

    phoneItem = true
    inCall = true
    canCall, state = PhoneBridges.CanStartCall(72)
    ASSERT_FALSE(canCall)
    ASSERT_EQ(state.reason, 'phone_busy')

    inCall = false
    local isInCallExport = exports['lb-phone'].IsInCall
    exports['lb-phone'].IsInCall = nil
    canCall, state = PhoneBridges.CanStartCall(72)
    ASSERT_FALSE(canCall)
    ASSERT_EQ(state.reason, 'provider_export_unavailable')
    exports['lb-phone'].IsInCall = isInCallExport

    PhoneBridges.Shutdown()
    Connections.Clear()
    exports = previousExports
    GetResourceState = previousGetResourceState
    Config.PhoneBridge = previousConfig
end)

TEST('npwd adapter rejects calls while documented busy export is true', function()
    local previousConfig = Config.PhoneBridge
    local previousGetResourceState = GetResourceState
    local previousExports = exports
    local busy = true

    Config.PhoneBridge = 'npwd'
    GetResourceState = function(name)
        return name == 'npwd' and 'started' or 'stopped'
    end
    exports = {
        npwd = {
            isPlayerBusy = function(_, source) return busy, source end,
        },
    }

    setPhoneState(73)
    PhoneBridges.Shutdown()
    local ok, active = PhoneBridges.Initialize()
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'npwd')

    local canCall, state = PhoneBridges.CanStartCall(73)
    ASSERT_FALSE(canCall)
    ASSERT_EQ(state.reason, 'phone_busy')

    busy = false
    ASSERT_TRUE(PhoneBridges.CanStartCall(73))

    PhoneBridges.Shutdown()
    Connections.Clear()
    exports = previousExports
    GetResourceState = previousGetResourceState
    Config.PhoneBridge = previousConfig
end)

TEST('qs adapter reports display-only support and fails closed for unsupported gates', function()
    local previousConfig = Config.PhoneBridge
    local previousGetResourceState = GetResourceState

    Config.PhoneBridge = 'qs'
    GetResourceState = function(name)
        return name == 'qs-smartphone' and 'started' or 'stopped'
    end

    setPhoneState(74)
    PhoneBridges.Shutdown()
    local ok, active = PhoneBridges.Initialize()
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'qs')

    local status = PhoneBridges.GetStatus()
    ASSERT_EQ(status.supportLevel, PhoneBridgeContract.Levels.DISPLAY)
    ASSERT_FALSE(status.support.callGate)

    local canCall, state = PhoneBridges.CanStartCall(74)
    ASSERT_FALSE(canCall)
    ASSERT_EQ(state.reason, 'provider_gate_unsupported')
    ASSERT_EQ(state.blockedBy, 'provider')

    PhoneBridges.Shutdown()
    Connections.Clear()
    GetResourceState = previousGetResourceState
    Config.PhoneBridge = previousConfig
end)

TEST('phone network state is propagated through the selected provider', function()
    local previous = Config.PhoneBridge
    Config.PhoneBridge = 'generic'
    setPhoneState(75, { technology = '5G', signal = 91, rawSignal = 93 })
    PhoneBridges.Shutdown()
    ASSERT_TRUE(PhoneBridges.Initialize())

    local state = PhoneBridges.GetNetworkState(75)
    ASSERT_EQ(state.technology, '5G')
    ASSERT_EQ(state.signal, 91)
    ASSERT_EQ(state.rawSignal, 93)

    PhoneBridges.Shutdown()
    Connections.Clear()
    Config.PhoneBridge = previous
end)

TEST('provider-aware phone exports are additive to the core API', function()
    ASSERT_TRUE(type(registeredExports.CanStartCall) == 'function')
    ASSERT_TRUE(type(registeredExports.CanSendPhoneSMS) == 'function')
    ASSERT_TRUE(type(registeredExports.CanUsePhoneData) == 'function')
    ASSERT_TRUE(type(registeredExports.GetPhoneNetworkState) == 'function')
    ASSERT_TRUE(type(registeredExports.GetPhoneBridgeStatus) == 'function')
    ASSERT_TRUE(type(registeredExports.CanSendSMS) == 'function')
end)
