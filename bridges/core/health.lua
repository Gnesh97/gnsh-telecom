BridgeHealth = BridgeHealth or {}

BridgeHealth.States = {
    ACTIVE = 'ACTIVE',
    PARTIAL = 'PARTIAL',
    DEGRADED = 'DEGRADED',
    UNAVAILABLE = 'UNAVAILABLE',
    FAILED = 'FAILED',
    OPTIONAL = 'OPTIONAL',
}

function BridgeHealth.IsValid(state)
    for _, known in pairs(BridgeHealth.States) do
        if state == known then return true end
    end
    return false
end

function BridgeHealth.Normalize(value, fallback)
    local state = value
    if type(value) == 'table' then
        state = value.state or value.status
    elseif type(value) == 'boolean' then
        state = value and BridgeHealth.States.ACTIVE or BridgeHealth.States.DEGRADED
    end

    if type(state) == 'string' then
        state = state:upper()
        if BridgeHealth.IsValid(state) then return state end
    end
    return fallback or BridgeHealth.States.DEGRADED
end
