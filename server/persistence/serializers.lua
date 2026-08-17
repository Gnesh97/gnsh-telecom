PersistenceSerializers = PersistenceSerializers or {}

local defaultPayloadLimit = 4096
local maxIdentifierLength = 64
local maxSubscriberPlayerIdLength = 128
local maxSubscriberSimIdLength = 64
local maxSubscriberServiceClassLength = 32
local maxReasonLength = 512
local maxActionLength = 128
local maxSource = 2147483647
local maxTimestamp = 4102444800

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function payloadLimit()
    local configured = Config and Config.Persistence and Config.Persistence.maxPayloadBytes
    if type(configured) == 'number' and configured >= 512 then return configured end
    return defaultPayloadLimit
end

local escapeMap = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function encodeString(value)
    return ('"%s"'):format(value:gsub('[%z\1-\31\\"]', function(character)
        return escapeMap[character] or ('\\u%04x'):format(character:byte())
    end))
end

local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= 'string' then return nil, 'object_key_must_be_string' end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function encodeValue(value, depth, seen)
    if depth > 8 then return nil, 'json_depth_exceeded' end
    local valueType = type(value)
    if value == nil then return nil, 'json_null_unsupported' end
    if valueType == 'boolean' then return value and 'true' or 'false' end
    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, 'json_number_invalid'
        end
        return tostring(value)
    end
    if valueType == 'string' then return encodeString(value) end
    if valueType ~= 'table' then return nil, 'json_value_invalid' end
    if seen[value] then return nil, 'json_cycle_detected' end
    seen[value] = true

    local isArray = true
    local count = 0
    local maxIndex = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then
            isArray = false
            break
        end
        count = count + 1
        if key > maxIndex then maxIndex = key end
    end
    if isArray and count ~= maxIndex then isArray = false end

    local parts = {}
    if isArray then
        if maxIndex > 100 then seen[value] = nil return nil, 'json_field_limit_exceeded' end
        for index = 1, maxIndex do
            local encoded, errorCode = encodeValue(value[index], depth + 1, seen)
            if not encoded then seen[value] = nil return nil, errorCode end
            parts[#parts + 1] = encoded
        end
        seen[value] = nil
        return ('[%s]'):format(table.concat(parts, ','))
    end

    local keys, keyError = sortedKeys(value)
    if not keys then seen[value] = nil return nil, keyError end
    if #keys > 100 then seen[value] = nil return nil, 'json_field_limit_exceeded' end
    for _, key in ipairs(keys) do
        local encoded, errorCode = encodeValue(value[key], depth + 1, seen)
        if not encoded then seen[value] = nil return nil, errorCode end
        parts[#parts + 1] = encodeString(key) .. ':' .. encoded
    end
    seen[value] = nil
    return ('{%s}'):format(table.concat(parts, ','))
end

local function encodeJson(value)
    local encoded, errorCode = encodeValue(value, 0, {})
    if not encoded then return nil, errorCode end
    if #encoded > payloadLimit() then return nil, 'payload_too_large' end
    return encoded
end

local function decodeJson(value)
    if type(value) == 'table' then
        local _, validationError = encodeJson(value)
        if validationError then return nil, validationError end
        return copy(value)
    end
    if type(value) ~= 'string' then return nil, 'json_required' end
    if #value > payloadLimit() then return nil, 'payload_too_large' end

    local position = 1
    local length = #value

    local function skipWhitespace()
        while position <= length and value:sub(position, position):match('%s') do
            position = position + 1
        end
    end

    local parseValue
    local parseArray
    local parseObject
    local function parseString()
        if value:sub(position, position) ~= '"' then return nil, 'json_string_required' end
        position = position + 1
        local result = {}
        while position <= length do
            local character = value:sub(position, position)
            position = position + 1
            if character == '"' then return table.concat(result) end
            if character == '\\' then
                local escaped = value:sub(position, position)
                position = position + 1
                local replacement = {
                    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
                }
                if replacement[escaped] then
                    result[#result + 1] = replacement[escaped]
                elseif escaped == 'u' then
                    local hex = value:sub(position, position + 3)
                    if not hex:match('^%x%x%x%x$') then return nil, 'json_unicode_invalid' end
                    local code = tonumber(hex, 16)
                    if code > 127 then return nil, 'json_unicode_unsupported' end
                    result[#result + 1] = string.char(code)
                    position = position + 4
                else
                    return nil, 'json_escape_invalid'
                end
            elseif character:byte() < 32 then
                return nil, 'json_control_character'
            else
                result[#result + 1] = character
            end
        end
        return nil, 'json_string_unterminated'
    end

    local function parseNumber()
        local token = value:sub(position):match('^-?%d+%.?%d*[eE]?[+-]?%d*')
        if not token or token == '' then return nil, 'json_number_invalid' end
        local number = tonumber(token)
        if not number or number ~= number or number == math.huge or number == -math.huge then
            return nil, 'json_number_invalid'
        end
        position = position + #token
        return number
    end

    parseArray = function(depth)
        if depth > 8 then return nil, 'json_depth_exceeded' end
        position = position + 1
        local result = {}
        skipWhitespace()
        if value:sub(position, position) == ']' then position = position + 1 return result end
        while true do
            if #result >= 100 then return nil, 'json_field_limit_exceeded' end
            local item, errorCode = parseValue(depth + 1)
            if item == nil and errorCode then return nil, errorCode end
            result[#result + 1] = item
            skipWhitespace()
            local delimiter = value:sub(position, position)
            if delimiter == ']' then position = position + 1 return result end
            if delimiter ~= ',' then return nil, 'json_array_delimiter_required' end
            position = position + 1
            skipWhitespace()
        end
    end

    parseObject = function(depth)
        if depth > 8 then return nil, 'json_depth_exceeded' end
        position = position + 1
        local result = {}
        local fields = 0
        skipWhitespace()
        if value:sub(position, position) == '}' then position = position + 1 return result end
        while true do
            fields = fields + 1
            if fields > 100 then return nil, 'json_field_limit_exceeded' end
            local key, keyError = parseString()
            if not key then return nil, keyError end
            skipWhitespace()
            if value:sub(position, position) ~= ':' then return nil, 'json_object_colon_required' end
            position = position + 1
            skipWhitespace()
            local item, itemError = parseValue(depth + 1)
            if item == nil and itemError then return nil, itemError end
            result[key] = item
            skipWhitespace()
            local delimiter = value:sub(position, position)
            if delimiter == '}' then position = position + 1 return result end
            if delimiter ~= ',' then return nil, 'json_object_delimiter_required' end
            position = position + 1
            skipWhitespace()
        end
    end

    parseValue = function(depth)
        if depth > 8 then return nil, 'json_depth_exceeded' end
        skipWhitespace()
        local character = value:sub(position, position)
        if character == '"' then return parseString() end
        if character == '{' then return parseObject(depth) end
        if character == '[' then return parseArray(depth) end
        if value:sub(position, position + 3) == 'true' then position = position + 4 return true end
        if value:sub(position, position + 4) == 'false' then position = position + 5 return false end
        if value:sub(position, position + 3) == 'null' then
            return nil, 'json_null_unsupported'
        end
        return parseNumber()
    end

    local result, errorCode = parseValue(0)
    if result == nil and errorCode then return nil, errorCode end
    skipWhitespace()
    if position <= length then return nil, 'json_trailing_data' end
    return result
end

local function validId(value)
    return type(value) == 'string'
        and #value > 0 and #value <= maxIdentifierLength
        and value:match('^[%w_.:%-]+$') ~= nil
end

local function validBoundedId(value, maximumLength)
    return type(value) == 'string'
        and #value > 0 and #value <= maximumLength
        and value:match('^[%w_.:%-]+$') ~= nil
end

local function normalizeTimestamp(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number ~= math.floor(number) or number < 0 or number > maxTimestamp then
        return nil
    end
    return number
end

local function normalizeSource(value, optional)
    if value == nil and optional then return nil end
    local number = tonumber(value)
    if not number or number ~= math.floor(number) or number < 0 or number > maxSource then
        return nil
    end
    return number
end

local function normalizeActive(value)
    if value == true or value == 1 or value == '1' then return true end
    if value == false or value == 0 or value == '0' then return false end
    return nil
end

local function validateTowerAndType(towerId, failureType)
    if TowerRegistry and TowerRegistry.Exists and not TowerRegistry.Exists(towerId) then
        return false, 'unknown_tower'
    end
    if FailureTypes and FailureTypes.IsSupported and not FailureTypes.IsSupported(failureType) then
        return false, 'unknown_failure_type'
    end
    return true
end

local function metadataFromRow(row, field)
    local value = row[field]
    if value == nil then return nil, 'invalid_' .. field end
    local decoded, errorCode = decodeJson(value)
    if not decoded then return nil, errorCode == 'payload_too_large' and errorCode or 'invalid_' .. field end
    if type(decoded) ~= 'table' then return nil, 'invalid_' .. field end
    return decoded
end

function PersistenceSerializers.SerializeFailure(record)
    if type(record) ~= 'table' then return nil, 'failure_record_required' end
    if not validId(record.id) then return nil, 'failure_id_invalid' end
    if not validId(record.towerId) then return nil, 'tower_id_invalid' end
    if type(record.type) ~= 'string' then return nil, 'failure_type_invalid' end
    local valid, validationError = validateTowerAndType(record.towerId, record.type)
    if not valid then return nil, validationError end
    if record.active ~= true then return nil, 'inactive_failure' end
    local createdAt = normalizeTimestamp(record.createdAt)
    if not createdAt then return nil, 'created_at_invalid' end
    local updatedAt = normalizeTimestamp(record.updatedAt or createdAt)
    if not updatedAt then return nil, 'updated_at_invalid' end
    local source = normalizeSource(record.source, true)
    if record.source ~= nil and source == nil then return nil, 'failure_source_invalid' end
    if record.reason ~= nil and (type(record.reason) ~= 'string' or #record.reason > maxReasonLength) then
        return nil, 'reason_too_long'
    end
    if type(record.metadata) ~= 'table' then return nil, 'metadata_invalid' end
    local metadataJson, metadataError = encodeJson(record.metadata)
    if not metadataJson then return nil, metadataError end
    return {
        id = record.id,
        tower_id = record.towerId,
        failure_type = record.type,
        active = 1,
        created_at = createdAt,
        source = source,
        reason = record.reason,
        metadata_json = metadataJson,
        updated_at = updatedAt,
    }
end

function PersistenceSerializers.DeserializeFailure(row)
    if type(row) ~= 'table' then return nil, 'failure_row_required' end
    local id = row.id
    local towerId = row.tower_id or row.towerId
    local failureType = row.failure_type or row.type
    if not validId(id) then return nil, 'failure_id_invalid' end
    if not validId(towerId) then return nil, 'tower_id_invalid' end
    if type(failureType) ~= 'string' then return nil, 'failure_type_invalid' end
    local valid, validationError = validateTowerAndType(towerId, failureType)
    if not valid then return nil, validationError end
    if normalizeActive(row.active) ~= true then return nil, 'inactive_failure' end
    local createdAt = normalizeTimestamp(row.created_at or row.createdAt)
    if not createdAt then return nil, 'created_at_invalid' end
    local updatedAt = normalizeTimestamp(row.updated_at or row.updatedAt or createdAt)
    if not updatedAt then return nil, 'updated_at_invalid' end
    local source = normalizeSource(row.source, true)
    if row.source ~= nil and source == nil then return nil, 'failure_source_invalid' end
    local reason = row.reason
    if reason ~= nil and (type(reason) ~= 'string' or #reason > maxReasonLength) then
        return nil, 'reason_too_long'
    end
    local metadata, metadataError = metadataFromRow(row, 'metadata_json')
    if not metadata then
        if metadataError == 'invalid_metadata_json' or metadataError == 'payload_too_large' then
            return nil, metadataError
        end
        return nil, 'invalid_metadata_json'
    end
    return {
        id = id,
        towerId = towerId,
        type = failureType,
        active = true,
        createdAt = createdAt,
        source = source,
        reason = reason,
        metadata = metadata,
        updatedAt = updatedAt,
    }
end

function PersistenceSerializers.SerializeAudit(record)
    if type(record) ~= 'table' then return nil, 'audit_record_required' end
    if not validId(record.id) then return nil, 'audit_id_invalid' end
    local source = normalizeSource(record.source)
    if source == nil then return nil, 'audit_source_invalid' end
    if type(record.action) ~= 'string' or record.action == '' then return nil, 'action_invalid' end
    if #record.action > maxActionLength then return nil, 'action_too_long' end
    local timestamp = normalizeTimestamp(record.timestamp)
    if not timestamp then return nil, 'timestamp_invalid' end
    if type(record.details) ~= 'table' then return nil, 'details_invalid' end
    local detailsJson, detailsError = encodeJson(record.details)
    if not detailsJson then return nil, detailsError end
    return {
        id = record.id,
        source = source,
        action = record.action,
        details_json = detailsJson,
        timestamp = timestamp,
    }
end

function PersistenceSerializers.DeserializeAudit(row)
    if type(row) ~= 'table' then return nil, 'audit_row_required' end
    if not validId(row.id) then return nil, 'audit_id_invalid' end
    local source = normalizeSource(row.source)
    if source == nil then return nil, 'audit_source_invalid' end
    if type(row.action) ~= 'string' or row.action == '' then return nil, 'action_invalid' end
    if #row.action > maxActionLength then return nil, 'action_too_long' end
    local timestamp = normalizeTimestamp(row.timestamp)
    if not timestamp then return nil, 'timestamp_invalid' end
    local details, detailsError = metadataFromRow(row, 'details_json')
    if not details then
        if detailsError == 'invalid_details_json' or detailsError == 'payload_too_large' then
            return nil, detailsError
        end
        return nil, 'invalid_details_json'
    end
    return {
        id = row.id,
        source = source,
        action = row.action,
        details = details,
        timestamp = timestamp,
    }
end

function PersistenceSerializers.SerializeSubscriber(record)
    if type(record) ~= 'table' then return nil, 'subscriber_record_required' end
    if not validBoundedId(record.playerId, maxSubscriberPlayerIdLength) then
        return nil, 'subscriber_player_id_invalid'
    end
    if not validBoundedId(record.simId, maxSubscriberSimIdLength) then
        return nil, 'subscriber_sim_id_invalid'
    end
    if not validBoundedId(record.carrierId, maxIdentifierLength) then
        return nil, 'subscriber_carrier_id_invalid'
    end
    if type(record.roamingAllowed) ~= 'boolean' then
        return nil, 'subscriber_roaming_allowed_invalid'
    end
    if type(record.serviceClass) ~= 'string' or record.serviceClass == ''
        or #record.serviceClass > maxSubscriberServiceClassLength then
        return nil, 'subscriber_service_class_invalid'
    end
    return {
        player_id = record.playerId,
        sim_id = record.simId,
        carrier_id = record.carrierId,
        roaming_allowed = record.roamingAllowed and 1 or 0,
        service_class = record.serviceClass,
    }
end

function PersistenceSerializers.DeserializeSubscriber(row)
    if type(row) ~= 'table' then return nil, 'subscriber_row_required' end
    local playerId = row.player_id or row.playerId
    local simId = row.sim_id or row.simId
    local carrierId = row.carrier_id or row.carrierId
    if not validBoundedId(playerId, maxSubscriberPlayerIdLength) then
        return nil, 'subscriber_player_id_invalid'
    end
    if not validBoundedId(simId, maxSubscriberSimIdLength) then
        return nil, 'subscriber_sim_id_invalid'
    end
    if not validBoundedId(carrierId, maxIdentifierLength) then
        return nil, 'subscriber_carrier_id_invalid'
    end
    local rawRoamingAllowed = row.roaming_allowed
    if rawRoamingAllowed == nil then rawRoamingAllowed = row.roamingAllowed end
    local roamingAllowed = normalizeActive(rawRoamingAllowed)
    if roamingAllowed == nil then return nil, 'subscriber_roaming_allowed_invalid' end
    local serviceClass = row.service_class or row.serviceClass
    if type(serviceClass) ~= 'string' or serviceClass == ''
        or #serviceClass > maxSubscriberServiceClassLength then
        return nil, 'subscriber_service_class_invalid'
    end
    return {
        playerId = playerId,
        simId = simId,
        carrierId = carrierId,
        roamingAllowed = roamingAllowed,
        serviceClass = serviceClass,
    }
end

function PersistenceSerializers.GetLimits()
    return {
        maxIdentifierLength = maxIdentifierLength,
        maxSubscriberPlayerIdLength = maxSubscriberPlayerIdLength,
        maxSubscriberSimIdLength = maxSubscriberSimIdLength,
        maxSubscriberServiceClassLength = maxSubscriberServiceClassLength,
        maxReasonLength = maxReasonLength,
        maxActionLength = maxActionLength,
        maxPayloadBytes = payloadLimit(),
    }
end
