if FrameworkBridge and FrameworkBridge.Register then
    FrameworkBridge.Register('qbcore', {
        resource = 'qb-core',
        GetJob = function(source)
            if not exports or not exports['qb-core'] then return nil end
            local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if not ok or not core or not core.Functions then return nil end
            local player = core.Functions.GetPlayer(source)
            return player and player.PlayerData and player.PlayerData.job or nil
        end,
        GetStablePlayerId = function(source)
            if not exports or not exports['qb-core'] then return nil end
            local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if not ok or not core or not core.Functions then return nil end
            local player = core.Functions.GetPlayer(source)
            return player and player.PlayerData and player.PlayerData.citizenid or nil
        end,
    })
end
