local function withGlobals(values, callback)
    local previous = {}
    for name, value in pairs(values) do
        previous[name] = _G[name]
        _G[name] = value
    end

    local ok, errorMessage = pcall(callback)

    for name, value in pairs(previous) do _G[name] = value end
    if not ok then error(errorMessage, 0) end
end

local function loadClientSupportFile(path, environment)
    local chunk = assert(loadfile(path, 't', environment))
    chunk()
end

TEST('native notify emits a bounded client payload', function()
    withGlobals({
        TriggerClientEvent = function(name, source, payload)
            _G.__supportNotifyCall = { name = name, source = source, payload = payload }
        end,
    }, function()
        ASSERT_TRUE(NotifyBridge.SetAdapter('native'))
        local ok, errorMessage = NotifyBridge.Notify(7, 'info', 'tower online', {
            title = 'Telecom',
        })
        ASSERT_TRUE(ok, errorMessage)
        ASSERT_EQ(__supportNotifyCall.name, Constants.SupportEvents.NOTIFY)
        ASSERT_EQ(__supportNotifyCall.source, 7)
        ASSERT_EQ(__supportNotifyCall.payload.kind, 'info')
        ASSERT_EQ(__supportNotifyCall.payload.message, 'tower online')
        ASSERT_EQ(__supportNotifyCall.payload.data.title, 'Telecom')
        ASSERT_FALSE(NotifyBridge.Notify(math.huge, 'info', 'invalid source', {}))

        local cyclic = {}
        cyclic.self = cyclic
        ASSERT_FALSE(NotifyBridge.Notify(7, 'info', 'cyclic payload', cyclic))
        ASSERT_FALSE(NotifyBridge.Notify(7, 'info', 'large payload', {
            value = string.rep('x', 4097),
        }))
    end)
    _G.__supportNotifyCall = nil
end)

TEST('ox notify maps the generic info kind to the documented inform type', function()
    withGlobals({
        GetResourceState = function(name)
            return name == 'ox_lib' and 'started' or 'stopped'
        end,
        TriggerClientEvent = function(name, source, payload)
            _G.__supportNotifyCall = { name = name, source = source, payload = payload }
        end,
    }, function()
        ASSERT_TRUE(NotifyBridge.SetAdapter('ox'))
        local ok, errorMessage = NotifyBridge.Notify(7, 'info', 'ox online', {})
        ASSERT_TRUE(ok, errorMessage)
        ASSERT_EQ(__supportNotifyCall.name, Constants.SupportEvents.NOTIFY)
        ASSERT_EQ(__supportNotifyCall.payload.provider, 'ox')
        ASSERT_EQ(__supportNotifyCall.payload.kind, 'info')
        ASSERT_EQ(__supportNotifyCall.payload.message, 'ox online')
        ASSERT_TRUE(NotifyBridge.SetAdapter('native'))
    end)
    _G.__supportNotifyCall = nil
end)

TEST('native progress is presentation-only and keeps the server authoritative', function()
    local threadCalls = 0
    withGlobals({
        TriggerClientEvent = function(name, source, payload)
            _G.__supportProgressCall = { name = name, source = source, payload = payload }
        end,
        CreateThread = function() threadCalls = threadCalls + 1 end,
    }, function()
        ASSERT_TRUE(ProgressBridge.SetAdapter('native'))
        local ok, errorMessage = ProgressBridge.StartProgress(7, 'repair_tower', 2500, {
            label = 'Repairing',
        })
        ASSERT_TRUE(ok, errorMessage)
        ASSERT_EQ(__supportProgressCall.name, Constants.SupportEvents.PROGRESS_START)
        ASSERT_EQ(__supportProgressCall.source, 7)
        ASSERT_EQ(__supportProgressCall.payload.action, 'repair_tower')
        ASSERT_EQ(__supportProgressCall.payload.duration, 2500)
        ASSERT_EQ(__supportProgressCall.payload.options.label, 'Repairing')
        ASSERT_EQ(threadCalls, 0)

        local invalid = ProgressBridge.StartProgress(7, 'repair_tower', 0, {})
        ASSERT_FALSE(invalid)
        ASSERT_FALSE(ProgressBridge.StartProgress(7, 'repair_tower', math.huge, {}))
    end)
    _G.__supportProgressCall = nil
end)

TEST('notify provider exceptions fall back to native safely', function()
    local calls = 0
    withGlobals({
        TriggerClientEvent = function() calls = calls + 1 end,
    }, function()
        ASSERT_TRUE(NotifyBridge.Register({
            name = 'broken-notify',
            priority = 1000,
            Detect = function() return true end,
            Notify = function() error('provider exploded') end,
        }))
        ASSERT_TRUE(NotifyBridge.SetAdapter('broken-notify'))

        local ok, fallback = NotifyBridge.Notify(7, 'warning', 'degraded', {})
        ASSERT_TRUE(ok)
        ASSERT_EQ(fallback, 'native_fallback')
        ASSERT_EQ(calls, 1)

        ASSERT_TRUE(NotifyBridge.Unregister('broken-notify'))
        ASSERT_TRUE(NotifyBridge.SetAdapter('native'))
    end)
end)

TEST('dispatch remains optional when no provider is configured', function()
    ASSERT_TRUE(DispatchBridge.SetAdapter(nil))
    local ok, errorMessage = DispatchBridge.CreateAlert({ id = 'no-provider' })
    ASSERT_FALSE(ok)
    ASSERT_EQ(errorMessage, 'dispatch_adapter_unavailable')
end)

TEST('custom dispatch adapters implement CreateAlert without breaking Alert', function()
    local captured
    ASSERT_TRUE(DispatchBridge.SetCustomAdapter({
        name = 'custom-dispatch',
        CreateAlert = function(payload)
            captured = payload
            return true
        end,
    }))

    local ok, errorMessage = DispatchBridge.CreateAlert({ id = 'custom-alert' })
    ASSERT_TRUE(ok, errorMessage)
    ASSERT_EQ(captured.id, 'custom-alert')
    local legacyOk = DispatchBridge.Alert({ id = 'legacy-alert' })
    ASSERT_TRUE(legacyOk)
    ASSERT_EQ(captured.id, 'legacy-alert')
    local invalid = DispatchBridge.CreateCustomAdapter({
        Alert = 'not-callable',
        CreateAlert = function() return true end,
    })
    ASSERT_EQ(invalid, nil)
    ASSERT_TRUE(DispatchBridge.SetAdapter(nil))
end)

TEST('native dispatch is opt-in and emits a defensive alert event', function()
    withGlobals({
        TriggerEvent = function(name, payload)
            _G.__supportDispatchCall = { name = name, payload = payload }
        end,
    }, function()
        ASSERT_TRUE(DispatchBridge.SetNative())
        local ok, errorMessage = DispatchBridge.CreateAlert({ id = 'native-alert' })
        ASSERT_TRUE(ok, errorMessage)
        ASSERT_EQ(__supportDispatchCall.name, Constants.SupportEvents.DISPATCH_ALERT)
        ASSERT_EQ(__supportDispatchCall.payload.id, 'native-alert')
        ASSERT_TRUE(DispatchBridge.SetAdapter(nil))
    end)
    _G.__supportDispatchCall = nil
end)

TEST('client ox support events fall back to native presentation when ox_lib is absent', function()
    local handlers = {}
    local events = {}
    local environment = {
        _G = nil,
        NotifyBridge = {},
        ProgressBridge = {},
        IsDuplicityVersion = function() return false end,
        Config = {},
        AddEventHandler = function(name, handler)
            handlers[name] = handlers[name] or {}
            handlers[name][#handlers[name] + 1] = handler
        end,
        RegisterNetEvent = function() end,
        TriggerEvent = function(name, ...)
            events[#events + 1] = { name = name, args = { ... } }
        end,
        GetResourceState = function() return 'started' end,
    }
    environment._G = environment
    setmetatable(environment, { __index = _G })

    loadClientSupportFile('bridges/notify/native.lua', environment)
    loadClientSupportFile('bridges/notify/ox.lua', environment)
    local notifyHandlers = handlers[Constants.SupportEvents.NOTIFY]
    ASSERT_TRUE(type(notifyHandlers) == 'table')
    for _, handler in ipairs(notifyHandlers) do
        handler({ provider = 'ox', kind = 'info', message = 'fallback', data = {} })
    end

    loadClientSupportFile('bridges/progress/native.lua', environment)
    loadClientSupportFile('bridges/progress/ox.lua', environment)
    local progressHandlers = handlers[Constants.SupportEvents.PROGRESS_START]
    ASSERT_TRUE(type(progressHandlers) == 'table')
    for _, handler in ipairs(progressHandlers) do
        handler({ provider = 'ox', action = 'repair', duration = 1500, options = {} })
    end

    local sawChat, sawProgress = false, false
    for _, event in ipairs(events) do
        if event.name == 'chat:addMessage' then sawChat = true end
        if event.name == 'progress' then sawProgress = true end
    end
    ASSERT_TRUE(sawChat)
    ASSERT_TRUE(sawProgress)
end)

TEST('support providers revalidate stopped dependencies before sending', function()
    local calls = {}
    withGlobals({
        GetResourceState = function() return 'stopped' end,
        TriggerClientEvent = function(name, source, payload)
            calls[#calls + 1] = { name = name, source = source, payload = payload }
        end,
    }, function()
        ASSERT_TRUE(NotifyBridge.SetAdapter('ox'))
        ASSERT_TRUE(NotifyBridge.Notify(7, 'info', 'fallback notify', {}))
        ASSERT_EQ(calls[1].name, Constants.SupportEvents.NOTIFY)
        ASSERT_EQ(calls[1].payload.provider, 'native')

        ASSERT_TRUE(ProgressBridge.SetAdapter('ox'))
        ASSERT_TRUE(ProgressBridge.StartProgress(7, 'fallback_progress', 1000, {}))
        ASSERT_EQ(calls[2].name, Constants.SupportEvents.PROGRESS_START)
        ASSERT_EQ(calls[2].payload.provider, 'native')

        NotifyBridge.SetAdapter('native')
        ProgressBridge.SetAdapter('native')
    end)
end)

TEST('progress presentation never completes a server-owned maintenance session', function()
    local previousGetGameTimer = GetGameTimer
    local now = 500000
    GetGameTimer = function() return now end
    MaintenanceSessions.ClearAll()

    local presented = false
    ASSERT_TRUE(ProgressBridge.SetAdapter({
        name = 'test-progress',
        StartProgress = function(source, action, duration)
            presented = source == 7 and action == 'maintenance' and duration == 1000
            return true
        end,
    }))

    local created, session = MaintenanceSessions.Create(
        'SUPPORT',
        7,
        'license:support',
        'INC-SUPPORT',
        'FAIL-SUPPORT',
        'TOWER-SUPPORT',
        1000
    )
    ASSERT_TRUE(created)
    ASSERT_TRUE(ProgressBridge.StartProgress(7, 'maintenance', 1000, {}))
    ASSERT_TRUE(presented)

    local early, earlyError = MaintenanceSessions.IsElapsed(session)
    ASSERT_FALSE(early)
    ASSERT_EQ(earlyError, 'session_too_early')
    ASSERT_TRUE(MaintenanceSessions.Get(session.sessionId) ~= nil)

    now = now + 1000
    ASSERT_TRUE(MaintenanceSessions.IsElapsed(session))
    local finished, finishedSession = MaintenanceSessions.Finish(session.sessionId, 'COMPLETED')
    ASSERT_TRUE(finished)
    ASSERT_EQ(finishedSession.state, 'COMPLETED')
    ASSERT_EQ(MaintenanceSessions.Get(session.sessionId), nil)

    ProgressBridge.SetAdapter('native')
    MaintenanceSessions.ClearAll()
    GetGameTimer = previousGetGameTimer
end)
