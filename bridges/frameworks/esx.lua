if FrameworkBridge and FrameworkBridge.Register then
    FrameworkBridge.Register('esx', {
        resource = 'es_extended',
        GetJob = function(source)
            if not exports or not exports.es_extended then return nil end
            local ok, esx = pcall(function() return exports.es_extended:getSharedObject() end)
            if not ok or not esx or not esx.GetPlayerFromId then return nil end
            local player = esx.GetPlayerFromId(source)
            return player and player.getJob and player.getJob() or nil
        end,
        GetStablePlayerId = function(source)
            if not exports or not exports.es_extended then return nil end
            local ok, esx = pcall(function() return exports.es_extended:getSharedObject() end)
            if not ok or not esx or not esx.GetPlayerFromId then return nil end
            local player = esx.GetPlayerFromId(source)
            if not player then return nil end
            if type(player.identifier) == 'string' and player.identifier ~= '' then
                return player.identifier
            end
            if type(player.getIdentifier) == 'function' then
                local identifierOk, identifier = pcall(function()
                    return player:getIdentifier()
                end)
                if identifierOk then return identifier end
            end
            return nil
        end,
    })
end
