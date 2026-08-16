FailureTypes = FailureTypes or {}

local definitions = {
    ANTENNA_FAILURE = {
        description = 'reduced antenna coverage',
        signalMultiplier = 0.65,
        capacityMultiplier = 0.85,
        serviceFailures = {},
    },
    RADIO_FAILURE = {
        description = 'radio chain degradation',
        signalMultiplier = 0.45,
        capacityMultiplier = 0.60,
        serviceFailures = { data = true },
    },
    COOLING_FAILURE = {
        description = 'thermal protection degradation',
        signalMultiplier = 0.80,
        capacityMultiplier = 0.70,
        serviceFailures = {},
    },
    HARDWARE_DEGRADATION = {
        description = 'general hardware degradation',
        signalMultiplier = 0.75,
        capacityMultiplier = 0.80,
        serviceFailures = {},
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
