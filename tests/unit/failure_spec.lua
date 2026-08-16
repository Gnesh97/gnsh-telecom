local function makeFailureTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetFailureState()
    FailureEngine.Reset()
    local tower = makeFailureTower('FAILURE_TOWER')
    ASSERT_TRUE(TowerRegistry.Init({ tower }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    Connections.Clear()
    return tower
end

TEST('failure types are data-driven and supported', function()
    for _, name in ipairs({
        'ANTENNA_FAILURE',
        'RADIO_FAILURE',
        'COOLING_FAILURE',
        'HARDWARE_DEGRADATION',
    }) do
        ASSERT_TRUE(FailureTypes.IsSupported(name))
        local definition = FailureTypes.Get(name)
        ASSERT_TRUE(definition.signalMultiplier > 0)
        ASSERT_TRUE(definition.signalMultiplier < 1)
        ASSERT_TRUE(definition.capacityMultiplier > 0)
        ASSERT_TRUE(definition.capacityMultiplier < 1)
    end
end)

TEST('manual antenna failure reduces signal and capacity without outage', function()
    local tower = resetFailureState()
    local before = Signal.CalculateRaw(tower, vector3(0, 0, 0))
    local ok, failure = FailureEngine.Create('FAILURE_TOWER', 'ANTENNA_FAILURE')
    local effects = FailureEngine.GetEffects('FAILURE_TOWER')
    local runtime = TowerRegistry.GetRuntimeState('FAILURE_TOWER')

    ASSERT_TRUE(ok)
    ASSERT_TRUE(failure.id ~= nil)
    ASSERT_TRUE(effects.signalMultiplier < 1)
    ASSERT_TRUE(effects.signalMultiplier > 0)
    ASSERT_TRUE(effects.capacityMultiplier < 1)
    ASSERT_TRUE(effects.capacityMultiplier > 0)
    ASSERT_EQ(Signal.CalculateRaw(tower, vector3(0, 0, 0)),
        before * effects.signalMultiplier)
    ASSERT_EQ(runtime.capacityMultiplier, effects.capacityMultiplier)
    ASSERT_EQ(#runtime.activeFailures, 1)
end)

TEST('multiple failures aggregate deterministically', function()
    resetFailureState()
    local okA = FailureEngine.Create('FAILURE_TOWER', 'ANTENNA_FAILURE')
    local okB = FailureEngine.Create('FAILURE_TOWER', 'COOLING_FAILURE')
    local antenna = FailureTypes.Get('ANTENNA_FAILURE')
    local cooling = FailureTypes.Get('COOLING_FAILURE')
    local effects = FailureEngine.GetEffects('FAILURE_TOWER')

    ASSERT_TRUE(okA)
    ASSERT_TRUE(okB)
    ASSERT_EQ(effects.signalMultiplier,
        antenna.signalMultiplier * cooling.signalMultiplier)
    ASSERT_EQ(effects.capacityMultiplier,
        antenna.capacityMultiplier * cooling.capacityMultiplier)
    ASSERT_EQ(#effects.activeFailures, 2)
end)

TEST('clearing failures restores normal tower behavior', function()
    local tower = resetFailureState()
    local ok, failure = FailureEngine.Create('FAILURE_TOWER', 'RADIO_FAILURE')
    ASSERT_TRUE(ok)
    ASSERT_TRUE(FailureEngine.Clear(failure.id))

    local effects = FailureEngine.GetEffects('FAILURE_TOWER')
    local runtime = TowerRegistry.GetRuntimeState('FAILURE_TOWER')
    ASSERT_EQ(effects.signalMultiplier, 1.0)
    ASSERT_EQ(effects.capacityMultiplier, 1.0)
    ASSERT_EQ(#effects.activeFailures, 0)
    ASSERT_EQ(runtime.capacityMultiplier, 1.0)
    ASSERT_EQ(Signal.CalculateRaw(tower, vector3(0, 0, 0)), 100)

    local first = FailureEngine.Create('FAILURE_TOWER', 'ANTENNA_FAILURE')
    local second = FailureEngine.Create('FAILURE_TOWER', 'COOLING_FAILURE')
    ASSERT_TRUE(first)
    ASSERT_TRUE(second)
    ASSERT_TRUE(FailureEngine.ClearAll('FAILURE_TOWER'))
    ASSERT_EQ(#FailureEngine.GetTowerFailures('FAILURE_TOWER'), 0)
end)

TEST('failure engine refreshes connected players and service policy', function()
    local tower = resetFailureState()
    local before = Connections.Reevaluate(7, vector3(0, 0, 0))
    ASSERT_EQ(before.signal, 100)

    local ok = FailureEngine.Create('FAILURE_TOWER', 'RADIO_FAILURE')
    local after = Connections.Get(7)
    ASSERT_TRUE(ok)
    ASSERT_TRUE(after.signal < before.signal)
    ASSERT_EQ(after.failureEffects.signalMultiplier,
        FailureTypes.Get('RADIO_FAILURE').signalMultiplier)
    ASSERT_FALSE(after.services.data.available)

    ASSERT_TRUE(FailureEngine.ClearAll('FAILURE_TOWER'))
    local restored = Connections.Get(7)
    ASSERT_EQ(restored.signal, 100)
    ASSERT_EQ(restored.failureEffects.signalMultiplier, 1.0)
end)

TEST('disabled failure feature rejects manual failures and neutralizes effects', function()
    resetFailureState()
    local previous = Config.Features.Failures
    Config.Features.Failures = false

    local ok, reason = FailureEngine.Create('FAILURE_TOWER', 'ANTENNA_FAILURE')
    local effects = FailureEngine.GetEffects('FAILURE_TOWER')

    Config.Features.Failures = previous

    ASSERT_FALSE(ok)
    ASSERT_EQ(reason, 'failures_disabled')
    ASSERT_EQ(effects.signalMultiplier, 1.0)
    ASSERT_EQ(effects.capacityMultiplier, 1.0)
end)

TEST('automatic failure scheduler stays disabled by default', function()
    FailureScheduler.Stop()
    local ok, reason = FailureScheduler.Start()

    ASSERT_FALSE(ok)
    ASSERT_EQ(reason, 'automatic_failures_disabled')
    ASSERT_FALSE(FailureScheduler.IsRunning())
end)
