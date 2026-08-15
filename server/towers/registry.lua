TowerRegistry = {}

local staticById = {}
local orderedIds = {}
local initialized = false

function TowerRegistry.Init(definitions)
    definitions = definitions or Config.Towers
    local ok, errors, warnings, normalized = TowerValidation.ValidateAll(definitions)
    if not ok then
        return false, errors, warnings
    end

    local nextStatic = {}
    local nextIds = {}
    for _, tower in ipairs(normalized) do
        nextStatic[tower.id] = Utils.DeepCopy(tower)
        nextIds[#nextIds + 1] = tower.id
    end

    staticById = nextStatic
    orderedIds = nextIds
    TowerState.Initialize(normalized)
    initialized = true
    return true, {}, warnings
end

function TowerRegistry.Get(id)
    local tower = staticById[id]
    return tower and Utils.DeepCopy(tower) or nil
end

function TowerRegistry.GetAll()
    local towers = {}
    for _, id in ipairs(orderedIds) do
        towers[#towers + 1] = Utils.DeepCopy(staticById[id])
    end
    return towers
end

function TowerRegistry.Exists(id)
    return type(id) == 'string' and staticById[id] ~= nil
end

function TowerRegistry.Count()
    return #orderedIds
end

function TowerRegistry.GetRuntimeState(id)
    return TowerState.Get(id)
end

function TowerRegistry.IsInitialized()
    return initialized
end
