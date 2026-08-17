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
    if TowerSectors and TowerSectors.Initialize then
        TowerSectors.Initialize(normalized)
    end
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

function TowerRegistry.GetCarriers(id, sectorId)
    local tower = staticById[id]
    if not tower then return {} end
    if type(sectorId) == 'string' and type(tower.sectors) == 'table' then
        for _, sector in ipairs(tower.sectors) do
            if sector.id == sectorId then
                return Utils.DeepCopy(sector.carriers or tower.carriers or {})
            end
        end
    end
    return Utils.DeepCopy(tower.carriers or {})
end

TowerRegistry.GetCarrierIds = TowerRegistry.GetCarriers

function TowerRegistry.GetSectors(id)
    if TowerSectors and TowerSectors.GetForTower then
        return TowerSectors.GetForTower(id)
    end
    local tower = TowerRegistry.Get(id)
    return tower and Utils.DeepCopy(tower.sectors or {}) or {}
end

function TowerRegistry.GetSector(id, sectorId)
    if TowerSectors and TowerSectors.Get then return TowerSectors.Get(id, sectorId) end
    for _, sector in ipairs(TowerRegistry.GetSectors(id)) do
        if sector.id == sectorId then return sector end
    end
    return nil
end

function TowerRegistry.IsInitialized()
    return initialized
end
