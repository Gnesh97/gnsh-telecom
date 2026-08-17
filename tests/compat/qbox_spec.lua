RegisterCompatibilityEvidence({
    id = 'qbox-phone-inventory-target',
    label = 'EXPERIMENTAL',
    provider = 'qbox',
    providerVersion = 'NOT CAPTURED',
    resourceName = 'qbx_core',
    testDate = CompatibilityMatrix.date,
    runtimeCombination = 'Qbox + phone + inventory + target',
    capabilitiesVerified = {
        'Qbox framework contract',
        'inventory and target provider registration',
        'phone bridge discovery contract',
    },
    capabilitiesUnavailable = { 'live resource startup and connected-client evidence' },
    syntheticContractEvidence = true,
    realRuntimeEvidence = false,
    result = 'contract checks pass; live certification pending',
    knownLimitations = 'Export behavior and versions were represented by pure-Lua test doubles.',
})

TEST('compat Qbox contract resolves identity and companion providers', function()
    local previousFramework = Config.Framework
    local previousCustom = Config.CustomFramework
    local previousState = GetResourceState
    local previousExports = exports

    Config.Framework = 'auto'
    Config.CustomFramework = nil
    GetResourceState = function(name)
        return name == 'qbx_core' and 'started' or 'stopped'
    end
    exports = {
        qbx_core = {
            GetPlayer = function(_, source)
                return {
                    PlayerData = {
                        citizenid = 'QBOX-COMPAT-' .. tostring(source),
                        job = { name = 'telecom', grade = { level = 2 } },
                    },
                }
            end,
        },
    }

    ASSERT_EQ(FrameworkBridge.Detect(), 'qbox')
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(102), 'QBOX-COMPAT-102')
    ASSERT_TRUE(BridgeRegistry.Get('inventory', 'ox') ~= nil)
    ASSERT_TRUE(BridgeRegistry.Get('target', 'ox') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('npwd') ~= nil)

    Config.Framework = previousFramework
    Config.CustomFramework = previousCustom
    GetResourceState = previousState
    exports = previousExports
end)
