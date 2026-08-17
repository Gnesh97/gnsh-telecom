local function withResources(states, callback)
    local previousState = GetResourceState
    local previousExports = exports
    GetResourceState = function(name)
        return states[name] or 'stopped'
    end
    exports = {
        ox_target = {},
        ['qb-target'] = {},
    }

    local ok, result, errorMessage = pcall(callback, exports)
    GetResourceState = previousState
    exports = previousExports
    if not ok then error(result, 0) end
    return result, errorMessage
end

local function resetTarget()
    ASSERT_TRUE(TargetBridge.SetAdapter(nil))
    if TargetBridge.Reset then TargetBridge.Reset() end
end

TEST('target configuration validates supported and custom modes', function()
    local previousBridge = Config.TargetBridge
    local previousCustom = Config.CustomTarget

    Config.TargetBridge = 'unknown'
    ASSERT_FALSE(Config.Validate())
    Config.TargetBridge = 'custom'
    Config.CustomTarget = nil
    ASSERT_FALSE(Config.Validate())

    Config.TargetBridge = previousBridge
    Config.CustomTarget = previousCustom
    ASSERT_TRUE(Config.Validate())
end)

TEST('target bridge exposes the universal interaction contract', function()
    resetTarget()
    withResources({}, function()
        ASSERT_EQ(TargetBridge.GetName(), 'native')
        ASSERT_TRUE(TargetBridge.AddEntityInteraction('tower:entity', 17, {}))
        ASSERT_TRUE(TargetBridge.AddModelInteraction('tower:model', { 'prop_test' }, {}))
        ASSERT_TRUE(TargetBridge.AddZoneInteraction('tower:zone', {
            coords = vector3(1, 2, 3),
            radius = 2.0,
        }, {}))
        ASSERT_TRUE(TargetBridge.RemoveInteraction('tower:zone'))
    end)
end)

TEST('ox target adapter maps entity, model and zone interactions', function()
    resetTarget()
    withResources({ ox_target = 'started' }, function(targetExports)
        local calls = {}
        local ox = targetExports.ox_target
        ox.addEntity = function(_, entity, options)
            calls.entity = { entity, options }
            return 41
        end
        ox.addModel = function(_, models, options)
            calls.model = { models, options }
            return 42
        end
        ox.addBoxZone = function(_, data)
            calls.zone = data
            return 43
        end
        ox.removeZone = function(_, handle)
            calls.remove = handle
            return true
        end

        ASSERT_TRUE(TargetBridge.Initialize())
        ASSERT_EQ(TargetBridge.GetName(), 'ox')
        local added, entityHandle = TargetBridge.AddEntityInteraction(
            'tower:entity', 17, { { name = 'diagnose' } }
        )
        ASSERT_TRUE(added)
        ASSERT_EQ(entityHandle, 41)
        ASSERT_TRUE(TargetBridge.AddModelInteraction(
            'tower:model', { 'prop_test' }, { { name = 'diagnose' } }
        ))
        ASSERT_TRUE(TargetBridge.AddZoneInteraction(
            'tower:zone', { coords = vector3(1, 2, 3), radius = 2.0 }, {}
        ))
        ASSERT_EQ(calls.entity[1], 17)
        ASSERT_EQ(calls.model[1][1], 'prop_test')
        ASSERT_EQ(calls.zone.name, 'tower:zone')
        ASSERT_TRUE(TargetBridge.RemoveInteraction('tower:zone'))
        ASSERT_EQ(calls.remove, 43)
    end)
end)

TEST('qb target adapter maps entity, model and zone interactions', function()
    resetTarget()
    withResources({ ['qb-target'] = 'started' }, function(targetExports)
        local calls = {}
        local qb = targetExports['qb-target']
        qb.AddTargetEntity = function(_, entity, params)
            calls.entity = { entity, params }
            return true
        end
        qb.AddTargetModel = function(_, models, params)
            calls.model = { models, params }
            return true
        end
        qb.AddBoxZone = function(_, name, coords, length, width, zoneOptions, targetOptions)
            calls.zone = { name, coords, length, width, zoneOptions, targetOptions }
            return true
        end
        qb.RemoveZone = function(_, name)
            calls.remove = name
            return true
        end

        ASSERT_TRUE(TargetBridge.Initialize())
        ASSERT_EQ(TargetBridge.GetName(), 'qb')
        ASSERT_TRUE(TargetBridge.AddEntityInteraction(
            'tower:entity', 17, { { name = 'diagnose' } }
        ))
        ASSERT_TRUE(TargetBridge.AddModelInteraction(
            'tower:model', { 'prop_test' }, { { name = 'diagnose' } }
        ))
        ASSERT_TRUE(TargetBridge.AddZoneInteraction(
            'tower:zone', { coords = vector3(1, 2, 3), length = 2.0, width = 3.0 }, {}
        ))
        ASSERT_EQ(calls.entity[1], 17)
        ASSERT_EQ(calls.model[1][1], 'prop_test')
        ASSERT_EQ(calls.zone[1], 'tower:zone')
        ASSERT_TRUE(TargetBridge.RemoveInteraction('tower:zone'))
        ASSERT_EQ(calls.remove, 'tower:zone')
    end)
end)

TEST('custom target adapter follows the universal contract', function()
    local previousBridge = Config.TargetBridge
    local previousCustom = Config.CustomTarget
    local added
    Config.TargetBridge = 'custom'
    Config.CustomTarget = {
        AddZoneInteraction = function(id)
            added = id
            return true, 'custom-handle'
        end,
        RemoveInteraction = function() return true end,
    }
    resetTarget()
    ASSERT_TRUE(TargetBridge.Initialize())
    ASSERT_EQ(TargetBridge.GetName(), 'custom')
    local ok, handle = TargetBridge.AddZoneInteraction('tower:custom', {
        coords = vector3(1, 2, 3),
    }, {})
    ASSERT_TRUE(ok)
    ASSERT_EQ(added, 'tower:custom')
    ASSERT_EQ(handle, 'custom-handle')
    Config.TargetBridge = previousBridge
    Config.CustomTarget = previousCustom
    TargetBridge.SetAdapter(nil)
end)

TEST('target bridge falls back and reinstalls after provider lifecycle changes', function()
    resetTarget()
    local states = { ox_target = 'started' }
    withResources(states, function(targetExports)
        targetExports.ox_target.addEntity = function() return true end
        targetExports.ox_target.addModel = function() return true end
        targetExports.ox_target.addBoxZone = function() return 1 end
        ASSERT_TRUE(TargetBridge.Initialize())
        ASSERT_EQ(TargetBridge.GetName(), 'ox')
        states.ox_target = 'stopped'
        ASSERT_TRUE(TargetBridge.Refresh())
        ASSERT_EQ(TargetBridge.GetName(), 'native')
        states.ox_target = 'started'
        ASSERT_TRUE(TargetBridge.Refresh())
        ASSERT_EQ(TargetBridge.GetName(), 'ox')
    end)
end)

TEST('technician target intent contains only bounded action context', function()
    local previousTechnician = Config.Features.Technician
    Config.Features.Technician = true
    local previousTrigger = TriggerServerEvent
    local captured
    TriggerServerEvent = function(name, payload)
        captured = { name = name, payload = payload }
    end
    local ok, errorCode = TechnicianClient.RequestTower('begin', 'tower-a')
    TriggerServerEvent = previousTrigger
    Config.Features.Technician = previousTechnician
    ASSERT_TRUE(ok, errorCode)
    ASSERT_EQ(captured.name, Constants.Events.MAINTENANCE_TARGET_REQUEST)
    ASSERT_EQ(captured.payload.action, 'begin')
    ASSERT_EQ(captured.payload.towerId, 'tower-a')
    ASSERT_EQ(captured.payload.coords, nil)
    ASSERT_EQ(captured.payload.entity, nil)
end)

TEST('interaction installer can reinstall tower interactions without provider coupling', function()
    resetTarget()
    ASSERT_TRUE(TelecomInteractions.InstallTower({
        id = 'tower-a',
        coords = vector3(10, 20, 30),
    }))
    ASSERT_TRUE(TelecomInteractions.GetInstalled('tower-a'))
    ASSERT_TRUE(TelecomInteractions.Reinstall())
    ASSERT_TRUE(TelecomInteractions.RemoveTower('tower-a'))
    ASSERT_FALSE(TelecomInteractions.GetInstalled('tower-a'))
end)
