local function containsError(errors, fragment)
    for _, message in ipairs(errors or {}) do
        if tostring(message):find(fragment, 1, true) then return true end
    end
    return false
end

TEST('bridge configuration exposes deterministic defaults', function()
    local ok, errors = Config.Validate()
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(Config.Bridges.Framework.provider, 'auto')
    ASSERT_EQ(Config.Bridges.Framework.fallback, 'standalone')
    ASSERT_EQ(Config.Bridges.Target.fallback, 'native')
    ASSERT_EQ(Config.Bridges.Notify.fallback, 'native')
    ASSERT_EQ(Config.Bridges.Progress.fallback, 'native')
    ASSERT_EQ(Config.Bridges.Phone.requireEnforcement, false)
end)

TEST('bridge configuration rejects malformed and unknown sections', function()
    local previous = Config.Bridges
    Config.Bridges = {
        Target = { provider = '', fallback = 42 },
        Notify = { provider = 'not-a-provider', fallback = false },
        Unknown = { provider = 'native' },
    }

    local ok, errors = Config.Validate()
    ASSERT_FALSE(ok)
    ASSERT_TRUE(containsError(errors, 'Bridges.Target.provider'))
    ASSERT_TRUE(containsError(errors, 'Bridges.Target.fallback'))
    ASSERT_TRUE(containsError(errors, 'Bridges.Notify.fallback'))
    ASSERT_TRUE(containsError(errors, 'Bridges contains unknown category'))
    Config.Bridges = previous
end)

TEST('central custom provider settings validate their adapter configuration', function()
    local candidate = Utils.DeepCopy(Config)
    candidate.Bridges.Framework.provider = 'custom'
    candidate.Framework = 'auto'
    candidate.CustomFramework = nil

    local ok = Config.Validate(candidate)
    ASSERT_FALSE(ok)

    candidate.CustomFramework = {
        GetPlayer = function() return nil end,
    }
    ok = Config.Validate(candidate)
    ASSERT_TRUE(ok)
    ASSERT_EQ(BridgeConfig.GetProvider('framework', candidate), 'custom')
end)

TEST('legacy notify and progress settings remain effective under automatic bridge config', function()
    local previousBridges = Config.Bridges
    local previousNotify = Config.NotifyBridge
    local previousProgress = Config.ProgressBridge
    Config.Bridges = {
        Notify = { provider = 'auto', fallback = 'native' },
        Progress = { provider = 'auto', fallback = 'native' },
    }
    Config.NotifyBridge = 'framework'
    Config.ProgressBridge = 'ox'

    ASSERT_EQ(BridgeConfig.GetProvider('notify'), 'framework')
    ASSERT_EQ(BridgeConfig.GetProvider('progress'), 'ox')

    Config.Bridges = previousBridges
    Config.NotifyBridge = previousNotify
    Config.ProgressBridge = previousProgress
end)

TEST('explicit bridge provider uses configured fallback before other providers', function()
    local previous = Config.Bridges
    Config.Bridges = {
        Dispatch = {
            provider = 'missing-dispatch',
            fallback = 'fallback-dispatch',
            required = false,
        },
    }
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.Register({
        name = 'fallback-dispatch',
        category = 'dispatch',
        priority = 1,
        Detect = function() return true end,
    }))

    local ok, active = BridgeManager.InitializeCategory('dispatch')
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'fallback-dispatch')
    local status = BridgeManager.GetBridgeStatus('dispatch')
    ASSERT_EQ(status.configured, 'missing-dispatch')
    ASSERT_EQ(status.fallback, 'fallback-dispatch')
    ASSERT_TRUE(status.fallbackUsed)

    Config.Bridges = previous
    BridgeManager.Reset()
end)

TEST('legacy provider settings remain effective when bridge providers stay automatic', function()
    local previousBridges = Config.Bridges
    local previousFramework = Config.Framework
    Config.Bridges = {
        Framework = { provider = 'auto', fallback = 'standalone' },
    }
    Config.Framework = 'standalone'
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.Register({
        name = 'standalone',
        category = 'framework',
        priority = 0,
    }))

    local ok, active = BridgeManager.InitializeCategory('framework')
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'standalone')
    local status = BridgeManager.GetBridgeStatus('framework')
    ASSERT_EQ(status.configured, 'standalone')
    ASSERT_FALSE(status.fallbackUsed)

    Config.Bridges = previousBridges
    Config.Framework = previousFramework
    BridgeManager.Reset()
end)

TEST('automatic fallback usage is reported in bridge status', function()
    local previous = Config.Bridges
    Config.Bridges = {
        Dispatch = {
            provider = 'auto',
            fallback = 'fallback-dispatch',
            required = false,
        },
    }
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.Register({
        name = 'fallback-dispatch',
        category = 'dispatch',
        priority = 1,
        Detect = function() return true end,
    }))

    local ok = BridgeManager.InitializeCategory('dispatch')
    ASSERT_TRUE(ok)
    local status = BridgeManager.GetBridgeStatus('dispatch')
    ASSERT_EQ(status.provider, 'fallback-dispatch')
    ASSERT_TRUE(status.fallbackUsed)

    Config.Bridges = previous
    BridgeManager.Reset()
end)

TEST('required phone enforcement rejects display-only providers', function()
    local previous = Config.Bridges
    Config.Bridges = {
        Phone = {
            provider = 'display-phone',
            requireEnforcement = true,
        },
    }
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.Register({
        name = 'display-phone',
        category = 'phone',
        supportLevel = 'DISPLAY',
        Detect = function() return true end,
    }))

    local ok = BridgeManager.InitializeAll()
    ASSERT_FALSE(ok)
    local status = BridgeManager.GetBridgeStatus('phone')
    ASSERT_FALSE(status.requiredSatisfied)
    ASSERT_TRUE(status.requireEnforcement)

    Config.Bridges = previous
    BridgeManager.Reset()
end)

TEST('health degradation reinitializes and fails required providers closed', function()
    local previous = Config.Bridges
    local health = 'ACTIVE'
    Config.Bridges = {
        Dispatch = {
            provider = 'health-dispatch',
            required = true,
        },
    }
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.Register({
        name = 'health-dispatch',
        category = 'dispatch',
        Detect = function() return true end,
        HealthCheck = function() return health end,
    }))
    ASSERT_TRUE(BridgeManager.InitializeCategory('dispatch'))

    health = 'FAILED'
    ASSERT_FALSE(BridgeManager.Refresh('dispatch'))
    local status = BridgeManager.GetBridgeStatus('dispatch')
    ASSERT_EQ(status.active, nil)
    ASSERT_FALSE(status.requiredSatisfied)

    Config.Bridges = previous
    BridgeManager.Reset()
end)

TEST('required provider absence fails initialization while optional absence stays compatible', function()
    local previous = Config.Bridges
    Config.Bridges = {
        Dispatch = { provider = 'missing-dispatch', required = true },
    }
    BridgeManager.Reset()

    local ok = BridgeManager.InitializeAll()
    ASSERT_FALSE(ok)
    local status = BridgeManager.GetBridgeStatus('dispatch')
    ASSERT_TRUE(status.required)
    ASSERT_FALSE(status.requiredSatisfied)

    Config.Bridges = previous
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.InitializeAll())
end)

TEST('integration summary includes capabilities and support providers', function()
    local previous = Config.Bridges
    Config.Bridges = {
        Dispatch = { provider = 'summary-dispatch', required = false },
        Notify = { provider = 'auto', fallback = 'native' },
        Progress = { provider = 'auto', fallback = 'native' },
    }
    BridgeManager.Reset()
    ASSERT_TRUE(BridgeManager.Register({
        name = 'summary-dispatch',
        category = 'dispatch',
        capabilities = { 'Alert' },
        Detect = function() return true end,
    }))
    ASSERT_TRUE(BridgeManager.InitializeAll())
    ASSERT_TRUE(NotifyBridge.SetAdapter('native'))
    ASSERT_TRUE(ProgressBridge.SetAdapter('native'))

    local summary = BridgeManager.GetIntegrationSummary()
    ASSERT_TRUE(summary.compatible)
    ASSERT_EQ(summary.categories.dispatch.provider, 'summary-dispatch')
    ASSERT_TRUE(summary.categories.dispatch.capabilities.Alert)
    ASSERT_EQ(summary.categories.notify.provider, 'native')
    ASSERT_EQ(summary.categories.progress.provider, 'native')
    ASSERT_TRUE(summary.categories.notify.fallbackUsed)
    ASSERT_TRUE(summary.categories.progress.fallbackUsed)
    ASSERT_TRUE(summary.text:find('Integration Summary', 1, true) ~= nil)
    ASSERT_TRUE(summary.text:find('Compatibility : OK', 1, true) ~= nil)

    Config.Bridges = previous
    BridgeManager.Reset()
end)
