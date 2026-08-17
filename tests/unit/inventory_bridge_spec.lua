local function withInventoryEnvironment(started, mockExports, callback)
    local previousGetResourceState = GetResourceState
    local previousExports = exports
    local previousBridge = Config.InventoryBridge
    local previousCustom = Config.CustomInventory

    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end
    exports = mockExports

    local ok, err = pcall(callback)
    Config.InventoryBridge = previousBridge
    Config.CustomInventory = previousCustom
    GetResourceState = previousGetResourceState
    exports = previousExports
    BridgeManager.InitializeCategory('inventory', nil, true)
    if not ok then error(err, 0) end
end

TEST('inventory configuration validates supported and custom modes', function()
    local previousBridge = Config.InventoryBridge
    local previousCustom = Config.CustomInventory

    Config.InventoryBridge = 'unknown'
    ASSERT_FALSE(Config.Validate())

    Config.InventoryBridge = 'custom'
    Config.CustomInventory = nil
    ASSERT_FALSE(Config.Validate())

    Config.InventoryBridge = previousBridge
    Config.CustomInventory = previousCustom
    ASSERT_TRUE(Config.Validate())
end)

TEST('standalone inventory is safe and item-free actions continue', function()
    withInventoryEnvironment({}, {}, function()
        Config.InventoryBridge = 'auto'
        ASSERT_TRUE(BridgeManager.InitializeCategory('inventory', nil, true))
        ASSERT_EQ(InventoryBridge.GetName(), 'standalone')
        ASSERT_FALSE(InventoryBridge.HasItem(7, 'repair_kit', 1))
        ASSERT_FALSE(InventoryBridge.RemoveItem(7, 'repair_kit', 1))
        ASSERT_FALSE(InventoryBridge.AddItem(7, 'repair_kit', 1))
        ASSERT_FALSE(InventoryBridge.CanCarry(7, 'repair_kit', 1))
        ASSERT_EQ(InventoryBridge.GetItemCount(7, 'repair_kit'), 0)
        ASSERT_FALSE(InventoryBridge.HasItem(7, 'repair_kit', 0))
        ASSERT_FALSE(InventoryBridge.AddItem(7, 'repair_kit', 10001))
        ASSERT_FALSE(InventoryBridge.AddItem(7, 'repair_kit', 1, 'invalid'))
        ASSERT_TRUE(InventoryBridge.HasItem(7, nil, 1))
        ASSERT_TRUE(InventoryBridge.RemoveItem(7, nil, 1))
        ASSERT_TRUE(InventoryBridge.AddItem(7, nil, 1))
    end)
end)

TEST('ox inventory adapter maps the universal contract', function()
    local counts = { repair_kit = 2 }
    local added = 0
    local removed = 0

    withInventoryEnvironment({ ox_inventory = true }, {
        ox_inventory = {
            Search = function(_, source, mode, item)
                ASSERT_EQ(source, 7)
                ASSERT_EQ(mode, 'count')
                return counts[item] or 0
            end,
            CanCarryItem = function(_, source, item, amount)
                return source == 7 and item == 'repair_kit' and amount == 1
            end,
            RemoveItem = function(_, source, item, amount)
                if source == 7 and counts[item] >= amount then
                    counts[item] = counts[item] - amount
                    removed = removed + amount
                    return true
                end
                return false
            end,
            AddItem = function(_, source, item, amount)
                if source ~= 7 then return false end
                counts[item] = (counts[item] or 0) + amount
                added = added + amount
                return true
            end,
        },
    }, function()
        ASSERT_TRUE(BridgeManager.InitializeCategory('inventory', nil, true))
        ASSERT_EQ(InventoryBridge.GetName(), 'ox')
        ASSERT_TRUE(InventoryBridge.HasItem(7, 'repair_kit', 2))
        ASSERT_FALSE(InventoryBridge.HasItem(7, 'repair_kit', 3))
        ASSERT_EQ(InventoryBridge.GetItemCount(7, 'repair_kit'), 2)
        ASSERT_TRUE(InventoryBridge.CanCarry(7, 'repair_kit', 1))
        ASSERT_TRUE(InventoryBridge.RemoveItem(7, 'repair_kit', 1))
        ASSERT_TRUE(InventoryBridge.AddItem(7, 'repair_kit', 1))
        ASSERT_EQ(removed, 1)
        ASSERT_EQ(added, 1)
    end)
end)

TEST('QB and QS inventory adapters reconcile through resource lifecycle', function()
    local started = { ['qb-inventory'] = true }
    local previousGetResourceState = GetResourceState
    local previousExports = exports
    local counts = { repair_kit = 3 }

    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end
    exports = {
        ['qb-inventory'] = {
            HasItem = function(_, source, item, amount)
                return source == 7 and (counts[item] or 0) >= amount
            end,
            GetItemCount = function(_, source, item)
                return source == 7 and (counts[item] or 0) or 0
            end,
            CanAddItem = function(_, source, item, amount)
                return source == 7 and item == 'repair_kit' and amount == 1
            end,
            RemoveItem = function(_, source, item, amount)
                if source ~= 7 or (counts[item] or 0) < amount then return false end
                counts[item] = counts[item] - amount
                return true
            end,
            AddItem = function(_, source, item, amount)
                if source ~= 7 then return false end
                counts[item] = (counts[item] or 0) + amount
                return true
            end,
        },
    }

    ASSERT_TRUE(BridgeManager.InitializeCategory('inventory', nil, true))
    ASSERT_EQ(InventoryBridge.GetName(), 'qb')
    ASSERT_TRUE(InventoryBridge.HasItem(7, 'repair_kit', 3))
    ASSERT_EQ(InventoryBridge.GetItemCount(7, 'repair_kit'), 3)
    ASSERT_TRUE(InventoryBridge.CanCarry(7, 'repair_kit', 1))
    started['qb-inventory'] = nil
    ASSERT_TRUE(BridgeManager.HandleResourceStop('qb-inventory'))
    ASSERT_EQ(InventoryBridge.GetName(), 'standalone')

    started['qs-inventory'] = true
    exports = {
        ['qs-inventory'] = {
            GetItemTotalAmount = function(_, source, item)
                return source == 7 and (counts[item] or 0) or 0
            end,
            CanCarryItem = function() return true end,
            RemoveItem = function() return true end,
            AddItem = function() return true end,
        },
    }
    ASSERT_TRUE(BridgeManager.HandleResourceStart('qs-inventory'))
    ASSERT_EQ(InventoryBridge.GetName(), 'qs')
    ASSERT_EQ(InventoryBridge.GetItemCount(7, 'repair_kit'), 3)
    ASSERT_TRUE(InventoryBridge.HasItem(7, 'repair_kit', 1))

    exports = previousExports
    GetResourceState = previousGetResourceState
    BridgeManager.InitializeCategory('inventory', nil, true)
end)

TEST('custom inventory adapter uses configured callbacks and restart fallback', function()
    local counts = { repair_kit = 4 }
    Config.InventoryBridge = 'custom'
    Config.CustomInventory = {
        HasItem = function(source, item, amount)
            return source == 11 and (counts[item] or 0) >= amount
        end,
        RemoveItem = function(source, item, amount)
            if source ~= 11 or (counts[item] or 0) < amount then return false end
            counts[item] = counts[item] - amount
            return true
        end,
        AddItem = function(source, item, amount)
            if source ~= 11 then return false end
            counts[item] = (counts[item] or 0) + amount
            return true
        end,
        CanCarry = function() return true end,
        GetItemCount = function(source, item)
            return source == 11 and (counts[item] or 0) or 0
        end,
    }

    local previousGetResourceState = GetResourceState
    local previousExports = exports
    GetResourceState = function() return 'stopped' end
    exports = {}
    ASSERT_TRUE(BridgeManager.InitializeCategory('inventory', nil, true))
    ASSERT_EQ(InventoryBridge.GetName(), 'custom')
    ASSERT_TRUE(InventoryBridge.HasItem(11, 'repair_kit', 4))
    ASSERT_EQ(InventoryBridge.GetItemCount(11, 'repair_kit'), 4)
    ASSERT_TRUE(InventoryBridge.RemoveItem(11, 'repair_kit', 1))
    ASSERT_TRUE(InventoryBridge.AddItem(11, 'repair_kit', 1))
    ASSERT_TRUE(InventoryBridge.CanCarry(11, 'repair_kit', 1))

    Config.InventoryBridge = 'auto'
    Config.CustomInventory = nil
    ASSERT_TRUE(BridgeManager.InitializeCategory('inventory', nil, true))
    ASSERT_EQ(InventoryBridge.GetName(), 'standalone')
    exports = previousExports
    GetResourceState = previousGetResourceState
end)

TEST('runtime inventory adapter preserves rollback-safe destructive semantics', function()
    local removed = false
    InventoryBridge.SetAdapter({
        name = 'runtime-inventory',
        HasItem = function() return true end,
        CanCarry = function() return true end,
        RemoveItem = function() removed = true; return false end,
        AddItem = function() return false end,
        GetItemCount = function() return 1 end,
    })

    ASSERT_EQ(InventoryBridge.GetName(), 'runtime-inventory')
    ASSERT_TRUE(InventoryBridge.HasItem(7, 'repair_kit', 1))
    ASSERT_FALSE(InventoryBridge.RemoveItem(7, 'repair_kit', 1))
    ASSERT_FALSE(InventoryBridge.AddItem(7, 'repair_kit', 1))
    ASSERT_TRUE(removed)
    InventoryBridge.SetAdapter(nil)
end)
