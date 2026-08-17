local function runAsResource(callback)
    local previousInvoking = GetInvokingResource
    local previousState = GetResourceState
    local owner = 'gnsh-sdk-test'
    local activeOwner = owner

    GetInvokingResource = function() return activeOwner end
    GetResourceState = function(resourceName)
        return resourceName == activeOwner and 'started' or 'stopped'
    end

    local ok, first, second, third = pcall(callback, function(resourceName)
        activeOwner = resourceName
    end)

    GetInvokingResource = previousInvoking
    GetResourceState = previousState

    if not ok then error(first, 0) end
    return first, second, third
end

local function dispatchProvider(name, callbacks)
    local provider = {
        name = name,
        priority = 900,
        Detect = function() return true end,
        Initialize = function() return true end,
        Shutdown = function() return true end,
        HealthCheck = function() return 'ACTIVE' end,
        Alert = function() return true end,
    }
    for key, value in pairs(callbacks or {}) do provider[key] = value end
    return provider
end

TEST('custom bridge sdk registers a validated external provider', function()
    ASSERT_TRUE(type(registeredExports.RegisterBridge) == 'function')
    ASSERT_TRUE(type(registeredExports.UnregisterBridge) == 'function')
    ASSERT_TRUE(type(registeredExports.GetBridgeRegistrations) == 'function')
    ASSERT_EQ(#BridgeSDK.GetSupportedCategories(), 7)

    runAsResource(function()
        local ok, registration = BridgeSDK.RegisterBridge(
            'dispatch',
            dispatchProvider('sdk-valid-dispatch')
        )

        ASSERT_TRUE(ok)
        ASSERT_EQ(registration.category, 'dispatch')
        ASSERT_EQ(registration.name, 'sdk-valid-dispatch')
        ASSERT_TRUE(registration.capabilities.Alert)
        ASSERT_EQ(registration.ownerResource, 'gnsh-sdk-test')

        ASSERT_TRUE(BridgeSDK.UnregisterBridge('dispatch', 'sdk-valid-dispatch'))
    end)
end)

TEST('custom bridge sdk rejects invalid category, name, and callback contracts', function()
    runAsResource(function()
        local ok, errorMessage = BridgeSDK.RegisterBridge(
            'unsupported',
            dispatchProvider('sdk-invalid-category')
        )
        ASSERT_FALSE(ok)
        ASSERT_EQ(errorMessage, 'unsupported_category')

        ok, errorMessage = BridgeSDK.RegisterBridge(
            'dispatch',
            dispatchProvider('sdk invalid name')
        )
        ASSERT_FALSE(ok)
        ASSERT_EQ(errorMessage, 'invalid_bridge_name')

        ok, errorMessage = BridgeSDK.RegisterBridge(
            'dispatch',
            dispatchProvider('sdk-invalid-callback', { Alert = 'not-a-function' })
        )
        ASSERT_FALSE(ok)
        ASSERT_TRUE(type(errorMessage) == 'string')
    end)
end)

TEST('custom bridge sdk rejects duplicate providers and enforces ownership', function()
    runAsResource(function(setOwner)
        local definition = dispatchProvider('sdk-duplicate-dispatch')
        ASSERT_TRUE(BridgeSDK.RegisterBridge('dispatch', definition))

        local ok, errorMessage = BridgeSDK.RegisterBridge(
            'dispatch',
            dispatchProvider('sdk-duplicate-dispatch')
        )
        ASSERT_FALSE(ok)
        ASSERT_EQ(errorMessage, 'bridge_duplicate')

        setOwner('other-resource')
        ok, errorMessage = BridgeSDK.UnregisterBridge('dispatch', 'sdk-duplicate-dispatch')
        ASSERT_FALSE(ok)
        ASSERT_EQ(errorMessage, 'bridge_owner_mismatch')

        setOwner('gnsh-sdk-test')
        ASSERT_TRUE(BridgeSDK.UnregisterBridge('dispatch', 'sdk-duplicate-dispatch'))
    end)
end)

TEST('custom bridge sdk exposes capabilities and protects lifecycle callbacks', function()
    runAsResource(function()
        local initialized = false
        local shutDown = false
        local definition = dispatchProvider('sdk-lifecycle-dispatch', {
            Initialize = function() initialized = true; return true end,
            Shutdown = function() shutDown = true; return true end,
        })

        local ok = BridgeSDK.RegisterBridge('dispatch', definition)
        ASSERT_TRUE(ok)
        ASSERT_TRUE(initialized)
        ASSERT_EQ(BridgeManager.GetActive('dispatch').name, 'sdk-lifecycle-dispatch')
        ASSERT_TRUE(BridgeManager.HasCapability('dispatch', 'Alert'))
        ASSERT_TRUE(BridgeManager.Call('dispatch', 'Alert', { message = 'test' }))

        local listed = BridgeSDK.GetBridgeRegistrations('dispatch')
        ASSERT_EQ(#listed, 1)
        ASSERT_EQ(listed[1].name, 'sdk-lifecycle-dispatch')
        ASSERT_TRUE(listed[1].capabilities.Alert)

        ASSERT_TRUE(BridgeSDK.UnregisterBridge('dispatch', 'sdk-lifecycle-dispatch'))
        ASSERT_TRUE(shutDown)
    end)
end)

TEST('custom bridge sdk cleans registrations when the owner resource stops', function()
    runAsResource(function()
        ASSERT_TRUE(BridgeSDK.RegisterBridge(
            'target',
            dispatchProvider('sdk-stop-target', {
                AddEntityInteraction = function() return true end,
            })
        ))

        TriggerTestEvent('onResourceStop', 'gnsh-sdk-test')

        ASSERT_EQ(BridgeRegistry.Get('target', 'sdk-stop-target'), nil)
        ASSERT_EQ(BridgeSDK.GetBridgeRegistration('target', 'sdk-stop-target'), nil)
    end)
end)

TEST('custom bridge sdk integrates notify and progress provider registries', function()
    runAsResource(function()
        local notifyOk, notifyRegistration = BridgeSDK.RegisterBridge('notify', {
            name = 'sdk-notify',
            priority = 900,
            Notify = function() return true end,
        })
        ASSERT_TRUE(notifyOk)
        ASSERT_TRUE(notifyRegistration.capabilities.Notify)
        ASSERT_EQ(NotifyBridge.GetActive().name, 'sdk-notify')

        local progressOk, progressRegistration = BridgeSDK.RegisterBridge('progress', {
            name = 'sdk-progress',
            priority = 900,
            StartProgress = function() return true end,
        })
        ASSERT_TRUE(progressOk)
        ASSERT_TRUE(progressRegistration.capabilities.StartProgress)
        ASSERT_EQ(ProgressBridge.GetActive().name, 'sdk-progress')

        ASSERT_TRUE(BridgeSDK.UnregisterBridge('notify', 'sdk-notify'))
        ASSERT_TRUE(BridgeSDK.UnregisterBridge('progress', 'sdk-progress'))
    end)
end)
