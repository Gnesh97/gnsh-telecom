if InventoryBridge and type(InventoryBridge.Register) == 'function' then
    InventoryBridge.Register({
        name = 'standalone',
        priority = 0,
        Detect = function()
            return not Config or Config.InventoryBridge == 'auto'
                or Config.InventoryBridge == 'standalone'
        end,
        HasItem = function() return false end,
        RemoveItem = function() return false end,
        AddItem = function() return false end,
        CanCarry = function() return false end,
        GetItemCount = function() return 0 end,
    })
end
