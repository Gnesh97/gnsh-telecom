TEST('client state applies defensive server snapshots', function()
    ClientState.Clear()
    ASSERT_TRUE(ClientState.Apply({ source = 1, towerId = 'TOWER_A', signal = 80 }))

    local stored = ClientState.Get()
    ASSERT_EQ(stored.towerId, 'TOWER_A')
    stored.signal = 0
    ASSERT_EQ(ClientState.Get().signal, 80)
end)

TEST('client state reports only validated position payloads', function()
    local eventName
    local payload
    local previousTrigger = TriggerServerEvent
    TriggerServerEvent = function(name, value)
        eventName = name
        payload = value
    end

    ASSERT_TRUE(ClientState.ReportPosition(vector3(1, 2, 3)))
    ASSERT_EQ(eventName, Constants.Events.POSITION_UPDATE)
    ASSERT_EQ(payload.x, 1)
    ASSERT_EQ(payload.y, 2)
    ASSERT_EQ(payload.z, 3)
    ASSERT_FALSE(ClientState.ReportPosition({ x = 1, y = 2 }))

    TriggerServerEvent = previousTrigger
end)

TEST('client state start and stop are idempotent without a game thread', function()
    ClientState.Stop()
    ASSERT_TRUE(ClientState.Start())
    ASSERT_TRUE(ClientState.IsRunning())
    ASSERT_FALSE(ClientState.Start())
    ClientState.Stop()
    ASSERT_FALSE(ClientState.IsRunning())
end)
