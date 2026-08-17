-- Framework-free synthetic scale harness.
-- Run from the resource root:
--   lua tests/performance/scale_harness.lua

local startedAt = os.clock()

function vector3(x, y, z)
    return { x = x, y = y, z = z }
end

GetGameTimer = function()
    return math.floor((os.clock() - startedAt) * 1000)
end

dofile('tests/performance/metrics.lua')
dofile('config/default.lua')
dofile('config/towers.lua')
dofile('shared/config.lua')
dofile('shared/constants.lua')
dofile('shared/enums.lua')
dofile('shared/technologies.lua')
dofile('shared/carriers.lua')
dofile('shared/feature_flags.lua')
dofile('shared/utils.lua')
dofile('shared/service_policy.lua')
dofile('server/towers/sectors.lua')
dofile('server/towers/validation.lua')
dofile('server/towers/state.lua')
dofile('server/towers/registry.lua')
dofile('server/carriers/registry.lua')
dofile('server/towers/spatial_index.lua')
dofile('server/network/signal.lua')
dofile('server/network/coverage.lua')
dofile('server/network/technology_selection.lua')
dofile('server/carriers/selection.lua')
dofile('server/network/selection.lua')
dofile('server/network/capacity.lua')
dofile('server/network/services.lua')
dofile('server/backhaul/nodes.lua')
dofile('server/backhaul/links.lua')
dofile('server/backhaul/regions.lua')
dofile('server/backhaul/graph.lua')
dofile('server/backhaul/routing.lua')
dofile('server/security/validation.lua')
dofile('server/security/rate_limit.lua')
dofile('server/network/qos.lua')
dofile('server/network/connections.lua')
dofile('server/network/service_sessions.lua')
dofile('server/incidents/severity.lua')
dofile('server/incidents/tickets.lua')
dofile('server/incidents/manager.lua')
dofile('server/jammers.lua')
dofile('server/statistics.lua')
dofile('noc/server.lua')
dofile('noc/server_stream.lua')

Config.Debug.enabled = false
Config.Debug.logLevel = 'error'
Config.Features.Backhaul = true
Config.Features.Incidents = true
Config.Features.Jammers = true
Config.Features.NOC = true
Config.Features.QoS = true
Config.Features.ServiceSessions = true

local runs = {}
local currentTowers = {}
local currentPlayers = 0

local function fail(message)
    error(message, 0)
end

local function assertOk(ok, message)
    if not ok then fail(message or 'synthetic setup failed') end
end

local function makeTowers(count)
    local towers = {}
    local side = math.ceil(math.sqrt(count))
    for index = 1, count do
        local zeroIndex = index - 1
        local column = zeroIndex % side
        local row = math.floor(zeroIndex / side)
        towers[index] = {
            id = ('SCALE-TOWER-%03d'):format(index),
            coords = vector3(column * 140, row * 140, 25),
            coverage = { radius = 220, minimum = 8 },
            technologies = { '4G', '5G' },
            capacity = { maximum = 100 },
        }
    end
    return towers
end

local function makeBackhaul(towers)
    local nodes = {
        { id = 'SCALE-CORE-1', type = 'CORE' },
        { id = 'SCALE-CORE-2', type = 'CORE' },
    }
    local links = {
        {
            id = 'SCALE-LINK-CORE-1',
            from = 'SCALE-AGG-1',
            to = 'SCALE-CORE-1',
            type = 'FIBER',
            capacity = 10000,
        },
        {
            id = 'SCALE-LINK-CORE-2',
            from = 'SCALE-AGG-2',
            to = 'SCALE-CORE-2',
            type = 'FIBER',
            capacity = 10000,
        },
        {
            id = 'SCALE-LINK-CORE-BACKUP',
            from = 'SCALE-CORE-1',
            to = 'SCALE-CORE-2',
            type = 'FIBER',
            capacity = 10000,
        },
    }
    local towerNodes = {}
    local towerRegions = {}
    local regions = {}
    for regionIndex = 1, 2 do
        regions[#regions + 1] = {
            id = ('SCALE-REGION-%d'):format(regionIndex),
            popNode = ('SCALE-AGG-%d'):format(regionIndex),
            nodeIds = { ('SCALE-AGG-%d'):format(regionIndex) },
            coreNodes = { ('SCALE-CORE-%d'):format(regionIndex) },
            towerIds = {},
        }
        nodes[#nodes + 1] = {
            id = ('SCALE-AGG-%d'):format(regionIndex),
            type = 'AGGREGATION',
        }
    end
    for index, tower in ipairs(towers) do
        local regionIndex = ((index - 1) % 2) + 1
        towerNodes[tower.id] = ('SCALE-AGG-%d'):format(regionIndex)
        towerRegions[tower.id] = ('SCALE-REGION-%d'):format(regionIndex)
        regions[regionIndex].towerIds[#regions[regionIndex].towerIds + 1] = tower.id
    end

    Config.Backhaul = {
        nodes = nodes,
        links = links,
        coreNodes = { 'SCALE-CORE-1', 'SCALE-CORE-2' },
        towerNodes = towerNodes,
        towerRegions = towerRegions,
        regions = regions,
        maxRouteCacheEntries = 512,
        maxRecomputeNodes = 256,
        maxRegionalTowers = 256,
        maxPathHops = 16,
    }
    assertOk(BackhaulGraph.Rebuild())
    assertOk(BackhaulRouting.Initialize())
end

local function setupWorld(towerCount)
    Connections.Clear()
    ServiceSessions.Reset()
    Jammers.Reset()
    IncidentTickets.Reset()
    NocServer.ResetStream()
    currentTowers = makeTowers(towerCount)
    Config.Towers = currentTowers
    assertOk(TowerRegistry.Init(currentTowers))
    assertOk(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    makeBackhaul(currentTowers)
end

local function playerPosition(index, offset)
    local tower = currentTowers[((index - 1) % #currentTowers) + 1]
    local direction = ((index + (offset or 0)) % 4) * 15
    return vector3(tower.coords.x + direction, tower.coords.y + direction, tower.coords.z)
end

local function makeConnection(source)
    local tower = currentTowers[((source - 1) % #currentTowers) + 1]
    return {
        source = source,
        towerId = tower.id,
        signal = 90,
        rawSignal = 90,
        signalLevel = Signal.GetLevel(90),
        technology = '4G',
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    }
end

local function preparePlayers(count)
    currentPlayers = count
    for source = 1, count do
        assertOk(Connections.Set(source, makeConnection(source), { skipCapacity = true }))
        local ok, _, errorCode = Connections.Reevaluate(source, playerPosition(source), {
            category = 'OPEN_AREA',
        })
        if not ok and errorCode then fail(errorCode) end
    end
end

local function measureMovement(playerCount, towerCount, offset, label)
    setupWorld(towerCount)
    preparePlayers(playerCount)
    local run = PerformanceMetrics.NewRun(label, {
        players = playerCount,
        towers = towerCount,
    })
    local candidates = 0
    PerformanceMetrics.Measure(run, 'movement', playerCount, function()
        for source = 1, playerCount do
            local coords = playerPosition(source, offset)
            candidates = candidates + #Coverage.GetCandidates(coords, {
                category = 'OPEN_AREA',
            })
            local _, _, errorCode = Connections.Reevaluate(source, coords, {
                category = 'OPEN_AREA',
            })
            if errorCode then fail(errorCode) end
        end
        return { averageCandidates = candidates / playerCount }
    end)
    runs[#runs + 1] = run
end

local function measureEventCongestion()
    local playerCount, towerCount, rounds = 200, 200, 10
    setupWorld(towerCount)
    preparePlayers(playerCount)
    local run = PerformanceMetrics.NewRun('event congestion', {
        players = playerCount,
        towers = towerCount,
        rounds = rounds,
    })
    local candidates = 0
    PerformanceMetrics.Measure(run, 'position events', playerCount * rounds, function()
        for round = 1, rounds do
            for source = 1, playerCount do
                local coords = playerPosition(source, round)
                candidates = candidates + #Coverage.GetCandidates(coords, nil)
                Connections.Reevaluate(source, coords, nil)
            end
        end
        return { averageCandidates = candidates / (playerCount * rounds) }
    end)
    runs[#runs + 1] = run
end

local function measureSpatialIndex()
    local run = PerformanceMetrics.NewRun('spatial index rebuild', {})
    for _, towerCount in ipairs({ 20, 50, 100, 200 }) do
        local towers = makeTowers(towerCount)
        PerformanceMetrics.Measure(run, ('towers-%d'):format(towerCount), towerCount, function()
            assertOk(SpatialIndex.Rebuild(towers))
            return SpatialIndex.GetStats()
        end)
    end
    runs[#runs + 1] = run
end

local function measureBackhaulOutage()
    setupWorld(200)
    local run = PerformanceMetrics.NewRun('regional outage', { towers = 200 })
    BackhaulRouting.RecalculateLoads()
    PerformanceMetrics.Measure(run, 'region-1 link outage and recovery', 2, function()
        assertOk(BackhaulLinks.SetState(
            'SCALE-LINK-CORE-1',
            Enums.LinkState.OFFLINE
        ))
        local outage = BackhaulRouting.GetRegionalSnapshot()
        local regionCount = 0
        for _ in pairs(outage or {}) do regionCount = regionCount + 1 end
        assertOk(BackhaulLinks.SetState(
            'SCALE-LINK-CORE-1',
            Enums.LinkState.ONLINE
        ))
        return { regions = regionCount }
    end)
    runs[#runs + 1] = run
end

local function measureIncidents()
    setupWorld(100)
    local run = PerformanceMetrics.NewRun('incident storm', { incidents = 100 })
    PerformanceMetrics.Measure(run, 'create 100 incidents', 100, function()
        for index = 1, 100 do
            local record, errorCode = IncidentTickets.Create({
                failureId = ('SCALE-FAIL-%03d'):format(index),
                towerId = currentTowers[((index - 1) % #currentTowers) + 1].id,
                severity = 'HIGH',
                metadata = { scenario = 'synthetic-scale' },
            })
            if not record then fail(errorCode) end
        end
        return { total = #IncidentTickets.GetAll() }
    end)
    runs[#runs + 1] = run
end

local function measureNocOpen()
    setupWorld(200)
    preparePlayers(200)
    local run = PerformanceMetrics.NewRun('NOC open', { towers = 200, players = 200 })
    local snapshot = {
        towers = TowerRegistry.GetAll(),
        incidents = { incidents = IncidentTickets.GetAll(), counts = {} },
        backhaul = BackhaulRouting.GetSnapshot(),
        backhaulLoads = BackhaulRouting.GetLoadSnapshot(),
        backhaulNodes = BackhaulNodes.GetAll(),
        regions = BackhaulRouting.GetRegionalSnapshot(),
        jammers = Jammers.GetAll(),
        subscribers = {},
        serviceSessions = ServiceSessions.GetAll(600),
    }
    PerformanceMetrics.Measure(run, 'build NOC entities', 5, function()
        local entityCount = 0
        for _ = 1, 5 do entityCount = #NocServer.BuildEntities(snapshot) end
        return { entities = entityCount }
    end)
    runs[#runs + 1] = run
end

local function measureJammers()
    setupWorld(100)
    preparePlayers(100)
    local previousMaximum = Config.Jammers.maxActive
    local previousCooldown = Config.Jammers.cooldownMs
    Config.Jammers.maxActive = 200
    Config.Jammers.cooldownMs = 1
    for index = 1, 50 do
        local ok, errorCode = Jammers.Create(
            10000 + index,
            currentTowers[((index - 1) % #currentTowers) + 1].coords,
            { radius = 180, strength = 0.25, durationMs = 600000 }
        )
        if not ok then fail(errorCode) end
    end
    local run = PerformanceMetrics.NewRun('multiple jammers', { jammers = 50, players = 100 })
    PerformanceMetrics.Measure(run, 'evaluate jammer effects', 100, function()
        local active = 0
        for source = 1, 100 do
            local effect = Jammers.GetEffect(playerPosition(source), { '4G' })
            active = active + #(effect.jammers or {})
        end
        return { averageActive = active / 100 }
    end)
    runs[#runs + 1] = run
    Jammers.Reset()
    Config.Jammers.maxActive = previousMaximum
    Config.Jammers.cooldownMs = previousCooldown
end

local function measureServiceSessions()
    setupWorld(200)
    preparePlayers(200)
    -- Keep this scenario focused on session bookkeeping rather than signal
    -- selection. Rebind each synthetic player to a known strong connection
    -- distributed across the tower set so capacity remains realistic.
    for source = 1, 200 do
        assertOk(Connections.Set(source, makeConnection(source), { skipCapacity = true }))
    end
    local previousMaximum = Config.ServiceSessions.maxActive
    local previousPerSource = Config.ServiceSessions.maxActivePerSource
    local previousBegins = Config.ServiceSessions.maxBeginsPerSecond
    Config.ServiceSessions.maxActive = 600
    Config.ServiceSessions.maxActivePerSource = 4
    Config.ServiceSessions.maxBeginsPerSecond = 1000

    for _, sessionCount in ipairs({ 0, 50, 200, 500 }) do
        ServiceSessions.Reset()
        for source = 1, 200 do TelecomRateLimit.Clear(source) end
        local run = PerformanceMetrics.NewRun('large phone session count', {
            sessions = sessionCount,
            players = 200,
        })
        PerformanceMetrics.Measure(run, ('begin-%d'):format(sessionCount), sessionCount, function()
            for index = 1, sessionCount do
                local source = ((index - 1) % 200) + 1
                local ok, errorCode = ServiceSessions.Begin(source, 'DATA', {
                    requestId = ('scale-%d'):format(index),
                })
                if not ok then fail(errorCode) end
            end
            return { active = ServiceSessions.Count() }
        end)
        runs[#runs + 1] = run
    end
    ServiceSessions.Reset()
    Config.ServiceSessions.maxActive = previousMaximum
    Config.ServiceSessions.maxActivePerSource = previousPerSource
    Config.ServiceSessions.maxBeginsPerSecond = previousBegins
end

measureSpatialIndex()
measureMovement(2, 20, 0, 'normal movement')
measureMovement(16, 50, 0, 'normal movement')
measureMovement(32, 50, 0, 'normal movement')
measureMovement(64, 100, 0, 'normal movement')
measureMovement(128, 200, 0, 'normal movement')
measureMovement(200, 200, 0, 'normal movement')
measureMovement(32, 50, 1, 'mass handover')
measureMovement(128, 200, 1, 'mass handover')
measureMovement(200, 200, 1, 'mass handover')
measureEventCongestion()
measureBackhaulOutage()
measureIncidents()
measureNocOpen()
measureJammers()
measureServiceSessions()

PerformanceMetrics.Render(runs)
print('REAL FIVEM RUNTIME TEST')
print('not run; connected clients: 0')
