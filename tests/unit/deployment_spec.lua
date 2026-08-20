local function legacyTower()
    return {
        id = 'LEGACY_TOWER',
        coords = vector3(10.0, 20.0, 30.0),
        coverage = { radius = 1600.0, minimum = 50.0 },
        technologies = { '4G' },
        capacity = { maximum = 150 },
    }
end

TEST('deployment exposes reusable archetypes and coverage policy', function()
    ASSERT_TRUE(type(Config.TowerArchetypes) == 'table')
    ASSERT_EQ(Config.TowerArchetypes.METRO_MACRO.coverageRadius, 850)
    ASSERT_EQ(Config.TowerArchetypes.REMOTE_REPEATER.capacity, 10)
    ASSERT_TRUE(type(Config.CoverageZones) == 'table')
    ASSERT_TRUE(type(Config.CoverageZones.INTENTIONAL_DEADZONE) == 'table')
end)

TEST('deployment fills archetype defaults and preserves per-tower overrides', function()
    local tower = legacyTower()
    tower.class = 'METRO_MACRO'
    tower.coverage = { minimum = 42.0 }
    tower.capacity = { maximum = 99 }

    local ok, errors, normalized = TelecomDeployment.NormalizeTower(tower)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(normalized.coverage.radius, 850)
    ASSERT_EQ(normalized.coverage.minimum, 42.0)
    ASSERT_EQ(normalized.capacity.maximum, 99)
    ASSERT_EQ(normalized.class, 'METRO_MACRO')
end)

TEST('deployment supports class-only tower definitions', function()
    local tower = legacyTower()
    tower.class = 'REMOTE_REPEATER'
    tower.coverage = nil
    tower.capacity = nil

    local ok, errors, normalized = TelecomDeployment.NormalizeTower(tower)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(normalized.coverage.radius, 450)
    ASSERT_EQ(normalized.coverage.minimum, 50)
    ASSERT_EQ(normalized.capacity.maximum, 10)
end)

TEST('tower validation preserves advanced metadata while applying archetypes', function()
    local tower = legacyTower()
    tower.class = 'HIGHWAY_REPEATER'
    tower.coverage = nil
    tower.capacity = nil
    tower.coverageZone = 'HIGHWAY'
    tower.regionId = 'REGION_TEST'
    tower.backhaulNodeId = 'NODE_TEST'
    tower.carriers = { 'carrier_a' }

    local ok, errors, normalized = TowerValidation.Validate(tower)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(normalized.coverage.radius, 750)
    ASSERT_EQ(normalized.capacity.maximum, 30)
    ASSERT_EQ(normalized.regionId, 'REGION_TEST')
    ASSERT_EQ(normalized.backhaulNodeId, 'NODE_TEST')
    ASSERT_EQ(normalized.carriers[1], 'carrier_a')
end)

TEST('deployment rejects unknown archetypes and coverage zones', function()
    local unknownClass = legacyTower()
    unknownClass.class = 'NOT_A_TOWER_CLASS'
    local ok, errors = TelecomDeployment.NormalizeTower(unknownClass)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('unknown tower archetype', 1, true) ~= nil)

    local unknownZone = legacyTower()
    unknownZone.coverageZone = 'NOT_A_ZONE'
    ok, errors = TelecomDeployment.NormalizeTower(unknownZone)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('unknown coverage zone', 1, true) ~= nil)
end)

TEST('legacy tower definitions remain unchanged without an archetype', function()
    local ok, errors, normalized = TelecomDeployment.NormalizeTower(legacyTower())
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
    ASSERT_EQ(normalized.coverage.radius, 1600.0)
    ASSERT_EQ(normalized.capacity.maximum, 150)
    ASSERT_EQ(normalized.class, nil)
end)

TEST('config validation applies archetypes and rejects unknown deployment metadata', function()
    local valid = Utils.DeepCopy(Config)
    valid.Towers = { legacyTower() }
    valid.Towers[1].class = 'TOWN_MACRO'
    valid.Towers[1].coverage = nil
    valid.Towers[1].capacity = nil

    local ok, errors = Config.Validate(valid)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))

    local invalid = Utils.DeepCopy(valid)
    invalid.Towers[1].class = 'UNKNOWN_MACRO'
    ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('unknown tower archetype', 1, true) ~= nil)
end)

TEST('config validation uses custom deployment tables passed to the validator', function()
    local custom = Utils.DeepCopy(Config)
    custom.TowerArchetypes.CUSTOM_MACRO = {
        coverageRadius = 900,
        capacity = 40,
    }
    custom.Towers = { legacyTower() }
    custom.Towers[1].class = 'CUSTOM_MACRO'
    custom.Towers[1].coverage = nil
    custom.Towers[1].capacity = nil

    local ok, errors = Config.Validate(custom)
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
end)

TEST('production towers align region and backhaul metadata', function()
    local seen = {}
    for _, tower in ipairs(Config.Towers) do
        seen[tower.id] = true
        ASSERT_TRUE(type(tower.regionId) == 'string')
        ASSERT_TRUE(type(tower.backhaulNodeId) == 'string')
        ASSERT_EQ(Config.Backhaul.towerNodes[tower.id], tower.backhaulNodeId)
    end
    ASSERT_EQ(#Config.Towers, 40)
    ASSERT_TRUE(seen['BC-CHUMASH-01'])

    local ok, errors = Config.Validate()
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
end)

TEST('config validation rejects mismatched deployment metadata', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.Towers[1].backhaulNodeId = 'AGG-LS-01'

    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('backhaulNodeId', 1, true) ~= nil)
end)
