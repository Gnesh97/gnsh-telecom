OutagePropagation = OutagePropagation or {}

local impactsById = {}
local sequence = 0

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[copy(key)] = copy(nested) end
    return result
end

local function now()
    if type(GetGameTimer) == 'function' then
        local ok, value = pcall(GetGameTimer)
        if ok and type(value) == 'number' then return value end
    end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

local function maximumTowers()
    local configured = Config and Config.Backhaul and tonumber(Config.Backhaul.maxRegionalTowers)
    if not configured or configured < 1 then return 128 end
    return math.floor(configured)
end

local function addVisited(set, value)
    if validId(value) then set[value] = true end
end

local function sortedSet(set)
    local result = {}
    for value in pairs(set or {}) do result[#result + 1] = value end
    table.sort(result)
    return result
end

local function rootField(rootFailure, name)
    if type(rootFailure) ~= 'table' then return nil end
    if validId(rootFailure[name]) then return rootFailure[name] end
    local metadata = rootFailure.metadata or rootFailure.details
    if type(metadata) == 'table' and validId(metadata[name]) then return metadata[name] end
    return nil
end

local function rootFailureId(rootFailure)
    local id = type(rootFailure) == 'table'
        and (rootFailure.id or rootFailure.failureId or rootFailure.rootFailureId)
        or nil
    if validId(id) then return id end
    sequence = sequence + 1
    return ('OUTAGE-%06d'):format(sequence)
end

local function pathContains(path, nodeId, linkId)
    if type(path) ~= 'table' then return false end
    if nodeId and path.visitedNodes and path.visitedNodes[nodeId] then return true end
    if linkId and path.visitedLinks and path.visitedLinks[linkId] then return true end
    if nodeId then
        for _, value in ipairs(path.nodes or {}) do
            if value == nodeId then return true end
        end
    end
    if linkId then
        for _, value in ipairs(path.links or {}) do
            if value == linkId then return true end
        end
    end
    return false
end

local function routeContains(route, nodeId, linkId, regionId)
    if type(route) ~= 'table' then return false end
    if regionId and route.regionId == regionId then return true end
    return pathContains(route.primary, nodeId, linkId)
        or pathContains(route.backup, nodeId, linkId)
end

local function routePrimaryChanged(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table' then return left ~= right end
    local leftLinks, rightLinks = left.primary and left.primary.links or {}, right.primary
        and right.primary.links or {}
    if #leftLinks ~= #rightLinks then return true end
    for index, value in ipairs(leftLinks) do
        if value ~= rightLinks[index] then return true end
    end
    return left.status ~= right.status
end

local function collectRoutes()
    local routes = {}
    local towers = TowerRegistry and TowerRegistry.GetAll and TowerRegistry.GetAll() or {}
    local limit = maximumTowers()
    for index = 1, math.min(#towers, limit) do
        local tower = towers[index]
        local ok, route = BackhaulRouting.FindRoute(tower.id)
        routes[tower.id] = {
            ok = ok == true,
            route = copy(route),
        }
    end
    return routes, towers, limit
end

local function applyRoot(rootFailure)
    local linkId = rootField(rootFailure, 'linkId') or rootField(rootFailure, 'rootLinkId')
    local nodeId = rootField(rootFailure, 'rootNodeId') or rootField(rootFailure, 'nodeId')
    local regionId = rootField(rootFailure, 'regionId')
    if not nodeId and regionId and BackhaulRegions and BackhaulRegions.Get then
        local region = BackhaulRegions.Get(regionId)
        nodeId = region and region.popNode or nil
    end

    local applied = {
        linkId = linkId,
        nodeId = nodeId,
        regionId = regionId,
        linkState = nil,
        nodeState = nil,
        linkChanged = false,
        nodeChanged = false,
    }
    if linkId then
        local link = BackhaulLinks and BackhaulLinks.Get and BackhaulLinks.Get(linkId)
        if not link then return false, 'root_link_not_found' end
        applied.linkState = link.state
        if link.state ~= Enums.LinkState.OFFLINE then
            local ok = BackhaulLinks.SetState(linkId, Enums.LinkState.OFFLINE)
            if not ok then return false, 'root_link_update_failed' end
            applied.linkChanged = true
        end
    elseif nodeId then
        local node = BackhaulNodes and BackhaulNodes.Get and BackhaulNodes.Get(nodeId)
        if not node then return false, 'root_node_not_found' end
        applied.nodeState = node.state
        if node.state ~= Enums.BackhaulNodeState.OFFLINE then
            local ok = BackhaulNodes.SetState(nodeId, Enums.BackhaulNodeState.OFFLINE)
            if not ok then return false, 'root_node_update_failed' end
            applied.nodeChanged = true
        end
    elseif not regionId and not rootField(rootFailure, 'towerId') then
        return false, 'root_cause_required'
    end

    if BackhaulRouting and BackhaulRouting.Invalidate then BackhaulRouting.Invalidate() end
    return true, applied
end

local function addRouteGraph(graph, route)
    if type(route) ~= 'table' then return end
    for _, path in ipairs({ route.primary, route.backup }) do
        if type(path) == 'table' then
            for _, nodeId in ipairs(path.nodes or {}) do addVisited(graph.nodes, nodeId) end
            for _, linkId in ipairs(path.links or {}) do addVisited(graph.links, linkId) end
        end
    end
    addVisited(graph.regions, route.regionId)
end

local function updateTowerRuntime(towerId, baseline, status, rootId, route)
    local runtime = TowerRegistry and TowerRegistry.GetRuntimeState
        and TowerRegistry.GetRuntimeState(towerId)
    if not runtime or not TowerState or not TowerState.Set then return false end
    local nextState = copy(runtime)
    local targetState = status == Enums.BackhaulState.OFFLINE
        and Enums.TowerState.OFFLINE or Enums.TowerState.DEGRADED
    if runtime.state ~= Enums.TowerState.DESTROYED
        and runtime.state ~= Enums.TowerState.MAINTENANCE then
        nextState.state = targetState
    end
    nextState.backhaulStatus = status
    nextState.outagePropagation = {
        rootFailureId = rootId,
        status = status,
        route = copy(route),
    }
    nextState.outageBaselineState = baseline and baseline.state or runtime.state
    return TowerState.Set(towerId, nextState)
end

local function refreshAffected(towerIds)
    local ordered = sortedSet(towerIds)
    if Connections and Connections.RefreshTowers then
        Connections.RefreshTowers(ordered)
    elseif Connections and Connections.RefreshTower then
        for _, towerId in ipairs(ordered) do Connections.RefreshTower(towerId) end
    end
    if Capacity and Capacity.RecalculateTowers then
        Capacity.RecalculateTowers(ordered, Connections and Connections.GetAll
            and Connections.GetAll() or {})
    elseif Capacity and Capacity.RecalculateTower then
        local states = Connections and Connections.GetAll and Connections.GetAll() or {}
        for _, towerId in ipairs(ordered) do Capacity.RecalculateTower(towerId, states) end
    end
end

local function restoreTowerOverlay(rootFailureId, towerId, baseline)
    local current = TowerState and TowerState.Get and TowerState.Get(towerId)
    if not current or not baseline or not TowerState.Set then return false end

    local base = copy(baseline)
    local unwound = {}
    while type(base.outagePropagation) == 'table' do
        local previousId = base.outagePropagation.rootFailureId
        local previousImpact = impactsById[previousId]
        local previousBaseline = previousImpact
            and previousImpact.recoveryState == 'RECOVERED'
            and previousImpact.baselineRuntime
            and previousImpact.baselineRuntime[towerId]
        if not previousBaseline or unwound[previousId] then break end
        unwound[previousId] = true
        base = copy(previousBaseline)
    end

    local nextState = copy(current)
    nextState.state = base.state
    nextState.backhaulStatus = base.backhaulStatus
    nextState.outagePropagation = base.outagePropagation
    nextState.outageBaselineState = base.outageBaselineState

    local otherIds = {}
    for otherId, otherImpact in pairs(impactsById) do
        if otherId ~= rootFailureId and otherImpact.recoveryState ~= 'RECOVERED'
            and otherImpact.affectedTowers and otherImpact.affectedTowers[towerId] then
            otherIds[#otherIds + 1] = otherId
        end
    end
    table.sort(otherIds)
    for _, otherId in ipairs(otherIds) do
        local effect = impactsById[otherId].affectedTowers[towerId]
        local targetState = effect.status == Enums.BackhaulState.OFFLINE
            and Enums.TowerState.OFFLINE or Enums.TowerState.DEGRADED
        if nextState.state ~= Enums.TowerState.DESTROYED
            and nextState.state ~= Enums.TowerState.MAINTENANCE then
            nextState.state = targetState
        end
        nextState.backhaulStatus = effect.status
        nextState.outagePropagation = {
            rootFailureId = otherId,
            status = effect.status,
            route = copy(effect.route),
        }
    end
    return TowerState.Set(towerId, nextState)
end

function OutagePropagation.Propagate(rootFailure)
    if type(rootFailure) ~= 'table' then return false, 'root_failure_required' end
    local id = rootFailureId(rootFailure)
    local existing = impactsById[id]
    if existing and existing.recoveryState ~= 'RECOVERED' then
        return true, copy(existing)
    end
    if existing and existing.recoveryState == 'RECOVERED' then
        return false, 'outage_already_recovered'
    end
    if not BackhaulRouting or not BackhaulRouting.FindRoute then
        return false, 'routing_unavailable'
    end

    local baselineRoutes, towers, limit = collectRoutes()
    local rootOk, appliedOrError = applyRoot(rootFailure)
    if not rootOk then return false, appliedOrError end
    local applied = appliedOrError
    local currentRoutes = {}
    local visited = { nodes = {}, links = {}, regions = {}, towers = {} }
    local graph = { nodes = {}, links = {}, regions = {} }
    if applied.nodeId then addVisited(visited.nodes, applied.nodeId) end
    if applied.linkId then addVisited(visited.links, applied.linkId) end
    if applied.regionId then addVisited(visited.regions, applied.regionId) end

    local rootTowerId = rootField(rootFailure, 'towerId')
    local affectedTowers = {}
    local baselineRuntime = {}
    local backupRouteLoad = {}
    local pendingTowers = {}

    for index = 1, math.min(#towers, limit) do
        local tower = towers[index]
        local towerId = tower.id
        local currentOk, currentRoute = BackhaulRouting.FindRoute(towerId)
        currentRoutes[towerId] = { ok = currentOk == true, route = copy(currentRoute) }
        local baseline = baselineRoutes[towerId] or { ok = false }
        local baselineRoute = baseline.route
        local route = currentRoutes[towerId].route
        local touched = towerId == rootTowerId
            or routeContains(baselineRoute, applied.nodeId, applied.linkId, applied.regionId)
        local changed = routePrimaryChanged(baselineRoute, route)
        local status = currentOk and currentRoute and currentRoute.status
            or Enums.BackhaulState.OFFLINE
        local affected = touched or (changed and (applied.linkId or applied.nodeId or applied.regionId))
        if affected then
            addVisited(visited.towers, towerId)
            addRouteGraph(graph, baselineRoute)
            addRouteGraph(graph, route)
            baselineRuntime[towerId] = TowerRegistry.GetRuntimeState(towerId)
            local degraded = status ~= Enums.BackhaulState.OFFLINE
                and (touched or changed)
            local propagatedStatus = status == Enums.BackhaulState.OFFLINE
                and Enums.BackhaulState.OFFLINE
                or degraded and Enums.BackhaulState.DEGRADED
                or status
            local usedBackup = baselineRoute and baselineRoute.primary
                and pathContains(baselineRoute.primary, applied.nodeId, applied.linkId)
                and route and route.primary
                and not pathContains(route.primary, applied.nodeId, applied.linkId)
            if usedBackup then
                for _, linkId in ipairs(route.primary.links or {}) do
                    backupRouteLoad[linkId] = (backupRouteLoad[linkId] or 0) + 1
                end
            end
            updateTowerRuntime(towerId, baselineRuntime[towerId], propagatedStatus, id, route)
            affectedTowers[towerId] = {
                towerId = towerId,
                status = propagatedStatus,
                routeStatus = status,
                baselineStatus = baselineRoute and baselineRoute.status
                    or Enums.BackhaulState.OFFLINE,
                usedBackup = usedBackup == true,
                route = copy(route),
            }
        end
    end

    for index = limit + 1, #towers do
        pendingTowers[#pendingTowers + 1] = towers[index].id
    end

    local loadSnapshot = BackhaulRouting.RecalculateLoads()
    refreshAffected(visited.towers)
    local impact = {
        rootFailureId = id,
        rootCause = copy(rootFailure),
        appliedRoot = copy(applied),
        recoveryState = 'ACTIVE',
        createdAt = now(),
        visited = visited,
        affectedGraph = {
            nodes = sortedSet(graph.nodes),
            links = sortedSet(graph.links),
            regions = sortedSet(graph.regions),
        },
        affectedTowers = affectedTowers,
        pendingTowers = pendingTowers,
        complete = #pendingTowers == 0,
        reconciliationRequired = #pendingTowers > 0,
        secondaryEffects = {
            backupRouteLoad = backupRouteLoad,
            routeLoads = copy(loadSnapshot.links),
            processedTowers = math.min(#towers, limit),
            complete = #towers <= limit and loadSnapshot.complete ~= false,
            bounded = true,
        },
        baselineRuntime = baselineRuntime,
        baselineRoutes = baselineRoutes,
        currentRoutes = currentRoutes,
    }
    impactsById[id] = impact
    return true, copy(impact)
end

function OutagePropagation.GetImpact(rootFailureId)
    return copy(impactsById[rootFailureId])
end

function OutagePropagation.Recover(rootFailureId)
    local impact = impactsById[rootFailureId]
    if not impact then return false, 'outage_not_found' end
    if impact.recoveryState == 'RECOVERED' then return true, copy(impact) end

    local applied = impact.appliedRoot or {}
    if applied.linkChanged and applied.linkId and BackhaulLinks and BackhaulLinks.SetState then
        BackhaulLinks.SetState(applied.linkId, applied.linkState)
    end
    if applied.nodeChanged and applied.nodeId and BackhaulNodes and BackhaulNodes.SetState then
        BackhaulNodes.SetState(applied.nodeId, applied.nodeState)
    end
    if BackhaulRouting and BackhaulRouting.Invalidate then BackhaulRouting.Invalidate() end

    local towerIds = {}
    for towerId, baseline in pairs(impact.baselineRuntime or {}) do
        towerIds[towerId] = true
        restoreTowerOverlay(rootFailureId, towerId, baseline)
    end
    local orderedTowerIds = sortedSet(towerIds)
    if FailureEngine and FailureEngine.ApplyTower then
        for _, towerId in ipairs(orderedTowerIds) do
            FailureEngine.ApplyTower(towerId)
        end
    end
    if BackhaulRouting and BackhaulRouting.RecalculateLoads then
        BackhaulRouting.RecalculateLoads()
    end
    refreshAffected(orderedTowerIds)
    impact.recoveryState = 'RECOVERED'
    impact.recoveredAt = now()
    return true, copy(impact)
end

function OutagePropagation.Reset()
    local ids = {}
    for id, impact in pairs(impactsById) do
        if impact.recoveryState ~= 'RECOVERED' then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do OutagePropagation.Recover(id) end
    impactsById = {}
end
