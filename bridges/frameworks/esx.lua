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
    })
end
