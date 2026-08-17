Config = {
    ResourceName = 'gnsh-telecom',
    Version = '0.1.0',
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
        Sabotage = false,
        Jammers = true,
        Statistics = false,
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

    Selection = {
        signalWeight = 1.0,
        loadPenaltyWeight = 0.25,
        healthPenaltyWeight = 0.20,
        technologyPenaltyWeight = 0.10,
    },

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
        allowAdmin = true,
    },

    NOC = {
        ace = 'gnsh-telecom.noc',
        refreshIntervalMs = 2000,
        maxTowers = 200,
    },

    Backhaul = {
        routeCacheTtlMs = 5000,
        coreNodes = {},
        towerNodes = {},
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
    PhoneBridge = 'auto',
    Towers = {},
}
