local function resourceFor(adapter)
    return PhoneBridgeManager.FirstStarted(adapter.resourceNames)
end

local function requirePhoneItem(adapter, source)
    local resourceName = resourceFor(adapter)
    if not resourceName then
        return false, {
            available = false,
            reason = 'provider_unavailable',
            blockedBy = 'provider',
        }
    end

    local numberOk, phoneNumber, numberError = PhoneBridgeManager.ExportCall(
        resourceName,
        'GetEquippedPhoneNumber',
        source
    )
    if not numberOk then
        return false, {
            available = false,
            reason = 'provider_export_unavailable',
            blockedBy = 'provider',
            export = 'GetEquippedPhoneNumber',
            error = numberError,
        }
    end
    if type(phoneNumber) ~= 'string' or phoneNumber == '' or #phoneNumber > 32 then
        return false, {
            available = false,
            reason = 'phone_unavailable',
            blockedBy = 'provider',
        }
    end

    local itemOk, hasPhone, itemError = PhoneBridgeManager.ExportCall(
        resourceName,
        'HasPhoneItem',
        source,
        phoneNumber
    )
    if not itemOk then
        return false, {
            available = false,
            reason = 'provider_export_unavailable',
            blockedBy = 'provider',
            export = 'HasPhoneItem',
            error = itemError,
        }
    end
    if hasPhone ~= true then
        return false, {
            available = false,
            reason = 'phone_item',
            blockedBy = 'provider',
        }
    end
    return true, nil
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
        networkChangeHooks = false,
    },
})

function adapter:CanStartCall(source)
    local available, state = PhoneBridgeManager.ServiceGate(source, 'voice')
    if not available then return false, state end

    local hasPhone, phoneState = requirePhoneItem(self, source)
    if not hasPhone then return false, phoneState end

    local resourceName = resourceFor(self)
    local exportOk, inCall, errorCode = PhoneBridgeManager.ExportCall(
        resourceName,
        'IsInCall',
        source
    )
    if exportOk and inCall == true then
        return false, {
            available = false,
            reason = 'phone_busy',
            blockedBy = 'provider',
        }
    end
    if not exportOk then
        return false, {
            available = false,
            reason = 'provider_export_unavailable',
            blockedBy = 'provider',
            export = 'IsInCall',
            error = errorCode,
        }
    end
    return true, state
end

function adapter:CanSendSMS(source)
    local available, state = PhoneBridgeManager.ServiceGate(source, 'sms')
    if not available then return false, state end
    local hasPhone, phoneState = requirePhoneItem(self, source)
    if not hasPhone then return false, phoneState end
    return true, state
end

function adapter:CanUseData(source)
    return PhoneBridgeManager.ServiceGate(source, 'data')
end

PhoneBridges.Register(adapter)
