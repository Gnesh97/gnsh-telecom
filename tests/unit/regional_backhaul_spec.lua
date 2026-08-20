local function makeRegionalTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function regionalTopology()
    return {
        routeCacheTtlMs = 60000,
        maxRouteCacheEntries = 2,
        maxRecomputeNodes = 2,
        maxPathHops = 16,
        maxRegionalTowers = 8,
        coreNodes = { 'CORE-A', 'CORE-B' },
        towerNodes = {
            REGIONAL_TOWER_A = 'AGG-A',
            REGIONAL_TOWER_B = 'AGG-B',
            REGIONAL_TOWER_C = 'AGG-C',
        },
        towerRegions = {
            REGIONAL_TOWER_A = 'REGION-NORTH',
            REGIONAL_TOWER_B = 'REGION-NORTH',
            REGIONAL_TOWER_C = 'REGION-NORTH',
        },
        regions = {
            {
                id = 'REGION-NORTH',
                popNode = 'POP-NORTH',
                towerIds = { 'REGIONAL_TOWER_A', 'REGIONAL_TOWER_B', 'REGIONAL_TOWER_C' },
            },
        },
        nodes = {
            { id = 'AGG-A', type = 'AGGREGATION' },
            { id = 'AGG-B', type = 'AGGREGATION' },
            { id = 'AGG-C', type = 'AGGREGATION' },
            { id = 'POP-NORTH', type = 'REGIONAL_POP' },
            { id = 'CORE-A', type = 'CORE' },
            { id = 'CORE-B', type = 'CORE' },
        },
        links = {
            { id = 'LINK-A-PRIMARY', from = 'REGIONAL_TOWER_A', to = 'AGG-A' },
            { id = 'LINK-A-BACKUP', from = 'REGIONAL_TOWER_A', to = 'AGG-B' },
            { id = 'LINK-B-POP', from = 'AGG-B', to = 'POP-NORTH' },
            { id = 'LINK-A-POP', from = 'AGG-A', to = 'POP-NORTH' },
            { id = 'LINK-C-POP', from = 'REGIONAL_TOWER_C', to = 'POP-NORTH' },
            { id = 'LINK-POP-CORE-A', from = 'POP-NORTH', to = 'CORE-A' },
            { id = 'LINK-POP-CORE-B', from = 'POP-NORTH', to = 'CORE-B' },
        },
    }
end

local function withRegionalTopology(fn)
    local previous = {
        backhaul = Utils.DeepCopy(Config.Backhaul),
        towers = Utils.DeepCopy(Config.Towers),
        feature = Config.Features.Backhaul,
        timer = rawget(_G, 'GetGameTimer'),
    }
    local now = 1000
    Config.Features.Backhaul = true
    Config.Backhaul = regionalTopology()
    Config.Towers = {
        makeRegionalTower('REGIONAL_TOWER_A'),
        makeRegionalTower('REGIONAL_TOWER_B'),
        makeRegionalTower('REGIONAL_TOWER_C'),
    }
    GetGameTimer = function() return now end
    TowerRegistry.Init(Config.Towers)
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    ASSERT_TRUE(BackhaulGraph.Rebuild())
    ASSERT_TRUE(BackhaulRouting.Initialize())

    local ok, err = pcall(fn, function(value) now = value end)

    BackhaulNodes.Reset()
    BackhaulLinks.Reset()
    BackhaulRegions.Reset()
    Config.Backhaul = previous.backhaul
    Config.Towers = previous.towers
    Config.Features.Backhaul = previous.feature
    rawset(_G, 'GetGameTimer', previous.timer)
    BackhaulGraph.Rebuild()
    BackhaulRouting.Initialize()
    if not ok then error(err, 0) end
end

TEST('regional backhaul prefers a deterministic primary and exposes a backup route', function()
    withRegionalTopology(function()
        local ok, route = BackhaulRouting.FindRoute('REGIONAL_TOWER_A')
        ASSERT_TRUE(ok)
        ASSERT_EQ(route.status, Enums.BackhaulState.ONLINE)
        ASSERT_EQ(route.primary.coreNode, 'CORE-A')
        ASSERT_TRUE(route.backup ~= nil)
        ASSERT_EQ(route.backup.coreNode, 'CORE-B')
        ASSERT_EQ(route.primary.nodes[2], 'AGG-A')
    end)
end)

TEST('configured backhaul keeps unmapped runtime towers implicitly online', function()
    withRegionalTopology(function()
        local ok, route = BackhaulRouting.FindRoute('RUNTIME_TOWER')
        ASSERT_TRUE(ok)
        ASSERT_EQ(route.status, Enums.BackhaulState.ONLINE)
        ASSERT_TRUE(route.implicit)
        ASSERT_TRUE(route.unmapped)
    end)
end)

TEST('regional backhaul fails over to the backup path when the primary link is offline', function()
    withRegionalTopology(function()
        ASSERT_TRUE(BackhaulLinks.SetState('LINK-A-PRIMARY', Enums.LinkState.OFFLINE))
        local ok, route = BackhaulRouting.FindRoute('REGIONAL_TOWER_A')
        ASSERT_TRUE(ok)
        ASSERT_EQ(route.status, Enums.BackhaulState.ONLINE)
        ASSERT_EQ(route.primary.nodes[2], 'AGG-B')
        ASSERT_EQ(BackhaulRouting.GetTowerStatus('REGIONAL_TOWER_A'), Enums.BackhaulState.ONLINE)
    end)
end)

TEST('regional POP outage scopes the regional status and restoration recovers service', function()
    withRegionalTopology(function()
        ASSERT_TRUE(BackhaulNodes.SetState('POP-NORTH', Enums.BackhaulNodeState.OFFLINE))
        local towerStatus = BackhaulRouting.GetTowerStatus('REGIONAL_TOWER_A')
        ASSERT_EQ(towerStatus, Enums.BackhaulState.OFFLINE)
        local regionalOk, regional = BackhaulRouting.GetRegionalStatus('REGION-NORTH')
        ASSERT_TRUE(regionalOk)
        ASSERT_EQ(regional.status, Enums.BackhaulState.OFFLINE)
        ASSERT_EQ(regional.offlineCount, 3)

        ASSERT_TRUE(BackhaulNodes.SetState('POP-NORTH', Enums.BackhaulNodeState.ONLINE))
        ASSERT_EQ(BackhaulRouting.GetTowerStatus('REGIONAL_TOWER_A'), Enums.BackhaulState.ONLINE)
        local restoredOk, restored = BackhaulRouting.GetRegionalStatus('REGION-NORTH')
        ASSERT_TRUE(restoredOk)
        ASSERT_EQ(restored.status, Enums.BackhaulState.ONLINE)
    end)
end)

TEST('regional backhaul supports core failover, cycle protection and bounded recomputation', function()
    withRegionalTopology(function(setNow)
        BackhaulRouting.GetTowerStatus('REGIONAL_TOWER_A')
        BackhaulRouting.GetTowerStatus('REGIONAL_TOWER_B')
        BackhaulRouting.GetTowerStatus('REGIONAL_TOWER_C')

        ASSERT_TRUE(BackhaulNodes.SetState('CORE-A', Enums.BackhaulNodeState.OFFLINE))
        local failoverOk, failover = BackhaulRouting.FindRoute('REGIONAL_TOWER_A')
        ASSERT_TRUE(failoverOk)
        ASSERT_EQ(failover.primary.coreNode, 'CORE-B')

        local recomputeOk, stats = BackhaulRouting.RecomputeAffected('POP-NORTH')
        ASSERT_TRUE(recomputeOk)
        ASSERT_TRUE(stats.invalidated <= Config.Backhaul.maxRouteCacheEntries)
        ASSERT_TRUE(stats.recomputed <= Config.Backhaul.maxRecomputeNodes)
        ASSERT_TRUE(stats.bounded)

        setNow(70000)
        local cachedOk, cached = BackhaulRouting.FindRoute('REGIONAL_TOWER_A')
        ASSERT_TRUE(cachedOk)
        ASSERT_TRUE(cached.primary ~= nil)
    end)
end)

TEST('regional backhaul rejects unknown regions and preserves defensive route data', function()
    withRegionalTopology(function()
        local denied, errorCode = BackhaulRouting.GetRegionalStatus('UNKNOWN-REGION')
        ASSERT_FALSE(denied)
        ASSERT_EQ(errorCode, 'region_not_found')

        local ok, route = BackhaulRouting.FindRoute('REGIONAL_TOWER_A')
        ASSERT_TRUE(ok)
        route.primary.nodes[1] = 'MUTATED'
        local nextOk, nextRoute = BackhaulRouting.FindRoute('REGIONAL_TOWER_A', { force = true })
        ASSERT_TRUE(nextOk)
        ASSERT_EQ(nextRoute.primary.nodes[1], 'REGIONAL_TOWER_A')
    end)
end)

TEST('regional backhaul entities are exposed through the NOC extensible snapshot', function()
    withRegionalTopology(function()
        local previousNoc = Config.Features.NOC
        local previousAce = rawget(_G, 'IsPlayerAceAllowed')
        Config.Features.NOC = true
        IsPlayerAceAllowed = function() return true end

        local ok, snapshot = NocServer.GetSnapshot(7)
        ASSERT_TRUE(ok)
        local regionFound, popFound = false, false
        for _, entity in ipairs(snapshot.entities or {}) do
            if entity.entityType == 'region' and entity.entityId == 'REGION-NORTH' then
                regionFound = true
            end
            if entity.entityType == 'backhaul' and entity.entityId == 'POP-NORTH' then
                popFound = true
            end
        end
        ASSERT_TRUE(regionFound)
        ASSERT_TRUE(popFound)

        Config.Features.NOC = previousNoc
        rawset(_G, 'IsPlayerAceAllowed', previousAce)
    end)
end)
