-- Golden coverage anchors.
--
-- Required-service and intentional-weak positions below are copied from
-- verified FiveM captures; do not invent coordinates from memory.
Config.CoverageExpectations = {
    -- Required urban service anchors.
    {
        id = 'DOWNTOWN_CORE',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(438.99, -634.52, 34.45),
        expectation = 'STRONG',
        source = 'LS-DOWNTOWN-01 verified capture',
    },
    {
        id = 'LSIA_CORE',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(-981.56, -2637.11, 89.52),
        expectation = 'STRONG',
        source = 'LS-LSIA-01 verified capture',
    },
    {
        id = 'MISSION_ROW_CORE',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(480.32, -939.01, 36.34),
        expectation = 'STRONG',
        source = 'LS-MISSIONROW-01 verified capture',
    },
    {
        id = 'VESPUCCI_CORE',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(-1184.18, -705.81, 42.27),
        expectation = 'STRONG',
        source = 'LS-VESPUCCI-01 verified capture',
    },
    {
        id = 'EAST_LS_CORE',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(381.05, 247.36, 116.55),
        expectation = 'STRONG',
        source = 'LS-EAST-01 verified capture',
    },

    -- Required town anchors. GOOD accepts GOOD or STRONG signal.
    {
        id = 'SANDY_CENTER',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(1856.94, 3691.29, 38.87),
        expectation = 'GOOD',
        source = 'BC-SANDY-01 verified capture',
    },
    {
        id = 'GRAPESEED_CENTER',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(1689.93, 4817.64, 45.96),
        expectation = 'GOOD',
        source = 'BC-GRAPESEED-01 verified capture',
    },
    {
        id = 'PALETO_CENTER',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(-751.19, 5560.72, 40.97),
        expectation = 'GOOD',
        source = 'BC-PALETO-01 verified capture',
    },
    {
        id = 'HARMONY_CENTER',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(1181.93, 2644.72, 43.50),
        expectation = 'GOOD',
        source = 'BC-HARMONY-01 verified capture',
    },
    {
        id = 'CHUMASH_CENTER',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(-3132.92, 1097.85, 21.51),
        expectation = 'GOOD',
        source = 'BC-CHUMASH-01 verified capture',
    },

    -- Highway anchors. MODERATE accepts MODERATE or stronger signal.
    {
        id = 'GOH_SOUTH_CORRIDOR',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(-2184.18, 4295.78, 53.81),
        expectation = 'MODERATE',
        source = 'HW-GOH-01 verified capture',
    },
    {
        id = 'SENORA_CORRIDOR',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(1968.45, 4628.43, 46.43),
        expectation = 'MODERATE',
        source = 'HW-SENORA-01 verified capture',
    },
    {
        id = 'PALOMINO_CORRIDOR',
        category = 'REQUIRED_SERVICE_ZONE',
        position = vector3(2590.98, 430.23, 111.89),
        expectation = 'MODERATE',
        source = 'HW-PALOMINO-01 verified capture',
    },

    -- Intentional weak anchors. Uncaptured entries remain pending regression.
    {
        id = 'MOUNT_CHILIAD_WILDERNESS',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(421.27, 5007.20, 401.93),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
    },
    {
        id = 'RATON_REMOTE',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(-1359.16, 4201.02, 18.98),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
    },
    {
        id = 'TONGVA_INTERIOR',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(-2365.52, 1893.07, 186.30),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
    },
    {
        id = 'TATAVIAM_MOUNTAINS',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(1920.28, 775.37, 193.55),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
    },
    {
        id = 'PALOMINO_HIGHLANDS',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(2604.71, -966.07, 28.86),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
    },
    {
        id = 'ALAMO_NORTH_WILDERNESS',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(796.95, 4526.07, 48.37),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
    },
    {
        id = 'BLAINE_REMOTE_DIRT_ROAD',
        category = 'INTENTIONAL_WEAK_ZONE',
        position = vector3(658.42, 4613.10, 163.61),
        expectation = 'WEAK_OR_NONE',
        source = 'verified FiveM capture',
        note = 'Previous capture at signal 50.08 failed; final point was recaptured farther from service.',
    },
}
