BackhaulLinks = BackhaulLinks or {}

local linksById = {}
local orderedIds = {}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

function BackhaulLinks.Initialize(definitions)
    local nextLinks = {}
    local nextOrder = {}
    for _, definition in ipairs(definitions or {}) do
        if type(definition) == 'table'
            and validId(definition.id)
            and validId(definition.from)
            and validId(definition.to)
            and not nextLinks[definition.id] then
            nextLinks[definition.id] = {
                id = definition.id,
                from = definition.from,
                to = definition.to,
                type = definition.type or 'FIBER',
                capacity = tonumber(definition.capacity) or 0,
                health = tonumber(definition.health) or 100,
                state = definition.state or Enums.LinkState.ONLINE,
                bidirectional = definition.bidirectional ~= false,
                metadata = copy(definition.metadata or {}),
            }
            nextOrder[#nextOrder + 1] = definition.id
        end
    end
    table.sort(nextOrder)
    linksById = nextLinks
    orderedIds = nextOrder
    return true, #orderedIds
end

function BackhaulLinks.Get(id)
    return linksById[id] and copy(linksById[id]) or nil
end

function BackhaulLinks.GetAll()
    local result = {}
    for _, id in ipairs(orderedIds) do result[#result + 1] = copy(linksById[id]) end
    return result
end

function BackhaulLinks.SetState(id, state)
    if not linksById[id]
        or state ~= Enums.LinkState.ONLINE
        and state ~= Enums.LinkState.DEGRADED
        and state ~= Enums.LinkState.OFFLINE then
        return false, 'invalid_backhaul_link_state'
    end
    linksById[id].state = state
    if BackhaulGraph and BackhaulGraph.Invalidate then BackhaulGraph.Invalidate() end
    return true, copy(linksById[id])
end

function BackhaulLinks.Reset()
    linksById = {}
    orderedIds = {}
end
