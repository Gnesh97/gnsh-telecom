Carriers = Carriers or {}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function nonEmptyString(value)
    return type(value) == 'string' and value:match('%S') ~= nil
end

local function normalizeTechnologies(value)
    if value == nil then value = Technologies.GetAll() end
    if type(value) ~= 'table' or #value == 0 then
        return nil, 'technologies must contain at least one supported technology'
    end

    local result, seen = {}, {}
    for index, technology in ipairs(value) do
        if not Technologies.IsSupported(technology) then
            return nil, ('unsupported technology at index %d: %s')
                :format(index, tostring(technology))
        end
        if seen[technology] then
            return nil, ('duplicate technology: %s'):format(technology)
        end
        seen[technology] = true
        result[#result + 1] = technology
    end
    return result
end

local function normalizeRoamingPartners(value)
    if value == nil then return {} end
    if type(value) ~= 'table' then
        return nil, 'roamingPartners must be a table'
    end

    local result, seen = {}, {}
    for index, partner in ipairs(value) do
        if not nonEmptyString(partner) then
            return nil, ('roamingPartners[%d] must be a non-empty string'):format(index)
        end
        if not seen[partner] then
            seen[partner] = true
            result[#result + 1] = partner
        end
    end
    return result
end

function Carriers.Normalize(definition)
    if type(definition) ~= 'table' then
        return nil, 'carrier definition must be a table'
    end
    if not nonEmptyString(definition.id) then
        return nil, 'id must be a non-empty string'
    end
    if #definition.id > 64 then
        return nil, 'id must not exceed 64 characters'
    end
    if not nonEmptyString(definition.name) then
        return nil, 'name must be a non-empty string'
    end

    local technologies, technologyError = normalizeTechnologies(definition.technologies)
    if not technologies then return nil, technologyError end
    local roamingPartners, roamingError = normalizeRoamingPartners(definition.roamingPartners)
    if not roamingPartners then return nil, roamingError end

    local priority = definition.priority
    if priority == nil then priority = 0 end
    if not isFiniteNumber(priority) then return nil, 'priority must be a finite number' end

    return {
        id = definition.id,
        name = definition.name,
        technologies = technologies,
        roamingPartners = roamingPartners,
        priority = priority,
        branding = copy(definition.branding),
    }
end

function Carriers.Validate(definition)
    local normalized, errorMessage = Carriers.Normalize(definition)
    if not normalized then return false, { errorMessage } end
    return true, {}, normalized
end

local function sourceDefinitions(definitions)
    if type(definitions) ~= 'table' then return nil end
    if type(definitions.definitions) == 'table' then return definitions.definitions end
    return definitions
end

function Carriers.NormalizeAll(definitions)
    definitions = sourceDefinitions(definitions or {})
    if type(definitions) ~= 'table' then
        return false, { 'Carriers must be a table' }, {}
    end

    local entries = {}
    if #definitions > 0 then
        for index, definition in ipairs(definitions) do
            entries[#entries + 1] = { key = index, value = definition }
        end
    else
        for key, definition in pairs(definitions) do
            if type(definition) == 'table' and definition.id == nil then
                definition = copy(definition)
                definition.id = key
            end
            entries[#entries + 1] = { key = tostring(key), value = definition }
        end
        table.sort(entries, function(left, right)
            return left.key < right.key
        end)
    end

    local errors, normalized, seen = {}, {}, {}
    for index, entry in ipairs(entries) do
        local value, errorMessage = Carriers.Normalize(entry.value)
        if not value then
            errors[#errors + 1] = ('Carriers[%s] %s')
                :format(tostring(entry.key or index), tostring(errorMessage))
        elseif seen[value.id] then
            errors[#errors + 1] = ('duplicate carrier id: %s'):format(value.id)
        else
            seen[value.id] = true
            normalized[#normalized + 1] = value
        end
    end

    table.sort(normalized, function(left, right) return left.id < right.id end)
    return #errors == 0, errors, normalized
end

function Carriers.Copy(value)
    return copy(value)
end
