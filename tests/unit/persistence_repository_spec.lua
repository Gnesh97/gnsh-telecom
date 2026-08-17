TEST('memory persistence repository is portable and returns defensive copies', function()
    local repository = MemoryRepository.New()
    ASSERT_TRUE(repository:Initialize())
    ASSERT_TRUE(repository:IsAvailable())

    local row = {
        id = 'FAIL-000201',
        tower_id = 'PERSIST_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        source = 7,
        reason = 'test',
        metadata_json = '{"safe":true}',
    }
    ASSERT_TRUE(repository:SaveFailure(row))
    row.metadata_json = 'mutated-after-save'

    local ok, failures = repository:LoadFailures()
    ASSERT_TRUE(ok)
    ASSERT_EQ(#failures, 1)
    ASSERT_EQ(failures[1].metadata_json, '{"safe":true}')
    failures[1].id = 'changed'
    local _, secondRead = repository:LoadFailures()
    ASSERT_EQ(secondRead[1].id, 'FAIL-000201')

    ASSERT_TRUE(repository:DeleteFailure('FAIL-000201'))
    local _, empty = repository:LoadFailures()
    ASSERT_EQ(#empty, 0)

    local subscriber = {
        player_id = 'license:memory',
        sim_id = 'sim-memory',
        carrier_id = 'carrier_a',
        roaming_allowed = 1,
        service_class = 'standard',
    }
    ASSERT_TRUE(repository:SaveSubscriber(subscriber))
    subscriber.service_class = 'mutated-after-save'
    local subscribersOk, subscribers = repository:LoadSubscribers()
    ASSERT_TRUE(subscribersOk)
    ASSERT_EQ(#subscribers, 1)
    ASSERT_EQ(subscribers[1].service_class, 'standard')
    ASSERT_TRUE(repository:DeleteSubscriber('license:memory'))
    local _, emptySubscribers = repository:LoadSubscribers()
    ASSERT_EQ(#emptySubscribers, 0)

    local audit = {
        id = 'AUDIT-000201',
        source = 7,
        action = 'inspect',
        details_json = '{}',
        timestamp = 1700000000,
    }
    ASSERT_TRUE(repository:AppendAudit(audit))
    local auditOk, audits = repository:LoadAudit(10)
    ASSERT_TRUE(auditOk)
    ASSERT_EQ(#audits, 1)
    audits[1].action = 'changed'
    local _, auditSecondRead = repository:LoadAudit(10)
    ASSERT_EQ(auditSecondRead[1].action, 'inspect')
end)

TEST('memory persistence repository enforces audit retention', function()
    local repository = MemoryRepository.New()
    repository:Initialize()
    for index = 1, 3 do
        ASSERT_TRUE(repository:AppendAudit({
            id = ('AUDIT-%06d'):format(index),
            source = 7,
            action = 'inspect',
            details_json = '{}',
            timestamp = 1700000000 + index,
        }))
    end
    ASSERT_TRUE(repository:PruneAudit(2))
    local ok, rows = repository:LoadAudit(10)
    ASSERT_TRUE(ok)
    ASSERT_EQ(#rows, 2)
    ASSERT_EQ(rows[1].id, 'AUDIT-000003')
    ASSERT_EQ(rows[2].id, 'AUDIT-000002')
end)
