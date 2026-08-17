local function withFrameworkEnvironment(started, mockExports, callback)
    local previousGetResourceState = GetResourceState
    local previousExports = exports

    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end
    exports = mockExports

    local ok, err = pcall(callback)
    GetResourceState = previousGetResourceState
    exports = previousExports
    if not ok then error(err, 0) end
end

local function detectStandalone()
    Config.Framework = 'auto'
    Config.CustomFramework = nil
    local detected = FrameworkBridge.Detect()
    ASSERT_EQ(detected, 'standalone')
end

TEST('framework configuration validates supported and custom modes', function()
    local previousFramework = Config.Framework
    local previousCustom = Config.CustomFramework

    Config.Framework = 'unknown'
    local valid = Config.Validate()
    ASSERT_FALSE(valid)

    Config.Framework = 'custom'
    Config.CustomFramework = nil
    valid = Config.Validate()
    ASSERT_FALSE(valid)

    Config.Framework = previousFramework
    Config.CustomFramework = previousCustom
    ASSERT_TRUE(Config.Validate())
end)

TEST('framework contract provides safe standalone fallbacks', function()
    withFrameworkEnvironment({}, {}, function()
        detectStandalone()
        ASSERT_EQ(FrameworkBridge.GetPlayer(7), nil)
        ASSERT_EQ(FrameworkBridge.GetStablePlayerId(7), nil)
        ASSERT_EQ(FrameworkBridge.GetJob(7), nil)
        ASSERT_FALSE(FrameworkBridge.HasJob(7, { technician = true }))
        ASSERT_FALSE(FrameworkBridge.IsAdmin(7))
        ASSERT_EQ(FrameworkBridge.GetCharacterName(7), nil)
        ASSERT_FALSE(FrameworkBridge.AddMoney(7, 'cash', 10))
        ASSERT_FALSE(FrameworkBridge.RemoveMoney(7, 'cash', 10))
        ASSERT_FALSE(FrameworkBridge.AddMoney(7, 'cash', math.huge))
        ASSERT_FALSE(FrameworkBridge.RemoveMoney(7, string.rep('x', 33), 10))
    end)
end)

TEST('QBCore satisfies the universal framework contract', function()
    local player = {
        PlayerData = {
            citizenid = 'QBCORE-CHAR-7',
            job = { name = 'technician', grade = { level = 2 } },
            charinfo = { firstname = 'Ada', lastname = 'Lovelace' },
            permission = 'admin',
        },
        Functions = {
            AddMoney = function(account, amount)
                return account == 'cash' and amount == 25
            end,
            RemoveMoney = function(account, amount)
                return account == 'cash' and amount == 10
            end,
        },
    }

    withFrameworkEnvironment({ ['qb-core'] = true }, {
        ['qb-core'] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayer = function(source)
                            ASSERT_EQ(source, 7)
                            return player
                        end,
                        HasPermission = function(source, permission)
                            return source == 7 and permission == 'admin'
                        end,
                    },
                }
            end,
        },
    }, function()
        ASSERT_EQ(FrameworkBridge.Detect(), 'qbcore')
        ASSERT_EQ(FrameworkBridge.GetPlayer(7), player)
        ASSERT_EQ(FrameworkBridge.GetStablePlayerId(7), 'QBCORE-CHAR-7')
        ASSERT_EQ(FrameworkBridge.GetJob(7).name, 'technician')
        ASSERT_TRUE(FrameworkBridge.HasJob(7, 'technician'))
        ASSERT_TRUE(FrameworkBridge.HasJob(7, { technician = true }))
        ASSERT_TRUE(FrameworkBridge.IsAdmin(7))
        ASSERT_EQ(FrameworkBridge.GetCharacterName(7), 'Ada Lovelace')
        ASSERT_TRUE(FrameworkBridge.AddMoney(7, 'cash', 25))
        ASSERT_TRUE(FrameworkBridge.RemoveMoney(7, 'cash', 10))
        ASSERT_TRUE(BridgeManager.HasCapability('framework', 'GetPlayer'))
    end)
end)

TEST('Qbox lifecycle and fallback permissions remain safe', function()
    local player = {
        PlayerData = {
            citizenid = 'QBOX-CHAR-8',
            job = { name = 'telecom', grade = 3 },
            charinfo = { firstname = 'Grace', lastname = 'Hopper' },
            permission = 'god',
        },
        Functions = {
            AddMoney = function(account, amount)
                return account == 'bank' and amount == 30
            end,
            RemoveMoney = function(account, amount)
                return account == 'bank' and amount == 15
            end,
        },
    }

    withFrameworkEnvironment({ qbx_core = true }, {
        qbx_core = {
            GetPlayer = function(_, source)
                ASSERT_EQ(source, 8)
                return player
            end,
        },
    }, function()
        ASSERT_EQ(FrameworkBridge.Detect(), 'qbox')
        ASSERT_EQ(FrameworkBridge.GetPlayer(8), player)
        ASSERT_EQ(FrameworkBridge.GetStablePlayerId(8), 'QBOX-CHAR-8')
        ASSERT_TRUE(FrameworkBridge.HasJob(8, { telecom = true }))
        ASSERT_TRUE(FrameworkBridge.IsAdmin(8))
        ASSERT_EQ(FrameworkBridge.GetCharacterName(8), 'Grace Hopper')
        ASSERT_TRUE(FrameworkBridge.AddMoney(8, 'bank', 30))
        ASSERT_TRUE(FrameworkBridge.RemoveMoney(8, 'bank', 15))
    end)
end)

TEST('ESX lifecycle supports identifier, job and character fallbacks', function()
    local player = {
        identifier = 'ESX-CHAR-9',
        job = { name = 'technician', grade = 1 },
        firstName = 'Katherine',
        lastName = 'Johnson',
        getJob = function() return player.job end,
        getGroup = function() return 'admin' end,
        addAccountMoney = function(account, amount)
            return account == 'bank' and amount == 40
        end,
        removeAccountMoney = function(account, amount)
            return account == 'bank' and amount == 20
        end,
    }

    withFrameworkEnvironment({ es_extended = true }, {
        es_extended = {
            getSharedObject = function()
                return {
                    GetPlayerFromId = function(source)
                        ASSERT_EQ(source, 9)
                        return player
                    end,
                }
            end,
        },
    }, function()
        ASSERT_EQ(FrameworkBridge.Detect(), 'esx')
        ASSERT_EQ(FrameworkBridge.GetPlayer(9), player)
        ASSERT_EQ(FrameworkBridge.GetStablePlayerId(9), 'ESX-CHAR-9')
        ASSERT_TRUE(FrameworkBridge.HasJob(9, 'technician'))
        ASSERT_TRUE(FrameworkBridge.IsAdmin(9))
        ASSERT_EQ(FrameworkBridge.GetCharacterName(9), 'Katherine Johnson')
        ASSERT_TRUE(FrameworkBridge.AddMoney(9, 'bank', 40))
        ASSERT_TRUE(FrameworkBridge.RemoveMoney(9, 'bank', 20))
    end)
end)

TEST('missing framework exports and nil players fail closed', function()
    withFrameworkEnvironment({ ['qb-core'] = true }, {
        ['qb-core'] = {},
    }, function()
        ASSERT_EQ(FrameworkBridge.Detect(), 'qbcore')
        ASSERT_EQ(FrameworkBridge.GetPlayer(7), nil)
        ASSERT_EQ(FrameworkBridge.GetJob(7), nil)
        ASSERT_FALSE(FrameworkBridge.HasJob(7, { technician = true }))
        ASSERT_FALSE(FrameworkBridge.IsAdmin(7))
        ASSERT_EQ(FrameworkBridge.GetCharacterName(7), nil)
        ASSERT_FALSE(FrameworkBridge.AddMoney(7, 'cash', 1))
        ASSERT_FALSE(FrameworkBridge.RemoveMoney(7, 'cash', 1))
    end)
end)

TEST('custom framework adapter follows the same contract', function()
    local player = { id = 'custom-player-1' }
    Config.Framework = 'custom'
    Config.CustomFramework = {
        GetPlayer = function(source)
            ASSERT_EQ(source, 11)
            return player
        end,
        GetStablePlayerId = function(source)
            return 'CUSTOM-CHAR-' .. tostring(source)
        end,
        GetJob = function()
            return { name = 'telecom', grade = 4 }
        end,
        IsAdmin = function(source)
            return source == 11
        end,
        GetCharacterName = function()
            return 'Custom Operator'
        end,
        AddMoney = function(_, account, amount)
            return account == 'cash' and amount == 50
        end,
        RemoveMoney = function(_, account, amount)
            return account == 'cash' and amount == 25
        end,
    }

    local previousGetResourceState = GetResourceState
    GetResourceState = function() return 'stopped' end
    ASSERT_EQ(FrameworkBridge.Detect(), 'custom')
    ASSERT_EQ(FrameworkBridge.GetPlayer(11), player)
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(11), 'CUSTOM-CHAR-11')
    ASSERT_TRUE(FrameworkBridge.HasJob(11, { telecom = true }))
    ASSERT_TRUE(FrameworkBridge.IsAdmin(11))
    ASSERT_EQ(FrameworkBridge.GetCharacterName(11), 'Custom Operator')
    ASSERT_TRUE(FrameworkBridge.AddMoney(11, 'cash', 50))
    ASSERT_TRUE(FrameworkBridge.RemoveMoney(11, 'cash', 25))
    Config.Framework = 'auto'
    Config.CustomFramework = nil
    GetResourceState = previousGetResourceState
    ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')
end)

TEST('framework provider restart returns to standalone safely', function()
    local started = { ['qb-core'] = true }
    local previousGetResourceState = GetResourceState
    local previousExports = exports
    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end
    exports = {
        ['qb-core'] = {
            GetCoreObject = function()
                return { Functions = { GetPlayer = function() return nil end } }
            end,
        },
    }

    ASSERT_EQ(FrameworkBridge.Detect(), 'qbcore')
    started['qb-core'] = nil
    ASSERT_TRUE(BridgeManager.HandleResourceStop('qb-core'))
    ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')
    ASSERT_EQ(FrameworkBridge.GetPlayer(7), nil)

    exports = previousExports
    GetResourceState = previousGetResourceState
end)
