Config = {
    ResourceName = 'gnsh-telecom',
    Version = '0.1.0-rc.1',
    Locale = 'en',

    Debug = {
        enabled = false,
        logLevel = 'info',
        adminAce = 'gnsh-telecom.admin',
    },

    Features = {
        Capacity = true,
        Failures = true,
        Technician = false,
        Incidents = true,
        NOC = true,
        Handover = true,
        Backhaul = true,
        Carriers = false,
        Sabotage = false,
        Jammers = false,
        Statistics = false,
        DeploymentTools = false,
        ServiceSessions = true,
        QoS = true,
    },

    Signal = {
        Base = 100,
        Levels = {
            EXCELLENT = { min = 90, max = 100 },
            GOOD = { min = 75, max = 89 },
            NORMAL = { min = 55, max = 74 },
            WEAK = { min = 30, max = 54 },
            VERY_WEAK = { min = 10, max = 29 },
            NO_SERVICE = { min = 0, max = 9 },
        },
    },

    Services = {
        voice = { minimumSignal = 25 },
        sms = { minimumSignal = 15 },
        data = { minimumSignal = 35 },
        gps = { minimumSignal = 20 },
        emergency = { minimumSignal = 10 },
    },

    Capacity = {
        thresholds = {
            busy = 60,
            congested = 80,
            critical = 95,
            overloaded = 100,
        },
        effects = {
            NORMAL = {
                signalMultiplier = 1.00,
                dataPerformance = 'NORMAL',
                dataAvailable = true,
                callSetupReliability = 1.00,
                smsDelayMs = 0,
            },
            BUSY = {
                signalMultiplier = 0.98,
                dataPerformance = 'DEGRADED',
                dataAvailable = true,
                callSetupReliability = 0.98,
                smsDelayMs = 250,
            },
            CONGESTED = {
                signalMultiplier = 0.92,
                dataPerformance = 'SLOW',
                dataAvailable = true,
                callSetupReliability = 0.90,
                smsDelayMs = 750,
            },
            CRITICAL = {
                signalMultiplier = 0.82,
                dataPerformance = 'VERY_SLOW',
                dataAvailable = true,
                callSetupReliability = 0.75,
                smsDelayMs = 1500,
            },
            OVERLOADED = {
                signalMultiplier = 0.65,
                dataPerformance = 'UNAVAILABLE',
                dataAvailable = false,
                callSetupReliability = 0.50,
                smsDelayMs = 3000,
            },
        },
    },

    Performance = {
        stationaryIntervalMs = 3000,
        walkingIntervalMs = 1500,
        vehicleIntervalMs = 500,
        meaningfulSignalDelta = 2,
    },

    Spatial = {
        cellSize = 1000.0,
    },

    Sectors = {
        maxPerTower = 16,
        maxCandidates = 64,
    },

    Selection = {
        signalWeight = 1.0,
        loadPenaltyWeight = 0.25,
        healthPenaltyWeight = 0.20,
        technologyPenaltyWeight = 0.10,
    },

    Deployment = {
        defaultCoverageMinimum = 50,
    },

    DeploymentTools = {
        maxCaptures = 64,
        convar = 'gnsh_telecom_deployment_tools',
    },

    TowerArchetypes = {
        METRO_MACRO = {
            coverageRadius = 850,
            capacity = 150,
        },
        TOWN_MACRO = {
            coverageRadius = 1200,
            capacity = 80,
        },
        RURAL_MACRO = {
            coverageRadius = 1500,
            capacity = 50,
        },
        HIGHWAY_REPEATER = {
            coverageRadius = 750,
            capacity = 30,
        },
        REMOTE_REPEATER = {
            coverageRadius = 450,
            capacity = 10,
        },
    },

    CoverageZones = {
        METRO_CORE = { required = true, target = 'STRONG' },
        METRO_EDGE = { required = true, target = 'STRONG' },
        TOWN = { required = true, target = 'GOOD' },
        HIGHWAY = { required = true, target = 'MODERATE' },
        RURAL = { required = false, target = 'VARIABLE' },
        WILDERNESS = { required = false, target = 'WEAK' },
        INTENTIONAL_DEADZONE = { required = false, target = 'WEAK_OR_NONE' },
    },

    Carriers = {},

    Handover = {
        enabled = true,
        minimumScoreAdvantage = 10.0,
        candidateHoldMs = 2000,
        cooldownMs = 3000,
    },

    Environment = {
        default = 'OPEN_AREA',
        allowed = {
            OPEN_AREA = true,
            URBAN = true,
            BUILDING = true,
            UNDERGROUND = true,
            TUNNEL = true,
            SPECIAL_ZONE = true,
        },
        multipliers = {
            OPEN_AREA = 1.00,
            URBAN = 0.90,
            BUILDING = 0.75,
            UNDERGROUND = 0.55,
            TUNNEL = 0.45,
            SPECIAL_ZONE = 0.80,
        },
        zones = {},
    },

    FailureScheduler = {
        enabled = false,
        intervalMs = 60000,
    },

    Persistence = {
        enabled = true,
        adapter = 'auto',
        auditRetention = 200,
        maxPayloadBytes = 4096,
        maxRetries = 3,
        retryIntervalMs = 5000,
    },

    Incidents = {
        autoCreate = true,
        defaultSeverity = 'MEDIUM',
        severityByFailure = {
            ANTENNA_FAILURE = 'MEDIUM',
            RADIO_FAILURE = 'HIGH',
            SECTOR_FAILURE = 'HIGH',
            RADIO_UNIT_FAILURE = 'CRITICAL',
            COOLING_FAILURE = 'HIGH',
            FIBER_FAILURE = 'CRITICAL',
            BACKHAUL_FAILURE = 'CRITICAL',
            CONTROLLER_FAILURE = 'CRITICAL',
            SOFTWARE_FAILURE = 'MEDIUM',
            HARDWARE_DEGRADATION = 'LOW',
        },
    },

    Technician = {
        jobs = { technician = true, telecom = true },
        interactionDistance = 5.0,
        repairDurationMs = 10000,
        diagnosticDurationMs = 2500,
        requiredItems = {},
        components = {},
        verification = {
            minimumTowerHealth = 1,
            requireBackhaul = true,
            requireServices = true,
        },
        allowAdmin = true,
    },

    NOC = {
        ace = 'gnsh-telecom.noc',
        refreshIntervalMs = 2000,
        reconcileIntervalMs = 10000,
        subscriptionTtlMs = 30000,
        maxSubscriptions = 64,
        maxTowers = 200,
        maxEntities = 500,
        maxDeltaEntities = 100,
        maxDeltasPerSecond = 30,
    },

    Backhaul = {
        routeCacheTtlMs = 5000,
        maxRouteCacheEntries = 256,
        maxRecomputeNodes = 128,
        maxPathHops = 64,
        maxRegionalTowers = 128,
        coreNodes = {},
        towerNodes = {},
        towerRegions = {},
        regions = {},
        nodes = {},
        links = {},
    },

    Sabotage = {
        cooldownMs = 60000,
        interactionDistance = 4.0,
        maxConcurrent = 1,
        alarmProbability = 0.25,
        actions = {
            antenna = {
                failureType = 'ANTENNA_FAILURE',
                requiredItem = nil,
            },
            fiber = {
                failureType = 'FIBER_FAILURE',
                requiredItem = nil,
            },
            radio = {
                failureType = 'RADIO_UNIT_FAILURE',
                requiredItem = nil,
            },
        },
    },

    Jammers = {
        maxActive = 10,
        defaultRadius = 250.0,
        defaultStrength = 0.75,
        defaultDurationMs = 600000,
        cooldownMs = 30000,
        maxPlacementDistance = 6.0,
        technologies = { '3G', '4G', '5G' },
    },

    Statistics = {
        flushIntervalMs = 60000,
        retention = 1000,
    },

    Framework = 'auto',
    CustomFramework = nil,
    InventoryBridge = 'auto',
    CustomInventory = nil,
    TargetBridge = 'auto',
    CustomTarget = nil,
    CustomDispatch = nil,
    NotifyBridge = 'auto',
    ProgressBridge = 'auto',
    PhoneBridge = 'auto',
    Bridges = {
        Framework = {
            provider = 'auto',
            fallback = 'standalone',
        },
        Inventory = {
            provider = 'auto',
            required = false,
        },
        Target = {
            provider = 'auto',
            fallback = 'native',
        },
        Phone = {
            provider = 'auto',
            requireEnforcement = false,
        },
        Dispatch = {
            provider = 'auto',
            required = false,
        },
        Notify = {
            provider = 'auto',
            fallback = 'native',
        },
        Progress = {
            provider = 'auto',
            fallback = 'native',
        },
    },

    ServiceSessions = {
        maxActive = 256,
        maxActivePerSource = 4,
        maxMetadataFields = 16,
        maxMetadataDepth = 3,
        maxDurationMs = 1800000,
        maxBeginsPerSecond = 8,
        maxUpdatesPerSecond = 20,
        maxEndsPerSecond = 20,
        demands = {
            VOICE = 2.0,
            SMS = 0.5,
            DATA = 5.0,
            GPS = 0.75,
            EMERGENCY = 3.0,
            BACKGROUND_DATA = 1.0,
        },
    },

    QoS = {
        priorities = {
            EMERGENCY = 100,
            VOICE = 90,
            SMS = 70,
            DATA_HIGH = 50,
            DATA_NORMAL = 30,
            BACKGROUND = 10,
        },
    },
    Towers = {},
}
