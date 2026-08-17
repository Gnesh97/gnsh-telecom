local function makeSector(id, azimuth, overrides)
    local sector = {
        id = id,
        azimuth = azimuth,
        beamWidth = 90,
        coverageRadius = 100,
        technologies = { '4G' },
        capacity = 50,
        health = 100,
        state = Enums.TowerState.OPERATIONAL,
    }
    for key, value in pairs(overrides or {}) do sector[key] = value end
    return sector
end

local function makeTower(id, sectors)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
        sectors = sectors,
    }
end

TEST('sector validation accepts the documented model and rejects invalid geometry', function()
    local valid = makeTower('SECTOR_VALID', {
        makeSector('EAST', 0),
        makeSector('NORTH', 90),
    })
    local ok, errors, normalized = TowerValidation.Validate(valid)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(#normalized.sectors, 2)
    ASSERT_EQ(normalized.sectors[1].capacity, 50)

    local invalid = makeTower('SECTOR_INVALID', {
        makeSector('BAD', 360, { beamWidth = 0, coverageRadius = 101 }),
    })
    ok, errors = TowerValidation.Validate(invalid)
    ASSERT_FALSE(ok)
    local message = table.concat(errors or {}, '; ')
    ASSERT_TRUE(message:find('azimuth', 1, true) ~= nil)
    ASSERT_TRUE(message:find('beamWidth', 1, true) ~= nil)
    ASSERT_TRUE(message:find('coverageRadius', 1, true) ~= nil)
end)

TEST('sector directional math handles bearings, wraparound, and inclusive boundaries', function()
    local east = makeSector('EAST', 0, { beamWidth = 90 })
    ASSERT_EQ(TowerSectors.GetBearing(vector3(0, 0, 0), vector3(1, 0, 0)), 0)
    ASSERT_TRUE(TowerSectors.IsWithinBeam(east, vector3(0, 0, 0), vector3(1, 0, 0)))
    ASSERT_TRUE(TowerSectors.IsWithinBeam(east, vector3(0, 0, 0), vector3(1, 1, 0)))
    ASSERT_FALSE(TowerSectors.IsWithinBeam(east, vector3(0, 0, 0), vector3(1, 1.01, 0)))

    local wrap = makeSector('WRAP', 350, { beamWidth = 30 })
    ASSERT_TRUE(TowerSectors.IsWithinBeam(wrap, vector3(0, 0, 0), vector3(1, 0.08, 0)))
    ASSERT_FALSE(TowerSectors.IsWithinBeam(wrap, vector3(0, 0, 0), vector3(1, 1, 0)))
end)

TEST('sector coverage is directional while legacy towers remain omnidirectional', function()
    local directional = makeTower('SECTOR_COVERAGE', {
        makeSector('EAST', 0, { beamWidth = 100 }),
        makeSector('WEST', 180, { beamWidth = 100 }),
    })
    local legacy = makeTower('LEGACY_COVERAGE')
    legacy.coords = vector3(300, 0, 0)
    legacy.sectors = nil

    ASSERT_TRUE(SpatialIndex.Rebuild({ directional, legacy }))
    local east = Coverage.GetCandidates(vector3(50, 0, 0))
    ASSERT_EQ(east[1].towerId, 'SECTOR_COVERAGE')
    ASSERT_EQ(east[1].sectorId, 'EAST')

    local west = Coverage.GetCandidates(vector3(-50, 0, 0))
    ASSERT_EQ(west[1].towerId, 'SECTOR_COVERAGE')
    ASSERT_EQ(west[1].sectorId, 'WEST')

    local fallback = Coverage.GetCandidates(vector3(300, 0, 0))
    ASSERT_EQ(#fallback, 1)
    ASSERT_EQ(fallback[1].towerId, 'LEGACY_COVERAGE')
    ASSERT_EQ(fallback[1].sectorId, nil)
end)

TEST('sector capacity is isolated per sector and exposed to selection', function()
    local tower = makeTower('SECTOR_CAPACITY', {
        makeSector('A', 0, { capacity = 2 }),
        makeSector('B', 180, { capacity = 10 }),
    })
    ASSERT_TRUE(TowerRegistry.Init({ tower }))

    local result = Capacity.RecalculateSector('SECTOR_CAPACITY', 'A', {
        { towerId = 'SECTOR_CAPACITY', sectorId = 'A' },
        { towerId = 'SECTOR_CAPACITY', sectorId = 'A' },
        { towerId = 'SECTOR_CAPACITY', sectorId = 'B' },
    })
    ASSERT_EQ(result.connectedClients, 2)
    ASSERT_EQ(result.effectiveCapacity, 2)
    ASSERT_EQ(result.loadPercent, 100)
    ASSERT_EQ(TowerSectors.GetRuntime('SECTOR_CAPACITY', 'A').congestion,
        Enums.CongestionState.CRITICAL)

    local candidate = {
        towerId = 'SECTOR_CAPACITY',
        sectorId = 'B',
        tower = tower,
        sector = tower.sectors[2],
        signal = 80,
    }
    local score, details = Selection.Score(candidate)
    ASSERT_TRUE(score ~= nil)
    ASSERT_EQ(details.loadPercent, 0)
end)

TEST('sector failure is localized and does not remove neighboring beams', function()
    local tower = makeTower('SECTOR_FAILURE', {
        makeSector('EAST', 0),
        makeSector('WEST', 180),
    })
    ASSERT_TRUE(TowerRegistry.Init({ tower }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    ASSERT_TRUE(TowerSectors.SetState('SECTOR_FAILURE', 'EAST', Enums.TowerState.OFFLINE))

    local east = Coverage.GetCandidates(vector3(50, 0, 0))
    local west = Coverage.GetCandidates(vector3(-50, 0, 0))
    ASSERT_EQ(#east, 0)
    ASSERT_EQ(#west, 1)
    ASSERT_EQ(west[1].sectorId, 'WEST')
end)

TEST('sector failure records apply only to the addressed sector and stream to NOC', function()
    local tower = makeTower('SECTOR_FAILURE_ENGINE', {
        makeSector('EAST', 0),
        makeSector('WEST', 180),
    })
    FailureEngine.Reset()
    ASSERT_TRUE(TowerRegistry.Init({ tower }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local beforeEast = Coverage.GetCandidates(vector3(50, 0, 0))[1].signal
    local beforeWest = Coverage.GetCandidates(vector3(-50, 0, 0))[1].signal
    local ok, failure = FailureEngine.Create('SECTOR_FAILURE_ENGINE', 'SECTOR_FAILURE', {
        metadata = { sectorId = 'EAST' },
    })
    ASSERT_TRUE(ok)
    ASSERT_EQ(failure.metadata.sectorId, 'EAST')
    ASSERT_EQ(TowerSectors.GetRuntime('SECTOR_FAILURE_ENGINE', 'EAST').state,
        Enums.TowerState.DEGRADED)
    ASSERT_EQ(Coverage.GetCandidates(vector3(50, 0, 0))[1].signal, beforeEast * 0.70)
    ASSERT_EQ(Coverage.GetCandidates(vector3(-50, 0, 0))[1].signal, beforeWest)

    local entities = NocServer.BuildEntities({ towers = { tower } })
    local foundSector = false
    for _, entity in ipairs(entities) do
        if entity.entityType == 'sector'
            and entity.entityId == 'SECTOR_FAILURE_ENGINE:EAST' then
            foundSector = true
            ASSERT_EQ(entity.state.state, Enums.TowerState.DEGRADED)
        end
    end
    ASSERT_TRUE(foundSector)

    local debugSnapshot = TelecomDebug.InspectTower('SECTOR_FAILURE_ENGINE')
    ASSERT_TRUE(debugSnapshot ~= nil)
    ASSERT_EQ(#debugSnapshot.sectors, 2)
    local snapshotEntities = NocServer.BuildEntities({ towers = { debugSnapshot } })
    local snapshotSector = false
    for _, entity in ipairs(snapshotEntities) do
        if entity.entityType == 'sector'
            and entity.entityId == 'SECTOR_FAILURE_ENGINE:EAST' then
            snapshotSector = true
            break
        end
    end
    ASSERT_TRUE(snapshotSector)

    ASSERT_TRUE(FailureEngine.Clear(failure.id))
    ASSERT_EQ(Coverage.GetCandidates(vector3(50, 0, 0))[1].signal, beforeEast)
    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
end)

TEST('sector backhaul failure blocks services without taking neighboring towers offline', function()
    local tower = makeTower('SECTOR_BACKHAUL', {
        makeSector('EAST', 0),
    })
    FailureEngine.Reset()
    Connections.Clear()
    ASSERT_TRUE(TowerRegistry.Init({ tower }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local ok, failure = FailureEngine.Create('SECTOR_BACKHAUL', 'BACKHAUL_FAILURE', {
        metadata = { sectorId = 'EAST' },
    })
    ASSERT_TRUE(ok)
    local state = Connections.Reevaluate(102, vector3(50, 0, 0))
    ASSERT_EQ(state.towerId, 'SECTOR_BACKHAUL')
    ASSERT_EQ(state.backhaulStatus, Enums.BackhaulState.OFFLINE)
    ASSERT_FALSE(state.services.voice.available)
    ASSERT_EQ(state.services.voice.reason, 'backhaul')

    ASSERT_TRUE(FailureEngine.Clear(failure.id))
    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
end)

TEST('coverage enforces a bounded global candidate budget', function()
    local towers = {}
    for index = 1, 80 do
        towers[index] = makeTower(('BUDGET_%03d'):format(index))
    end
    ASSERT_TRUE(SpatialIndex.Rebuild(towers))
    local candidates = Coverage.GetCandidates(vector3(0, 0, 0))
    ASSERT_EQ(#candidates, Config.Sectors.maxCandidates)
    SpatialIndex.Rebuild({})
end)

TEST('sector registry bounds per-tower work and preserves old tower behavior', function()
    local sectors = {}
    for index = 1, 17 do sectors[index] = makeSector(('S%02d'):format(index), 0) end
    local ok, errors = TowerValidation.Validate(makeTower('SECTOR_LIMIT', sectors))
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors or {}, '; '):find('maximum', 1, true) ~= nil)

    local legacy = makeTower('OLD_TOWER')
    legacy.sectors = nil
    ASSERT_TRUE(TowerRegistry.Init({ legacy }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    ASSERT_EQ(#Coverage.GetCandidates(vector3(0, 0, 0)), 1)
    ASSERT_EQ(Coverage.GetCandidates(vector3(0, 0, 0))[1].towerId, 'OLD_TOWER')
end)
