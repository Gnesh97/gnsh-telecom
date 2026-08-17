BridgeContracts = BridgeContracts or {}

BridgeContracts.Categories = {
    framework = true,
    inventory = true,
    target = true,
    dispatch = true,
    phone = true,
    notify = true,
    progress = true,
}

local function copyTable(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end

local function normalizeResources(resources)
    if resources == nil then return {} end
    if type(resources) == 'string' then resources = { resources } end
    if type(resources) ~= 'table' then
        return nil, 'resources must be a table or string'
    end

    local result = {}
    for _, resourceName in ipairs(resources) do
        if type(resourceName) ~= 'string' or resourceName == '' then
            return nil, 'resources must contain non-empty strings'
        end
        result[#result + 1] = resourceName
    end
    return result
end

local function defaultDetect(self)
    return BridgeLifecycle.ResourcesAvailable(self)
end

local function defaultInitialize()
    return true
end

local function defaultShutdown()
    return true
end

local function defaultHealthCheck()
    return BridgeHealth.States.ACTIVE
end

function BridgeContracts.IsCategory(category)
    return type(category) == 'string' and BridgeContracts.Categories[category] == true
end

function BridgeContracts.Validate(contract)
    if type(contract) ~= 'table' then return false, 'bridge contract must be a table' end
    if type(contract.name) ~= 'string' or contract.name == '' or #contract.name > 64 then
        return false, 'bridge contract name must be a non-empty string'
    end
    if not BridgeContracts.IsCategory(contract.category) then
        return false, 'bridge contract category is unsupported'
    end
    if contract.priority ~= nil
        and (type(contract.priority) ~= 'number' or contract.priority ~= math.floor(contract.priority)) then
        return false, 'bridge contract priority must be an integer'
    end
    for _, method in ipairs({ 'Detect', 'Initialize', 'Shutdown', 'HealthCheck' }) do
        if contract[method] ~= nil and type(contract[method]) ~= 'function' then
            return false, ('bridge contract %s must be a function'):format(method)
        end
    end
    return true
end

function BridgeContracts.Normalize(contract)
    local valid, errorMessage = BridgeContracts.Validate(contract)
    if not valid then return nil, errorMessage end

    local resources, resourceError = normalizeResources(contract.resources)
    if not resources then return nil, resourceError end

    local normalized = copyTable(contract)
    normalized.priority = contract.priority or 0
    normalized.resources = resources
    normalized.resourceMode = contract.resourceMode == 'all' and 'all' or 'any'
    normalized.optional = contract.optional ~= false
    normalized.Detect = contract.Detect or defaultDetect
    normalized.Initialize = contract.Initialize or defaultInitialize
    normalized.Shutdown = contract.Shutdown or defaultShutdown
    normalized.HealthCheck = contract.HealthCheck or defaultHealthCheck

    local capabilities, capabilityError = BridgeCapabilities.Infer(
        normalized.category,
        normalized,
        contract.capabilities
    )
    if not capabilities then return nil, capabilityError end
    normalized.capabilities = capabilities
    return normalized
end
