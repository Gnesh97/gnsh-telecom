local function makeTower(technologies, sector)
    return {
        id = 'TECH_TOWER',
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = technologies or { '5G', '4G', '3G', 'EDGE' },
        capacity = { maximum = 100 },
        sector = sector,
    }
end

TEST('technology fallback order is deterministic and ends at no service', function()
    local order = TechnologySelection.GetFallbackOrder()
    ASSERT_EQ(table.concat(order, ','), '5G,4G,3G,EDGE')
    ASSERT_EQ(Technologies.NO_SERVICE, 'NO_SERVICE')
end)

TEST('5G is selected when the tower supports a valid 5G radio', function()
    local result = TechnologySelection.Resolve(
        makeTower({ '4G', '5G' }),
        { signal = 90 },
        {}
    )

    ASSERT_TRUE(result.available)
    ASSERT_EQ(result.technology, '5G')
    ASSERT_EQ(result.reason, 'selected')
end)

TEST('failed 5G falls back to 4G without losing service', function()
    local result = TechnologySelection.Resolve(
        makeTower({ '5G', '4G' }),
        { technology = '5G', signal = 90 },
        { failedTechnologies = { ['5G'] = true } }
    )

    ASSERT_TRUE(result.available)
    ASSERT_EQ(result.technology, '4G')
    ASSERT_EQ(result.fallbackFrom, '5G')
    ASSERT_EQ(result.reason, 'fallback')
end)

TEST('technology congestion skips only the congested radio and keeps fallback order', function()
    local result = TechnologySelection.Resolve(
        makeTower({ '5G', '4G', '3G' }),
        { signal = 90 },
        {
            congestionByTechnology = { ['5G'] = Enums.CongestionState.OVERLOADED },
        }
    )

    ASSERT_EQ(result.technology, '4G')
    ASSERT_EQ(result.reason, 'fallback')
    ASSERT_EQ(result.blockedTechnology, '5G')
end)

TEST('sector technology list constrains fallback independently from the parent tower', function()
    local sector = {
        id = 'SECTOR_A',
        technologies = { '4G', '3G' },
    }
    local result = TechnologySelection.Resolve(
        makeTower({ '5G', '4G' }, sector),
        { signal = 90 },
        {}
    )

    ASSERT_EQ(result.technology, '4G')
    ASSERT_FALSE(result.technology == '5G')
end)

TEST('technology capacity and service metadata affect the connection projection', function()
    local fiveG = TechnologySelection.Resolve(makeTower({ '5G' }), { signal = 90 }, {})
    ASSERT_TRUE(fiveG.capacityMultiplier > 1)
    ASSERT_TRUE(Capacity.GetEffectiveTechnologyCapacity(100, '5G') > 100)

    local edge = Services.Evaluate({
        source = 1,
        towerId = 'EDGE_TOWER',
        signal = 60,
        technology = 'EDGE',
        congestion = Enums.CongestionState.NORMAL,
        services = {},
    })
    ASSERT_EQ(edge.services.data.dataPerformance, 'VERY_SLOW')
    ASSERT_EQ(edge.technology, 'EDGE')
end)

TEST('connection reevaluation changes network type after a 5G technology failure', function()
    local tower = makeTower({ '5G', '4G' })
    tower.id = 'TECH_LIVE'
    ASSERT_TRUE(TowerRegistry.Init({ tower }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    Connections.Clear()

    local first = Connections.Reevaluate(77, vector3(0, 0, 0))
    ASSERT_EQ(first.technology, '5G')
    ASSERT_TRUE(TowerState.Update('TECH_LIVE', {
        technologyFailures = { ['5G'] = true },
    }))

    local fallback = Connections.Reevaluate(77, vector3(0, 0, 0))
    ASSERT_EQ(fallback.technology, '4G')
    ASSERT_EQ(fallback.technologyFallbackFrom, '5G')

    Connections.Clear()
    TowerState.Initialize({})
    SpatialIndex.Rebuild({})
end)

TEST('no available technology is explicit and fails closed', function()
    local result = TechnologySelection.Resolve(
        makeTower({ '5G', '4G' }),
        { signal = 90 },
        { failedTechnologies = { ['5G'] = true, ['4G'] = true } }
    )

    ASSERT_FALSE(result.available)
    ASSERT_EQ(result.technology, Technologies.NO_SERVICE)
    ASSERT_EQ(result.reason, 'no_available_technology')
end)
