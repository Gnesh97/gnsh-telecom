local function makeTower(id, x, y, radius)
    return {
        id = id,
        coords = vector3(x, y, 0),
        coverage = {
            radius = radius or 50,
            minimum = 10,
        },
        technologies = { '4G' },
        capacity = {
            maximum = 100,
        },
    }
end

local function ids(towers)
    local result = {}
    for _, tower in ipairs(towers) do
        result[#result + 1] = tower.id
    end
    table.sort(result)
    return result
end

local function assertIds(towers, expected)
    local actual = ids(towers)
    ASSERT_EQ(#actual, #expected, 'candidate count differs')
    for index, id in ipairs(expected) do
        ASSERT_EQ(actual[index], id, ('candidate %d differs'):format(index))
    end
end

TEST('spatial index maps positive and negative coordinates to deterministic cells', function()
    local previousCellSize = Config.Spatial.cellSize
    Config.Spatial.cellSize = 100

    ASSERT_EQ(SpatialIndex.GetCell(vector3(0, 0, 0)), '0:0')
    ASSERT_EQ(SpatialIndex.GetCell(vector3(99.99, -100, 0)), '0:-1')
    ASSERT_EQ(SpatialIndex.GetCell(vector3(-0.01, 0, 0)), '-1:0')

    Config.Spatial.cellSize = previousCellSize
end)

TEST('spatial index finds coverage crossing neighboring cells', function()
    local previousCellSize = Config.Spatial.cellSize
    Config.Spatial.cellSize = 100

    local towers = {
        makeTower('EDGE', 50, 50, 75),
        makeTower('FAR', 1000, 1000, 50),
    }
    ASSERT_TRUE(SpatialIndex.Rebuild(towers))

    local candidates = SpatialIndex.GetNearbyTowers(vector3(125, 50, 0))
    assertIds(candidates, { 'EDGE' })

    Config.Spatial.cellSize = previousCellSize
end)

TEST('spatial index excludes distant towers and exposes candidate statistics', function()
    local towers = {
        makeTower('NEAR', 0, 0, 100),
        makeTower('MID', 2000, 0, 100),
        makeTower('FAR', 5000, 5000, 100),
    }
    ASSERT_TRUE(SpatialIndex.Rebuild(towers))

    assertIds(SpatialIndex.GetNearbyTowers(vector3(0, 0, 0)), { 'NEAR' })
    assertIds(SpatialIndex.GetNearbyTowers(vector3(5000, 5000, 0)), { 'FAR' })

    local stats = SpatialIndex.GetStats()
    ASSERT_EQ(stats.towerCount, 3)
    ASSERT_TRUE(stats.cellCount > 0)
    ASSERT_EQ(stats.candidateCount, 1)
    ASSERT_TRUE(stats.candidateCount < stats.towerCount)
end)

TEST('spatial index rebuild produces deterministic candidates', function()
    local first = {
        makeTower('ZETA', 0, 0, 150),
        makeTower('ALPHA', 100, 0, 150),
        makeTower('BETA', 2000, 0, 50),
    }
    local second = {
        first[3],
        first[1],
        first[2],
    }

    ASSERT_TRUE(SpatialIndex.Rebuild(first))
    local firstCandidates = SpatialIndex.GetNearbyTowers(vector3(100, 0, 0))
    ASSERT_TRUE(SpatialIndex.Rebuild(second))
    local secondCandidates = SpatialIndex.GetNearbyTowers(vector3(100, 0, 0))

    assertIds(firstCandidates, { 'ALPHA', 'ZETA' })
    assertIds(secondCandidates, { 'ALPHA', 'ZETA' })
end)

TEST('spatial index handles one hundred towers with a reduced candidate set', function()
    local towers = {}
    for index = 1, 100 do
        towers[index] = makeTower(('T%03d'):format(index), index * 2000, 0, 50)
    end

    ASSERT_TRUE(SpatialIndex.Rebuild(towers))
    local candidates = SpatialIndex.GetNearbyTowers(vector3(2000, 0, 0))
    local stats = SpatialIndex.GetStats()

    ASSERT_EQ(#candidates, 1)
    ASSERT_EQ(candidates[1].id, 'T001')
    ASSERT_EQ(stats.towerCount, 100)
    ASSERT_TRUE(stats.candidateCount < stats.towerCount)
end)

TEST('spatial index insert returns defensive copies', function()
    ASSERT_TRUE(SpatialIndex.Rebuild({}))
    local tower = makeTower('COPY', 10, 10, 100)
    ASSERT_TRUE(SpatialIndex.InsertTower(tower))

    tower.coords.x = 9999
    local candidates = SpatialIndex.GetNearbyTowers(vector3(10, 10, 0))
    ASSERT_EQ(#candidates, 1)
    ASSERT_EQ(candidates[1].coords.x, 10)

    candidates[1].coverage.radius = 1
    ASSERT_EQ(SpatialIndex.GetNearbyTowers(vector3(10, 10, 0))[1].coverage.radius, 100)
end)

TEST('spatial index rebuild failure preserves the previous index', function()
    local valid = makeTower('STABLE', 0, 0, 100)
    ASSERT_TRUE(SpatialIndex.Rebuild({ valid }))

    local ok = SpatialIndex.Rebuild({ makeTower('INVALID', 0, 0, -1) })
    ASSERT_FALSE(ok)
    assertIds(SpatialIndex.GetNearbyTowers(vector3(0, 0, 0)), { 'STABLE' })
end)
