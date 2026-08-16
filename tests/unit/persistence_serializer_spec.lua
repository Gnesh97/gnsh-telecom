local function persistenceFailureTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

TEST('persistence serializers round-trip valid failure and audit records', function()
    ASSERT_TRUE(TowerRegistry.Init({ persistenceFailureTower('PERSIST_TOWER') }))

    local failure = {
        id = 'FAIL-000101',
        towerId = 'PERSIST_TOWER',
        type = 'RADIO_FAILURE',
        active = true,
        createdAt = 1700000000,
        source = 7,
        reason = 'admin_debug',
        metadata = { command = 'telecom fail', attempt = 1 },
    }
    local failureRow, failureError = PersistenceSerializers.SerializeFailure(failure)
    ASSERT_TRUE(failureRow ~= nil, failureError)
    ASSERT_EQ(failureRow.id, failure.id)
    ASSERT_EQ(failureRow.tower_id, failure.towerId)
    ASSERT_TRUE(failureRow.metadata_json:find('command', 1, true) ~= nil)

    local restoredFailure, restoreError = PersistenceSerializers.DeserializeFailure(failureRow)
    ASSERT_TRUE(restoredFailure ~= nil, restoreError)
    ASSERT_EQ(restoredFailure.id, failure.id)
    ASSERT_EQ(restoredFailure.towerId, failure.towerId)
    ASSERT_EQ(restoredFailure.type, failure.type)
    ASSERT_EQ(restoredFailure.createdAt, failure.createdAt)
    ASSERT_EQ(restoredFailure.metadata.attempt, 1)
    ASSERT_TRUE(restoredFailure.connectedClients == nil)

    local audit = {
        id = 'AUDIT-000101',
        source = 7,
        action = 'create_failure',
        details = { towerId = 'PERSIST_TOWER', failureId = failure.id },
        timestamp = 1700000001,
    }
    local auditRow, auditError = PersistenceSerializers.SerializeAudit(audit)
    ASSERT_TRUE(auditRow ~= nil, auditError)
    local restoredAudit, restoredAuditError = PersistenceSerializers.DeserializeAudit(auditRow)
    ASSERT_TRUE(restoredAudit ~= nil, restoredAuditError)
    ASSERT_EQ(restoredAudit.id, audit.id)
    ASSERT_EQ(restoredAudit.details.failureId, failure.id)
end)

TEST('persistence serializers reject malformed or runtime-only rows', function()
    ASSERT_TRUE(TowerRegistry.Init({ persistenceFailureTower('PERSIST_TOWER') }))

    local base = {
        id = 'FAIL-000102',
        tower_id = 'PERSIST_TOWER',
        failure_type = 'RADIO_FAILURE',
        active = 1,
        created_at = 1700000000,
        source = 7,
        reason = 'test',
        metadata_json = '{"safe":true}',
        connected_clients = 99,
        load_percent = 100,
    }
    local restored = PersistenceSerializers.DeserializeFailure(base)
    ASSERT_TRUE(restored ~= nil)
    ASSERT_TRUE(restored.connectedClients == nil)
    ASSERT_TRUE(restored.loadPercent == nil)

    base.metadata_json = '{not-json'
    local invalidJson, invalidJsonError = PersistenceSerializers.DeserializeFailure(base)
    ASSERT_FALSE(invalidJson)
    ASSERT_EQ(invalidJsonError, 'invalid_metadata_json')

    base.metadata_json = '{"safe":true}'
    base.failure_type = 'UNKNOWN_FAILURE'
    local unknownType, unknownTypeError = PersistenceSerializers.DeserializeFailure(base)
    ASSERT_FALSE(unknownType)
    ASSERT_EQ(unknownTypeError, 'unknown_failure_type')

    base.failure_type = 'RADIO_FAILURE'
    base.tower_id = 'UNKNOWN_TOWER'
    local unknownTower, unknownTowerError = PersistenceSerializers.DeserializeFailure(base)
    ASSERT_FALSE(unknownTower)
    ASSERT_EQ(unknownTowerError, 'unknown_tower')

    local malformedAudit, malformedAuditError = PersistenceSerializers.DeserializeAudit({
        id = 'AUDIT-000102',
        source = 7,
        action = 'inspect',
        timestamp = 1700000000,
        details_json = '{"nested": [1, 2]}',
    })
    ASSERT_TRUE(malformedAudit ~= nil, malformedAuditError)

    local oversized, oversizedError = PersistenceSerializers.SerializeAudit({
        id = 'AUDIT-000103',
        source = 7,
        action = string.rep('x', 129),
        details = {},
        timestamp = 1700000000,
    })
    ASSERT_FALSE(oversized)
    ASSERT_EQ(oversizedError, 'action_too_long')

    local deep = {}
    local cursor = deep
    for _ = 1, 10 do
        cursor.next = {}
        cursor = cursor.next
    end
    local deepFailure, deepError = PersistenceSerializers.SerializeFailure({
        id = 'FAIL-000104',
        towerId = 'PERSIST_TOWER',
        type = 'RADIO_FAILURE',
        active = true,
        createdAt = 1700000000,
        metadata = deep,
    })
    ASSERT_FALSE(deepFailure)
    ASSERT_EQ(deepError, 'json_depth_exceeded')

    base.tower_id = 'PERSIST_TOWER'
    base.metadata_json = '{"unsafe":null}'
    local nullValue, nullValueError = PersistenceSerializers.DeserializeFailure(base)
    ASSERT_FALSE(nullValue)
    ASSERT_EQ(nullValueError, 'invalid_metadata_json')

    base.metadata_json = nil
    local missingMetadata, missingMetadataError = PersistenceSerializers.DeserializeFailure(base)
    ASSERT_FALSE(missingMetadata)
    ASSERT_EQ(missingMetadataError, 'invalid_metadata_json')
end)
