CarrierRegistry = CarrierRegistry or {}

local definitionsById = {}
local orderedIds = {}
local availabilityById = {}

local function copy(value)
    if Carriers and Carriers.Copy then return Carriers.Copy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

local function rebuildOrder()
    orderedIds = {}
    for id in pairs(definitionsById) do orderedIds[#orderedIds + 1] = id end
    table.sort(orderedIds)
end

function CarrierRegistry.Initialize(definitions)
    definitions = definitions
        or (Config and Config.Carriers)
        or {}
    local ok, errors, normalized = Carriers.NormalizeAll(definitions)
    if not ok then return false, errors, {} end

    local nextDefinitions, nextAvailability = {}, {}
    for _, carrier in ipairs(normalized) do
        nextDefinitions[carrier.id] = copy(carrier)
        nextAvailability[carrier.id] = true
    end

    definitionsById = nextDefinitions
    availabilityById = nextAvailability
    rebuildOrder()
    return true, {}, {}
end

function CarrierRegistry.Register(definition)
    local carrier, errorMessage = Carriers.Normalize(definition)
    if not carrier then return false, errorMessage end
    if definitionsById[carrier.id] then return false, 'carrier_exists' end

    definitionsById[carrier.id] = copy(carrier)
    availabilityById[carrier.id] = true
    rebuildOrder()
    return true, copy(carrier)
end

function CarrierRegistry.Get(id)
    local carrier = definitionsById[id]
    if not carrier then return nil end
    local result = copy(carrier)
    result.available = availabilityById[id] ~= false
    return result
end

function CarrierRegistry.GetAll()
    local carriers = {}
    for _, id in ipairs(orderedIds) do carriers[#carriers + 1] = CarrierRegistry.Get(id) end
    return carriers
end

function CarrierRegistry.GetAvailable()
    local carriers = {}
    for _, carrier in ipairs(CarrierRegistry.GetAll()) do
        if carrier.available then carriers[#carriers + 1] = carrier end
    end
    return carriers
end

function CarrierRegistry.Exists(id)
    return type(id) == 'string' and definitionsById[id] ~= nil
end

function CarrierRegistry.Count()
    return #orderedIds
end

function CarrierRegistry.IsAvailable(id)
    return CarrierRegistry.Exists(id) and availabilityById[id] ~= false
end

function CarrierRegistry.SetAvailability(id, available)
    if not CarrierRegistry.Exists(id) or type(available) ~= 'boolean' then return false end
    availabilityById[id] = available
    return true
end

CarrierRegistry.SetAvailable = CarrierRegistry.SetAvailability

function CarrierRegistry.GetForTower(tower, sectorId)
    if type(tower) ~= 'table' then return {} end
    local source = tower
    if sectorId and type(tower.sectors) == 'table' then
        for _, sector in ipairs(tower.sectors) do
            if sector.id == sectorId then source = sector break end
        end
    end
    local ids = type(source.carriers) == 'table' and source.carriers or {}
    local result = {}
    for _, entry in ipairs(ids) do
        local id = type(entry) == 'table' and entry.id or entry
        local carrier = CarrierRegistry.Get(id)
        if carrier then result[#result + 1] = carrier end
    end
    return result
end

function CarrierRegistry.Reset()
    definitionsById = {}
    orderedIds = {}
    availabilityById = {}
end
