local expectedSiteIds = {
    'LS-LSIA-01',
    'LS-PORT-01',
    'LS-LAPUERTA-01',
    'LS-VESPUCCI-01',
    'LS-DELPERRO-01',
    'LS-ROCKFORD-01',
    'LS-DOWNTOWN-01',
    'LS-MISSIONROW-01',
    'LS-DAVIS-01',
    'LS-LAMESA-01',
    'LS-CYPRESS-01',
    'LS-MURRIETA-01',
    'LS-VINEWOOD-01',
    'LS-MIRRORPARK-01',
    'LS-RICHMAN-01',
    'LS-EAST-01',
    'BC-SANDY-01',
    'BC-SANDY-02',
    'BC-GRAPESEED-01',
    'BC-PALETO-01',
    'BC-PALETO-02',
    'BC-HARMONY-01',
    'BC-CHUMASH-01',
    'BC-ZANCUDO-01',
    'HW-GOH-01',
    'HW-GOH-02',
    'HW-SENORA-01',
    'HW-SENORA-02',
    'HW-R68-01',
    'HW-PALOMINO-01',
    'HW-NORTH-01',
    'RM-CHILIAD-CABLE-01',
}

local function hasValue(values, expected)
    for _, value in ipairs(values) do
        if value == expected then return true end
    end
    return false
end

TEST('deployment site catalog contains the planned ids without coordinates', function()
    ASSERT_EQ(#Config.DeploymentSites, #expectedSiteIds)
    local seen = {}
    for _, site in ipairs(Config.DeploymentSites) do
        ASSERT_FALSE(seen[site.id], 'deployment site ids must be unique')
        ASSERT_FALSE(site.coords ~= nil, 'site catalog must not contain production coordinates')
        seen[site.id] = true
    end
    for _, siteId in ipairs(expectedSiteIds) do
        ASSERT_TRUE(seen[siteId], ('missing deployment site: %s'):format(siteId))
    end
end)

TEST('deployment site catalog uses known archetypes, zones and purposes', function()
    local validClasses = {
        METRO_MACRO = true,
        TOWN_MACRO = true,
        RURAL_MACRO = true,
        HIGHWAY_REPEATER = true,
        REMOTE_REPEATER = true,
    }
    local validZones = {
        METRO_CORE = true,
        METRO_EDGE = true,
        TOWN = true,
        HIGHWAY = true,
        RURAL = true,
        WILDERNESS = true,
        INTENTIONAL_DEADZONE = true,
    }
    for _, site in ipairs(Config.DeploymentSites) do
        ASSERT_TRUE(validClasses[site.class], 'site class must be known')
        ASSERT_TRUE(validZones[site.coverageZone], 'site zone must be known')
        ASSERT_TRUE(type(site.purpose) == 'string' and site.purpose ~= '')
        ASSERT_TRUE(type(site.technologies) == 'table' and #site.technologies > 0)
    end
end)

TEST('deployment editor is disabled by the production default', function()
    ASSERT_FALSE(Config.Features.DeploymentTools)
    ASSERT_FALSE(TelecomDeploymentEditor.IsEnabled())
end)

TEST('deployment editor builds an immutable capture from a catalog site', function()
    local site = TelecomDeploymentEditor.FindSite('LS-DOWNTOWN-01')
    local capture, errorCode = TelecomDeploymentEditor.BuildCapture(
        site,
        { x = 123.4567, y = -456.7891, z = 30.1234 },
        721.25
    )

    ASSERT_TRUE(capture)
    ASSERT_EQ(errorCode, nil)
    ASSERT_EQ(capture.id, 'LS-DOWNTOWN-01')
    ASSERT_EQ(capture.class, 'METRO_MACRO')
    ASSERT_EQ(capture.coverageZone, 'METRO_CORE')
    ASSERT_EQ(capture.coords.x, 123.4567)
    ASSERT_EQ(capture.heading, 1.25)
    ASSERT_EQ(site.coords, nil)
    capture.coords.x = 999
    ASSERT_EQ(site.coords, nil)
end)

TEST('deployment editor rejects invalid captures and unknown sites', function()
    local site = TelecomDeploymentEditor.FindSite('LS-DOWNTOWN-01')
    local capture, errorCode = TelecomDeploymentEditor.BuildCapture(
        site,
        { x = math.huge, y = 0, z = 0 },
        0
    )
    ASSERT_EQ(capture, nil)
    ASSERT_EQ(errorCode, 'invalid_coordinates')

    capture, errorCode = TelecomDeploymentEditor.BuildCapture(
        nil,
        { x = 0, y = 0, z = 0 },
        0
    )
    ASSERT_EQ(capture, nil)
    ASSERT_EQ(errorCode, 'unknown_site')
end)

TEST('deployment editor export is deterministic and ready for tower configuration', function()
    local first = TelecomDeploymentEditor.BuildCapture(
        TelecomDeploymentEditor.FindSite('LS-DOWNTOWN-01'),
        { x = 20, y = 10, z = 30 },
        90
    )
    local second = TelecomDeploymentEditor.BuildCapture(
        TelecomDeploymentEditor.FindSite('LS-LSIA-01'),
        { x = 1, y = 2, z = 3 },
        180
    )
    local lines = TelecomDeploymentEditor.FormatExport({ first, second })
    local output = table.concat(lines, '\n')

    ASSERT_TRUE(type(lines) == 'table')
    ASSERT_TRUE(output:find("id = 'LS%-LSIA%-01'", 1, false) ~= nil)
    ASSERT_TRUE(output:find("id = 'LS%-DOWNTOWN%-01'", 1, false) ~= nil)
    ASSERT_TRUE(output:find('coords = vector3%(1%.00, 2%.00, 3%.00%)', 1, false) ~= nil)
    ASSERT_TRUE(output:find("class = 'METRO_MACRO'", 1, false) ~= nil)
    ASSERT_TRUE(output:find('capturedHeading = 180.00', 1, false) ~= nil)
    ASSERT_TRUE(output:find('Config.Towers = {', 1, true) == nil)
    ASSERT_TRUE(output:find('LS%-DOWNTOWN%-01') < output:find('LS%-LSIA%-01'))

    local repeated = table.concat(TelecomDeploymentEditor.FormatExport({ second, first }), '\n')
    ASSERT_EQ(output, repeated)
end)

TEST('config validation rejects deployment catalog coordinates', function()
    local candidate = Utils.DeepCopy(Config)
    candidate.DeploymentSites[1].coords = vector3(1, 2, 3)
    local ok, errors = Config.Validate(candidate)
    ASSERT_FALSE(ok)
    local found = false
    for _, message in ipairs(errors) do
        if message:find('DeploymentSites%[1%]%.coords') then found = true end
    end
    ASSERT_TRUE(found, 'catalog coordinates must be rejected')
end)

TEST('config validation rejects catalog holes and duplicate technologies', function()
    local candidate = Utils.DeepCopy(Config)
    candidate.DeploymentSites[2] = nil
    local ok, errors = Config.Validate(candidate)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('contiguous array', 1, true) ~= nil)

    candidate = Utils.DeepCopy(Config)
    candidate.DeploymentSites[1].technologies = { '4G', '4G' }
    ok, errors = Config.Validate(candidate)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('duplicates 4G', 1, true) ~= nil)
end)

TEST('deployment export fails closed for invalid captures', function()
    local lines, errors = TelecomDeploymentEditor.FormatExport({
        {
            id = 'LS-DOWNTOWN-01',
            class = 'METRO_MACRO',
            coverageZone = 'METRO_CORE',
            purpose = 'invalid capture',
            technologies = { '4G' },
            coords = { x = math.huge, y = 0, z = 0 },
        },
    })
    ASSERT_EQ(lines, nil)
    ASSERT_TRUE(type(errors) == 'table' and #errors > 0)
end)

TEST('config validation requires a non-empty catalog when tools are enabled', function()
    local candidate = Utils.DeepCopy(Config)
    candidate.Features.DeploymentTools = true
    candidate.DeploymentSites = {}
    local ok, errors = Config.Validate(candidate)
    ASSERT_FALSE(ok)
    ASSERT_TRUE(table.concat(errors, '; '):find('DeploymentSites must not be empty', 1, true) ~= nil)
end)

TEST('client editor preview state is isolated and removable', function()
    TelecomClientDeploymentEditor.SetEnabled(false)
    TelecomClientDeploymentEditor.SetPreview({
        id = 'LS-DOWNTOWN-01',
        class = 'METRO_MACRO',
        coverageRadius = 850,
    })
    local status = TelecomClientDeploymentEditor.GetStatus()
    ASSERT_TRUE(status.enabled)
    ASSERT_EQ(status.preview.id, 'LS-DOWNTOWN-01')
    TelecomClientDeploymentEditor.ClearPreview()
    ASSERT_EQ(TelecomClientDeploymentEditor.GetStatus().preview, nil)
    TelecomClientDeploymentEditor.SetEnabled(false)
end)

TEST('server editor starts without authoritative captures', function()
    TelecomDeploymentEditorServer.Reset()
    ASSERT_EQ(#TelecomDeploymentEditorServer.GetCaptures(), 0)
end)

TEST('server editor does not register commands under production defaults', function()
    ASSERT_FALSE(TelecomDeploymentEditorServer.IsEnabled())
    local ok, errorCode = TelecomDeploymentEditorServer.RegisterCommands()
    ASSERT_FALSE(ok)
    ASSERT_EQ(errorCode, 'deployment_tools_disabled')
end)
