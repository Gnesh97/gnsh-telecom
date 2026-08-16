TelecomClientHandover = TelecomClientHandover or {}

local lastTower
local lastChangedAt

function TelecomClientHandover.GetLast()
    return {
        towerId = lastTower,
        changedAt = lastChangedAt,
    }
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.CONNECTION_STATE, function(state)
        if type(state) ~= 'table' then return end
        if lastTower and state.towerId and lastTower ~= state.towerId then
            lastChangedAt = type(GetGameTimer) == 'function' and GetGameTimer() or 0
        end
        lastTower = state.towerId
    end)
    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            lastTower = nil
            lastChangedAt = nil
        end
    end)
end
