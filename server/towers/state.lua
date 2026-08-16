TowerState = {}

local runtimeById = {}

function TowerState.Create(tower)
    return {
        towerId = tower.id,
        connectedClients = 0,
        loadPercent = 0,
        effectiveCapacity = tower.capacity and tower.capacity.maximum or 0,
        capacityMultiplier = 1.0,
        congestion = Enums.CongestionState.NORMAL,
        capacityEffects = {},
        failureEffects = {
            signalMultiplier = 1.0,
            capacityMultiplier = 1.0,
            coverageMultiplier = 1.0,
            serviceFailures = {},
            backhaulStatus = nil,
            healthDelta = 0,
            activeFailures = {},
        },
        health = tower.hardware and tower.hardware.health or 100,
        state = tower.state or Enums.TowerState.OPERATIONAL,
        activeFailures = {},
        backhaulStatus = tower.backhaul
            and tower.backhaul.status
            or Enums.BackhaulState.ONLINE,
        updatedAt = 0,
    }
end

function TowerState.Initialize(towers)
    local nextRuntime = {}
    for _, tower in ipairs(towers or {}) do
        nextRuntime[tower.id] = TowerState.Create(tower)
    end
    runtimeById = nextRuntime
end

function TowerState.Get(id)
    local state = runtimeById[id]
    return state and Utils.DeepCopy(state) or nil
end

function TowerState.GetAll()
    local states = {}
    for _, state in pairs(runtimeById) do
        states[#states + 1] = Utils.DeepCopy(state)
    end
    table.sort(states, function(left, right)
        return left.towerId < right.towerId
    end)
    return states
end

function TowerState.Set(id, state)
    if type(id) ~= 'string' or type(state) ~= 'table'
        or state.towerId ~= id or runtimeById[id] == nil then
        return false
    end
    runtimeById[id] = Utils.DeepCopy(state)
    return true
end

function TowerState.Update(id, patch)
    local current = runtimeById[id]
    if not current or type(patch) ~= 'table' then return false end

    local nextState = Utils.DeepCopy(current)
    for key, value in pairs(patch) do
        nextState[key] = Utils.DeepCopy(value)
    end
    return TowerState.Set(id, nextState)
end

function TowerState.Count()
    local count = 0
    for _ in pairs(runtimeById) do count = count + 1 end
    return count
end
