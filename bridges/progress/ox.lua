local function isServer()
    if type(IsDuplicityVersion) == 'function' then
        local ok, value = pcall(IsDuplicityVersion)
        if ok then return value == true end
    end
    return true
end

local function resourceStarted(name)
    if type(GetResourceState) ~= 'function' then return false end
    local ok, state = pcall(GetResourceState, name)
    return ok and state == 'started'
end

local function boundedString(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum and value or nil
end

local function oxPayload(action, duration, options)
    local options = type(options) == 'table' and options or {}
    local payload = {
        duration = duration,
        label = boundedString(options.label, 128) or action,
        canCancel = options.canCancel ~= false,
    }
    if type(options.useWhileDead) == 'boolean' then
        payload.useWhileDead = options.useWhileDead
    end
    if type(options.allowRagdoll) == 'boolean' then payload.allowRagdoll = options.allowRagdoll end
    if type(options.allowCuffed) == 'boolean' then payload.allowCuffed = options.allowCuffed end
    if type(options.allowFalling) == 'boolean' then payload.allowFalling = options.allowFalling end
    if type(options.allowSwimming) == 'boolean' then payload.allowSwimming = options.allowSwimming end
    if type(options.disable) == 'table' then
        local disable = {}
        for _, key in ipairs({ 'move', 'car', 'combat', 'mouse', 'sprint' }) do
            if type(options.disable[key]) == 'boolean' then
                disable[key] = options.disable[key]
            end
        end
        payload.disable = disable
    end
    return payload
end

local function runOxProgress(action, duration, options)
    if type(lib) ~= 'table' then return false, 'ox_lib_progress_unavailable' end
    local payload = oxPayload(action, duration, options)
    local handler = options and options.type == 'circle' and lib.progressCircle or lib.progressBar
    if type(handler) ~= 'function' then return false, 'ox_lib_progress_unavailable' end
    local ok, result = pcall(handler, payload)
    if not ok then return false, 'ox_lib_progress_failed' end
    return true, result
end

local function oxStartProgress(source, action, duration, options)
    if isServer() then
        if type(TriggerClientEvent) ~= 'function' then
            return false, 'ox_progress_transport_unavailable'
        end
        local ok = pcall(TriggerClientEvent, Constants.SupportEvents.PROGRESS_START, source, {
            provider = 'ox',
            action = action,
            duration = duration,
            options = options,
        })
        if not ok then return false, 'ox_progress_transport_failed' end
        return true
    end
    return runOxProgress(action, duration, options)
end

if ProgressBridge and type(ProgressBridge.Register) == 'function' then
    ProgressBridge.Register({
        name = 'ox',
        priority = 100,
        resources = { 'ox_lib' },
        Detect = function() return resourceStarted('ox_lib') end,
        StartProgress = oxStartProgress,
    })
end

if not isServer() and type(AddEventHandler) == 'function' then
    if type(RegisterNetEvent) == 'function' then
        pcall(RegisterNetEvent, Constants.SupportEvents.PROGRESS_START)
    end
    AddEventHandler(Constants.SupportEvents.PROGRESS_START, function(payload)
        if type(payload) ~= 'table' or payload.provider ~= 'ox'
            or type(payload.action) ~= 'string' or type(payload.duration) ~= 'number' then
            return
        end
        local ok = runOxProgress(payload.action, payload.duration, payload.options or {})
        if not ok and ProgressBridge and type(ProgressBridge.StartNative) == 'function' then
            ProgressBridge.StartNative(nil, payload.action, payload.duration, payload.options or {})
        end
    end)
end
