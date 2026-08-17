RegisterCompatibilityEvidence({
    id = 'esx-phone-inventory-target',
    label = 'EXPERIMENTAL',
    provider = 'esx',
    providerVersion = 'NOT CAPTURED',
    resourceName = 'es_extended',
    testDate = CompatibilityMatrix.date,
    runtimeCombination = 'ESX + phone + inventory + target',
    capabilitiesVerified = {
        'ESX framework contract',
        'inventory and target provider registration',
        'phone bridge discovery contract',
    },
    capabilitiesUnavailable = { 'live resource startup and connected-client evidence' },
    syntheticContractEvidence = true,
    realRuntimeEvidence = false,
    result = 'contract checks pass; live certification pending',
    knownLimitations = 'Export behavior and versions were represented by pure-Lua test doubles.',
})

TEST('compat ESX contract resolves identity and companion providers', function()
    local previousFramework = Config.Framework
    local previousCustom = Config.CustomFramework
    local previousState = GetResourceState
    local previousExports = exports

    Config.Framework = 'auto'
    Config.CustomFramework = nil
    GetResourceState = function(name)
        return name == 'es_extended' and 'started' or 'stopped'
    end
    exports = {
        es_extended = {
            getSharedObject = function()
                return {
                    GetPlayerFromId = function(source)
                        return {
                            identifier = 'ESX-COMPAT-' .. tostring(source),
                            job = { name = 'telecom', grade = 2 },
                        }
                    end,
                }
            end,
        },
    }

    ASSERT_EQ(FrameworkBridge.Detect(), 'esx')
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(103), 'ESX-COMPAT-103')
    ASSERT_TRUE(BridgeRegistry.Get('inventory', 'standalone') ~= nil)
    ASSERT_TRUE(BridgeRegistry.Get('target', 'native') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('qs') ~= nil)

    Config.Framework = previousFramework
    Config.CustomFramework = previousCustom
    GetResourceState = previousState
    exports = previousExports
end)
