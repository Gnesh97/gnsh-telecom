TEST('category bridge wrappers register through the central platform', function()
    ASSERT_EQ(BridgeRegistry.Get('framework', 'standalone').category, 'framework')
    ASSERT_EQ(BridgeRegistry.Get('phone', 'generic').category, 'phone')

    ASSERT_TRUE(InventoryBridge.SetAdapter({
        name = 'test-inventory',
        HasItem = function() return true end,
    }))
    ASSERT_EQ(BridgeManager.GetBridgeStatus('inventory').active, 'test-inventory')
    ASSERT_TRUE(BridgeManager.GetBridgeCapabilities('inventory').HasItem)
    ASSERT_TRUE(InventoryBridge.SetAdapter(nil))

    ASSERT_TRUE(TargetBridge.SetAdapter({
        name = 'test-target',
        AddTowerTarget = function() return true end,
        RemoveTowerTarget = function() return true end,
    }))
    ASSERT_EQ(BridgeManager.GetBridgeStatus('target').active, 'test-target')
    ASSERT_TRUE(TargetBridge.SetAdapter(nil))

    ASSERT_TRUE(DispatchBridge.SetAdapter({
        name = 'test-dispatch',
        Alert = function() return true end,
    }))
    ASSERT_EQ(BridgeManager.GetBridgeStatus('dispatch').active, 'test-dispatch')
    ASSERT_TRUE(DispatchBridge.SetAdapter(nil))
end)
