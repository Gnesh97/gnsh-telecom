DispatchBridge = DispatchBridge or {}

local adapter

function DispatchBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end
    adapter = value
    return true
end

function DispatchBridge.Alert(payload)
    if adapter and type(adapter.Alert) == 'function' then
        local ok, result = pcall(adapter.Alert, payload)
        if ok then return result ~= false end
        return false
    end
    if Log and Log.warn then Log.warn('dispatch alert', payload) end
    return false, 'dispatch_adapter_unavailable'
end
