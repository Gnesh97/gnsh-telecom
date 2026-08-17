NocClient = NocClient or {}

function NocClient.Open()
    if not Config or not Config.Features or Config.Features.NOC ~= true then
        return false, 'noc_disabled'
    end
    if type(TriggerServerEvent) ~= 'function' then return false, 'event_api_unavailable' end
    TriggerServerEvent(Constants.Events.NOC_REQUEST)
    return true
end

function NocClient.Close()
    if NocClient.Unsubscribe then NocClient.Unsubscribe() end
    return TelecomNui and TelecomNui.Close and TelecomNui.Close('noc') or false
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.NOC_STATE)
end
if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.NOC_STATE, function(payload)
        if type(payload) ~= 'table' then return end
        if NocClient.HandleState then
            local handled, errorCode = NocClient.HandleState(payload)
            if not handled and type(print) == 'function' then
                print(('[gnsh-telecom] NOC rejected: %s'):format(tostring(errorCode)))
            end
            return
        end
        if payload.ok then
            TelecomNui.Open('noc', payload.snapshot)
        elseif type(print) == 'function' then
            print(('[gnsh-telecom] NOC rejected: %s'):format(tostring(payload.error)))
        end
    end)
    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then NocClient.Close() end
    end)
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('telecomnoc', function()
        NocClient.Open()
    end, false)
end
