TelecomDeployment = {}

local function addError(errors, path, message)
    errors[#errors + 1] = ('%s.%s'):format(path, message)
end

local function configTable(config, key)
    local source = type(config) == 'table' and config or Config
    local value = type(source) == 'table' and source[key]
    return type(value) == 'table' and value or {}
end

local function defaultCoverageMinimum(config)
    local deployment = configTable(config, 'Deployment')
    local value = deployment.defaultCoverageMinimum
    return type(value) == 'number' and value or 50
end

function TelecomDeployment.IsKnownArchetype(name, config)
    if type(name) ~= 'string' or name == '' then return false end
    return type(configTable(config, 'TowerArchetypes')[name]) == 'table'
end

function TelecomDeployment.IsKnownCoverageZone(name, config)
    if type(name) ~= 'string' or name == '' then return false end
    return type(configTable(config, 'CoverageZones')[name]) == 'table'
end

function TelecomDeployment.NormalizeTower(tower, path, config)
    path = path or 'Tower'
    if type(tower) ~= 'table' then
        return false, { path .. ' must be a table' }, nil
    end

    local source = type(config) == 'table' and config or Config
    local normalized = Utils.DeepCopy(tower)
    local errors = {}
    local archetypeName = normalized.class

    if archetypeName ~= nil then
        if type(archetypeName) ~= 'string' or archetypeName == '' then
            addError(errors, path, 'class must be a non-empty string')
        elseif not TelecomDeployment.IsKnownArchetype(archetypeName, source) then
            addError(errors, path, ('unknown tower archetype: %s'):format(archetypeName))
        else
            local archetype = configTable(source, 'TowerArchetypes')[archetypeName]
            local coverage = normalized.coverage
            local capacity = normalized.capacity

            if coverage == nil then
                coverage = {}
                normalized.coverage = coverage
            end
            if type(coverage) == 'table' then
                if coverage.radius == nil then
                    coverage.radius = archetype.coverageRadius
                end
                if coverage.minimum == nil then
                    coverage.minimum = defaultCoverageMinimum(source)
                end
            end

            if capacity == nil then
                capacity = {}
                normalized.capacity = capacity
            end
            if type(capacity) == 'table' and capacity.maximum == nil then
                capacity.maximum = archetype.capacity
            end
        end
    end

    if normalized.coverageZone ~= nil
        and not TelecomDeployment.IsKnownCoverageZone(normalized.coverageZone, source) then
        addError(errors, path, ('unknown coverage zone: %s')
            :format(tostring(normalized.coverageZone)))
    end

    return #errors == 0, errors, normalized
end
