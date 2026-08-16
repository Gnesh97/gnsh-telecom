Environment = Environment or {}

local fallbackCategory = 'OPEN_AREA'

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPoint(value)
    return Utils and Utils.IsPoint and Utils.IsPoint(value)
        or (type(value) == 'table'
            and isFiniteNumber(value.x)
            and isFiniteNumber(value.y)
            and isFiniteNumber(value.z))
end

local function isKnownCategory(category, environment)
    return type(category) == 'string'
        and type(environment) == 'table'
        and type(environment.allowed) == 'table'
        and environment.allowed[category] == true
end

local function distanceSquared(left, right)
    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return dx * dx + dy * dy + dz * dz
end

local function isValidZone(zone, environment)
    return type(zone) == 'table'
        and type(zone.id) == 'string'
        and zone.id ~= ''
        and isPoint(zone.coords)
        and isFiniteNumber(zone.radius)
        and zone.radius > 0
        and isKnownCategory(zone.category, environment)
end

local function isPreferredZone(candidate, selected)
    if not selected then return true end
    if candidate.radius ~= selected.radius then
        return candidate.radius < selected.radius
    end
    return candidate.id < selected.id
end

function Environment.GetContext(coords)
    local environment = Config and Config.Environment or {}
    local default = isKnownCategory(environment.default, environment)
        and environment.default
        or fallbackCategory
    local selected

    if isPoint(coords) and type(environment.zones) == 'table' then
        for _, zone in ipairs(environment.zones) do
            if isValidZone(zone, environment)
                and distanceSquared(zone.coords, coords) <= zone.radius * zone.radius
                and isPreferredZone(zone, selected) then
                selected = zone
            end
        end
    end

    if selected then
        return {
            category = selected.category,
            zoneId = selected.id,
        }
    end

    return { category = default }
end
