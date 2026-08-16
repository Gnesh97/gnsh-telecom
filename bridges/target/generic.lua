TargetBridge = TargetBridge or {}

local adapter

function TargetBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end
    adapter = value
    return true
end

function TargetBridge.AddTowerTarget(tower, callbacks)
    if adapter and type(adapter.AddTowerTarget) == 'function' then
        return adapter.AddTowerTarget(tower, callbacks)
    end
    return false, 'target_adapter_unavailable'
end

function TargetBridge.RemoveTowerTarget(towerId)
    if adapter and type(adapter.RemoveTowerTarget) == 'function' then
        return adapter.RemoveTowerTarget(towerId)
    end
    return false, 'target_adapter_unavailable'
end
