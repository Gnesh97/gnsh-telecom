local function resourceFor(adapter)
    return PhoneBridgeManager.FirstStarted(adapter.resourceNames)
end

local function requirePhoneItem(adapter)
    local resourceName = resourceFor(adapter)
    if not resourceName then
        return false, {
            available = false,
            reason = 'provider_unavailable',
            blockedBy = 'provider',
        }
    end
    return PhoneBridgeManager.OptionalBooleanExportGate(
        resourceName,
        'HasPhoneItem',
        'phone_item'
    )
end

local adapter = PhoneBridges.CreateResourceAdapter('lbphone', {
    'lb-phone',
    'lbphone',
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

function adapter:CanStartCall()
    local available, state = PhoneBridgeManager.ServiceGate(nil, 'voice')
    if not available then return false, state end
    local hasPhone, phoneState = requirePhoneItem(self)
    if not hasPhone then return false, phoneState end

    local resourceName = resourceFor(self)
    local exportOk, inCall, errorCode = PhoneBridgeManager.ExportCall(
        resourceName,
        'IsInCall'
    )
    if exportOk and inCall == true then
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
            export = 'IsInCall',
        }
    end
    return true, state
end

function adapter:CanSendSMS()
    local available, state = PhoneBridgeManager.ServiceGate(nil, 'sms')
    if not available then return false, state end
    local hasPhone, phoneState = requirePhoneItem(self)
    if not hasPhone then return false, phoneState end
    return true, state
end

function adapter:CanUseData()
    return PhoneBridgeManager.ServiceGate(nil, 'data')
end

function adapter:OnNetworkState(state)
    if type(state) ~= 'table' then return false end
    local resourceName = resourceFor(self)
    if not resourceName then return false end
    local signal = tonumber(state.signal) or 0
    local bars = math.floor(math.max(0, math.min(4, signal * 4 / 100 + 0.5)))
    local ok = PhoneBridgeManager.ExportCall(resourceName, 'SetServiceBars', bars)
    local technology = state.technology or state.networkType
    if ok == true and type(technology) == 'string' and technology ~= '' then
        PhoneBridgeManager.ExportCall(resourceName, 'SetNetworkType', technology)
    end
    return ok == true
end

PhoneBridges.Register(adapter)
