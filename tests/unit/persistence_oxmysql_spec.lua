TEST('oxmysql adapter is optional and binds all values as parameters', function()
    local calls = {}
    local repository = OxmysqlRepository.New({
        available = true,
        query = function(query, params)
            calls[#calls + 1] = { kind = 'query', query = query, params = params }
            return {}
        end,
        execute = function(query, params)
            calls[#calls + 1] = { kind = 'execute', query = query, params = params }
            return true
        end,
    })
    ASSERT_TRUE(repository:Initialize())
    ASSERT_TRUE(repository:SaveFailure({
        id = 'FAIL-000301',
        tower_id = 'PERSIST_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        source = 7,
        reason = 'value-with-?;still-bound',
        metadata_json = '{"safe":true}',
        updated_at = 1700000000,
    }))
    ASSERT_TRUE(#calls > 0)
    local call = calls[#calls]
    ASSERT_TRUE(call.query:find('?', 1, true) ~= nil)
    ASSERT_EQ(call.params[1], 'FAIL-000301')
    ASSERT_TRUE(call.query:find('value-with', 1, true) == nil)

    ASSERT_TRUE(repository:SaveSubscriber({
        player_id = 'license:oxmysql',
        sim_id = 'sim-oxmysql',
        carrier_id = 'carrier_a',
        roaming_allowed = 1,
        service_class = 'standard',
    }))
    local subscriberCall = calls[#calls]
    ASSERT_TRUE(subscriberCall.query:find('telecom_subscribers', 1, true) ~= nil)
    ASSERT_EQ(subscriberCall.params[1], 'license:oxmysql')
    local loadedSubscribersOk, loadedSubscribers = repository:LoadSubscribers()
    ASSERT_TRUE(loadedSubscribersOk)
    ASSERT_EQ(#loadedSubscribers, 0)
    ASSERT_TRUE(repository:DeleteSubscriber('license:oxmysql'))

    local _, autoRepository = PersistenceRepository.Create({ adapter = 'auto' })
    ASSERT_TRUE(autoRepository == nil)

    local unavailableResult = OxmysqlRepository.New({
        available = true,
        query = function() return nil end,
        execute = function() return nil end,
    })
    ASSERT_TRUE(unavailableResult:Initialize())
    local queryOk, _, queryError = unavailableResult:LoadFailures()
    ASSERT_FALSE(queryOk)
    ASSERT_EQ(queryError, 'database_result_empty')
    local saveOk, saveError = unavailableResult:SaveFailure({
        id = 'FAIL-000302',
        tower_id = 'PERSIST_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        metadata_json = '{}',
        updated_at = 1700000000,
    })
    ASSERT_FALSE(saveOk)
    ASSERT_EQ(saveError, 'database_result_empty')

    local invalidShape = OxmysqlRepository.New({
        available = true,
        query = function() return {{ version = 'not-a-version' }} end,
        execute = function() return {} end,
    })
    ASSERT_TRUE(invalidShape:Initialize())
    local invalidVersionOk, _, invalidVersionError = invalidShape:GetSchemaVersion()
    ASSERT_FALSE(invalidVersionOk)
    ASSERT_EQ(invalidVersionError, 'schema_version_invalid')
    local invalidExecuteOk, invalidExecuteError = invalidShape:SaveFailure({
        id = 'FAIL-000303',
        tower_id = 'PERSIST_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        metadata_json = '{}',
        updated_at = 1700000000,
    })
    ASSERT_FALSE(invalidExecuteOk)
    ASSERT_EQ(invalidExecuteError, 'database_result_invalid')
end)
