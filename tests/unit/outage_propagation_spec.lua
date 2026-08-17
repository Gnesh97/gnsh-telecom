local function makeTower(id, capacity)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = capacity or 100 },
    }
end

local function outageTopology(withBackup)
    local links = {
        { id = 'A-PRIMARY', from = 'OUTAGE_A', to = 'AGG-A' },
        { id = 'A-CORE', from = 'AGG-A', to = 'CORE' },
        { id = 'B-AGG', from = 'OUTAGE_B', to = 'AGG-B' },
        { id = 'B-CORE', from = 'AGG-B', to = 'CORE' },
    }
    if withBackup then
        links[#links + 1] = { id = 'A-BACKUP', from = 'OUTAGE_A', to = 'AGG-B' }
    end
    return {
        routeCacheTtlMs = 60000,
        maxRouteCacheEntries = 16,
        maxRecomputeNodes = 16,
        maxPathHops = 16,
        maxRegionalTowers = 16,
        coreNodes = { 'CORE' },
        towerNodes = {
            OUTAGE_A = 'AGG-A',
            OUTAGE_B = 'AGG-B',
        },
        towerRegions = {
            OUTAGE_A = 'OUTAGE_REGION',
            OUTAGE_B = 'OUTAGE_REGION',
        },
        regions = {
            {
                id = 'OUTAGE_REGION',
                towerIds = { 'OUTAGE_A', 'OUTAGE_B' },
            },
        },
        nodes = {
            { id = 'AGG-A', type = 'AGGREGATION' },
            { id = 'AGG-B', type = 'AGGREGATION' },
            { id = 'CORE', type = 'CORE' },
        },
        links = links,
    }
end

local function withOutageTopology(withBackup, fn)
    local previous = {
        backhaul = Utils.DeepCopy(Config.Backhaul),
        towers = Utils.DeepCopy(Config.Towers),
        feature = Config.Features.Backhaul,
    }
    Config.Features.Backhaul = true
    Config.Backhaul = outageTopology(withBackup)
    Config.Towers = {
        makeTower('OUTAGE_A', 100),
        makeTower('OUTAGE_B', 1),
    }
    TowerRegistry.Init(Config.Towers)
    SpatialIndex.Rebuild(TowerRegistry.GetAll())
    BackhaulGraph.Rebuild()
    BackhaulRouting.Initialize()
    OutagePropagation.Reset()
    Connections.Clear()

    local ok, errorMessage = pcall(fn)

    OutagePropagation.Reset()
    FailureEngine.Reset()
    Connections.Clear()
    BackhaulNodes.Reset()
    BackhaulLinks.Reset()
    BackhaulRegions.Reset()
    Config.Backhaul = previous.backhaul
    Config.Towers = previous.towers
    Config.Features.Backhaul = previous.feature
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
    BackhaulGraph.Rebuild()
    BackhaulRouting.Initialize()
    if not ok then error(errorMessage, 0) end
end

TEST('fiber root failure routes dependent traffic over the backup and marks towers degraded', function()
    withOutageTopology(true, function()
        local beforeOk, before = BackhaulRouting.FindRoute('OUTAGE_A')
        ASSERT_TRUE(beforeOk)
        ASSERT_EQ(before.primary.links[1], 'A-PRIMARY')

        local ok, impact = OutagePropagation.Propagate({
            id = 'OUTAGE-BACKUP-1',
            type = 'FIBER_FAILURE',
            metadata = { linkId = 'A-PRIMARY' },
        })
        ASSERT_TRUE(ok)
        ASSERT_EQ(impact.rootCause.type, 'FIBER_FAILURE')
        ASSERT_TRUE(impact.visited.links['A-PRIMARY'])
        ASSERT_EQ(impact.affectedTowers.OUTAGE_A.status, Enums.BackhaulState.DEGRADED)
        ASSERT_EQ(TowerState.Get('OUTAGE_A').state, Enums.TowerState.DEGRADED)

        local loads = BackhaulRouting.GetLoadSnapshot()
        ASSERT_TRUE((loads.links['A-BACKUP'] or 0) >= 1)
        ASSERT_TRUE((impact.secondaryEffects.backupRouteLoad['A-BACKUP'] or 0) >= 1)

        local entities = NocServer.BuildEntities({ backhaulLoads = loads })
        local zeroLoadLink = false
        for _, entity in ipairs(entities) do
            if entity.entityType == 'backhaul_link'
                and entity.entityId == 'A-PRIMARY'
                and entity.state.load == 0 then
                zeroLoadLink = true
                break
            end
        end
        ASSERT_TRUE(zeroLoadLink)
    end)
end)

TEST('route-load telemetry invalidates when a link changes outside propagation', function()
    withOutageTopology(true, function()
        local before = BackhaulRouting.GetLoadSnapshot()
        ASSERT_TRUE((before.links['A-PRIMARY'] or 0) >= 1)
        ASSERT_TRUE(BackhaulLinks.SetState('A-PRIMARY', Enums.LinkState.OFFLINE))
        local after = BackhaulRouting.GetLoadSnapshot()
        ASSERT_EQ(after.links['A-PRIMARY'], 0)
        ASSERT_TRUE((after.links['A-BACKUP'] or 0) >= 1)
    end)
end)

TEST('offline dependent tower hands players to a neighbor and recalculates secondary congestion', function()
    withOutageTopology(false, function()
        local first = Connections.Reevaluate(201, vector3(0, 0, 0))
        ASSERT_EQ(first.towerId, 'OUTAGE_A')

        local ok, impact = OutagePropagation.Propagate({
            id = 'OUTAGE-HANDOVER-1',
            type = 'FIBER_FAILURE',
            metadata = { linkId = 'A-PRIMARY' },
        })
        ASSERT_TRUE(ok)
        ASSERT_EQ(impact.affectedTowers.OUTAGE_A.status, Enums.BackhaulState.OFFLINE)

        local next = Connections.Get(201)
        ASSERT_EQ(next.towerId, 'OUTAGE_B')
        ASSERT_EQ(TowerState.Get('OUTAGE_B').connectedClients, 1)
        ASSERT_EQ(TowerState.Get('OUTAGE_B').congestion, Enums.CongestionState.CRITICAL)
    end)
end)

TEST('fiber failure records trigger propagation and recovery is idempotent', function()
    withOutageTopology(false, function()
        local ok, failure = FailureEngine.Create('OUTAGE_A', 'FIBER_FAILURE', {
            id = 'FAIL-OUTAGE-001',
            metadata = { linkId = 'A-PRIMARY' },
        })
        ASSERT_TRUE(ok)
        ASSERT_TRUE(OutagePropagation.GetImpact(failure.id) ~= nil)
        ASSERT_EQ(TowerState.Get('OUTAGE_A').state, Enums.TowerState.OFFLINE)

        local recovered, impact = OutagePropagation.Recover(failure.id)
        ASSERT_TRUE(recovered)
        ASSERT_EQ(impact.recoveryState, 'RECOVERED')
        ASSERT_EQ(BackhaulLinks.Get('A-PRIMARY').state, Enums.LinkState.ONLINE)
        ASSERT_EQ(TowerState.Get('OUTAGE_A').state, Enums.TowerState.OPERATIONAL)

        local repeated, repeatedImpact = OutagePropagation.Recover(failure.id)
        ASSERT_TRUE(repeated)
        ASSERT_EQ(repeatedImpact.recoveryState, 'RECOVERED')
        ASSERT_TRUE(FailureEngine.Clear(failure.id))
    end)
end)

TEST('recovering one outage preserves a second active outage on the same tower', function()
    withOutageTopology(true, function()
        local firstOk = OutagePropagation.Propagate({
            id = 'OUTAGE-OVERLAP-1',
            type = 'FIBER_FAILURE',
            metadata = { linkId = 'A-PRIMARY' },
        })
        ASSERT_TRUE(firstOk)
        local secondOk, second = OutagePropagation.Propagate({
            id = 'OUTAGE-OVERLAP-2',
            type = 'FIBER_FAILURE',
            metadata = { linkId = 'A-BACKUP' },
        })
        ASSERT_TRUE(secondOk)
        ASSERT_EQ(second.affectedTowers.OUTAGE_A.status, Enums.BackhaulState.OFFLINE)

        ASSERT_TRUE(OutagePropagation.Recover('OUTAGE-OVERLAP-1'))
        ASSERT_EQ(TowerState.Get('OUTAGE_A').state, Enums.TowerState.OFFLINE)
        ASSERT_TRUE(OutagePropagation.Recover('OUTAGE-OVERLAP-2'))
        ASSERT_EQ(TowerState.Get('OUTAGE_A').state, Enums.TowerState.OPERATIONAL)
    end)
end)

TEST('outage propagation remains bounded and cycle-safe', function()
    withOutageTopology(true, function()
        ASSERT_TRUE(BackhaulLinks.Initialize({
            { id = 'CYCLE-A', from = 'AGG-A', to = 'AGG-B' },
            { id = 'CYCLE-B', from = 'AGG-B', to = 'AGG-A' },
            { id = 'A-PRIMARY', from = 'OUTAGE_A', to = 'AGG-A' },
            { id = 'A-CORE', from = 'AGG-A', to = 'CORE' },
            { id = 'B-AGG', from = 'OUTAGE_B', to = 'AGG-B' },
            { id = 'B-CORE', from = 'AGG-B', to = 'CORE' },
        }))
        BackhaulGraph.Rebuild()
        BackhaulRouting.Initialize()

        local ok, impact = OutagePropagation.Propagate({
            id = 'OUTAGE-CYCLE-1',
            type = 'FIBER_FAILURE',
            metadata = { linkId = 'A-PRIMARY' },
        })
        ASSERT_TRUE(ok)
        ASSERT_TRUE(#impact.affectedGraph.nodes <= Config.Backhaul.maxRecomputeNodes * 2)
        ASSERT_TRUE(impact.visited.towers.OUTAGE_A == true)
    end)
end)
