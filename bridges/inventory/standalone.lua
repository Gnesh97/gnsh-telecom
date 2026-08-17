if InventoryBridge and type(InventoryBridge.Register) == 'function' then
    InventoryBridge.Register({
        name = 'standalone',
        priority = 0,
        Detect = function()
            local configured = BridgeConfig and BridgeConfig.GetProvider
                and BridgeConfig.GetProvider('inventory')
                or (Config and Config.InventoryBridge or 'auto')
            return configured == 'auto' or configured == 'standalone'
        end,
        HasItem = function() return false end,
        RemoveItem = function() return false end,
        AddItem = function() return false end,
        CanCarry = function() return false end,
        GetItemCount = function() return 0 end,
    })
end
