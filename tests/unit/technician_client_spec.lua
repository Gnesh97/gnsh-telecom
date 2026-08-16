TEST('technician client sends validated maintenance requests', function()
    local previousTechnician = Config.Features.Technician
    local previousIncidents = Config.Features.Incidents
    local previousTrigger = TriggerServerEvent
    local eventName
    local payload

    Config.Features.Technician = true
    Config.Features.Incidents = true
    TriggerServerEvent = function(name, value)
        eventName = name
        payload = value
    end

    ASSERT_TRUE(TechnicianClient.Request('DIAGNOSE', 'INC-000001'))
    ASSERT_EQ(eventName, Constants.Events.MAINTENANCE_REQUEST)
    ASSERT_EQ(payload.action, 'diagnose')
    ASSERT_EQ(payload.incidentId, 'INC-000001')
    ASSERT_EQ(payload.reason, nil)
    ASSERT_FALSE(TechnicianClient.Request('unknown', 'INC-000001'))
    ASSERT_FALSE(TechnicianClient.Request('diagnose', string.rep('x', 65)))
    ASSERT_FALSE(TechnicianClient.Request('cancel', 'INC-000001', string.rep('x', 129)))

    TriggerServerEvent = previousTrigger
    Config.Features.Technician = previousTechnician
    Config.Features.Incidents = previousIncidents
end)

TEST('technician client keeps defensive maintenance responses', function()
    TechnicianClient.ClearLastResponse()
    TriggerTestEvent(Constants.Events.MAINTENANCE_STATE, {
        ok = true,
        result = {
            incident = { id = 'INC-000002', status = 'DIAGNOSING' },
        },
    })

    local response = TechnicianClient.GetLastResponse()
    ASSERT_TRUE(response.ok)
    ASSERT_EQ(response.result.incident.status, 'DIAGNOSING')
    response.result.incident.status = 'MUTATED'
    ASSERT_EQ(TechnicianClient.GetLastResponse().result.incident.status, 'DIAGNOSING')

    TriggerTestEvent(Constants.Events.MAINTENANCE_STATE, {
        ok = false,
        error = 'too_far',
    })
    ASSERT_FALSE(TechnicianClient.GetLastResponse().ok)
    ASSERT_EQ(TechnicianClient.GetLastResponse().error, 'too_far')
end)
