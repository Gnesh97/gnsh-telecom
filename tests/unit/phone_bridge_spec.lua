local function makeBridgeState(source)
    return {
        source = source,
        towerId = 'BRIDGE_TOWER',
        signal = 80,
        rawSignal = 80,
        signalLevel = 'GOOD',
        technology = '4G',
        services = {},
        environment = { category = 'OPEN_AREA', multiplier = 1.0 },
    }
end

TEST('phone bridge registry exposes generic and optional adapters', function()
    ASSERT_TRUE(PhoneBridges.Get('generic') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('lbphone') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('npwd') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('qs') ~= nil)
    ASSERT_TRUE(PhoneBridges.Get('custom') ~= nil)
end)

TEST('phone bridge falls back to generic when no phone resource is available', function()
    local previous = Config.PhoneBridge
    Config.PhoneBridge = 'auto'

    local ok, active = PhoneBridges.Initialize()
    local status = PhoneBridges.GetStatus()

    Config.PhoneBridge = previous

    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'generic')
    ASSERT_EQ(status.active, 'generic')
    ASSERT_EQ(status.available, true)
end)

TEST('explicit missing phone adapter does not break telecom API access', function()
    local previous = Config.PhoneBridge
    Config.PhoneBridge = 'lbphone'
    local ok, active = PhoneBridges.Initialize()
    Config.PhoneBridge = previous

    ASSERT_TRUE(ok)
    ASSERT_EQ(active.name, 'generic')
end)

TEST('active phone bridge delegates queries through public telecom API', function()
    Connections.Clear()
    ASSERT_TRUE(Connections.Set(40, makeBridgeState(40), { skipCapacity = true }))
    ASSERT_TRUE(PhoneBridges.Initialize())

    local active = PhoneBridges.GetActive()
    ASSERT_EQ(active.name, 'generic')
    ASSERT_TRUE(active:HasSignal(40))
    ASSERT_EQ(active:GetSignalStrength(40), 80)
    ASSERT_EQ(active:GetSignalLevel(40), 'GOOD')
    ASSERT_EQ(active:GetNetworkType(40), '4G')
    ASSERT_EQ(active:GetConnectedTower(40), 'BRIDGE_TOWER')
    ASSERT_TRUE(active:CanCall(40))
    ASSERT_TRUE(active:CanSendSMS(40))
    ASSERT_TRUE(active:HasDataConnection(40))

    local api = PhoneBridges.GetTelecomAPI()
    api.HasSignal = function() return false end
    ASSERT_TRUE(active:HasSignal(40))

    local state = PhoneBridges.GetStatus()
    state.active = 'mutated'
    ASSERT_EQ(PhoneBridges.GetStatus().active, 'generic')

    Connections.Clear()
end)
