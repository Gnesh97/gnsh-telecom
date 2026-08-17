TelecomNui = TelecomNui or {}

local focused = false

local function setFocus(value)
    focused = value == true
    if type(SetNuiFocus) == 'function' then SetNuiFocus(focused, focused) end
end

function TelecomNui.Open(name, payload)
    if type(SendNUIMessage) ~= 'function' then return false, 'nui_unavailable' end
    SendNUIMessage({ action = 'open', view = name, data = Utils.DeepCopy(payload or {}) })
    setFocus(true)
    return true
end

function TelecomNui.Close(name)
    if type(SendNUIMessage) == 'function' then
        SendNUIMessage({ action = 'close', view = name })
    end
    setFocus(false)
    return true
end

function TelecomNui.IsFocused()
    return focused
end

if type(RegisterNUICallback) == 'function' then
    RegisterNUICallback('close', function(_, callback)
        if NocClient and NocClient.Close then
            NocClient.Close()
        else
            TelecomNui.Close('noc')
        end
        if callback then callback({ ok = true }) end
    end)
end
