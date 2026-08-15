local function makeTower(id, x)
    return {
        id = id,
        coords = vector3(x or 0.0, 0.0, 0.0),
        coverage = { radius = 1600.0, minimum = 50.0 },
        technologies = { '3G', '4G', '5G' },
        capacity = { maximum = 150 },
        hardware = { health = 100, antennas = {}, radio = {}, cooling = {} },
        backhaul = { status = Enums.BackhaulState.ONLINE },
        state = Enums.TowerState.OPERATIONAL,
    }
end

TEST('tower validation accepts a valid definition', function()
    local ok, errors = TowerValidation.Validate(makeTower('LS_01'))
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
end)

TEST('registry registers towers deterministically', function()
    local ok, errors = TowerRegistry.Init({
        makeTower('LS_02', 200.0),
        makeTower('LS_01', 100.0),
    })
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(TowerRegistry.Count(), 2)
    ASSERT_EQ(TowerRegistry.GetAll()[1].id, 'LS_01')
    ASSERT_EQ(TowerRegistry.GetAll()[2].id, 'LS_02')
end)

TEST('registry handles fifty towers', function()
    local towers = {}
    for index = 1, 50 do
        towers[index] = makeTower(('LS_%02d'):format(index), index * 100.0)
    end
    local ok, errors = TowerRegistry.Init(towers)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(TowerRegistry.Count(), 50)
    ASSERT_TRUE(TowerRegistry.Exists('LS_01'))
    ASSERT_TRUE(TowerRegistry.Exists('LS_50'))
end)

TEST('registry initializes independent runtime state', function()
    TowerRegistry.Init({ makeTower('LS_RUNTIME') })
    local runtime = TowerRegistry.GetRuntimeState('LS_RUNTIME')
    ASSERT_EQ(runtime.towerId, 'LS_RUNTIME')
    ASSERT_EQ(runtime.connectedClients, 0)
    ASSERT_EQ(runtime.loadPercent, 0)
    ASSERT_EQ(runtime.health, 100)
    ASSERT_EQ(runtime.state, Enums.TowerState.OPERATIONAL)
    ASSERT_EQ(runtime.backhaulStatus, Enums.BackhaulState.ONLINE)
    ASSERT_EQ(#runtime.activeFailures, 0)
end)

TEST('duplicate tower ids are rejected atomically', function()
    TowerRegistry.Init({ makeTower('LS_STABLE') })
    local ok, errors = TowerRegistry.Init({
        makeTower('LS_DUPLICATE'),
        makeTower('LS_DUPLICATE', 100.0),
    })
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('duplicate tower id', 1, true) ~= nil)
    ASSERT_EQ(TowerRegistry.Count(), 1)
    ASSERT_TRUE(TowerRegistry.Exists('LS_STABLE'))
end)

TEST('invalid radius and technology are rejected', function()
    local invalidRadius = makeTower('LS_BAD_RADIUS')
    invalidRadius.coverage.radius = -1
    local ok, errors = TowerValidation.Validate(invalidRadius)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('coverage.radius', 1, true) ~= nil)

    local invalidTechnology = makeTower('LS_BAD_TECH')
    invalidTechnology.technologies = { '6G' }
    ok, errors = TowerValidation.Validate(invalidTechnology)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('unsupported technology', 1, true) ~= nil)
end)

TEST('invalid coordinates and capacity are rejected', function()
    local invalidCoordinates = makeTower('LS_BAD_COORDS')
    invalidCoordinates.coords = { x = 0.0, y = 'not-a-number', z = 0.0 }
    local ok, errors = TowerValidation.Validate(invalidCoordinates)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('coords', 1, true) ~= nil)

    local invalidCapacity = makeTower('LS_BAD_CAPACITY')
    invalidCapacity.capacity.maximum = 0
    ok, errors = TowerValidation.Validate(invalidCapacity)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('capacity.maximum', 1, true) ~= nil)
end)

TEST('registry returns defensive copies', function()
    TowerRegistry.Init({ makeTower('LS_COPY') })
    local tower = TowerRegistry.Get('LS_COPY')
    tower.coverage.radius = 10
    tower.technologies[1] = 'EDGE'
    local runtime = TowerRegistry.GetRuntimeState('LS_COPY')
    runtime.activeFailures[1] = 'FAIL-1'

    ASSERT_EQ(TowerRegistry.Get('LS_COPY').coverage.radius, 1600.0)
    ASSERT_EQ(TowerRegistry.Get('LS_COPY').technologies[1], '3G')
    ASSERT_EQ(#TowerRegistry.GetRuntimeState('LS_COPY').activeFailures, 0)
end)

TEST('unknown tower lookups return safe nil values', function()
    TowerRegistry.Init({ makeTower('LS_KNOWN') })
    ASSERT_FALSE(TowerRegistry.Exists('LS_UNKNOWN'))
    ASSERT_EQ(TowerRegistry.Get('LS_UNKNOWN'), nil)
    ASSERT_EQ(TowerRegistry.GetRuntimeState('LS_UNKNOWN'), nil)
end)
