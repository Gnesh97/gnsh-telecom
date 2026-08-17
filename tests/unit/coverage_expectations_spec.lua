local function makeExpectationTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetExpectationState()
    Connections.Clear()
    FailureEngine.Reset()
    TowerRegistry.Init({})
    SpatialIndex.Rebuild({})
end

TEST('coverage expectation catalog contains required and pending anchors', function()
    local valid, errors = TelecomCoverageExpectations.Validate()
    ASSERT_TRUE(valid, table.concat(errors or {}, '; '))

    local anchors = TelecomCoverageExpectations.GetAll()
    ASSERT_EQ(#anchors, 20)
    ASSERT_TRUE(TelecomCoverageExpectations.Find('DOWNTOWN_CORE'))
    ASSERT_TRUE(TelecomCoverageExpectations.Find('LSIA_CORE'))
    ASSERT_TRUE(TelecomCoverageExpectations.Find('SENORA_CORRIDOR'))

    local remote = TelecomCoverageExpectations.Find('RATON_REMOTE')
    ASSERT_TRUE(remote)
    ASSERT_TRUE(remote.captureRequired)
    ASSERT_EQ(remote.position, nil)
end)

TEST('coverage expectation validation requires real coordinates unless capture is pending', function()
    local previous = Config.CoverageExpectations
    Config.CoverageExpectations = {
        {
            id = 'INVALID_ANCHOR',
            category = 'INTENTIONAL_WEAK_ZONE',
            expectation = 'WEAK_OR_NONE',
        },
    }

    local valid, errors = TelecomCoverageExpectations.Validate()
    Config.CoverageExpectations = previous

    ASSERT_FALSE(valid)
    ASSERT_TRUE(#errors > 0)
end)

TEST('coverage expectation thresholds are monotonic', function()
    ASSERT_TRUE(TelecomCoverageExpectations.MatchesExpectation(100, 'STRONG'))
    ASSERT_FALSE(TelecomCoverageExpectations.MatchesExpectation(79.99, 'STRONG'))
    ASSERT_TRUE(TelecomCoverageExpectations.MatchesExpectation(55, 'GOOD'))
    ASSERT_TRUE(TelecomCoverageExpectations.MatchesExpectation(30, 'MODERATE'))
    ASSERT_TRUE(TelecomCoverageExpectations.MatchesExpectation(29.99, 'WEAK_OR_NONE'))
    ASSERT_FALSE(TelecomCoverageExpectations.MatchesExpectation(30, 'WEAK_OR_NONE'))
end)

TEST('pending weak anchor does not fabricate an evaluation', function()
    local result = TelecomCoverageExpectations.Evaluate(
        TelecomCoverageExpectations.Find('RATON_REMOTE')
    )

    ASSERT_EQ(result.status, 'PENDING_CAPTURE')
    ASSERT_EQ(result.signal, nil)
    ASSERT_EQ(result.band, nil)
end)

TEST('captured expectation evaluates the real coverage pipeline', function()
    resetExpectationState()
    TowerRegistry.Init({ makeExpectationTower('EXPECTATION_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local result = TelecomCoverageExpectations.Evaluate({
        id = 'TEST_ANCHOR',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(0, 0, 0),
        expectation = 'STRONG',
    })

    ASSERT_EQ(result.status, 'PASS')
    ASSERT_EQ(result.signal, 100)
    ASSERT_EQ(result.band, 'GREEN')
    ASSERT_EQ(result.towerId, 'EXPECTATION_TOWER')
    ASSERT_EQ(result.candidateCount, 1)
    ASSERT_EQ(Connections.Get(0), nil)

    resetExpectationState()
end)

TEST('coverage expectation commands register as development tools', function()
    local previousRegister = rawget(_G, 'RegisterCommand')
    local registered = {}
    RegisterCommand = function(name, handler) registered[name] = handler end

    local ok, errorCode = TelecomCoverageExpectations.RegisterCommands()
    ASSERT_TRUE(ok, errorCode)
    ASSERT_TRUE(type(registered.telecom_coverage_expectations) == 'function')
    ASSERT_TRUE(type(registered.telecom_coverage_capture) == 'function')

    rawset(_G, 'RegisterCommand', previousRegister)
end)
