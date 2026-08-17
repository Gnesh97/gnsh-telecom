BackhaulRegions = BackhaulRegions or {}

local regionsById = {}
local orderedIds = {}
local regionByTower = {}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

local function stringList(value)
    local result, seen = {}, {}
    if type(value) ~= 'table' then return result end
    for _, item in ipairs(value) do
        if validId(item) and not seen[item] then
            seen[item] = true
            result[#result + 1] = item
        end
    end
    table.sort(result)
    return result
end

local function definitionsList(definitions)
    if type(definitions) ~= 'table' then return {} end
    if #definitions > 0 then return definitions end
    local result = {}
    for id, definition in pairs(definitions) do
        if type(definition) == 'table' then
            local value = copy(definition)
            value.id = value.id or id
            result[#result + 1] = value
        end
    end
    table.sort(result, function(left, right) return tostring(left.id) < tostring(right.id) end)
    return result
end

local function normalize(definition)
    if type(definition) ~= 'table' or not validId(definition.id) then return nil end
    local popNode = definition.popNode or definition.regionalPop or definition.pop
    if popNode ~= nil and not validId(popNode) then popNode = nil end
    return {
        id = definition.id,
        popNode = popNode,
        towerIds = stringList(definition.towerIds or definition.towers),
        nodeIds = stringList(definition.nodeIds),
        coreNodes = stringList(definition.coreNodes),
        nodes = copy(definition.nodes or {}),
        metadata = copy(definition.metadata or {}),
    }
end

function BackhaulRegions.Initialize(definitions)
    local nextRegions, nextOrder, nextByTower = {}, {}, {}
    for _, definition in ipairs(definitionsList(definitions)) do
        local region = normalize(definition)
        if region and not nextRegions[region.id] then
            nextRegions[region.id] = region
            nextOrder[#nextOrder + 1] = region.id
            for _, towerId in ipairs(region.towerIds) do
                nextByTower[towerId] = region.id
            end
        end
    end

    local configuredTowerRegions = Config and Config.Backhaul and Config.Backhaul.towerRegions
    if type(configuredTowerRegions) == 'table' then
        for towerId, regionId in pairs(configuredTowerRegions) do
            if validId(towerId) and validId(regionId) then
                if not nextRegions[regionId] then
                    nextRegions[regionId] = {
                        id = regionId,
                        popNode = nil,
                        towerIds = {},
                        nodeIds = {},
                        coreNodes = {},
                        nodes = {},
                        metadata = {},
                    }
                    nextOrder[#nextOrder + 1] = regionId
                end
                nextByTower[towerId] = regionId
                local region = nextRegions[regionId]
                local exists = false
                for _, value in ipairs(region.towerIds) do
                    if value == towerId then exists = true break end
                end
                if not exists then region.towerIds[#region.towerIds + 1] = towerId end
            end
        end
    end

    for _, region in pairs(nextRegions) do table.sort(region.towerIds) end
    table.sort(nextOrder)
    regionsById = nextRegions
    orderedIds = nextOrder
    regionByTower = nextByTower
    return true, #orderedIds
end

function BackhaulRegions.Get(id)
    return regionsById[id] and copy(regionsById[id]) or nil
end

function BackhaulRegions.GetAll()
    local result = {}
    for _, id in ipairs(orderedIds) do result[#result + 1] = copy(regionsById[id]) end
    return result
end

function BackhaulRegions.GetForTower(towerId)
    local regionId = regionByTower[towerId]
    return regionId and copy(regionsById[regionId]) or nil
end

function BackhaulRegions.GetForNode(nodeId)
    if not validId(nodeId) then return nil end
    for _, id in ipairs(orderedIds) do
        local region = regionsById[id]
        if region.popNode == nodeId then return copy(region) end
        for _, value in ipairs(region.nodeIds) do
            if value == nodeId then return copy(region) end
        end
        for _, node in ipairs(region.nodes) do
            if type(node) == 'table' and node.id == nodeId then return copy(region) end
        end
    end
    return nil
end

function BackhaulRegions.Reset()
    regionsById = {}
    orderedIds = {}
    regionByTower = {}
end
