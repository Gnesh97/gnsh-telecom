BackhaulRouting = BackhaulRouting or {}

local cache = {}
local cacheVersion = -1

local function enabled()
    return Config and Config.Features and Config.Features.Backhaul == true
end

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function cacheTtl()
    local ttl = Config and Config.Backhaul and Config.Backhaul.routeCacheTtlMs
    return type(ttl) == 'number' and math.max(0, ttl) or 5000
end

local function configuredTopology()
    local config = Config and Config.Backhaul or {}
    return type(config.nodes) == 'table' and #config.nodes > 0
        or type(config.links) == 'table' and #config.links > 0
end

local function towerStart(towerId)
    local mapping = Config and Config.Backhaul and Config.Backhaul.towerNodes
    if type(mapping) == 'table' and type(mapping[towerId]) == 'string' then
        local towerNeighbors = BackhaulGraph and BackhaulGraph.GetNeighbors
            and BackhaulGraph.GetNeighbors(towerId) or {}
        if #towerNeighbors > 0 then return towerId end
        return mapping[towerId]
    end
    return towerId
end

local function coreNodes()
    return Config and Config.Backhaul and Config.Backhaul.coreNodes or {}
end

local function route(towerId)
    if not enabled() then return Enums.BackhaulState.ONLINE, { disabled = true } end
    if not configuredTopology() then
        return Enums.BackhaulState.ONLINE, { implicit = true }
    end

    local start = towerStart(towerId)
    local targets = {}
    for _, nodeId in ipairs(coreNodes()) do targets[nodeId] = true end
    local queue = { { nodeId = start, degraded = false } }
    local bestCost = { [start] = 0 }
    local foundDegraded = false
    local head = 1

    while queue[head] do
        local item = queue[head]
        head = head + 1
        local nodeId = item.nodeId
        local node = BackhaulNodes.Get(nodeId)
        if node and node.state ~= Enums.BackhaulNodeState.OFFLINE then
            if targets[nodeId] then
                if not item.degraded then
                    return Enums.BackhaulState.ONLINE, { pathFound = true, degraded = false }
                end
                foundDegraded = true
            end
            for _, neighbor in ipairs(BackhaulGraph.GetNeighbors(nodeId)) do
                local link = neighbor.link
                local nextNode = BackhaulNodes.Get(neighbor.to)
                if link and nextNode and link.state ~= Enums.LinkState.OFFLINE
                    and nextNode.state ~= Enums.BackhaulNodeState.OFFLINE then
                    local degraded = item.degraded or link.state == Enums.LinkState.DEGRADED
                    local cost = degraded and 1 or 0
                    if bestCost[neighbor.to] == nil or cost < bestCost[neighbor.to] then
                        bestCost[neighbor.to] = cost
                        queue[#queue + 1] = { nodeId = neighbor.to, degraded = degraded }
                    end
                end
            end
        end
    end
    if foundDegraded then return Enums.BackhaulState.DEGRADED, { pathFound = true, degraded = true } end
    return Enums.BackhaulState.OFFLINE, { pathFound = false }
end

function BackhaulRouting.Initialize()
    cache = {}
    cacheVersion = BackhaulGraph.GetVersion and BackhaulGraph.GetVersion() or -1
    return true
end

function BackhaulRouting.GetTowerStatus(towerId)
    if type(towerId) ~= 'string' then return Enums.BackhaulState.OFFLINE end
    local runtime = TowerRegistry and TowerRegistry.GetRuntimeState
        and TowerRegistry.GetRuntimeState(towerId)
    if runtime and runtime.failureEffects
        and runtime.failureEffects.backhaulStatus == Enums.BackhaulState.OFFLINE then
        return Enums.BackhaulState.OFFLINE
    end

    local version = BackhaulGraph.GetVersion and BackhaulGraph.GetVersion() or 0
    if version ~= cacheVersion then cache = {}; cacheVersion = version end
    local cached = cache[towerId]
    if cached and now() - cached.at <= cacheTtl() then return cached.status end
    local status = route(towerId)
    cache[towerId] = { status = status, at = now() }
    return status
end

function BackhaulRouting.Invalidate()
    cache = {}
    cacheVersion = BackhaulGraph.GetVersion and BackhaulGraph.GetVersion() or -1
end

function BackhaulRouting.GetSnapshot()
    local result = {}
    for _, tower in ipairs(TowerRegistry.GetAll and TowerRegistry.GetAll() or {}) do
        result[tower.id] = BackhaulRouting.GetTowerStatus(tower.id)
    end
    return result
end
