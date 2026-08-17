Sabotage = Sabotage or {}

local activeBySource = {}

local function enabled()
    return Config and Config.Features and Config.Features.Sabotage == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function actionConfig(actionId)
    local actions = Config and Config.Sabotage and Config.Sabotage.actions
    if type(actionId) ~= 'string' or type(actions) ~= 'table' then return nil end
    return actions[actionId]
end

local function requiredItemRequest(action)
    local item = action and action.requiredItem
    if item == nil or item == '' then return nil, 1 end
    if type(item) ~= 'string' or #item > 64 then
        return nil, 'invalid_required_item'
    end

    local amount = tonumber(action.requiredAmount) or 1
    if amount ~= math.floor(amount) or amount <= 0 or amount > 10000
        or amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil, 'invalid_required_amount'
    end
    return item, amount
end

function Sabotage.Execute(source, towerId, actionId)
    if not enabled() then return false, 'sabotage_disabled' end
    local configured = Config.Sabotage or {}
    local action = actionConfig(actionId)
    if not action then return false, 'unknown_sabotage_action' end

    local maxConcurrent = tonumber(configured.maxConcurrent) or 1
    if activeBySource[source] and maxConcurrent <= 1 then return false, 'sabotage_in_progress' end
    local allowed, rateError = TelecomRateLimit.Allow(
        source,
        'sabotage',
        tonumber(configured.cooldownMs) or 60000,
        1
    )
    if not allowed then return false, rateError end

    local near, tower, distance = TelecomSecurity.ValidateTower(
        source,
        towerId,
        tonumber(configured.interactionDistance) or 4.0
    )
    if not near then return false, tower end

    local requiredItem, requiredAmountOrError = requiredItemRequest(action)
    if requiredItem == nil and requiredAmountOrError ~= 1 then
        return false, requiredAmountOrError
    end
    local requiredAmount = requiredAmountOrError
    local hasItem, itemError = InventoryBridge.HasItem(source, requiredItem, requiredAmount)
    if not hasItem then return false, itemError or 'required_item_missing' end

    local existing = FailureEngine.GetTowerFailures(towerId)
    for _, failure in ipairs(existing or {}) do
        if failure.active ~= false and failure.type == action.failureType then
            return false, 'sabotage_target_already_affected'
        end
    end

    local ok, failure, effects = FailureEngine.Create(towerId, action.failureType, {
        source = tonumber(source),
        reason = 'sabotage',
        component = action.component,
        metadata = {
            action = actionId,
            distance = distance,
        },
    })
    if not ok then return false, failure end
    if requiredItem then
        local removed, removeError = InventoryBridge.RemoveItem(
            source,
            requiredItem,
            requiredAmount
        )
        if not removed then
            FailureEngine.Clear(failure.id)
            return false, removeError or 'required_item_remove_failed'
        end
    end

    activeBySource[source] = nil
    local alarm = math.random() < (tonumber(configured.alarmProbability) or 0)
    local alert = {
        towerId = towerId,
        action = actionId,
        source = tonumber(source),
        alarm = alarm,
    }
    if alarm then DispatchBridge.Alert(alert) end
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source, 'sabotage', alert)
    end
    if TelecomStatistics and TelecomStatistics.RecordSabotage then TelecomStatistics.RecordSabotage() end
    return true, {
        tower = tower,
        failure = copy(failure),
        effects = copy(effects),
        alarm = alarm,
    }
end

if type(RegisterNetEvent) == 'function' then RegisterNetEvent(Constants.Events.SABOTAGE_REQUEST) end
if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.SABOTAGE_REQUEST, function(payload)
        local sourceId = source
        if type(payload) ~= 'table'
            or not TelecomSecurity.IsSafeString(payload.towerId, 64)
            or not TelecomSecurity.IsSafeString(payload.action, 64) then return end
        local ok, result = Sabotage.Execute(sourceId, payload.towerId, payload.action)
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent(Constants.Events.SABOTAGE_STATE, sourceId, {
                ok = ok,
                result = ok and copy(result) or nil,
                error = ok and nil or result,
            })
        end
    end)
    AddEventHandler('playerDropped', function()
        activeBySource[source] = nil
        TelecomRateLimit.Clear(source)
    end)
end
