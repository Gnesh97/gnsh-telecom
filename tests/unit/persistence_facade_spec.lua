local function facadeTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetPersistenceScenario()
    local previousAdapter = Config.Persistence.adapter
    Config.Persistence.adapter = 'memory'
    Config.Persistence.enabled = true
    FailureEngine.Reset()
    Connections.Clear()
    TelecomAudit.Clear()
    ASSERT_TRUE(TowerRegistry.Init({ facadeTower('FACADE_TOWER') }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    return previousAdapter
end

TEST('persistence facade saves and deletes failure mutations without runtime counters', function()
    local previousAdapter = resetPersistenceScenario()
    local repository = MemoryRepository.New()
    repository:Initialize()
    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Initialize())

    local ok, failure = FailureEngine.Create('FACADE_TOWER', 'RADIO_FAILURE', {
        source = 7,
        reason = 'test',
        metadata = { test = true },
    })
    ASSERT_TRUE(ok)
    local loadOk, rows = repository:LoadFailures()
    ASSERT_TRUE(loadOk)
    ASSERT_EQ(#rows, 1)
    ASSERT_TRUE(rows[1].connected_clients == nil)
    ASSERT_TRUE(rows[1].load_percent == nil)

    ASSERT_TRUE(FailureEngine.Clear(failure.id))
    local _, clearedRows = repository:LoadFailures()
    ASSERT_EQ(#clearedRows, 0)

    TelecomPersistence.Reset()
    Config.Persistence.adapter = previousAdapter
end)

TEST('active failures and audit history restore through the facade', function()
    local previousAdapter = resetPersistenceScenario()
    local repository = MemoryRepository.New()
    repository:Initialize()
    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Initialize())

    local ok, failure = FailureEngine.Create('FACADE_TOWER', 'ANTENNA_FAILURE', {
        id = 'FAIL-000401',
        source = 7,
        createdAt = 1700000000,
        reason = 'persisted',
        metadata = { source = 'unit' },
    })
    ASSERT_TRUE(ok)
    local audit = TelecomAudit.Record(7, 'create_failure', { failureId = failure.id })
    ASSERT_TRUE(audit ~= nil)

    FailureEngine.Reset()
    TelecomAudit.Clear()
    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Initialize())

    local restored = FailureEngine.Get('FAIL-000401')
    ASSERT_TRUE(restored ~= nil)
    ASSERT_EQ(restored.createdAt, 1700000000)
    ASSERT_EQ(FailureEngine.GetEffects('FACADE_TOWER').signalMultiplier,
        FailureTypes.Get('ANTENNA_FAILURE').signalMultiplier)
    ASSERT_EQ(#TelecomAudit.GetAll(), 1)
    ASSERT_EQ(TelecomAudit.GetAll()[1].id, audit.id)
    ASSERT_TRUE(TelecomPersistence.GetStatus().restoredFailures >= 1)

    TelecomPersistence.Reset()
    Config.Persistence.adapter = previousAdapter
end)

TEST('persistence remains memory-authoritative during outage and flushes after recovery', function()
    local previousAdapter = Config.Persistence.adapter
    Config.Persistence.adapter = 'auto'
    Config.Persistence.enabled = true
    FailureEngine.Reset()
    Connections.Clear()
    ASSERT_TRUE(TowerRegistry.Init({ facadeTower('OUTAGE_TOWER') }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local repository = MemoryRepository.New()
    repository.Name = 'oxmysql'
    repository:Initialize()
    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Initialize())

    repository.initialized = false
    local ok, failure = FailureEngine.Create('OUTAGE_TOWER', 'COOLING_FAILURE')
    ASSERT_TRUE(ok)
    ASSERT_TRUE(TelecomPersistence.GetStatus().pendingWrites >= 1)
    ASSERT_TRUE(FailureEngine.Get(failure.id) ~= nil)

    repository.initialized = true
    ASSERT_TRUE(TelecomPersistence.Flush())
    local loadOk, rows = repository:LoadFailures()
    ASSERT_TRUE(loadOk)
    ASSERT_EQ(#rows, 1)

    TelecomPersistence.Reset()
    Config.Persistence.adapter = previousAdapter
end)

TEST('restore skips malformed optional rows and keeps valid failures', function()
    local previousAdapter = resetPersistenceScenario()
    local repository = MemoryRepository.New()
    repository:Initialize()
    ASSERT_TRUE(repository:SaveFailure({
        id = 'FAIL-000501',
        tower_id = 'FACADE_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        source = 7,
        reason = 'valid',
        metadata_json = '{}',
        updated_at = 1700000000,
    }))
    repository.failures['BROKEN'] = {
        id = 'BROKEN',
        tower_id = 'FACADE_TOWER',
        failure_type = 'NOT_A_FAILURE',
        active = 1,
        created_at = 1700000000,
        metadata_json = '{}',
        updated_at = 1700000000,
    }

    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Initialize())
    ASSERT_TRUE(FailureEngine.Get('FAIL-000501') ~= nil)
    ASSERT_EQ(TelecomPersistence.GetStatus().skippedRows, 1)

    TelecomPersistence.Reset()
    Config.Persistence.adapter = previousAdapter
end)

TEST('failure mutation rejects payloads that cannot be persisted', function()
    local previousAdapter = resetPersistenceScenario()
    local metadata = {}
    metadata.self = metadata
    TelecomPersistence.Reset()

    local ok, errorCode = FailureEngine.Create('FACADE_TOWER', 'RADIO_FAILURE', {
        metadata = metadata,
    })
    ASSERT_FALSE(ok)
    ASSERT_EQ(errorCode, 'failure_persistence_json_cycle_detected')
    ASSERT_EQ(#FailureEngine.GetAll(), 0)

    Config.Persistence.adapter = previousAdapter
end)

TEST('database recovery merges durable rows with newer local mutations', function()
    local previousAdapter = Config.Persistence.adapter
    Config.Persistence.adapter = 'auto'
    Config.Persistence.enabled = true
    FailureEngine.Reset()
    Connections.Clear()
    ASSERT_TRUE(TowerRegistry.Init({ facadeTower('MERGE_TOWER') }))
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local repository = MemoryRepository.New()
    repository.Name = 'oxmysql'
    repository:Initialize()
    ASSERT_TRUE(repository:SaveFailure({
        id = 'FAIL-000601',
        tower_id = 'MERGE_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        metadata_json = '{}',
        updated_at = 1700000000,
    }))
    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Initialize())
    ASSERT_TRUE(FailureEngine.Get('FAIL-000601') ~= nil)

    repository.initialized = false
    local localOk, localFailure = FailureEngine.Create('MERGE_TOWER', 'COOLING_FAILURE', {
        id = 'FAIL-000602',
    })
    ASSERT_TRUE(localOk)
    repository.initialized = true
    ASSERT_TRUE(repository:SaveFailure({
        id = 'FAIL-000603',
        tower_id = 'MERGE_TOWER',
        failure_type = 'ANTENNA_FAILURE',
        active = 1,
        created_at = 1700000000,
        metadata_json = '{}',
        updated_at = 1700000000,
    }))
    TelecomPersistence.SetRepository(repository)
    ASSERT_TRUE(TelecomPersistence.Recover())
    ASSERT_TRUE(FailureEngine.Get('FAIL-000601') ~= nil)
    ASSERT_TRUE(FailureEngine.Get(localFailure.id) ~= nil)
    ASSERT_TRUE(FailureEngine.Get('FAIL-000603') ~= nil)

    TelecomPersistence.Reset()
    Config.Persistence.adapter = previousAdapter
end)
