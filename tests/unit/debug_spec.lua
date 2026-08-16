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
    Config.Features.Failures = true
    Config.Debug.enabled = true
end

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
        return true
    end

    ASSERT_TRUE(TelecomPermissions.IsAdmin(12))
    ASSERT_EQ(seenSource, '12')
    ASSERT_EQ(seenAce, Config.Debug.adminAce)

    rawset(_G, 'IsPlayerAceAllowed', previous)
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
