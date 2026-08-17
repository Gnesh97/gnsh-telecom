RegisterCompatibilityEvidence({
    id = 'qbcore-phone-inventory-target',
    label = 'EXPERIMENTAL',
    provider = 'qbcore',
    providerVersion = 'NOT CAPTURED',
    resourceName = 'qb-core',
    testDate = CompatibilityMatrix.date,
    runtimeCombination = 'QBCore + phone + inventory + target',
    capabilitiesVerified = {
        'QBCore framework contract',
        'qb-inventory provider registration',
        'qb-target provider registration',
        'generic phone contract registration',
    },
    capabilitiesUnavailable = { 'live resource startup and connected-client evidence' },
    syntheticContractEvidence = true,
    realRuntimeEvidence = false,
    result = 'contract checks pass; live certification pending',
    knownLimitations = 'Export behavior and versions were represented by pure-Lua test doubles.',
})

TEST('compat QBCore contract resolves identity and companion providers', function()
    local previousFramework = Config.Framework
    local previousCustom = Config.CustomFramework
    local previousState = GetResourceState
    local previousExports = exports

    Config.Framework = 'auto'
    Config.CustomFramework = nil
    GetResourceState = function(name)
        return name == 'qb-core' and 'started' or 'stopped'
    end
    exports = {
        ['qb-core'] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayer = function(source)
                            return {
                                PlayerData = {
                                    citizenid = 'QBCORE-COMPAT-' .. tostring(source),
                                    job = { name = 'telecom', grade = { level = 2 } },
                                },
                            }
                        end,
                    },
                }
            end,
        },
    }

    ASSERT_EQ(FrameworkBridge.Detect(), 'qbcore')
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(101), 'QBCORE-COMPAT-101')
    ASSERT_TRUE(BridgeRegistry.Get('inventory', 'qb') ~= nil)
    ASSERT_TRUE(BridgeRegistry.Get('target', 'qb') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('lbphone') ~= nil)

    Config.Framework = previousFramework
    Config.CustomFramework = previousCustom
    GetResourceState = previousState
    exports = previousExports
end)
