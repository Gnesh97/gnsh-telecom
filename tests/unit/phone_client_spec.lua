TEST('lb phone client maps connection signal changes to documented service bars', function()
    local registered
    local calls = {}
    local environment = {
        PhoneBridgeContract = {
            Levels = { FUNCTIONAL = 'FUNCTIONAL' },
        },
        PhoneBridgeManager = {
            FirstStarted = function() return 'lb-phone' end,
            OptionalBooleanExportGate = function() return true end,
            ServiceGate = function() return true, { available = true } end,
            ExportCall = function(resourceName, exportName, bars)
                calls[#calls + 1] = {
                    resourceName = resourceName,
                    exportName = exportName,
                    bars = bars,
                }
                return true
            end,
        },
        PhoneBridges = {
            CreateResourceAdapter = function(name, resources, options)
                local adapter = {
                    name = name,
                    resources = resources,
                    resourceNames = resources,
                }
                for key, value in pairs(options or {}) do adapter[key] = value end
                return adapter
            end,
            Register = function(adapter) registered = adapter end,
        },
    }
    setmetatable(environment, { __index = _G })

    local chunk = assert(loadfile(
        'bridges/phones/lbphone/client.lua',
        't',
        environment
    ))
    chunk()

    ASSERT_TRUE(registered ~= nil)
    ASSERT_TRUE(registered:OnNetworkState({ signal = 90 }))
    ASSERT_EQ(calls[1].resourceName, 'lb-phone')
    ASSERT_EQ(calls[1].exportName, 'SetServiceBars')
    ASSERT_EQ(calls[1].bars, 4)

    ASSERT_TRUE(registered:OnNetworkState({ signal = 90, technology = '5G' }))
    ASSERT_EQ(calls[2].exportName, 'SetServiceBars')
    ASSERT_EQ(calls[3].resourceName, 'lb-phone')
    ASSERT_EQ(calls[3].exportName, 'SetNetworkType')
    ASSERT_EQ(calls[3].bars, '5G')
end)

TEST('qb phone client forwards connection signal changes to the phone UI event', function()
    local registered
    local event
    local environment = {
        PhoneBridgeContract = {
            Levels = { FUNCTIONAL = 'FUNCTIONAL' },
        },
        PhoneBridgeManager = {
            FirstStarted = function() return 'qb-phone' end,
            ServiceGate = function() return true, { available = true } end,
        },
        PhoneBridges = {
            CreateResourceAdapter = function(name, resources, options)
                local adapter = {
                    name = name,
                    resources = resources,
                    resourceNames = resources,
                }
                for key, value in pairs(options or {}) do adapter[key] = value end
                return adapter
            end,
            Register = function(adapter) registered = adapter end,
        },
        TriggerEvent = function(name, state)
            event = { name = name, state = state }
        end,
    }
    setmetatable(environment, { __index = _G })

    local chunk = assert(loadfile(
        'bridges/phones/qbphone/client.lua',
        't',
        environment
    ))
    chunk()

    ASSERT_TRUE(registered ~= nil)
    ASSERT_TRUE(registered:OnNetworkState({ signal = 37, signalLevel = 'RED' }))
    ASSERT_EQ(event.name, 'qb-phone:client:UpdateTelecomNetwork')
    ASSERT_EQ(event.state.signal, 37)
    ASSERT_EQ(event.state.signalLevel, 'RED')
end)
