local releaseVersion = '0.1.0-rc.1'

local function readFile(path)
    local handle = io.open(path, 'r')
    if not handle then return nil end
    local content = handle:read('*a')
    handle:close()
    return content
end

local function fileExists(path)
    return readFile(path) ~= nil
end

local function loadDefaultConfig()
    local environment = {}
    setmetatable(environment, { __index = _G })
    local chunk = assert(loadfile('config/default.lua', 't', environment))
    chunk()
    return environment.Config
end

TEST('release metadata and package files are internally consistent', function()
    ASSERT_EQ(Config.Version, releaseVersion)
    ASSERT_EQ(Constants.ApiVersion, '1.0')

    local manifest = readFile('fxmanifest.lua')
    ASSERT_TRUE(type(manifest) == 'string')
    ASSERT_TRUE(manifest:find("version '" .. releaseVersion .. "'", 1, true) ~= nil)

    for _, path in ipairs({
        'LICENSE',
        'CHANGELOG.md',
        'CARRIER_GUIDE.md',
        'COMPATIBILITY.md',
        'PERFORMANCE.md',
        'RELEASE_TEST_REPORT.md',
        'README.md',
        'INSTALLATION.md',
        'CONFIGURATION.md',
        'API.md',
        'BRIDGES.md',
        'PHONE_BRIDGE_GUIDE.md',
        'CUSTOM_INTEGRATION.md',
        'TOWER_CONFIGURATION.md',
        'DEPLOYMENT_EDITOR.md',
        'TECHNICIAN_CONFIGURATION.md',
        'NOC_GUIDE.md',
        'BACKHAUL_GUIDE.md',
        'SECURITY.md',
        'TROUBLESHOOTING.md',
    }) do
        ASSERT_TRUE(fileExists(path), 'release file missing: ' .. path)
    end

    local license = readFile('LICENSE')
    ASSERT_TRUE(license:find('MIT License', 1, true) ~= nil)
    local changelog = readFile('CHANGELOG.md')
    ASSERT_TRUE(changelog:find(releaseVersion, 1, true) ~= nil)
end)

TEST('release defaults are production-safe', function()
    local defaults = loadDefaultConfig()
    ASSERT_FALSE(defaults.Debug.enabled)
    ASSERT_EQ(defaults.Debug.logLevel, 'info')
    ASSERT_FALSE(defaults.Features.Sabotage)
    ASSERT_FALSE(defaults.Features.Statistics)
    ASSERT_FALSE(defaults.Features.DeploymentTools)
    ASSERT_EQ(defaults.Persistence.adapter, 'auto')
end)

TEST('release gate keeps live evidence as a separate blocker', function()
    ASSERT_TRUE(type(CompatibilityMatrix) == 'table')
    ASSERT_EQ(CompatibilityMatrix.connectedClients, 0)

    local liveSupported = 0
    for _, entry in ipairs(CompatibilityMatrix.entries or {}) do
        if entry.label == 'SUPPORTED' or entry.label == 'FULLY SUPPORTED' then
            ASSERT_TRUE(entry.realRuntimeEvidence == true)
            liveSupported = liveSupported + 1
        end
    end
    ASSERT_EQ(liveSupported, 0)

    local report = readFile('RELEASE_TEST_REPORT.md')
    ASSERT_TRUE(report:find('Real FiveM runtime', 1, true) ~= nil)
end)
