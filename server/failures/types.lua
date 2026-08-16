FailureTypes = FailureTypes or {}

local definitions = {
    ANTENNA_FAILURE = {
        description = 'reduced antenna coverage',
        signalMultiplier = 0.65,
        capacityMultiplier = 0.85,
        serviceFailures = {},
        component = 'antenna',
    },
    RADIO_FAILURE = {
        description = 'radio chain degradation',
        signalMultiplier = 0.45,
        capacityMultiplier = 0.60,
        serviceFailures = { data = true },
        component = 'radio',
    },
    COOLING_FAILURE = {
        description = 'thermal protection degradation',
        signalMultiplier = 0.80,
        capacityMultiplier = 0.70,
        serviceFailures = {},
        component = 'cooling',
    },
    HARDWARE_DEGRADATION = {
        description = 'general hardware degradation',
        signalMultiplier = 0.75,
        capacityMultiplier = 0.80,
        serviceFailures = {},
        component = 'hardware',
    },
    SECTOR_FAILURE = {
        description = 'single radio sector failure',
        signalMultiplier = 0.70,
        capacityMultiplier = 0.55,
        serviceFailures = {},
        component = 'sector',
    },
    RADIO_UNIT_FAILURE = {
        description = 'radio unit failure',
        signalMultiplier = 0.35,
        capacityMultiplier = 0.35,
        serviceFailures = { data = true },
        component = 'radio_unit',
    },
    FIBER_FAILURE = {
        description = 'fiber backhaul failure',
        signalMultiplier = 1.00,
        capacityMultiplier = 1.00,
        serviceFailures = {},
        backhaulStatus = Enums.BackhaulState.OFFLINE,
        component = 'fiber',
    },
    BACKHAUL_FAILURE = {
        description = 'backhaul path failure',
        signalMultiplier = 1.00,
        capacityMultiplier = 1.00,
        serviceFailures = {},
        backhaulStatus = Enums.BackhaulState.OFFLINE,
        component = 'backhaul',
    },
    CONTROLLER_FAILURE = {
        description = 'tower controller failure',
        signalMultiplier = 0.80,
        capacityMultiplier = 0.50,
        serviceFailures = { voice = true, sms = true, data = true, gps = true },
        component = 'controller',
    },
    SOFTWARE_FAILURE = {
        description = 'network software failure',
        signalMultiplier = 0.90,
        capacityMultiplier = 0.85,
        serviceFailures = { data = true },
        component = 'software',
    },
}

function FailureTypes.IsSupported(name)
    return type(name) == 'string' and definitions[name] ~= nil
end

function FailureTypes.Get(name)
    local definition = definitions[name]
    return definition and Utils.DeepCopy(definition) or nil
end

function FailureTypes.Names()
    local names = {}
    for name in pairs(definitions) do names[#names + 1] = name end
    table.sort(names)
    return names
end
