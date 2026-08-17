CompatibilityMatrix = CompatibilityMatrix or {
    date = '2026-08-17',
    connectedClients = 0,
    entries = {},
    labels = {
        ['FULLY SUPPORTED'] = true,
        ['SUPPORTED'] = true,
        ['PARTIAL'] = true,
        ['EXPERIMENTAL'] = true,
        ['UNSUPPORTED'] = true,
    },
}

function RegisterCompatibilityEvidence(entry)
    CompatibilityMatrix.entries[#CompatibilityMatrix.entries + 1] = entry
end

RegisterCompatibilityEvidence({
    id = 'standalone-no-phone',
    label = 'EXPERIMENTAL',
    provider = 'standalone',
    providerVersion = 'NOT CAPTURED',
    resourceName = 'none',
    testDate = CompatibilityMatrix.date,
    runtimeCombination = 'Standalone + no phone',
    capabilitiesVerified = {
        'standalone framework fallback',
        'generic phone fallback without a phone resource',
        'core API remains available',
    },
    capabilitiesUnavailable = { 'live FiveM runtime evidence' },
    syntheticContractEvidence = true,
    realRuntimeEvidence = false,
    result = 'contract checks pass; live certification pending',
    knownLimitations = 'No connected FiveM client or production provider version was available.',
})

local function withGlobals(values, callback)
    local previous = {}
    for name, value in pairs(values) do
        previous[name] = _G[name]
        _G[name] = value
    end

    local ok, errorMessage = pcall(callback)

    for name, value in pairs(previous) do _G[name] = value end
    if not ok then error(errorMessage, 0) end
end

TEST('compat standalone mode falls back safely without phone resources', function()
    local previousFramework = Config.Framework
    local previousPhone = Config.PhoneBridge

    withGlobals({
        GetResourceState = function() return 'stopped' end,
        exports = {},
    }, function()
        Config.Framework = 'auto'
        Config.PhoneBridge = 'auto'
        ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')

        PhoneBridges.Shutdown()
        local ok, active = PhoneBridges.Initialize()
        ASSERT_TRUE(ok)
        ASSERT_EQ(active.name, 'generic')
        ASSERT_EQ(PhoneBridges.GetStatus().active, 'generic')
    end)

    Config.Framework = previousFramework
    Config.PhoneBridge = previousPhone
end)
