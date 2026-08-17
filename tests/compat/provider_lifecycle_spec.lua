local lifecycleEvidence = {
    {
        id = 'phone-start-after-telecom',
        provider = 'phone lifecycle',
        resourceName = 'lb-phone',
        runtimeCombination = 'Phone starts after telecom',
        capabilitiesVerified = { 'generic fallback', 'phone provider reconciliation' },
    },
    {
        id = 'phone-stop-while-telecom-runs',
        provider = 'phone lifecycle',
        resourceName = 'lb-phone',
        runtimeCombination = 'Phone stops while telecom runs',
        capabilitiesVerified = { 'safe return to generic provider' },
    },
    {
        id = 'inventory-restart',
        provider = 'inventory lifecycle',
        resourceName = 'qb-inventory / ox_inventory',
        runtimeCombination = 'Inventory restart',
        capabilitiesVerified = { 'central lifecycle reconciliation path' },
    },
    {
        id = 'target-restart',
        provider = 'target lifecycle',
        resourceName = 'qb-target / ox_target',
        runtimeCombination = 'Target restart',
        capabilitiesVerified = { 'central lifecycle reconciliation path' },
    },
    {
        id = 'framework-restart',
        provider = 'framework lifecycle',
        resourceName = 'qb-core / qbx_core / es_extended',
        runtimeCombination = 'Framework restart',
        capabilitiesVerified = { 'safe provider re-selection path' },
    },
    {
        id = 'notify-restart',
        provider = 'notify lifecycle',
        resourceName = 'ox_lib',
        runtimeCombination = 'Notify restart',
        capabilitiesVerified = { 'native presentation fallback' },
    },
    {
        id = 'progress-restart',
        provider = 'progress lifecycle',
        resourceName = 'ox_lib',
        runtimeCombination = 'Progress restart',
        capabilitiesVerified = { 'native presentation fallback' },
    },
}

for _, item in ipairs(lifecycleEvidence) do
    RegisterCompatibilityEvidence({
        id = item.id,
        label = 'EXPERIMENTAL',
        provider = item.provider,
        providerVersion = 'NOT CAPTURED',
        resourceName = item.resourceName,
        testDate = CompatibilityMatrix.date,
        runtimeCombination = item.runtimeCombination,
        capabilitiesVerified = item.capabilitiesVerified,
        capabilitiesUnavailable = { 'live restart and connected-client evidence' },
        syntheticContractEvidence = true,
        realRuntimeEvidence = false,
        result = 'contract checks pass; live certification pending',
        knownLimitations = 'Resource state and exports were represented by pure-Lua test doubles.',
    })
end

TEST('compat framework inventory and target restarts reconcile without breaking core', function()
    local previousState = GetResourceState
    local previousExports = exports
    local previousFramework = Config.Framework
    local started = {}

    Config.Framework = 'auto'
    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end
    exports = {}

    started['qb-core'] = true
    ASSERT_TRUE(BridgeManager.HandleResourceStart('qb-core'))
    ASSERT_TRUE(BridgeManager.HandleResourceStop('qb-core'))

    started['qb-inventory'] = true
    ASSERT_TRUE(BridgeManager.HandleResourceStart('qb-inventory'))
    ASSERT_TRUE(BridgeManager.HandleResourceStop('qb-inventory'))

    started['qb-target'] = true
    ASSERT_TRUE(BridgeManager.HandleResourceStart('qb-target'))
    ASSERT_TRUE(BridgeManager.HandleResourceStop('qb-target'))

    local frameworkStatus = BridgeManager.GetBridgeStatus('framework')
    ASSERT_TRUE(frameworkStatus.state ~= 'FAILED')

    Config.Framework = previousFramework
    GetResourceState = previousState
    exports = previousExports
end)

TEST('compat notify and progress restart paths fall back to native presentation', function()
    local previousState = GetResourceState
    local previousTriggerClientEvent = TriggerClientEvent
    local calls = {}

    GetResourceState = function() return 'stopped' end
    TriggerClientEvent = function(name, source, payload)
        calls[#calls + 1] = { name = name, source = source, payload = payload }
    end

    ASSERT_TRUE(NotifyBridge.SetAdapter('ox'))
    ASSERT_TRUE(NotifyBridge.Notify(7, 'warning', 'compat fallback', {}))
    ASSERT_TRUE(ProgressBridge.SetAdapter('ox'))
    ASSERT_TRUE(ProgressBridge.StartProgress(7, 'compat_fallback', 1000, {}))
    ASSERT_TRUE(#calls >= 2)

    NotifyBridge.SetAdapter('native')
    ProgressBridge.SetAdapter('native')
    GetResourceState = previousState
    TriggerClientEvent = previousTriggerClientEvent
end)

TEST('compatibility evidence gate rejects unsupported support claims without live proof', function()
    ASSERT_TRUE(#CompatibilityMatrix.entries >= 11)
    for _, entry in ipairs(CompatibilityMatrix.entries) do
        ASSERT_TRUE(CompatibilityMatrix.labels[entry.label])
        ASSERT_TRUE(type(entry.providerVersion) == 'string')
        ASSERT_TRUE(type(entry.resourceName) == 'string')
        ASSERT_EQ(entry.testDate, CompatibilityMatrix.date)
        ASSERT_TRUE(type(entry.runtimeCombination) == 'string')
        ASSERT_TRUE(type(entry.result) == 'string')
        ASSERT_TRUE(entry.syntheticContractEvidence == true)
        if entry.label == 'FULLY SUPPORTED' or entry.label == 'SUPPORTED' then
            ASSERT_TRUE(entry.realRuntimeEvidence == true)
        end
    end
    ASSERT_EQ(CompatibilityMatrix.connectedClients, 0)
end)
