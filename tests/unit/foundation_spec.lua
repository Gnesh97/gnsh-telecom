TEST('foundation exposes required configuration tables', function()
    ASSERT_TRUE(type(Config) == 'table')
    ASSERT_TRUE(type(Config.Debug) == 'table')
    ASSERT_TRUE(type(Config.Features) == 'table')
    ASSERT_TRUE(type(Config.Services) == 'table')
    ASSERT_TRUE(type(Config.Towers) == 'table')
end)

TEST('foundation defaults keep optional modules disabled', function()
    ASSERT_TRUE(Config.Features.Capacity)
    ASSERT_TRUE(Config.Features.Failures)
    ASSERT_TRUE(Config.Features.Handover)
    ASSERT_FALSE(Config.Features.Technician)
    ASSERT_FALSE(Config.Features.Incidents)
    ASSERT_FALSE(Config.Features.NOC)
    ASSERT_FALSE(Config.Features.Backhaul)
    ASSERT_FALSE(Config.Features.Sabotage)
    ASSERT_FALSE(Config.Features.Jammers)
    ASSERT_FALSE(Config.Features.Statistics)
end)

TEST('enums centralize tower and service states', function()
    ASSERT_EQ(Enums.TowerState.OPERATIONAL, 'OPERATIONAL')
    ASSERT_EQ(Enums.SignalLevel.NO_SERVICE, 'NO_SERVICE')
    ASSERT_EQ(Enums.Service.DATA, 'DATA')
    ASSERT_EQ(Enums.IncidentState.CLOSED, 'CLOSED')
end)

TEST('utils clamp and deep copy are immutable-safe', function()
    ASSERT_EQ(Utils.Clamp(-1, 0, 100), 0)
    ASSERT_EQ(Utils.Clamp(101, 0, 100), 100)
    ASSERT_EQ(Utils.Clamp(50, 0, 100), 50)

    local original = { nested = { value = 10 } }
    local copy = Utils.DeepCopy(original)
    copy.nested.value = 20
    ASSERT_EQ(original.nested.value, 10)
end)

TEST('locales resolve known keys and fall back safely', function()
    ASSERT_EQ(Locale.Translate('en', 'startup.ready'), 'gnsh-telecom started')
    ASSERT_EQ(Locale.Translate('tr', 'startup.ready'), 'gnsh-telecom başlatıldı')
    ASSERT_EQ(Locale.Translate('en', 'missing.key'), 'missing.key')
end)

TEST('default configuration passes validation', function()
    local ok, errors = Config.Validate()
    ASSERT_TRUE(ok, table.concat(errors or {}, '; '))
end)

TEST('invalid critical configuration fails validation', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.Signal.Levels.GOOD.min = 120
    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(#errors > 0)
end)

TEST('invalid debug and bridge settings fail validation', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.Debug.logLevel = 'verbose'
    invalid.PhoneBridge = 'unknown'
    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(#errors >= 2)
end)

TEST('invalid capacity thresholds fail validation', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.Capacity.thresholds.busy = 80
    invalid.Capacity.thresholds.congested = 70

    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('strictly increasing', 1, true) ~= nil)
end)

TEST('duplicate tower ids fail validation', function()
    local invalid = Utils.DeepCopy(Config)
    invalid.Towers = {
        {
            id = 'TEST_01',
            coords = vector3(0.0, 0.0, 0.0),
            coverage = { radius = 1000.0, minimum = 50.0 },
            technologies = { '4G' },
            capacity = { maximum = 100 },
        },
        {
            id = 'TEST_01',
            coords = vector3(100.0, 100.0, 0.0),
            coverage = { radius = 1000.0, minimum = 50.0 },
            technologies = { '4G' },
            capacity = { maximum = 100 },
        },
    }
    local ok, errors = Config.Validate(invalid)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('duplicate tower id', 1, true) ~= nil)
end)
