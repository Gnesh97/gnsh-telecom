local function makeCandidate(id, signal, technologies)
    return {
        towerId = id,
        tower = {
            id = id,
            coords = vector3(0, 0, 0),
            technologies = technologies or { '4G' },
        },
        distance = 100,
        signal = signal,
    }
end

local function makeRuntime(id, loadPercent, health, state)
    return {
        towerId = id,
        connectedClients = 0,
        loadPercent = loadPercent or 0,
        health = health or 100,
        state = state or Enums.TowerState.OPERATIONAL,
    }
end

local function rank(candidates, runtimeByTowerId, options)
    options = options or {}
    options.runtimeByTowerId = runtimeByTowerId
    return Selection.Rank(candidates, options)
end

TEST('selection prefers stronger signal under equal conditions', function()
    local ranked = rank({
        makeCandidate('FAR_STRONG', 90),
        makeCandidate('NEAR_WEAK', 70),
    }, {
        FAR_STRONG = makeRuntime('FAR_STRONG'),
        NEAR_WEAK = makeRuntime('NEAR_WEAK'),
    })

    ASSERT_EQ(ranked[1].towerId, 'FAR_STRONG')
end)

TEST('selection prefers a lower-load tower when signal difference is small', function()
    local ranked = rank({
        makeCandidate('BUSY', 90),
        makeCandidate('AVAILABLE', 80),
    }, {
        BUSY = makeRuntime('BUSY', 100),
        AVAILABLE = makeRuntime('AVAILABLE', 0),
    })

    ASSERT_EQ(ranked[1].towerId, 'AVAILABLE')
    ASSERT_TRUE(ranked[1].scoreDetails.loadPenalty < ranked[2].scoreDetails.loadPenalty)
end)

TEST('selection applies health penalty to degraded towers', function()
    local ranked = rank({
        makeCandidate('DEGRADED', 90),
        makeCandidate('HEALTHY', 80),
    }, {
        DEGRADED = makeRuntime('DEGRADED', 0, 0),
        HEALTHY = makeRuntime('HEALTHY', 0, 100),
    })

    ASSERT_EQ(ranked[1].towerId, 'HEALTHY')
end)

TEST('selection excludes offline towers', function()
    local ranked = rank({
        makeCandidate('OFFLINE', 100),
        makeCandidate('ACTIVE', 40),
    }, {
        OFFLINE = makeRuntime('OFFLINE', 0, 100, Enums.TowerState.OFFLINE),
        ACTIVE = makeRuntime('ACTIVE'),
    })

    ASSERT_EQ(#ranked, 1)
    ASSERT_EQ(ranked[1].towerId, 'ACTIVE')
end)

TEST('selection applies preferred technology penalty', function()
    local ranked = rank({
        makeCandidate('LTE', 80, { '4G' }),
        makeCandidate('FIVE_G', 80, { '5G' }),
    }, {
        LTE = makeRuntime('LTE'),
        FIVE_G = makeRuntime('FIVE_G'),
    }, {
        preferredTechnology = '5G',
    })

    ASSERT_EQ(ranked[1].towerId, 'FIVE_G')
end)

TEST('selection tie-breaking is deterministic and exposes debug data', function()
    local input = {
        makeCandidate('BETA', 80),
        makeCandidate('ALPHA', 80),
    }
    local ranked = rank(input, {
        BETA = makeRuntime('BETA'),
        ALPHA = makeRuntime('ALPHA'),
    })

    ASSERT_EQ(ranked[1].towerId, 'ALPHA')
    ASSERT_TRUE(type(ranked[1].scoreDetails) == 'table')
    ASSERT_TRUE(type(ranked[1].scoreDetails.score) == 'number')
    ASSERT_EQ(input[1].score, nil)
end)
