local phoneEvidence = {
    {
        id = 'phone-lbphone',
        provider = 'lbphone',
        resourceName = 'lb-phone',
        capabilitiesVerified = { 'signal UI contract', 'call/SMS/data gate contract' },
    },
    {
        id = 'phone-npwd',
        provider = 'npwd',
        resourceName = 'npwd',
        capabilitiesVerified = { 'signal UI contract', 'documented busy-call gate contract' },
    },
    {
        id = 'phone-qs',
        provider = 'qs',
        resourceName = 'qs-smartphone',
        capabilitiesVerified = { 'signal UI contract', 'display-only capability downgrade' },
    },
}

for _, item in ipairs(phoneEvidence) do
    RegisterCompatibilityEvidence({
        id = item.id,
        label = 'EXPERIMENTAL',
        provider = item.provider,
        providerVersion = 'NOT CAPTURED',
        resourceName = item.resourceName,
        testDate = CompatibilityMatrix.date,
        runtimeCombination = 'Telecom + optional phone provider',
        capabilitiesVerified = item.capabilitiesVerified,
        capabilitiesUnavailable = { 'live phone resource and connected-client evidence' },
        syntheticContractEvidence = true,
        realRuntimeEvidence = false,
        result = 'contract checks pass; live certification pending',
        knownLimitations = 'Provider exports were represented by pure-Lua test doubles.',
    })
end

TEST('compat phone provider can start after telecom and stop safely', function()
    local previousConfig = Config.PhoneBridge
    local previousState = GetResourceState
    local previousExports = exports
    local started = {}

    Config.PhoneBridge = 'auto'
    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end
    exports = {
        ['lb-phone'] = {
            GetEquippedPhoneNumber = function(_, source)
                return '555-COMPAT-' .. tostring(source)
            end,
            HasPhoneItem = function() return true end,
            IsInCall = function() return false end,
        },
    }

    PhoneBridges.Shutdown()
    local ok, active = PhoneBridges.Initialize()
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'generic')

    started['lb-phone'] = true
    TriggerTestEvent('onResourceStart', 'lb-phone')
    ASSERT_EQ(PhoneBridges.GetActive().name, 'lbphone')

    started['lb-phone'] = nil
    TriggerTestEvent('onResourceStop', 'lb-phone')
    ASSERT_EQ(PhoneBridges.GetActive().name, 'generic')

    PhoneBridges.Shutdown()
    Config.PhoneBridge = previousConfig
    GetResourceState = previousState
    exports = previousExports
end)

TEST('compat phone capability levels remain provider-specific and conservative', function()
    ASSERT_EQ(PhoneBridges.Get('lbphone').supportLevel, PhoneBridgeContract.Levels.FUNCTIONAL)
    ASSERT_EQ(PhoneBridges.Get('npwd').supportLevel, PhoneBridgeContract.Levels.FUNCTIONAL)
    ASSERT_EQ(PhoneBridges.Get('qs').supportLevel, PhoneBridgeContract.Levels.DISPLAY)
end)
