MaintenanceComponents = MaintenanceComponents or {}

local repairedByFailure = {}

local componentAliases = {
    ANTENNA = 'ANTENNA',
    SECTOR = 'SECTOR',
    RADIO = 'RADIO_UNIT',
    RADIO_UNIT = 'RADIO_UNIT',
    FIBER = 'FIBER_TRANSCEIVER',
    FIBER_TRANSCEIVER = 'FIBER_TRANSCEIVER',
    COOLING = 'COOLING',
    CONTROLLER = 'CONTROLLER',
    BACKHAUL = 'BACKHAUL_ROUTER',
    BACKHAUL_ROUTER = 'BACKHAUL_ROUTER',
    HARDWARE = 'CONTROLLER',
    SOFTWARE = 'CONTROLLER',
}

local failureComponents = {
    ANTENNA_FAILURE = 'ANTENNA',
    SECTOR_FAILURE = 'SECTOR',
    RADIO_FAILURE = 'RADIO_UNIT',
    RADIO_UNIT_FAILURE = 'RADIO_UNIT',
    FIBER_FAILURE = 'FIBER_TRANSCEIVER',
    BACKHAUL_FAILURE = 'BACKHAUL_ROUTER',
    COOLING_FAILURE = 'COOLING',
    CONTROLLER_FAILURE = 'CONTROLLER',
    HARDWARE_DEGRADATION = 'CONTROLLER',
    SOFTWARE_FAILURE = 'CONTROLLER',
}

local componentOrder = {
    'ANTENNA',
    'SECTOR',
    'RADIO_UNIT',
    'FIBER_TRANSCEIVER',
    'COOLING',
    'CONTROLLER',
    'BACKHAUL_ROUTER',
}

local defaults = {
    ANTENNA = { repairable = true, replaceable = true },
    SECTOR = { repairable = true, replaceable = true },
    RADIO_UNIT = { repairable = true, replaceable = true },
    FIBER_TRANSCEIVER = { repairable = true, replaceable = true },
    COOLING = { repairable = true, replaceable = true },
    CONTROLLER = { repairable = true, replaceable = true },
    BACKHAUL_ROUTER = { repairable = true, replaceable = true },
}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function safeString(value, maximumLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maximumLength
end

local function normalizeName(value)
    if not safeString(value, 64) then return nil end
    local normalized = value:upper():gsub('%s+', '_'):gsub('%-', '_')
    return componentAliases[normalized] or normalized
end

local function configuredDefinition(name)
    local configured = Config and Config.Technician
        and Config.Technician.components
    if type(configured) ~= 'table' then return {} end
    local value = configured[name] or configured[name:lower()]
    if type(value) ~= 'table' then return {} end
    return value
end

local function componentForFailure(failure)
    if type(failure) ~= 'table' then return nil end
    local explicit = normalizeName(failure.component)
    if explicit then return explicit end
    local mapped = failureComponents[failure.type]
    if mapped then return mapped end
    local definition = FailureTypes and FailureTypes.Get
        and FailureTypes.Get(failure.type)
    return definition and normalizeName(definition.component) or nil
end

local function requiredLegacyPart(failure)
    local requiredItems = Config and Config.Technician
        and Config.Technician.requiredItems or {}
    if type(requiredItems) ~= 'table' then return nil end
    return requiredItems[failure.type] or requiredItems.default
end

local function makeDefinition(name, failure)
    local configured = configuredDefinition(name)
    local defaultsForName = defaults[name] or {}
    local requiredPart = configured.requiredPart or configured.requiredItem
    local legacyPart = failure and requiredLegacyPart(failure)
    if not requiredPart then requiredPart = legacyPart end
    return {
        name = name,
        health = 100,
        state = 'OPERATIONAL',
        repairable = configured.repairable ~= false
            and defaultsForName.repairable ~= false,
        replaceable = configured.replaceable ~= false
            and defaultsForName.replaceable ~= false,
        requiredTool = configured.requiredTool,
        requiredPart = requiredPart,
        legacyPart = not configured.requiredPart and not configured.requiredItem
            and legacyPart ~= nil,
    }
end

function MaintenanceComponents.Normalize(value)
    return normalizeName(value)
end

function MaintenanceComponents.GetDefinition(value)
    local name = normalizeName(value)
    return name and copy(makeDefinition(name)) or nil
end

MaintenanceComponents.Get = MaintenanceComponents.GetDefinition

function MaintenanceComponents.ForFailure(failure)
    local name = componentForFailure(failure)
    return name and copy(makeDefinition(name, failure)) or nil
end

function MaintenanceComponents.RequiredForFailure(failure)
    local definition = MaintenanceComponents.ForFailure(failure)
    if not definition then return nil, 'component_unknown' end
    return definition
end

function MaintenanceComponents.ValidateRequirements(source, failure)
    local definition, errorCode = MaintenanceComponents.RequiredForFailure(failure)
    if not definition then return false, errorCode end

    if definition.requiredTool then
        local hasTool, toolError = InventoryBridge.HasItem(source, definition.requiredTool, 1)
        if not hasTool then return false, toolError or 'required_tool_missing', definition end
    end
    if definition.requiredPart then
        local hasPart, partError = InventoryBridge.HasItem(source, definition.requiredPart, 1)
        if not hasPart then
            local missing = definition.legacyPart
                and 'required_item_missing' or 'required_part_missing'
            return false, partError or missing, definition
        end
    end
    return true, definition
end

function MaintenanceComponents.CanReturnPart(source, definition)
    if type(definition) ~= 'table' or not definition.requiredPart then return true end
    if InventoryBridge and type(InventoryBridge.CanCarry) == 'function' then
        return InventoryBridge.CanCarry(source, definition.requiredPart, 1) == true
    end
    return InventoryBridge and type(InventoryBridge.CanAddItem) == 'function'
        and InventoryBridge.CanAddItem(source, definition.requiredPart, 1) == true
end

function MaintenanceComponents.MarkRepaired(failureId, context)
    if not safeString(failureId, 128) then return false, 'failure_id_required' end
    repairedByFailure[failureId] = copy(context or {})
    return true
end

function MaintenanceComponents.ClearRepair(failureId)
    repairedByFailure[failureId] = nil
end

local function towerComponentHealth(towerId)
    local state = TowerState and TowerState.Get and TowerState.Get(towerId)
    local health = state and tonumber(state.health) or 100
    return Utils and Utils.Clamp and Utils.Clamp(health, 0, 100) or health
end

function MaintenanceComponents.List(towerId)
    local failures = FailureEngine and FailureEngine.GetTowerFailures
        and FailureEngine.GetTowerFailures(towerId) or {}
    local failed = {}
    for _, failure in ipairs(failures) do
        local name = componentForFailure(failure)
        if name then failed[name] = true end
    end

    local result = {}
    local health = towerComponentHealth(towerId)
    for _, name in ipairs(componentOrder) do
        local definition = makeDefinition(name)
        definition.health = health
        definition.state = failed[name] and 'FAILED' or 'OPERATIONAL'
        result[#result + 1] = definition
    end
    return result
end

MaintenanceComponents.Inspect = MaintenanceComponents.List

local function hasBlockedServices(effects)
    for _, blocked in pairs(effects and effects.serviceFailures or {}) do
        if blocked then return true end
    end
    return false
end

function MaintenanceComponents.Verify(failure, towerId)
    if type(failure) ~= 'table' then return false, 'failure_required' end
    local projected, effects = FailureEngine.GetEffectsAfterClear(failure.id)
    if not projected then return false, effects end

    local name = componentForFailure(failure)
    local componentOperational = true
    for _, activeFailure in ipairs(effects.activeFailures or {}) do
        if activeFailure.id == failure.id then
            return false, 'failure_not_cleared'
        end
        if componentForFailure(activeFailure) == name then
            componentOperational = false
        end
    end

    local runtime = TowerState.Get(towerId)
    local verification = Config and Config.Technician
        and Config.Technician.verification or {}
    local minimumHealth = tonumber(verification.minimumTowerHealth) or 1
    local towerHealth = runtime and tonumber(runtime.health) or 0
    local checks = {
        failureCleared = true,
        componentOperational = componentOperational,
        sectorOperational = componentOperational,
        radioOperational = componentOperational
            and (tonumber(effects.signalMultiplier) or 0) > 0,
        backhaulReachable = effects.backhaulStatus ~= Enums.BackhaulState.OFFLINE,
        servicePolicyRestored = not hasBlockedServices(effects),
        towerHealthAcceptable = towerHealth >= minimumHealth,
        towerHealth = towerHealth,
    }
    checks.ok = checks.failureCleared
        and checks.componentOperational
        and checks.sectorOperational
        and checks.radioOperational
        and (verification.requireBackhaul == false or checks.backhaulReachable)
        and (verification.requireServices == false or checks.servicePolicyRestored)
        and checks.towerHealthAcceptable
    if not checks.ok then
        for key, value in pairs(checks) do
            if value == false then return false, key, checks end
        end
        return false, 'verification_failed', checks
    end
    return true, checks
end

function MaintenanceComponents.Reset()
    repairedByFailure = {}
end
