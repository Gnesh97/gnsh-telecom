if FrameworkBridge and FrameworkBridge.Register then
    FrameworkBridge.Register('qbox', {
        resource = 'qbx_core',
        priority = 300,
        GetJob = function(_, source)
            if not exports or not exports.qbx_core then return nil end
            local ok, player = pcall(function() return exports.qbx_core:GetPlayer(source) end)
            return ok and player and player.PlayerData and player.PlayerData.job or nil
        end,
        GetStablePlayerId = function(_, source)
            if not exports or not exports.qbx_core then return nil end
            local ok, player = pcall(function() return exports.qbx_core:GetPlayer(source) end)
            return ok and player and player.PlayerData
                and player.PlayerData.citizenid or nil
        end,
    })
end
