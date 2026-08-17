-- Development-only placement anchors.
--
-- These are map waypoints for the first authoring pass, not production tower
-- coordinates. They intentionally live outside Config.DeploymentSites and
-- Config.Towers. A verified player capture must replace them before export.
local function deploymentToolsEnabledAtLoad()
    if Config.Features and Config.Features.DeploymentTools == true then return true end
    if type(GetConvar) ~= 'function' then return true end
    local convarName = Config.DeploymentTools
        and Config.DeploymentTools.convar
        or 'gnsh_telecom_deployment_tools'
    local value = tostring(GetConvar(convarName, '0')):lower()
    return value == '1' or value == 'true' or value == 'on'
end

if deploymentToolsEnabledAtLoad() then
Config.DeploymentDrafts = {
    { id = 'LS-LSIA-01', coords = vector3(-1034.34, -2742.55, 20.36), heading = 330.0 },
    { id = 'LS-PORT-01', coords = vector3(144.32, -3005.92, 6.03), heading = 0.0 },
    { id = 'LS-LAPUERTA-01', coords = vector3(-1117.15, -1439.43, 5.11), heading = 103.0 },
    { id = 'LS-VESPUCCI-01', coords = vector3(-1093.89, -807.08, 18.26), heading = 42.0 },
    { id = 'LS-DELPERRO-01', coords = vector3(-1601.54, -890.34, 8.95), heading = 90.0 },
    { id = 'LS-ROCKFORD-01', coords = vector3(-560.76, -133.98, 37.06), heading = 210.0 },
    { id = 'LS-DOWNTOWN-01', coords = vector3(353.21, -613.03, 25.20), heading = 0.0 },
    { id = 'LS-MISSIONROW-01', coords = vector3(479.64, -976.68, 26.98), heading = 332.0 },
    { id = 'LS-DAVIS-01', coords = vector3(360.88, -1581.61, 28.29), heading = 24.0 },
    { id = 'LS-LAMESA-01', coords = vector3(926.28, -1560.31, 29.74), heading = 310.0 },
    { id = 'LS-CYPRESS-01', coords = vector3(1037.81, -2173.06, 30.53), heading = 270.0 },
    { id = 'LS-MURRIETA-01', coords = vector3(1213.23, -1251.25, 35.33), heading = 180.0 },
    { id = 'LS-VINEWOOD-01', coords = vector3(639.18, 1.77, 81.79), heading = 238.0 },
    { id = 'LS-MIRRORPARK-01', coords = vector3(945.95, -652.91, 58.02), heading = 90.0 },
    { id = 'LS-RICHMAN-01', coords = vector3(-813.60, 179.47, 71.15), heading = 111.0 },
    { id = 'LS-EAST-01', coords = vector3(349.84, 328.89, 103.27), heading = 0.0 },

    { id = 'BC-SANDY-01', coords = vector3(1856.35, 3682.06, 33.27), heading = 210.0 },
    { id = 'BC-SANDY-02', coords = vector3(1809.10, 3667.66, 14.28), heading = 0.0 },
    { id = 'BC-GRAPESEED-01', coords = vector3(1700.00, 4800.00, 41.00), heading = 90.0 },
    { id = 'BC-PALETO-01', coords = vector3(-440.74, 6019.89, 30.49), heading = 315.0 },
    { id = 'BC-PALETO-02', coords = vector3(-154.23, 6328.87, 31.57), heading = 133.0 },
    { id = 'BC-HARMONY-01', coords = vector3(1183.07, 2648.53, 37.84), heading = 194.0 },
    { id = 'BC-CHUMASH-01', coords = vector3(-3118.00, 1100.00, 20.00), heading = 90.0 },
    { id = 'BC-ZANCUDO-01', coords = vector3(-2145.00, 2875.00, 32.80), heading = 0.0 },

    { id = 'HW-GOH-01', coords = vector3(-1283.84, 5355.30, 10.00), heading = 165.0 },
    { id = 'HW-GOH-02', coords = vector3(-2360.00, 4500.00, 20.00), heading = 165.0 },
    { id = 'HW-SENORA-01', coords = vector3(2020.00, 4450.00, 40.00), heading = 90.0 },
    { id = 'HW-SENORA-02', coords = vector3(2400.00, 4750.00, 40.00), heading = 90.0 },
    { id = 'HW-R68-01', coords = vector3(1050.00, 2700.00, 38.00), heading = 90.0 },
    { id = 'HW-PALOMINO-01', coords = vector3(2600.00, 500.00, 90.00), heading = 90.0 },
    { id = 'HW-NORTH-01', coords = vector3(1016.95, 6585.86, 3.41), heading = 90.0 },
    { id = 'RM-CHILIAD-CABLE-01', coords = vector3(450.00, 5566.00, 800.00), heading = 0.0 },
}
else
    -- Production/default runtime does not load draft anchors into Config.
    Config.DeploymentDrafts = {}
end
