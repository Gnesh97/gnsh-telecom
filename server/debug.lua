TelecomDebug = TelecomDebug or {}

local registeredCommands = false
local overlayBySource = {}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= math.floor(number) or number < 0 then return nil end
    return number
end

local function token(args, index)
    local value = type(args) == 'table' and args[index]
    return type(value) == 'string' and value or nil
end

local function lower(value)
    return type(value) == 'string' and value:lower() or nil
end

local function authorized(source)
    if not TelecomPermissions or not TelecomPermissions.RequireAdmin then
        return false, 'security_unavailable'
    end
    return TelecomPermissions.RequireAdmin(source)
end

local function record(source, action, details)
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source, action, details)
    end
end

local function success(payload)
    return true, 'ok', copy(payload)
end

local function failure(errorCode)
    return false, errorCode
end

function TelecomDebug.InspectTower(towerId)
    if type(towerId) ~= 'string' or towerId == '' then
        return nil, 'tower_required'
    end

    local tower = TowerRegistry and TowerRegistry.Get and TowerRegistry.Get(towerId)
    local runtime = TowerRegistry and TowerRegistry.GetRuntimeState
        and TowerRegistry.GetRuntimeState(towerId)
    if not tower or not runtime then return nil, 'unknown_tower' end

    return {
        id = tower.id,
        coords = copy(tower.coords),
        coverage = copy(tower.coverage),
        technologies = copy(tower.technologies),
        capacity = copy(tower.capacity),
        runtime = copy(runtime),
        failures = FailureEngine and FailureEngine.GetTowerFailures
            and FailureEngine.GetTowerFailures(towerId)
            or {},
    }
end

function TelecomDebug.InspectPlayer(source)
    local number = normalizeSource(source)
    if not number or number == 0 then return nil, 'player_source_required' end
    local state = Connections and Connections.Get and Connections.Get(number)
    if not state then return nil, 'no_connection' end
    return {
        source = number,
        state = copy(state),
    }
end

function TelecomDebug.ListTowers()
    local towers = {}
    for _, tower in ipairs(TowerRegistry.GetAll and TowerRegistry.GetAll() or {}) do
        local snapshot = TelecomDebug.InspectTower(tower.id)
        if snapshot then towers[#towers + 1] = snapshot end
    end
    return towers
end

function TelecomDebug.GetNoc()
    local connections = Connections and Connections.GetAll and Connections.GetAll() or {}
    return {
        connectedPlayers = #connections,
        towers = TelecomDebug.ListTowers(),
    }
end

local function toggleOverlay(source)
    local number = normalizeSource(source)
    if not number or number == 0 then return failure('player_source_required') end

    local enabled = not overlayBySource[number]
    overlayBySource[number] = enabled
    if type(TriggerClientEvent) == 'function' then
        TriggerClientEvent(Constants.Events.DEBUG_OVERLAY, number, enabled)
    end
    record(number, 'toggle_overlay', { enabled = enabled })
    return success({ enabled = enabled })
end

local function executeTower(source, args)
    local towerId = token(args, 2)
    local snapshot, errorCode = TelecomDebug.InspectTower(towerId)
    if not snapshot then return failure(errorCode) end
    record(source, 'inspect_tower', { towerId = towerId })
    return success(snapshot)
end

local function executeTowers(source)
    local towers = TelecomDebug.ListTowers()
    record(source, 'list_towers', { count = #towers })
    return success(towers)
end

local function executeNoc(source)
    local payload = TelecomDebug.GetNoc()
    record(source, 'inspect_noc', { towerCount = #payload.towers })
    return success(payload)
end

local function executeSignal(source, args)
    local target = tonumber(token(args, 2) or source)
    local snapshot, errorCode = TelecomDebug.InspectPlayer(target)
    if not snapshot then return failure(errorCode) end
    record(source, 'inspect_signal', { target = snapshot.source })
    return success(snapshot)
end

local function executeFailure(source, args)
    local towerId = token(args, 2)
    local failureType = token(args, 3)
    if type(failureType) ~= 'string' then return failure('failure_type_required') end
    failureType = failureType:upper()

    local ok, recordData, effects = FailureEngine.Create(towerId, failureType, {
        source = normalizeSource(source),
        reason = 'admin_debug',
        metadata = { command = 'telecom fail' },
    })
    if not ok then return failure(recordData) end

    local snapshot, errorCode = TelecomDebug.InspectTower(towerId)
    if not snapshot then return failure(errorCode) end
    snapshot.createdFailure = recordData
    snapshot.failureEffects = effects
    record(source, 'create_failure', {
        towerId = towerId,
        failureType = failureType,
        failureId = recordData.id,
    })
    return success(snapshot)
end

local function executeRepair(source, args)
    local towerId = token(args, 2)
    local failures = FailureEngine.GetTowerFailures(towerId)
    if type(failures) ~= 'table' then return failure('unknown_tower') end

    for _, failureData in ipairs(failures) do
        local ok, errorCode = FailureEngine.Clear(failureData.id)
        if not ok then return failure(errorCode) end
    end

    local snapshot, errorCode = TelecomDebug.InspectTower(towerId)
    if not snapshot then return failure(errorCode) end
    snapshot.repairedCount = #failures
    record(source, 'repair_tower', {
        towerId = towerId,
        repairedCount = #failures,
    })
    return success(snapshot)
end

local function executeLoad(source, args)
    local towerId = token(args, 2)
    local value = lower(token(args, 3))
    local ok, result
    if value == 'clear' or value == 'reset' then
        ok, result = Capacity.ClearDebugLoad(towerId)
    else
        local loadPercent = tonumber(token(args, 3))
        if not loadPercent then return failure('load_percent_required') end
        ok, result = Capacity.SetDebugLoad(towerId, loadPercent)
    end
    if not ok then return failure(result) end

    local snapshot, errorCode = TelecomDebug.InspectTower(towerId)
    if not snapshot then return failure(errorCode) end
    snapshot.loadResult = result
    record(source, 'set_debug_load', {
        towerId = towerId,
        loadPercent = snapshot.runtime.debugLoadPercent,
    })
    return success(snapshot)
end

function TelecomDebug.Execute(source, args)
    local ok, errorCode = authorized(source)
    if not ok then return failure(errorCode) end

    local command = lower(token(args, 1)) or 'help'
    if command == 'debug' or command == 'overlay' or command == 'toggle' then
        return toggleOverlay(source)
    end
    if command == 'tower' then return executeTower(source, args) end
    if command == 'towers' then return executeTowers(source) end
    if command == 'noc' then return executeNoc(source) end
    if command == 'signal' or command == 'player' then
        return executeSignal(source, args)
    end
    if command == 'fail' then return executeFailure(source, args) end
    if command == 'repair' then return executeRepair(source, args) end
    if command == 'load' then return executeLoad(source, args) end
    if command == 'help' then
        return success({
            'telecomdebug',
            'telecom tower <id>',
            'telecom towers',
            'telecom signal [playerId]',
            'telecom fail <towerId> <failureType>',
            'telecom repair <towerId>',
            'telecom load <towerId> <percent|clear>',
            'telecom noc',
        })
    end
    return failure('unknown_debug_command')
end

local function reply(source, message)
    local number = normalizeSource(source)
    if number and number > 0 and type(TriggerClientEvent) == 'function' then
        TriggerClientEvent(Constants.Events.DEBUG_MESSAGE, number, message)
    elseif type(print) == 'function' then
        print(('[gnsh-telecom] %s'):format(message))
    end
end

local function executeCommand(source, args)
    local ok, errorCode, payload = TelecomDebug.Execute(source, args)
    if not ok then
        reply(source, ('debug command rejected: %s'):format(tostring(errorCode)))
        return
    end
    local command = lower(token(args, 1)) or 'help'
    local suffix = ''
    if command == 'towers' then
        suffix = (' towers=%d'):format(#payload)
    elseif command == 'noc' then
        suffix = (' towers=%d players=%d'):format(#payload.towers, payload.connectedPlayers)
    elseif payload and payload.id then
        suffix = (' tower=%s'):format(payload.id)
    elseif payload and payload.enabled ~= nil then
        suffix = (' enabled=%s'):format(tostring(payload.enabled))
    end
    reply(source, ('debug command ok:%s%s'):format(command, suffix))
end

function TelecomDebug.RegisterCommands()
    if registeredCommands then return false, 'commands_already_registered' end
    if type(RegisterCommand) ~= 'function' then return false, 'command_api_unavailable' end

    RegisterCommand('telecom', function(source, args)
        executeCommand(source, args)
    end, false)
    RegisterCommand('telecomdebug', function(source)
        executeCommand(source, { 'debug' })
    end, false)
    registeredCommands = true
    return true
end

TelecomDebug.RegisterCommands()

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        local number = normalizeSource(source)
        if number then overlayBySource[number] = nil end
    end)
end
