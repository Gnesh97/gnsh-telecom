TowerValidation = {}

local function addError(errors, path, message)
    errors[#errors + 1] = ('%s.%s'):format(path, message)
end

local function validState(value)
    return value == nil or value == Enums.TowerState.OPERATIONAL
        or value == Enums.TowerState.DEGRADED
        or value == Enums.TowerState.MAINTENANCE
        or value == Enums.TowerState.OFFLINE
        or value == Enums.TowerState.DESTROYED
end

local function validBackhaul(value)
    return value == nil or value == Enums.BackhaulState.ONLINE
        or value == Enums.BackhaulState.DEGRADED
        or value == Enums.BackhaulState.OFFLINE
end

local function validateHardware(tower, errors, path)
    if tower.hardware == nil then return end
    if type(tower.hardware) ~= 'table' then
        addError(errors, path, 'hardware must be a table')
        return
    end

    if tower.hardware.health ~= nil
        and (not Utils.IsFiniteNumber(tower.hardware.health)
            or tower.hardware.health < 0 or tower.hardware.health > 100) then
        addError(errors, path, 'hardware.health must be between 0 and 100')
    end
end

function TowerValidation.Validate(tower, path)
    path = path or 'Tower'
    local errors = {}
    if type(tower) ~= 'table' then
        return false, { path .. ' must be a table' }, nil
    end

    local normalized = Utils.DeepCopy(tower)
    if type(normalized.id) ~= 'string' or normalized.id:match('^%s*$') then
        addError(errors, path, 'id must be a non-empty string')
    end
    if not Utils.IsPoint(normalized.coords) then
        addError(errors, path, 'coords must contain finite x, y and z values')
    end

    local coverage = normalized.coverage
    if type(coverage) ~= 'table' then
        addError(errors, path, 'coverage must be a table')
    else
        if not Utils.IsFiniteNumber(coverage.radius) or coverage.radius <= 0 then
            addError(errors, path, 'coverage.radius must be greater than zero')
        end
        if not Utils.IsFiniteNumber(coverage.minimum) or coverage.minimum < 0 then
            addError(errors, path, 'coverage.minimum must be non-negative')
        elseif Utils.IsFiniteNumber(coverage.radius) and coverage.radius < coverage.minimum then
            addError(errors, path, 'coverage.radius must be at least coverage.minimum')
        end
    end

    if type(normalized.technologies) ~= 'table' or #normalized.technologies == 0 then
        addError(errors, path, 'technologies must contain at least one technology')
    else
        local seen = {}
        for index, technology in ipairs(normalized.technologies) do
            if not Technologies.IsSupported(technology) then
                addError(errors, path, ('unsupported technology at index %d: %s')
                    :format(index, tostring(technology)))
            elseif seen[technology] then
                addError(errors, path, ('duplicate technology: %s'):format(technology))
            else
                seen[technology] = true
            end
        end
    end

    local capacity = normalized.capacity
    if type(capacity) ~= 'table' or not Utils.IsFiniteNumber(capacity.maximum)
        or capacity.maximum <= 0 then
        addError(errors, path, 'capacity.maximum must be greater than zero')
    end

    validateHardware(normalized, errors, path)
    if not validState(normalized.state) then
        addError(errors, path, 'state is not a valid TowerState')
    end
    if type(normalized.backhaul) == 'table' and not validBackhaul(normalized.backhaul.status) then
        addError(errors, path, 'backhaul.status is not a valid BackhaulState')
    elseif normalized.backhaul ~= nil and type(normalized.backhaul) ~= 'table' then
        addError(errors, path, 'backhaul must be a table')
    end

    normalized.state = normalized.state or Enums.TowerState.OPERATIONAL
    normalized.backhaul = normalized.backhaul or { status = Enums.BackhaulState.ONLINE }
    normalized.backhaul.status = normalized.backhaul.status or Enums.BackhaulState.ONLINE
    normalized.hardware = normalized.hardware or {
        health = 100,
        antennas = {},
        radio = {},
        cooling = {},
    }
    normalized.hardware.health = normalized.hardware.health or 100

    return #errors == 0, errors, normalized
end

function TowerValidation.ValidateAll(towers)
    local errors, warnings, normalized = {}, {}, {}
    if type(towers) ~= 'table' then
        return false, { 'Towers must be a table' }, warnings, normalized
    end

    local seenIds = {}
    for index, tower in ipairs(towers) do
        local path = ('Towers[%d]'):format(index)
        local ok, towerErrors, candidate = TowerValidation.Validate(tower, path)
        if not ok then
            for _, message in ipairs(towerErrors) do errors[#errors + 1] = message end
        elseif seenIds[candidate.id] then
            addError(errors, path, ('duplicate tower id: %s'):format(candidate.id))
        else
            seenIds[candidate.id] = true
            normalized[#normalized + 1] = candidate
        end
    end

    table.sort(normalized, function(left, right)
        return left.id < right.id
    end)

    return #errors == 0, errors, warnings, normalized
end
