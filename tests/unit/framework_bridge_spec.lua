TEST('framework bridge follows supported resource lifecycle changes', function()
    local previousGetResourceState = GetResourceState
    local started = {}

    GetResourceState = function(name)
        if started[name] then return 'started' end
        return 'stopped'
    end

    started['qb-core'] = true
    ASSERT_EQ(FrameworkBridge.Detect(), 'qbcore')

    started['qb-core'] = nil
    started.qbx_core = true
    ASSERT_EQ(FrameworkBridge.Detect(), 'qbox')

    started.qbx_core = nil
    started.es_extended = true
    ASSERT_EQ(FrameworkBridge.Detect(), 'esx')

    started.es_extended = nil
    ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')

    GetResourceState = function()
        error('resource state unavailable')
    end
    ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')

    GetResourceState = previousGetResourceState
end)

TEST('framework bridges expose stable player identities', function()
    local previousGetResourceState = GetResourceState
    local previousGetPlayerIdentifierByType = rawget(_G, 'GetPlayerIdentifierByType')
    local previousExports = exports
    local started = {}

    GetResourceState = function(name)
        return started[name] and 'started' or 'stopped'
    end

    GetPlayerIdentifierByType = function(source, identifierType)
        return identifierType .. ':stable-' .. tostring(source)
    end
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(7), 'license:stable-7')

    exports = {
        ['qb-core'] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayer = function()
                            return { PlayerData = { citizenid = 'QBCORE-CHAR-7' } }
                        end,
                    },
                }
            end,
        },
    }
    started['qb-core'] = true
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(7), 'QBCORE-CHAR-7')

    exports = {
        qbx_core = {
            GetPlayer = function(_, source)
                ASSERT_EQ(source, 7)
                return { PlayerData = { citizenid = 'QBOX-CHAR-7' } }
            end,
        },
    }
    started['qb-core'] = nil
    started.qbx_core = true
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(7), 'QBOX-CHAR-7')

    exports = {
        es_extended = {
            getSharedObject = function()
                return {
                    GetPlayerFromId = function()
                        return { identifier = 'ESX-CHAR-7' }
                    end,
                }
            end,
        },
    }
    started.qbx_core = nil
    started.es_extended = true
    ASSERT_EQ(FrameworkBridge.GetStablePlayerId(7), 'ESX-CHAR-7')

    started.es_extended = nil
    exports = previousExports
    GetPlayerIdentifierByType = previousGetPlayerIdentifierByType
    GetResourceState = previousGetResourceState
end)
