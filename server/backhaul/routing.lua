BackhaulRouting = BackhaulRouting or {}

local cache = {}
local cacheOrder = {}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function enabled()
    return Config and Config.Features and Config.Features.Backhaul == true
end

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and type(value) == 'number' then return value end
    end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function numberConfig(name, fallback, minimum)
    local value = Config and Config.Backhaul and tonumber(Config.Backhaul[name])
    if not value or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    if minimum and value < minimum then value = minimum end
    return math.floor(value)
end

local function cacheTtl()
    return numberConfig('routeCacheTtlMs', 5000, 0)
end

local function hasEntries(value)
    if type(value) ~= 'table' then return false end
    for _ in pairs(value) do return true end
    return false
end

local function configuredTopology()
    local config = Config and Config.Backhaul or {}
    return hasEntries(config.nodes)
        or hasEntries(config.links)
        or hasEntries(config.coreNodes)
        or hasEntries(config.towerNodes)
        or hasEntries(config.regions)
end

local function maxCacheEntries()
    return numberConfig('maxRouteCacheEntries', 256, 1)
end

local function maxRecomputeNodes()
    return numberConfig('maxRecomputeNodes', 128, 1)
end

local function maxPathHops()
    return numberConfig('maxPathHops', 64, 1)
end

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

local function configuredCoreNodes()
    local result, seen = {}, {}
    local configured = Config and Config.Backhaul and Config.Backhaul.coreNodes
    for _, nodeId in ipairs(configured or {}) do
        if validId(nodeId) and not seen[nodeId] then
            seen[nodeId] = true
            result[#result + 1] = nodeId
        end
    end
    if #result == 0 and BackhaulNodes and BackhaulNodes.GetByType then
        for _, node in ipairs(BackhaulNodes.GetByType('CORE')) do
            if validId(node.id) and not seen[node.id] then
                seen[node.id] = true
                result[#result + 1] = node.id
            end
        end
    end
    table.sort(result)
    return result
end

local function towerStart(towerId)
    local mapping = Config and Config.Backhaul and Config.Backhaul.towerNodes
    local mapped = type(mapping) == 'table' and mapping[towerId] or nil
    if validId(mapped) then
        local neighbors = BackhaulGraph and BackhaulGraph.GetNeighbors
            and BackhaulGraph.GetNeighbors(towerId) or {}
        if #neighbors > 0 then return towerId end
        return mapped
    end
    return towerId
end

local function setFrom(value)
    local result = {}
    if type(value) ~= 'table' then return result end
    for key, item in pairs(value) do
        if type(key) == 'number' and validId(item) then result[item] = true end
        if type(key) == 'string' and item == true then result[key] = true end
    end
    return result
end

local function pathScore(path)
    return path.degradedLinks, path.hops, path.key
end

local function isBetter(left, right)
    if not right then return true end
    local leftDegraded, leftHops, leftKey = pathScore(left)
    local rightDegraded, rightHops, rightKey = pathScore(right)
    if leftDegraded ~= rightDegraded then return leftDegraded < rightDegraded end
    if leftHops ~= rightHops then return leftHops < rightHops end
    return leftKey < rightKey
end

local function edgeLess(left, right)
    if left.to == right.to then
        return tostring(left.link and left.link.id) < tostring(right.link and right.link.id)
    end
    return tostring(left.to) < tostring(right.to)
end

local function nodeAvailable(nodeId, excludedNodes)
    if excludedNodes[nodeId] then return false end
    local node = BackhaulNodes and BackhaulNodes.Get and BackhaulNodes.Get(nodeId)
    return node and node.state ~= Enums.BackhaulNodeState.OFFLINE
end

local function linkAvailable(link, excludedLinks)
    if type(link) ~= 'table' or excludedLinks[link.id] then return false end
    if link.state == Enums.LinkState.OFFLINE then return false end
    return link.state == nil or link.state == Enums.LinkState.ONLINE
        or link.state == Enums.LinkState.DEGRADED
end

local function pathKey(nodes)
    return table.concat(nodes, '>')
end

local function makePath(candidate)
    local visitedNodes, visitedLinks = {}, {}
    for _, nodeId in ipairs(candidate.nodes) do visitedNodes[nodeId] = true end
    for _, linkId in ipairs(candidate.links) do visitedLinks[linkId] = true end
    return {
        nodes = copy(candidate.nodes),
        links = copy(candidate.links),
        coreNode = candidate.coreNode,
        hops = candidate.hops,
        degradedLinks = candidate.degradedLinks,
        cost = candidate.degradedLinks * 1000 + candidate.hops,
        visitedNodes = visitedNodes,
        visitedLinks = visitedLinks,
    }
end

local function findPath(startNode, options)
    local excludedNodes = setFrom(options.excludeNodes)
    local excludedLinks = setFrom(options.excludeLinks)
    local targets = {}
    for _, nodeId in ipairs(options.targets or configuredCoreNodes()) do targets[nodeId] = true end
    if not validId(startNode) or not nodeAvailable(startNode, excludedNodes) then return nil end

    local initial = {
        nodeId = startNode,
        nodes = { startNode },
        links = {},
        visited = { [startNode] = true },
        degradedLinks = 0,
        hops = 0,
        key = startNode,
    }
    local open = { initial }
    local bestByNode = { [startNode] = initial }
    local limit = tonumber(options.maxHops) or maxPathHops()

    while #open > 0 do
        table.sort(open, isBetter)
        local current = table.remove(open, 1)
        if targets[current.nodeId] then
            current.coreNode = current.nodeId
            return makePath(current)
        end
        if current.hops < limit then
            local neighbors = BackhaulGraph and BackhaulGraph.GetNeighbors
                and BackhaulGraph.GetNeighbors(current.nodeId) or {}
            table.sort(neighbors, edgeLess)
            for _, neighbor in ipairs(neighbors) do
                local nextNode = neighbor.to
                local link = neighbor.link
                local linkId = type(link) == 'table' and link.id or nil
                if validId(nextNode) and validId(linkId)
                    and not current.visited[nextNode]
                    and nodeAvailable(nextNode, excludedNodes)
                    and linkAvailable(link, excludedLinks) then
                    local degraded = link.state == Enums.LinkState.DEGRADED
                    local candidate = {
                        nodeId = nextNode,
                        nodes = copy(current.nodes),
                        links = copy(current.links),
                        visited = copy(current.visited),
                        degradedLinks = current.degradedLinks + (degraded and 1 or 0),
                        hops = current.hops + 1,
                    }
                    candidate.nodes[#candidate.nodes + 1] = nextNode
                    candidate.links[#candidate.links + 1] = linkId
                    candidate.visited[nextNode] = true
                    candidate.key = pathKey(candidate.nodes)
                    if isBetter(candidate, bestByNode[nextNode]) then
                        bestByNode[nextNode] = candidate
                        open[#open + 1] = candidate
                    end
                end
            end
        end
    end
    return nil
end

local function cacheRemove(towerId)
    cache[towerId] = nil
    for index = #cacheOrder, 1, -1 do
        if cacheOrder[index] == towerId then table.remove(cacheOrder, index) end
    end
end

local function cacheTouch(towerId)
    for index = #cacheOrder, 1, -1 do
        if cacheOrder[index] == towerId then table.remove(cacheOrder, index) end
    end
    cacheOrder[#cacheOrder + 1] = towerId
end

local function cachePut(towerId, ok, result)
    cacheRemove(towerId)
    cache[towerId] = { at = now(), ok = ok, result = copy(result) }
    cacheTouch(towerId)
    while #cacheOrder > maxCacheEntries() do
        local oldest = table.remove(cacheOrder, 1)
        cache[oldest] = nil
    end
end

local function cacheGet(towerId)
    local entry = cache[towerId]
    if not entry then return nil end
    if now() - entry.at > cacheTtl() then
        cacheRemove(towerId)
        return nil
    end
    cacheTouch(towerId)
    return entry.ok, copy(entry.result)
end

local function computeRoute(towerId, options)
    if not enabled() then
        return true, { towerId = towerId, status = Enums.BackhaulState.ONLINE, disabled = true }
    end
    if not configuredTopology() then
        return true, { towerId = towerId, status = Enums.BackhaulState.ONLINE, implicit = true }
    end
    local runtime = TowerRegistry and TowerRegistry.GetRuntimeState
        and TowerRegistry.GetRuntimeState(towerId)
    if runtime and runtime.failureEffects
        and runtime.failureEffects.backhaulStatus == Enums.BackhaulState.OFFLINE then
        return false, {
            towerId = towerId,
            status = Enums.BackhaulState.OFFLINE,
            error = 'tower_backhaul_failure',
        }
    end

    local startNode = towerStart(towerId)
    local primary = findPath(startNode, options)
    if not primary then
        return false, {
            towerId = towerId,
            status = Enums.BackhaulState.OFFLINE,
            error = 'route_unavailable',
        }
    end

    local result = {
        towerId = towerId,
        regionId = BackhaulRegions and BackhaulRegions.GetForTower
            and (BackhaulRegions.GetForTower(towerId) or {}).id or nil,
        status = primary.degradedLinks > 0
            and Enums.BackhaulState.DEGRADED or Enums.BackhaulState.ONLINE,
        primary = primary,
        backup = nil,
    }
    if options.skipBackup ~= true then
        local backupOptions = {
            excludeNodes = copy(options.excludeNodes or {}),
            excludeLinks = setFrom(options.excludeLinks),
            maxHops = options.maxHops,
            targets = options.targets,
        }
        for _, linkId in ipairs(primary.links) do backupOptions.excludeLinks[linkId] = true end
        local backup = findPath(startNode, backupOptions)
        if backup then result.backup = backup end
    end
    return true, result
end

function BackhaulRouting.FindRoute(towerId, options)
    if not validId(towerId) then return false, { status = Enums.BackhaulState.OFFLINE, error = 'tower_required' } end
    options = type(options) == 'table' and options or {}
    local cacheable = next(options) == nil
    if cacheable then
        local cachedOk, cachedResult = cacheGet(towerId)
        if cachedOk ~= nil then return cachedOk, cachedResult end
    end
    local ok, result = computeRoute(towerId, options)
    if cacheable then cachePut(towerId, ok, result) end
    return ok, copy(result)
end

function BackhaulRouting.GetTowerStatus(towerId)
    local ok, route = BackhaulRouting.FindRoute(towerId)
    return ok and route.status or Enums.BackhaulState.OFFLINE
end

local function regionTowerIds(region)
    local result, seen = {}, {}
    for _, towerId in ipairs(region and region.towerIds or {}) do
        if validId(towerId) and not seen[towerId] then
            seen[towerId] = true
            result[#result + 1] = towerId
        end
    end
    if #result == 0 and Config.Backhaul and type(Config.Backhaul.towerRegions) == 'table' then
        for towerId, regionId in pairs(Config.Backhaul.towerRegions) do
            if regionId == region.id and validId(towerId) and not seen[towerId] then
                seen[towerId] = true
                result[#result + 1] = towerId
            end
        end
    end
    table.sort(result)
    local limit = numberConfig('maxRegionalTowers', 128, 1)
    while #result > limit do result[#result] = nil end
    return result
end

function BackhaulRouting.GetRegionalStatus(regionId)
    if not validId(regionId) then return false, 'region_required' end
    local region = BackhaulRegions and BackhaulRegions.Get and BackhaulRegions.Get(regionId)
    if not region then return false, 'region_not_found' end
    local towerStatuses, onlineCount, degradedCount, offlineCount = {}, 0, 0, 0
    for _, towerId in ipairs(regionTowerIds(region)) do
        local status = BackhaulRouting.GetTowerStatus(towerId)
        towerStatuses[towerId] = status
        if status == Enums.BackhaulState.ONLINE then onlineCount = onlineCount + 1
        elseif status == Enums.BackhaulState.DEGRADED then degradedCount = degradedCount + 1
        else offlineCount = offlineCount + 1 end
    end
    local total = onlineCount + degradedCount + offlineCount
    local status = total == 0 and Enums.BackhaulState.OFFLINE
        or offlineCount == total and Enums.BackhaulState.OFFLINE
        or (offlineCount > 0 or degradedCount > 0) and Enums.BackhaulState.DEGRADED
        or Enums.BackhaulState.ONLINE
    return true, {
        id = region.id,
        regionId = region.id,
        popNode = region.popNode,
        status = status,
        towerStatuses = towerStatuses,
        onlineCount = onlineCount,
        degradedCount = degradedCount,
        offlineCount = offlineCount,
        towerCount = total,
    }
end

function BackhaulRouting.GetRegionalSnapshot()
    local result = {}
    for _, region in ipairs(BackhaulRegions and BackhaulRegions.GetAll and BackhaulRegions.GetAll() or {}) do
        local ok, status = BackhaulRouting.GetRegionalStatus(region.id)
        if ok then result[region.id] = status end
    end
    return result
end

local function routeTouches(route, rootNodeId, rootLinkId, regionId)
    if type(route) ~= 'table' then return false end
    if regionId and route.regionId == regionId then return true end
    local function touchesPath(path)
        if type(path) ~= 'table' then return false end
        if path.visitedNodes and path.visitedNodes[rootNodeId] then return true end
        if rootLinkId and path.visitedLinks and path.visitedLinks[rootLinkId] then return true end
        return false
    end
    return touchesPath(route.primary) or touchesPath(route.backup)
end

function BackhaulRouting.RecomputeAffected(rootNodeId)
    if type(rootNodeId) == 'table' then rootNodeId = rootNodeId.rootNodeId end
    if not validId(rootNodeId) then return false, 'root_node_required' end
    local rootLink = BackhaulLinks and BackhaulLinks.Get and BackhaulLinks.Get(rootNodeId)
    local rootRegion = BackhaulRegions and BackhaulRegions.Get and BackhaulRegions.Get(rootNodeId)
    local invalidated = {}
    for towerId, entry in pairs(cache) do
        if entry.ok == false
            or routeTouches(entry.result, rootNodeId, rootLink and rootLink.id, rootRegion and rootRegion.id) then
            invalidated[#invalidated + 1] = towerId
        end
    end
    table.sort(invalidated)
    for _, towerId in ipairs(invalidated) do cacheRemove(towerId) end

    local recomputed = 0
    local limit = maxRecomputeNodes()
    for index = 1, math.min(#invalidated, limit) do
        local towerId = invalidated[index]
        local ok, result = BackhaulRouting.FindRoute(towerId)
        if ok or result then recomputed = recomputed + 1 end
    end
    return true, {
        rootNodeId = rootNodeId,
        invalidated = #invalidated,
        recomputed = recomputed,
        bounded = #invalidated > limit or recomputed <= limit,
    }
end

function BackhaulRouting.Initialize()
    cache = {}
    cacheOrder = {}
    return true
end

function BackhaulRouting.Invalidate(rootNodeId)
    if rootNodeId then return BackhaulRouting.RecomputeAffected(rootNodeId) end
    cache = {}
    cacheOrder = {}
    return true
end

function BackhaulRouting.GetSnapshot()
    local result = {}
    for _, tower in ipairs(TowerRegistry.GetAll and TowerRegistry.GetAll() or {}) do
        result[tower.id] = BackhaulRouting.GetTowerStatus(tower.id)
    end
    return result
end
