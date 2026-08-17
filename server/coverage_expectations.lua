TelecomCoverageExpectations = TelecomCoverageExpectations or {}

local registeredCommands = false
local EXPECTATIONS = {
    STRONG = true,
    GOOD = true,
    MODERATE = true,
    WEAK_OR_NONE = true,
}

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function finite(value)
    return Utils and Utils.IsFiniteNumber and Utils.IsFiniteNumber(value)
        or type(value) == 'number' and value == value
            and value ~= math.huge and value ~= -math.huge
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or not finite(number) or number ~= math.floor(number) or number < 0 then
        return nil
    end
    return number
end

local function token(args, index)
    local value = type(args) == 'table' and args[index]
    return type(value) == 'string' and value or nil
end

local function upper(value)
    return type(value) == 'string' and value:upper() or nil
end

local function validPoint(value)
    return Utils and Utils.IsPoint and Utils.IsPoint(value)
end

local function authorized(source)
    if not TelecomPermissions or not TelecomPermissions.RequireAdmin then
        return false, 'security_unavailable'
    end
    return TelecomPermissions.RequireAdmin(source)
end

local function enabled()
    return TelecomCoverageDebug and TelecomCoverageDebug.IsEnabled
        and TelecomCoverageDebug.IsEnabled()
end

local function reply(source, message)
    local number = normalizeSource(source)
    if number and number > 0 and type(TriggerClientEvent) == 'function'
        and Constants and Constants.Events and Constants.Events.DEBUG_MESSAGE then
        TriggerClientEvent(Constants.Events.DEBUG_MESSAGE, number, message)
    elseif type(print) == 'function' then
        print(('[gnsh-telecom] %s'):format(tostring(message)))
    end
end

local function anchors()
    return Config and Config.CoverageExpectations or {}
end

function TelecomCoverageExpectations.GetAll()
    return copy(anchors())
end

function TelecomCoverageExpectations.Find(id)
    if type(id) ~= 'string' then return nil end
    for _, anchor in ipairs(anchors()) do
        if type(anchor) == 'table' and anchor.id == id then return copy(anchor) end
    end
    return nil
end

function TelecomCoverageExpectations.Validate()
    local errors = {}
    local seen = {}
    local configured = anchors()
    if type(configured) ~= 'table' then
        return false, { 'CoverageExpectations must be a table' }
    end

    for index, anchor in ipairs(configured) do
        local path = ('CoverageExpectations[%d]'):format(index)
        if type(anchor) ~= 'table' then
            errors[#errors + 1] = path .. ' must be a table'
        else
            local id = anchor.id
            if type(id) ~= 'string' or not id:match('^[A-Z0-9][A-Z0-9_-]*$') then
                errors[#errors + 1] = path .. '.id must be an uppercase identifier'
            elseif seen[id] then
                errors[#errors + 1] = path .. '.id duplicates ' .. id
            else
                seen[id] = true
            end

            if type(anchor.category) ~= 'string' or anchor.category == '' then
                errors[#errors + 1] = path .. '.category must be a non-empty string'
            end
            if not EXPECTATIONS[anchor.expectation] then
                errors[#errors + 1] = path .. '.expectation is unsupported'
            end
            if anchor.position ~= nil and not validPoint(anchor.position) then
                errors[#errors + 1] = path .. '.position must be a finite point'
            elseif anchor.position == nil and anchor.captureRequired ~= true then
                errors[#errors + 1] = path .. '.position requires a verified capture'
            end
        end
    end
    return #errors == 0, errors
end

function TelecomCoverageExpectations.MatchesExpectation(signal, expectation)
    local value = finite(signal) and math.max(0, math.min(100, signal)) or 0
    if expectation == 'STRONG' then return value >= 80 end
    if expectation == 'GOOD' then return value >= 55 end
    if expectation == 'MODERATE' then return value >= 30 end
    if expectation == 'WEAK_OR_NONE' then return value < 30 end
    return false
end

local function evaluateAt(anchor, coords, environmentContext)
    if not validPoint(coords) then
        return {
            id = anchor.id,
            category = anchor.category,
            expectation = anchor.expectation,
            status = 'PENDING_CAPTURE',
        }
    end

    local candidates = Coverage and Coverage.GetCandidates
        and Coverage.GetCandidates(coords, environmentContext) or {}
    local ranked = Selection and Selection.Rank
        and Selection.Rank(candidates, { source = 0 }) or {}
    local best = ranked[1]
    local signal = best and best.signal or 0
    local band = TelecomCoverageDebug and TelecomCoverageDebug.GetHeatmapBand
        and TelecomCoverageDebug.GetHeatmapBand(signal)
        or 'BLACK'
    return {
        id = anchor.id,
        category = anchor.category,
        expectation = anchor.expectation,
        position = { x = coords.x, y = coords.y, z = coords.z },
        status = TelecomCoverageExpectations.MatchesExpectation(
            signal,
            anchor.expectation
        ) and 'PASS' or 'FAIL',
        signal = signal,
        band = band,
        towerId = best and best.towerId or nil,
        sectorId = best and best.sectorId or nil,
        candidateCount = #ranked,
    }
end

function TelecomCoverageExpectations.Evaluate(anchor, environmentContext)
    if type(anchor) ~= 'table' then return nil, 'invalid_anchor' end
    return evaluateAt(anchor, anchor.position, environmentContext)
end

function TelecomCoverageExpectations.EvaluateAll(environmentContext)
    local results = {}
    for _, anchor in ipairs(anchors()) do
        local result = TelecomCoverageExpectations.Evaluate(anchor, environmentContext)
        if result then results[#results + 1] = result end
    end
    return results
end

local function playerCoords(source)
    local number = normalizeSource(source)
    if not number or number == 0 then return nil, 'player_source_required' end
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return nil, 'position_unavailable'
    end
    local ped = GetPlayerPed(number)
    if not ped or ped == 0 then return nil, 'player_ped_unavailable' end
    local coords = GetEntityCoords(ped)
    if not validPoint(coords) then return nil, 'player_position_unavailable' end
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function environmentFor(source)
    local number = normalizeSource(source)
    if number and number > 0 and Connections and Connections.Get then
        local state = Connections.Get(number)
        return state and copy(state.environment) or nil
    end
    return nil
end

local function formatNumber(value)
    return finite(value) and ('%.2f'):format(value) or 'n/a'
end

local function formatPosition(coords)
    return ('vector3(%.2f, %.2f, %.2f)')
        :format(coords.x, coords.y, coords.z)
end

local function commandExpectations(source)
    local ok, errorCode = authorized(source)
    if not ok then
        reply(source, ('coverage expectations rejected: %s'):format(errorCode))
        return
    end
    if not enabled() then
        reply(source, 'coverage expectations rejected: coverage_tools_disabled')
        return
    end

    local valid, errors = TelecomCoverageExpectations.Validate()
    if not valid then
        for _, message in ipairs(errors) do reply(source, message) end
        return
    end

    local results = TelecomCoverageExpectations.EvaluateAll(environmentFor(source))
    local pass, fail, pending = 0, 0, 0
    for _, result in ipairs(results) do
        if result.status == 'PASS' then pass = pass + 1 end
        if result.status == 'FAIL' then fail = fail + 1 end
        if result.status == 'PENDING_CAPTURE' then pending = pending + 1 end
        reply(source, ('anchor=%s expected=%s status=%s signal=%s band=%s tower=%s')
            :format(
                result.id,
                result.expectation,
                result.status,
                formatNumber(result.signal),
                tostring(result.band),
                tostring(result.towerId)
            ))
    end
    reply(source, ('coverage expectations summary: pass=%d fail=%d pending=%d')
        :format(pass, fail, pending))

    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source, 'coverage_expectations_evaluate', {
            pass = pass,
            fail = fail,
            pending = pending,
        })
    end
end

local function commandCapture(source, args)
    local ok, errorCode = authorized(source)
    if not ok then
        reply(source, ('coverage capture rejected: %s'):format(errorCode))
        return
    end
    if not enabled() then
        reply(source, 'coverage capture rejected: coverage_tools_disabled')
        return
    end

    local playerSource = normalizeSource(source)
    if not playerSource or playerSource == 0 then
        reply(source, 'coverage capture rejected: player_source_required')
        return
    end

    local id = upper(token(args, 1))
    local anchor = id and TelecomCoverageExpectations.Find(id) or nil
    if not anchor then
        reply(source, 'coverage capture rejected: unknown_anchor')
        return
    end

    local coords
    coords, errorCode = playerCoords(playerSource)
    if not coords then
        reply(source, ('coverage capture rejected: %s'):format(errorCode))
        return
    end

    local expectation = upper(token(args, 2)) or anchor.expectation
    if not EXPECTATIONS[expectation] then
        reply(source, 'coverage capture rejected: unsupported_expectation')
        return
    end

    local result = evaluateAt(anchor, coords, environmentFor(playerSource))
    reply(playerSource, ('coverage capture id=%s coords=(%s,%s,%s) signal=%s band=%s status=%s')
        :format(
            id,
            formatNumber(coords.x),
            formatNumber(coords.y),
            formatNumber(coords.z),
            formatNumber(result.signal),
            tostring(result.band),
            result.status
        ))
    reply(playerSource, ('coverage config: { id = \'%s\', category = \'%s\', position = %s, expectation = \'%s\' }')
        :format(id, anchor.category, formatPosition(coords), expectation))

    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(playerSource, 'coverage_expectation_capture', {
            id = id,
            expectation = expectation,
            signal = result.signal,
            band = result.band,
        })
    end
end

function TelecomCoverageExpectations.RegisterCommands()
    if registeredCommands then return false, 'commands_already_registered' end
    if type(RegisterCommand) ~= 'function' then return false, 'command_api_unavailable' end

    RegisterCommand('telecom_coverage_expectations', function(source)
        commandExpectations(source)
    end, false)
    RegisterCommand('telecom_coverage_capture', function(source, args)
        commandCapture(source, args)
    end, false)
    registeredCommands = true
    return true
end

TelecomCoverageExpectations.RegisterCommands()
