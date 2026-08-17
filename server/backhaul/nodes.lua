BackhaulNodes = BackhaulNodes or {}

local nodesById = {}
local orderedIds = {}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

local function validType(value)
    local types = Enums and Enums.BackhaulNodeType or {
        TOWER = 'TOWER',
        AGGREGATION = 'AGGREGATION',
        REGIONAL_POP = 'REGIONAL_POP',
        CORE = 'CORE',
    }
    return value == types.TOWER or value == types.AGGREGATION
        or value == types.REGIONAL_POP or value == types.CORE
end

function BackhaulNodes.Initialize(definitions)
    local nextNodes = {}
    local nextOrder = {}
    for _, definition in ipairs(definitions or {}) do
        local nodeType = type(definition) == 'table'
            and (definition.type or 'AGGREGATION') or nil
        if type(definition) == 'table' and validId(definition.id)
            and validType(nodeType) and not nextNodes[definition.id] then
            nextNodes[definition.id] = {
                id = definition.id,
                type = nodeType,
                state = definition.state or Enums.BackhaulNodeState.ONLINE,
                metadata = copy(definition.metadata or {}),
            }
            nextOrder[#nextOrder + 1] = definition.id
        end
    end
    table.sort(nextOrder)
    nodesById = nextNodes
    orderedIds = nextOrder
    return true, #orderedIds
end

function BackhaulNodes.Get(id)
    return nodesById[id] and copy(nodesById[id]) or nil
end

function BackhaulNodes.GetAll()
    local result = {}
    for _, id in ipairs(orderedIds) do result[#result + 1] = copy(nodesById[id]) end
    return result
end

function BackhaulNodes.GetByType(nodeType)
    local result = {}
    for _, id in ipairs(orderedIds) do
        if nodesById[id].type == nodeType then result[#result + 1] = copy(nodesById[id]) end
    end
    return result
end

function BackhaulNodes.Exists(id)
    return nodesById[id] ~= nil
end

function BackhaulNodes.SetState(id, state)
    if not nodesById[id]
        or state ~= Enums.BackhaulNodeState.ONLINE
        and state ~= Enums.BackhaulNodeState.OFFLINE then
        return false, 'invalid_backhaul_node_state'
    end
    nodesById[id].state = state
    if BackhaulGraph and BackhaulGraph.Invalidate then BackhaulGraph.Invalidate() end
    if BackhaulRouting and BackhaulRouting.RecomputeAffected then
        BackhaulRouting.RecomputeAffected(id)
    end
    return true, copy(nodesById[id])
end

function BackhaulNodes.Reset()
    nodesById = {}
    orderedIds = {}
end
