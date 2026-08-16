local function resetBridgePlatform()
    BridgeManager.Reset()
end

local function registerProvider(name, priority, options)
    options = options or {}
    local provider = {
        name = name,
        category = options.category or 'dispatch',
        priority = priority,
        capabilities = options.capabilities,
        resources = options.resources,
        version = options.version,
        Detect = options.Detect,
        Initialize = options.Initialize,
        Shutdown = options.Shutdown,
        HealthCheck = options.HealthCheck,
    }

    local ok, errorMessage = BridgeManager.Register(provider)
    ASSERT_TRUE(ok, errorMessage or ('failed to register ' .. name))
    return provider
end

TEST('bridge platform validates contracts and normalizes capabilities', function()
    resetBridgePlatform()

    local invalid, invalidError = BridgeContracts.Normalize({
        category = 'dispatch',
    })
    ASSERT_EQ(invalid, nil)
    ASSERT_TRUE(type(invalidError) == 'string')

    registerProvider('capability-test', 10, {
        capabilities = { ' Alert ', 'alert', 'custom_hook' },
        Detect = function() return true end,
        HealthCheck = function() return 'PARTIAL' end,
    })

    local ok, active = BridgeManager.InitializeCategory('dispatch')
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'capability-test')

    local status = BridgeManager.GetBridgeStatus('dispatch')
    ASSERT_EQ(status.state, 'PARTIAL')
    ASSERT_TRUE(status.capabilities.Alert)
    ASSERT_TRUE(status.capabilities.custom_hook)
    ASSERT_EQ(status.providers[1].selected, true)

    resetBridgePlatform()
end)

TEST('bridge platform selects highest priority with deterministic ties', function()
    resetBridgePlatform()

    registerProvider('zeta', 10, { Detect = function() return true end })
    registerProvider('alpha', 10, { Detect = function() return true end })

    local ok, active = BridgeManager.InitializeCategory('dispatch')
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'alpha')

    resetBridgePlatform()
end)

TEST('bridge platform falls back after provider initialization exception', function()
    resetBridgePlatform()

    registerProvider('broken', 100, {
        Detect = function() return true end,
        Initialize = function() error('provider exploded') end,
    })
    registerProvider('fallback', 10, {
        Detect = function() return true end,
    })

    local ok, active = BridgeManager.InitializeCategory('dispatch')
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'fallback')

    local status = BridgeManager.GetBridgeStatus('dispatch')
    local brokenStatus
    for _, provider in ipairs(status.providers) do
        if provider.name == 'broken' then brokenStatus = provider end
    end
    ASSERT_EQ(brokenStatus.state, 'FAILED')
    ASSERT_EQ(status.active, 'fallback')

    resetBridgePlatform()
end)

TEST('bridge platform handles provider stop and start without crashing core', function()
    resetBridgePlatform()

    local previousGetResourceState = GetResourceState
    local started = { ['priority-dispatch'] = true }
    GetResourceState = function(resourceName)
        return started[resourceName] and 'started' or 'stopped'
    end

    registerProvider('priority-provider', 100, {
        resources = { 'priority-dispatch' },
    })
    registerProvider('fallback-provider', 1, {
        Detect = function() return true end,
    })

    local ok, active = BridgeManager.InitializeCategory('dispatch')
    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'priority-provider')

    started['priority-dispatch'] = nil
    ASSERT_TRUE(BridgeManager.HandleResourceStop('priority-dispatch'))
    ASSERT_EQ(BridgeManager.GetActive('dispatch').name, 'fallback-provider')

    started['priority-dispatch'] = true
    ASSERT_TRUE(BridgeManager.HandleResourceStart('priority-dispatch'))
    ASSERT_EQ(BridgeManager.GetActive('dispatch').name, 'priority-provider')

    GetResourceState = previousGetResourceState
    resetBridgePlatform()
end)

TEST('bridge platform replaces an active provider safely', function()
    resetBridgePlatform()

    local shutdownCount = 0
    registerProvider('replaceable', 10, {
        version = 1,
        Detect = function() return true end,
        Shutdown = function() shutdownCount = shutdownCount + 1 end,
    })
    ASSERT_TRUE(BridgeManager.InitializeCategory('dispatch'))
    ASSERT_EQ(BridgeManager.GetActive('dispatch').version, 1)

    registerProvider('replaceable', 20, {
        version = 2,
        Detect = function() return true end,
    })
    ASSERT_EQ(shutdownCount, 1)
    ASSERT_EQ(BridgeManager.GetActive('dispatch').version, 2)

    resetBridgePlatform()
end)

TEST('bridge platform reports missing optional categories safely', function()
    resetBridgePlatform()

    local status = BridgeManager.GetBridgeStatus('inventory')
    ASSERT_EQ(status.state, 'OPTIONAL')
    ASSERT_FALSE(status.available)
    ASSERT_EQ(next(BridgeManager.GetBridgeCapabilities('inventory')), nil)

    local all = GetBridgeStatus()
    ASSERT_EQ(all.inventory.state, 'OPTIONAL')
    ASSERT_EQ(next(GetBridgeCapabilities('inventory')), nil)

    resetBridgePlatform()
end)
