local function makeTower(id, x, y, radius, state)
    return {
        id = id,
        coords = vector3(x, y, 0),
        coverage = {
            radius = radius or 100,
            minimum = 10,
        },
        technologies = { '4G' },
        capacity = {
            maximum = 100,
        },
        state = state,
    }
end

TEST('raw signal uses a gradual configured distance falloff', function()
    local tower = makeTower('SIGNAL', 0, 0, 100)
    local exponent = Config.Signal.DistanceFalloffExponent
    local halfway = Signal.CalculateRaw(tower, vector3(50, 0, 0))
    local nearEdge = Signal.CalculateRaw(tower, vector3(99, 0, 0))
    local expectedHalfway = 100 * (1 - (0.5 ^ exponent))
    local expectedNearEdge = 100 * (1 - (0.99 ^ exponent))

    ASSERT_EQ(Signal.CalculateRaw(tower, vector3(0, 0, 0)), 100)
    ASSERT_TRUE(exponent > 1)
    ASSERT_TRUE(math.abs(halfway - expectedHalfway) < 0.000001)
    ASSERT_TRUE(math.abs(nearEdge - expectedNearEdge) < 0.000001)
    ASSERT_TRUE(halfway > 50)
    ASSERT_TRUE(nearEdge > 1)
    ASSERT_EQ(Signal.CalculateRaw(tower, vector3(101, 0, 0)), 0)
end)

TEST('signal distance falloff validation rejects non-gradual curves', function()
    local previous = Config.Signal.DistanceFalloffExponent
    Config.Signal.DistanceFalloffExponent = 0.5

    local valid, errors = Config.Validate()

    Config.Signal.DistanceFalloffExponent = previous

    ASSERT_FALSE(valid)
    ASSERT_TRUE(table.concat(errors or {}, '; '):find(
        'Signal.DistanceFalloffExponent', 1, true) ~= nil)
end)

TEST('raw signal returns no-service for invalid points and offline towers', function()
    local tower = makeTower('SIGNAL', 0, 0, 100)
    local offline = makeTower('OFFLINE', 0, 0, 100, Enums.TowerState.OFFLINE)

    ASSERT_EQ(Signal.CalculateRaw(tower, {}), 0)
    ASSERT_EQ(Signal.CalculateRaw(offline, vector3(0, 0, 0)), 0)
end)

TEST('coverage filters exact distance and unavailable tower states', function()
    local towers = {
        makeTower('ACTIVE', 0, 0, 100),
        makeTower('OFFLINE', 50, 0, 100, Enums.TowerState.OFFLINE),
        makeTower('EDGE_CANDIDATE', 900, 0, 200),
        makeTower('FAR', 5000, 5000, 100),
    }
    ASSERT_TRUE(SpatialIndex.Rebuild(towers))

    local candidates = Coverage.GetCandidates(vector3(0, 0, 0))
    ASSERT_EQ(#candidates, 1)
    ASSERT_EQ(candidates[1].towerId, 'ACTIVE')
    ASSERT_EQ(candidates[1].tower.id, 'ACTIVE')
    ASSERT_EQ(candidates[1].distance, 0)
    ASSERT_EQ(candidates[1].signal, 100)
end)

TEST('coverage returns candidates sorted by signal and tower ID', function()
    local towers = {
        makeTower('BETA', 25, 0, 100),
        makeTower('ALPHA', 0, 0, 100),
        makeTower('TIE', 0, 0, 100),
    }
    ASSERT_TRUE(SpatialIndex.Rebuild(towers))

    local candidates = Coverage.GetCandidates(vector3(0, 0, 0))
    ASSERT_EQ(#candidates, 3)
    ASSERT_EQ(candidates[1].towerId, 'ALPHA')
    ASSERT_EQ(candidates[2].towerId, 'TIE')
    ASSERT_EQ(candidates[3].towerId, 'BETA')
    ASSERT_TRUE(candidates[1].signal >= candidates[2].signal)
    ASSERT_TRUE(candidates[2].signal > candidates[3].signal)
end)

TEST('coverage delegates candidate discovery to spatial index', function()
    local tower = makeTower('INDEX_ONLY', 0, 0, 100)
    local previous = SpatialIndex.GetNearbyTowers
    local calls = 0
    SpatialIndex.GetNearbyTowers = function(coords)
        calls = calls + 1
        ASSERT_EQ(coords.x, 0)
        return { tower }
    end

    local candidates = Coverage.GetCandidates(vector3(0, 0, 0))
    SpatialIndex.GetNearbyTowers = previous

    ASSERT_EQ(calls, 1)
    ASSERT_EQ(#candidates, 1)
    ASSERT_EQ(candidates[1].towerId, 'INDEX_ONLY')
end)

TEST('coverage returns no candidates outside all tower radii', function()
    ASSERT_TRUE(SpatialIndex.Rebuild({ makeTower('ONLY', 0, 0, 100) }))
    ASSERT_EQ(#Coverage.GetCandidates(vector3(500, 500, 0)), 0)
    ASSERT_EQ(#Coverage.GetCandidates({}), 0)
end)
