local function makeDebugTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetDebugState()
    Connections.Clear()
    FailureEngine.Reset()
    TowerRegistry.Init({})
    SpatialIndex.Rebuild({})
    TelecomAudit.Clear()
    TriggerTestEvent('txAdmin:events:adminsUpdated', {})
    Config.Features.Failures = true
    Config.Debug.enabled = true
end

TEST('txAdmin authenticated admin can execute debug commands', function()
    resetDebugState()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function() return false end

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    local ok, errorCode = TelecomDebug.Execute(7, { 'towers' })

    rawset(_G, 'IsPlayerAceAllowed', previous)
    ASSERT_TRUE(ok)
    ASSERT_EQ(errorCode, 'ok')
end)

TEST('txAdmin admin revocation removes debug access', function()
    resetDebugState()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function() return false end

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = false })
    local ok, errorCode = TelecomDebug.Execute(7, { 'towers' })

    rawset(_G, 'IsPlayerAceAllowed', previous)
    ASSERT_FALSE(ok)
    ASSERT_EQ(errorCode, 'not_authorized')
end)

TEST('txAdmin global revoke clears every cached admin', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 8, isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = -1, isAdmin = false })

    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
    ASSERT_FALSE(TelecomPermissions.IsAdmin(8))
end)

TEST('invalid txAdmin global auth payload clears every cached admin', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = -1, isAdmin = true })

    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
end)

TEST('txAdmin adminsUpdated replaces the cached admin set', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminsUpdated', { 7, '8' })
    ASSERT_TRUE(TelecomPermissions.IsAdmin(7))
    ASSERT_TRUE(TelecomPermissions.IsAdmin(8))

    TriggerTestEvent('txAdmin:events:adminsUpdated', { 8 })
    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
    ASSERT_TRUE(TelecomPermissions.IsAdmin(8))
end)

TEST('txAdmin event handlers update and clear cached admins', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    ASSERT_TRUE(TelecomPermissions.IsAdmin(7))

    local previousSource = rawget(_G, 'source')
    rawset(_G, 'source', 7)
    TriggerTestEvent('playerDropped')
    rawset(_G, 'source', previousSource)

    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
end)

TEST('txAdmin authorization rejects malformed event payloads', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = 'true' })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 'not-a-player', isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = math.huge, isAdmin = true })
    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
end)

TEST('malformed txAdmin updates fail closed for cached admins', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminsUpdated', { [2] = 8 })

    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
    ASSERT_FALSE(TelecomPermissions.IsAdmin(8))
end)

TEST('malformed txAdmin auth revocation clears its cached source', function()
    resetDebugState()

    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = true })
    TriggerTestEvent('txAdmin:events:adminAuth', { netid = 7, isAdmin = 'revoked' })

    ASSERT_FALSE(TelecomPermissions.IsAdmin(7))
end)

TEST('debug permissions fail closed when ACE native is unavailable', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    rawset(_G, 'IsPlayerAceAllowed', nil)

    ASSERT_FALSE(TelecomPermissions.IsAdmin(1))
    ASSERT_TRUE(TelecomPermissions.IsAdmin(0))

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('debug permissions use the configured ACE node', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    local seenSource
    local seenAce
    IsPlayerAceAllowed = function(source, ace)
        seenSource = source
        seenAce = ace
        return source == '12' and ace == Config.Debug.adminAce
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))
    ASSERT_EQ(seenSource, '12')
    ASSERT_EQ(seenAce, Config.Debug.adminAce)

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('standard command ACE grants debug access', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function(_, ace)
        return ace == 'command'
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('existing server admin ACE grants debug access', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function(_, ace)
        return ace == 'admin'
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('existing QBCore god ACE grants debug access', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function(_, ace)
        return ace == 'god'
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('debug permissions support native numeric source ids', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function(source, ace)
        return source == 12 and ace == Config.Debug.adminAce
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('debug permissions accept numeric ACE results from the native', function()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function(_, ace)
        return ace == Config.Debug.adminAce and 1
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('console source aliases are treated as trusted server console', function()
    ASSERT_TRUE(TelecomPermissions.IsConsole('console'))
    ASSERT_TRUE(TelecomPermissions.IsAdmin('console'))
    ASSERT_TRUE(TelecomPermissions.IsConsole('0'))
    ASSERT_TRUE(TelecomPermissions.IsAdmin('0'))
    ASSERT_TRUE(TelecomPermissions.IsConsole('00'))
    ASSERT_TRUE(TelecomPermissions.IsAdmin('0.0'))
end)

TEST('malformed and negative player sources fail closed', function()
    ASSERT_FALSE(TelecomPermissions.IsAdmin(nil))
    ASSERT_FALSE(TelecomPermissions.IsAdmin(-1))
    ASSERT_FALSE(TelecomPermissions.IsAdmin('not-a-player'))
    ASSERT_FALSE(TelecomPermissions.IsAdmin(math.huge))
    ASSERT_FALSE(TelecomPermissions.IsAdmin(-math.huge))
end)

TEST('audit records immutable admin actions', function()
    resetDebugState()
    local details = { towerId = 'AUDIT_TOWER', nested = { value = 1 } }
    local record = TelecomAudit.Record(7, 'inspect_tower', details)
    details.nested.value = 99

    ASSERT_EQ(record.source, 7)
    ASSERT_EQ(record.action, 'inspect_tower')
    ASSERT_EQ(record.details.nested.value, 1)
    ASSERT_EQ(#TelecomAudit.GetAll(), 1)
end)

TEST('unauthorized debug command is rejected and not audited', function()
    resetDebugState()
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function() return false end

    local ok, errorCode = TelecomDebug.Execute(7, { 'towers' })

    ASSERT_FALSE(ok)
    ASSERT_EQ(errorCode, 'not_authorized')
    ASSERT_EQ(#TelecomAudit.GetAll(), 0)

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('admin can inspect tower and player snapshots', function()
    resetDebugState()
    TowerRegistry.Init({ makeDebugTower('DEBUG_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function() return true end

    local towerOk, _, tower = TelecomDebug.Execute(7, { 'tower', 'DEBUG_TOWER' })
    ASSERT_TRUE(towerOk)
    ASSERT_EQ(tower.id, 'DEBUG_TOWER')
    ASSERT_EQ(tower.runtime.towerId, 'DEBUG_TOWER')

    local state = Connections.Reevaluate(7, vector3(0, 0, 0))
    ASSERT_EQ(state.towerId, 'DEBUG_TOWER')
    local playerOk, _, player = TelecomDebug.Execute(7, { 'signal' })
    ASSERT_TRUE(playerOk)
    ASSERT_EQ(player.source, 7)
    ASSERT_EQ(player.state.towerId, 'DEBUG_TOWER')

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('admin can force and clear a tower load for single-player testing', function()
    resetDebugState()
    TowerRegistry.Init({ makeDebugTower('LOAD_TOWER') })
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function() return true end

    local setOk, _, setPayload = TelecomDebug.Execute(7, {
        'load', 'LOAD_TOWER', '125',
    })
    ASSERT_TRUE(setOk)
    ASSERT_EQ(setPayload.runtime.debugLoadPercent, 125)
    ASSERT_EQ(setPayload.runtime.loadPercent, 125)
    ASSERT_EQ(setPayload.runtime.congestion, Enums.CongestionState.OVERLOADED)

    local clearOk, _, clearPayload = TelecomDebug.Execute(7, {
        'load', 'LOAD_TOWER', 'clear',
    })
    ASSERT_TRUE(clearOk)
    ASSERT_EQ(clearPayload.runtime.debugLoadPercent, nil)
    ASSERT_EQ(clearPayload.runtime.loadPercent, 0)

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('admin can create and repair a tower failure', function()
    resetDebugState()
    TowerRegistry.Init({ makeDebugTower('FAILURE_TOWER') })
    local previous = rawget(_G, 'IsPlayerAceAllowed')
    IsPlayerAceAllowed = function() return true end

    local failOk, _, failPayload = TelecomDebug.Execute(7, {
        'fail', 'FAILURE_TOWER', 'RADIO_FAILURE',
    })
    ASSERT_TRUE(failOk)
    ASSERT_EQ(#failPayload.runtime.activeFailures, 1)
    ASSERT_EQ(failPayload.runtime.failureEffects.serviceFailures.data, true)

    local repairOk, _, repairPayload = TelecomDebug.Execute(7, {
        'repair', 'FAILURE_TOWER',
    })
    ASSERT_TRUE(repairOk)
    ASSERT_EQ(#repairPayload.runtime.activeFailures, 0)
    ASSERT_EQ(repairPayload.runtime.failureEffects.signalMultiplier, 1.0)

    rawset(_G, 'IsPlayerAceAllowed', previous)
end)

TEST('client debug overlay is disabled by default and toggles explicitly', function()
    TelecomClientDebug.Disable()
    ASSERT_FALSE(TelecomClientDebug.IsEnabled())
    ASSERT_TRUE(TelecomClientDebug.Enable())
    ASSERT_TRUE(TelecomClientDebug.IsEnabled())
    ASSERT_TRUE(TelecomClientDebug.Disable())
    ASSERT_FALSE(TelecomClientDebug.IsEnabled())
end)
