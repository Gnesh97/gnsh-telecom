CarrierSelection = CarrierSelection or {}

local function copy(value)
    if CarrierRegistry and CarrierRegistry.Get and type(value) == 'table' then
        if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

local function enabled()
    return Config and Config.Features and Config.Features.Carriers == true
end

local function towerOf(value)
    if type(value) ~= 'table' then return nil end
    local tower = type(value.tower) == 'table' and value.tower or value
    if type(tower.id) ~= 'string' and type(value.towerId) == 'string'
        and TowerRegistry and TowerRegistry.Get then
        tower = TowerRegistry.Get(value.towerId) or tower
    end
    return tower
end

local function sectorOf(value, tower)
    if type(value) == 'table' and type(value.sector) == 'table' then
        return value.sector
    end
    if tower and type(tower.sector) == 'table' then return tower.sector end
    if tower and value and value.sectorId and TowerRegistry and TowerRegistry.GetSector then
        return TowerRegistry.GetSector(tower.id, value.sectorId)
    end
    return nil
end

local function listEntries(value)
    if type(value) ~= 'table' then return {} end
    local result = {}
    if #value > 0 then
        for _, entry in ipairs(value) do result[#result + 1] = entry end
    else
        for id, enabledValue in pairs(value) do
            if enabledValue then result[#result + 1] = id end
        end
        table.sort(result, function(left, right) return tostring(left) < tostring(right) end)
    end
    return result
end

local function carrierId(entry)
    if type(entry) == 'table' then return entry.id end
    return entry
end

local function declaredCarriers(candidate, tower, sector, options)
    local sources = {}
    if options and options.carrierIds ~= nil then
        sources[#sources + 1] = options.carrierIds
    end
    if candidate and candidate.carriers ~= nil then
        sources[#sources + 1] = candidate.carriers
    end
    if sector and sector.carriers ~= nil then
        sources[#sources + 1] = sector.carriers
    end
    if tower and tower.carriers ~= nil then
        sources[#sources + 1] = tower.carriers
    end
    for _, source in ipairs(sources) do
        local entries = listEntries(source)
        if #entries > 0 then return entries, true end
    end
    return {}, false
end

local function mapBlocks(map, id)
    if type(map) ~= 'table' then return false end
    if map[id] ~= nil then return map[id] == true end
    for _, value in ipairs(map) do
        if value == id then return true end
    end
    return false
end

local function allowedByMap(map, id)
    if type(map) ~= 'table' then return true end
    if map[id] ~= nil then return map[id] == true end
    for _, value in ipairs(map) do
        if value == id then return true end
    end
    return false
end

local function supportsTechnology(carrier, technology)
    if technology == nil then return true end
    for _, supported in ipairs(carrier.technologies or {}) do
        if supported == technology then return true end
    end
    return false
end

local function sortCarriers(left, right)
    local leftPriority = tonumber(left.priority) or 0
    local rightPriority = tonumber(right.priority) or 0
    if leftPriority ~= rightPriority then return leftPriority > rightPriority end
    return left.id < right.id
end

function CarrierSelection.Resolve(candidate, options)
    options = type(options) == 'table' and options or {}
    if not enabled() then
        return {
            available = true,
            carrierId = nil,
            carrier = nil,
            priority = 0,
            reason = 'disabled',
        }
    end

    if not CarrierRegistry or not CarrierRegistry.GetAll then
        return { available = false, reason = 'no_carrier', priority = 0 }
    end

    local tower = towerOf(candidate)
    local sector = sectorOf(candidate, tower)
    local requested = options.preferredCarrier or options.requestedCarrier
    local declared, hasDeclared = declaredCarriers(candidate, tower, sector, options)
    local pool, invalidCount, knownCount = {}, 0, 0
    local seen = {}

    if hasDeclared then
        for _, entry in ipairs(declared) do
            local id = carrierId(entry)
            local carrier = CarrierRegistry.Get(id)
            if carrier then
                knownCount = knownCount + 1
                if not seen[carrier.id] then
                    seen[carrier.id] = true
                    pool[#pool + 1] = carrier
                end
            else
                invalidCount = invalidCount + 1
            end
        end
        if knownCount == 0 then
            pool = CarrierRegistry.GetAll()
            for _, carrier in ipairs(pool) do seen[carrier.id] = true end
        end
    else
        pool = CarrierRegistry.GetAll()
        for _, carrier in ipairs(pool) do seen[carrier.id] = true end
    end

    local eligible = {}
    local unavailable = false
    local incompatible = false
    for _, carrier in ipairs(pool) do
        if not CarrierRegistry.IsAvailable(carrier.id)
            or mapBlocks(options.failedCarriers, carrier.id)
            or mapBlocks(options.carrierFailures, carrier.id)
            or not allowedByMap(options.availableCarriers, carrier.id) then
            unavailable = true
        elseif not supportsTechnology(carrier, options.technology) then
            incompatible = true
        else
            eligible[#eligible + 1] = carrier
        end
    end

    if #eligible == 0 then
        local reason = 'no_carrier'
        if hasDeclared and knownCount == 0 then
            reason = invalidCount > 0 and 'invalid_carrier' or reason
        elseif hasDeclared and unavailable then
            reason = 'unavailable_carrier'
        elseif hasDeclared and incompatible then
            reason = 'incompatible_carrier'
        end
        return {
            available = false,
            carrierId = nil,
            carrier = nil,
            priority = 0,
            reason = reason,
            invalidCount = invalidCount,
        }
    end

    table.sort(eligible, sortCarriers)
    local selected = eligible[1]
    if requested then
        for _, carrier in ipairs(eligible) do
            if carrier.id == requested then selected = carrier break end
        end
    end

    local usedFallback = hasDeclared and knownCount == 0
    return {
        available = true,
        carrierId = selected.id,
        carrier = copy(selected),
        priority = tonumber(selected.priority) or 0,
        reason = usedFallback and 'fallback' or 'selected',
        invalidCount = invalidCount,
    }
end

CarrierSelection.ResolveCarrier = CarrierSelection.Resolve
