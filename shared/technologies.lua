Technologies = {
    EDGE = 'EDGE',
    THREE_G = '3G',
    FOUR_G = '4G',
    FIVE_G = '5G',
    NO_SERVICE = 'NO_SERVICE',
}

local supported = {
    [Technologies.EDGE] = true,
    [Technologies.THREE_G] = true,
    [Technologies.FOUR_G] = true,
    [Technologies.FIVE_G] = true,
}

local definitions = {
    [Technologies.EDGE] = {
        priority = 1,
        capacityMultiplier = 0.50,
        dataPerformance = 'VERY_SLOW',
        services = {
            voice = true,
            sms = true,
            data = true,
            gps = true,
            emergency = true,
        },
    },
    [Technologies.THREE_G] = {
        priority = 2,
        capacityMultiplier = 0.75,
        dataPerformance = 'SLOW',
        services = {
            voice = true,
            sms = true,
            data = true,
            gps = true,
            emergency = true,
        },
    },
    [Technologies.FOUR_G] = {
        priority = 3,
        capacityMultiplier = 1.00,
        dataPerformance = 'NORMAL',
        services = {
            voice = true,
            sms = true,
            data = true,
            gps = true,
            emergency = true,
        },
    },
    [Technologies.FIVE_G] = {
        priority = 4,
        capacityMultiplier = 1.25,
        dataPerformance = 'NORMAL',
        services = {
            voice = true,
            sms = true,
            data = true,
            gps = true,
            emergency = true,
        },
    },
}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

function Technologies.IsSupported(value)
    return supported[value] == true
end

function Technologies.GetAll()
    return { 'EDGE', '3G', '4G', '5G' }
end

function Technologies.GetDefinition(value)
    return copy(definitions[value])
end

function Technologies.GetCapacityMultiplier(value)
    local definition = definitions[value]
    return definition and definition.capacityMultiplier or 1.0
end

function Technologies.GetPriority(value)
    local definition = definitions[value]
    return definition and definition.priority or 0
end

function Technologies.GetServicePerformance(value, service)
    local definition = definitions[value]
    if not definition then return nil end
    if service == 'data' then return definition.dataPerformance end
    return nil
end

function Technologies.SupportsService(value, service)
    local definition = definitions[value]
    return definition and definition.services[service] == true or false
end
