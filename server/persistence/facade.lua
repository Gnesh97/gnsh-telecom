TelecomPersistence = TelecomPersistence or {}

local repository
local injectedRepository
local initialized = false
local configSnapshot = nil
local mutationGeneration = 0
local lastRestoreGeneration = 0
local restorePending = false
local retryRunning = false
local startRetryLoop
local pendingFailures = {}
local pendingAudits = {}
local pendingSubscribers = {}
local status = {
    mode = 'uninitialized',
    schemaVersion = 0,
    restoredFailures = 0,
    restoredAudits = 0,
    restoredSubscribers = 0,
    skippedRows = 0,
    pendingWrites = 0,
    lastError = nil,
}

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function getConfig()
    local configured = Config and Config.Persistence
    if type(configured) ~= 'table' then
        return {
            enabled = false,
            adapter = 'memory',
            auditRetention = 200,
            maxRetries = 3,
        }
    end
    return copy(configured)
end

local function databaseExpected()
    return configSnapshot and configSnapshot.enabled ~= false
        and configSnapshot.adapter ~= 'memory'
end

local function logWarn(message, data)
    if Log and Log.warn then Log.warn(message, data) end
end

local function logError(message, data)
    if Log and Log.error then Log.error(message, data) end
end

local function updatePendingCount()
    local count = 0
    for _ in pairs(pendingFailures) do count = count + 1 end
    for _ in pairs(pendingAudits) do count = count + 1 end
    for _ in pairs(pendingSubscribers) do count = count + 1 end
    status.pendingWrites = count
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function queueFailureSave(row)
    pendingFailures[row.id] = { operation = 'save', row = copy(row) }
    updatePendingCount()
end

local function queueFailureDelete(id)
    pendingFailures[id] = { operation = 'delete', id = id }
    updatePendingCount()
end

local function queueAudit(row)
    pendingAudits[row.id] = { row = copy(row) }
    updatePendingCount()
end

local function queueSubscriberSave(row)
    pendingSubscribers[row.player_id] = { operation = 'save', row = copy(row) }
    updatePendingCount()
end

local function queueSubscriberDelete(playerId)
    pendingSubscribers[playerId] = { operation = 'delete', playerId = playerId }
    updatePendingCount()
end

local function serializeFailure(record)
    if not PersistenceSerializers or not PersistenceSerializers.SerializeFailure then
        return nil, 'serializer_unavailable'
    end
    return PersistenceSerializers.SerializeFailure(record)
end

local function serializeAudit(record)
    if not PersistenceSerializers or not PersistenceSerializers.SerializeAudit then
        return nil, 'serializer_unavailable'
    end
    return PersistenceSerializers.SerializeAudit(record)
end

local function serializeSubscriber(record)
    if not PersistenceSerializers or not PersistenceSerializers.SerializeSubscriber then
        return nil, 'serializer_unavailable'
    end
    return PersistenceSerializers.SerializeSubscriber(record)
end

local function pruneAudit()
    if not repository or repository.Name == 'memory'
        or type(repository.PruneAudit) ~= 'function'
        or not repository:IsAvailable() then return true end
    local ok, errorCode = repository:PruneAudit(
        configSnapshot and configSnapshot.auditRetention or 200
    )
    if not ok then status.lastError = errorCode or 'audit_prune_failed' end
    return ok
end

local function persistFailure(record)
    local row, serializationError = serializeFailure(record)
    if not row then
        logError('failure persistence serialization failed', { error = serializationError })
        return false, serializationError
    end

    local wrote = false
    local writeError = 'persistence_not_initialized'
    if initialized and repository and repository:IsAvailable() then
        wrote, writeError = repository:SaveFailure(row)
    end
    if not wrote or (repository and repository.Name == 'memory' and databaseExpected()) then
        queueFailureSave(row)
    end
    if not wrote and writeError then
        status.lastError = writeError
    end
    updatePendingCount()
    return wrote or repository ~= nil, writeError
end

local function persistFailureDelete(id)
    local wrote = false
    local writeError = 'persistence_not_initialized'
    if initialized and repository and repository:IsAvailable() then
        wrote, writeError = repository:DeleteFailure(id)
    end
    if not wrote or (repository and repository.Name == 'memory' and databaseExpected()) then
        queueFailureDelete(id)
    end
    if not wrote and writeError then status.lastError = writeError end
    updatePendingCount()
    return wrote or repository ~= nil, writeError
end

local function persistAudit(record)
    local row, serializationError = serializeAudit(record)
    if not row then
        logError('audit persistence serialization failed', { error = serializationError })
        return false, serializationError
    end

    local wrote = false
    local writeError = 'persistence_not_initialized'
    if initialized and repository and repository:IsAvailable() then
        wrote, writeError = repository:AppendAudit(row)
    end
    if not wrote or (repository and repository.Name == 'memory' and databaseExpected()) then
        queueAudit(row)
    end
    if wrote then pruneAudit() end
    if not wrote and writeError then status.lastError = writeError end
    updatePendingCount()
    return wrote or repository ~= nil, writeError
end

local function persistSubscriber(record)
    local row, serializationError = serializeSubscriber(record)
    if not row then
        logError('subscriber persistence serialization failed', { error = serializationError })
        return false, serializationError
    end

    local wrote = false
    local writeError = 'persistence_not_initialized'
    if initialized and repository and repository:IsAvailable()
        and type(repository.SaveSubscriber) == 'function' then
        wrote, writeError = repository:SaveSubscriber(row)
    end
    if not wrote or (repository and repository.Name == 'memory' and databaseExpected()) then
        queueSubscriberSave(row)
    end
    if not wrote and writeError then status.lastError = writeError end
    updatePendingCount()
    return wrote or repository ~= nil, writeError
end

local function persistSubscriberDelete(playerId)
    local wrote = false
    local writeError = 'persistence_not_initialized'
    if initialized and repository and repository:IsAvailable()
        and type(repository.DeleteSubscriber) == 'function' then
        wrote, writeError = repository:DeleteSubscriber(playerId)
    end
    if not wrote or (repository and repository.Name == 'memory' and databaseExpected()) then
        queueSubscriberDelete(playerId)
    end
    if not wrote and writeError then status.lastError = writeError end
    updatePendingCount()
    return wrote or repository ~= nil, writeError
end

local function restoreRows(mergeLocalState)
    if not TowerRegistry or not TowerRegistry.IsInitialized
        or not TowerRegistry.IsInitialized() then
        return false, 'runtime_not_ready'
    end
    if not repository or not repository:IsAvailable() then
        return false, 'repository_unavailable'
    end
    if not FailureEngine or not FailureEngine.Restore then
        return false, 'failure_restore_unavailable'
    end

    local observedGeneration = mutationGeneration
    local failureOk, failureRows, failureError = repository:LoadFailures()
    if not failureOk then return false, failureError or 'failure_load_failed' end
    local auditOk, auditRows, auditError = repository:LoadAudit(
        configSnapshot and configSnapshot.auditRetention or 200
    )
    if not auditOk then return false, auditError or 'audit_load_failed' end
    local subscriberRows = {}
    local carriersEnabled = Config and Config.Features
        and Config.Features.Carriers == true
    if carriersEnabled and type(repository.LoadSubscribers) == 'function' then
        local subscribersOk, rows, subscribersError = repository:LoadSubscribers()
        if not subscribersOk then
            return false, subscribersError or 'subscriber_load_failed'
        end
        subscriberRows = rows or {}
    end
    if observedGeneration ~= mutationGeneration then return false, 'restore_conflict' end

    if not mergeLocalState then
        FailureEngine.Reset()
        if TelecomAudit and TelecomAudit.Clear then TelecomAudit.Clear() end
    end

    local restoredFailures = 0
    local skippedRows = 0
    local affectedTowers = {}
    for _, row in ipairs(failureRows or {}) do
        local record, errorCode = PersistenceSerializers.DeserializeFailure(row)
        if record then
            if mergeLocalState and FailureEngine.Get(record.id) then
                skippedRows = skippedRows + 1
                logWarn('persistent failure row skipped local conflict', { id = record.id })
            else
                local restored, restoreError = FailureEngine.Restore(record)
                if restored then
                    restoredFailures = restoredFailures + 1
                    affectedTowers[record.towerId] = true
                else
                    skippedRows = skippedRows + 1
                    logWarn('persistent failure row skipped', { error = restoreError })
                end
            end
        else
            skippedRows = skippedRows + 1
            logWarn('persistent failure row skipped', { error = errorCode })
        end
    end
    for towerId in pairs(affectedTowers) do
        FailureEngine.ApplyTower(towerId)
    end

    local validAudits = {}
    for _, row in ipairs(auditRows or {}) do
        local record, errorCode = PersistenceSerializers.DeserializeAudit(row)
        if record then
            validAudits[#validAudits + 1] = record
        else
            skippedRows = skippedRows + 1
            logWarn('persistent audit row skipped', { error = errorCode })
        end
    end
    table.sort(validAudits, function(left, right)
        if left.timestamp ~= right.timestamp then return left.timestamp < right.timestamp end
        return left.id < right.id
    end)
    if TelecomAudit and TelecomAudit.Restore then
        TelecomAudit.Restore(validAudits, mergeLocalState)
    end

    local validSubscribers = {}
    local skippedSubscribers = 0
    if carriersEnabled then
        for _, row in ipairs(subscriberRows or {}) do
            local record, errorCode = PersistenceSerializers.DeserializeSubscriber(row)
            if record then
                validSubscribers[#validSubscribers + 1] = record
            else
                skippedSubscribers = skippedSubscribers + 1
                logWarn('persistent subscriber row skipped', { error = errorCode })
            end
        end
    end

    local restoredSubscribers = 0
    if carriersEnabled
        and SubscriberRegistry and SubscriberRegistry.Restore then
        local restoredOk, restoredCount, skippedCount = SubscriberRegistry.Restore(
            validSubscribers, mergeLocalState
        )
        if restoredOk then
            restoredSubscribers = restoredCount or 0
            skippedSubscribers = skippedSubscribers + (skippedCount or 0)
        end
    end

    status.restoredFailures = restoredFailures
    status.restoredAudits = #validAudits
    status.restoredSubscribers = restoredSubscribers
    status.skippedRows = skippedRows + skippedSubscribers
    status.lastError = nil
    lastRestoreGeneration = mutationGeneration
    restorePending = false
    return true
end

local function initializeRepository(selected)
    local initializedOk, initializeError = selected:Initialize()
    if not initializedOk then return false, initializeError or 'repository_initialize_failed' end
    local migrationOk, migrationState = PersistenceMigrations.Run(selected)
    if not migrationOk then
        return false, migrationState and migrationState.error or 'migration_failed'
    end
    status.schemaVersion = migrationState.version or 0
    return true
end

local function fallbackToMemory(errorCode)
    local memory = MemoryRepository.New()
    memory:Initialize()
    local migrationOk, migrationState = PersistenceMigrations.Run(memory)
    repository = memory
    status.mode = 'memory'
    status.schemaVersion = migrationOk and migrationState.version or 0
    status.lastError = errorCode
    restorePending = true
    if errorCode then logWarn('persistence running in memory mode', { error = errorCode }) end
end

local function selectRepository()
    local selected, selectionError
    if injectedRepository then
        selected = injectedRepository
    else
        selected, selectionError = PersistenceRepository.Create(configSnapshot)
    end
    local ok, initializeError = initializeRepository(selected)
    if ok then
        repository = selected
        status.mode = selected.Name or 'unknown'
        if selectionError then status.lastError = selectionError end
        return true
    end
    fallbackToMemory(initializeError or selectionError)
    return false, initializeError or selectionError
end

local function flushPending(maxPasses)
    if not repository or repository.Name == 'memory' or not repository:IsAvailable() then
        updatePendingCount()
        return false, 'repository_unavailable'
    end

    maxPasses = tonumber(maxPasses) or 1
    maxPasses = math.max(1, math.min(10, math.floor(maxPasses)))
    local flushed = 0
    for _ = 1, maxPasses do
        for _, id in ipairs(sortedKeys(pendingFailures)) do
            local item = pendingFailures[id]
            local ok, errorCode
            if item.operation == 'delete' then
                ok, errorCode = repository:DeleteFailure(item.id)
            else
                ok, errorCode = repository:SaveFailure(item.row)
            end
            if ok then
                pendingFailures[id] = nil
                flushed = flushed + 1
            else
                status.lastError = errorCode or 'failure_retry_failed'
            end
        end
        for _, id in ipairs(sortedKeys(pendingAudits)) do
            local item = pendingAudits[id]
            local ok, errorCode = repository:AppendAudit(item.row)
            if ok then
                pendingAudits[id] = nil
                flushed = flushed + 1
            else
                status.lastError = errorCode or 'audit_retry_failed'
            end
        end
        for _, playerId in ipairs(sortedKeys(pendingSubscribers)) do
            local item = pendingSubscribers[playerId]
            local ok, errorCode
            if item.operation == 'delete' and type(repository.DeleteSubscriber) == 'function' then
                ok, errorCode = repository:DeleteSubscriber(item.playerId)
            elseif item.operation ~= 'delete' and type(repository.SaveSubscriber) == 'function' then
                ok, errorCode = repository:SaveSubscriber(item.row)
            else
                ok, errorCode = false, 'subscriber_persistence_unsupported'
            end
            if ok then
                pendingSubscribers[playerId] = nil
                flushed = flushed + 1
            else
                status.lastError = errorCode or 'subscriber_retry_failed'
            end
        end
        updatePendingCount()
        if status.pendingWrites == 0 then break end
    end
    updatePendingCount()
    if status.pendingWrites == 0 then pruneAudit() end
    return status.pendingWrites == 0, flushed
end

local function initialize()
    if initialized then return true, copy(status) end
    configSnapshot = getConfig()
    if configSnapshot.enabled == false then
        local memory = MemoryRepository.New()
        memory:Initialize()
        repository = memory
        initialized = true
        status.mode = 'disabled'
        status.schemaVersion = 0
        lastRestoreGeneration = mutationGeneration
        return true, copy(status)
    end

    local selectedOk, selectionError = selectRepository()
    initialized = true
    if not selectedOk then
        lastRestoreGeneration = mutationGeneration
        startRetryLoop()
        return true, copy(status)
    end
    pruneAudit()
    if repository.Name ~= 'memory' then
        local restored, restoreError = restoreRows()
        if not restored then
            status.mode = 'degraded'
            status.lastError = restoreError
            restorePending = true
            logWarn('persistence restore deferred', { error = restoreError })
        end
    else
        local restored, restoreError = restoreRows()
        if not restored then
            status.lastError = restoreError
            restorePending = restoreError ~= 'runtime_not_ready'
        end
    end
    if status.pendingWrites == 0 then pruneAudit() end
    updatePendingCount()
    startRetryLoop()
    return true, copy(status)
end

function TelecomPersistence.Initialize()
    return initialize()
end

function TelecomPersistence.SaveFailure(record)
    if not TelecomPersistence.IsEnabled() then return true end
    mutationGeneration = mutationGeneration + 1
    return persistFailure(record)
end

function TelecomPersistence.DeleteFailure(id)
    if not TelecomPersistence.IsEnabled() then return true end
    mutationGeneration = mutationGeneration + 1
    return persistFailureDelete(id)
end

function TelecomPersistence.AppendAudit(record)
    if not TelecomPersistence.IsEnabled() then return true end
    mutationGeneration = mutationGeneration + 1
    return persistAudit(record)
end

function TelecomPersistence.SaveSubscriber(record)
    if not TelecomPersistence.IsEnabled() then return true end
    mutationGeneration = mutationGeneration + 1
    return persistSubscriber(record)
end

function TelecomPersistence.DeleteSubscriber(playerId)
    if not TelecomPersistence.IsEnabled() then return true end
    mutationGeneration = mutationGeneration + 1
    return persistSubscriberDelete(playerId)
end

function TelecomPersistence.Flush(maxPasses)
    return flushPending(maxPasses)
end

function TelecomPersistence.Recover()
    configSnapshot = configSnapshot or getConfig()
    if configSnapshot.enabled == false then return false, 'persistence_disabled' end
    if not TowerRegistry or not TowerRegistry.IsInitialized
        or not TowerRegistry.IsInitialized() then
        restorePending = true
        return false, 'runtime_not_ready'
    end
    local selected
    if injectedRepository then
        selected = injectedRepository
    else
        selected = PersistenceRepository.Create(configSnapshot)
    end
    if not selected or selected.Name == 'memory' then
        restorePending = true
        return false, 'oxmysql_unavailable'
    end
    local initializedOk, initializeError = initializeRepository(selected)
    if not initializedOk then
        status.lastError = initializeError
        status.mode = 'degraded'
        restorePending = true
        return false, initializeError
    end
    repository = selected
    initialized = true
    status.mode = selected.Name or 'unknown'
    pruneAudit()
    local mergeLocalState = mutationGeneration ~= lastRestoreGeneration
    local localMutationCount = mutationGeneration - lastRestoreGeneration
    local restored, restoreError = restoreRows(mergeLocalState)
    if not restored then
        status.lastError = restoreError
        status.mode = 'degraded'
        restorePending = true
        return false, restoreError
    end
    if mergeLocalState then
        logWarn('persistence recovery merged local state with database', {
            localMutations = localMutationCount,
        })
    end
    restorePending = false
    flushPending()
    startRetryLoop()
    return true, copy(status)
end

startRetryLoop = function()
    if retryRunning or type(CreateThread) ~= 'function' or type(Wait) ~= 'function' then return end
    retryRunning = true
    CreateThread(function()
        while retryRunning do
            if restorePending then
                TelecomPersistence.Recover()
            elseif status.pendingWrites > 0 then
                flushPending()
            end
            if retryRunning then
                local interval = configSnapshot and configSnapshot.retryIntervalMs or 5000
                Wait(interval)
            end
        end
    end)
end

local function stopRetryLoop()
    retryRunning = false
end

function TelecomPersistence.Shutdown()
    stopRetryLoop()
    local retries = configSnapshot and configSnapshot.maxRetries or 1
    local flushed, flushError = flushPending(retries)
    if repository and repository.Close then repository:Close() end
    initialized = false
    return flushed, flushError
end

function TelecomPersistence.IsEnabled()
    local configured = Config and Config.Persistence
    return type(configured) == 'table' and configured.enabled ~= false
end

function TelecomPersistence.GetStatus()
    updatePendingCount()
    return copy(status)
end

function TelecomPersistence.LoadSubscribers()
    if not repository or not repository:IsAvailable()
        or type(repository.LoadSubscribers) ~= 'function' then
        return false, nil, 'subscriber_repository_unavailable'
    end
    return repository:LoadSubscribers()
end

function TelecomPersistence.SetRepository(testRepository)
    stopRetryLoop()
    injectedRepository = testRepository
    repository = nil
    initialized = false
    restorePending = false
end

function TelecomPersistence.GetRepository()
    return repository
end

function TelecomPersistence.Reset()
    stopRetryLoop()
    if repository and repository.Close then repository:Close() end
    repository = nil
    injectedRepository = nil
    initialized = false
    configSnapshot = nil
    mutationGeneration = 0
    lastRestoreGeneration = 0
    restorePending = false
    pendingFailures = {}
    pendingAudits = {}
    pendingSubscribers = {}
    status = {
        mode = 'uninitialized',
        schemaVersion = 0,
        restoredFailures = 0,
        restoredAudits = 0,
        restoredSubscribers = 0,
        skippedRows = 0,
        pendingWrites = 0,
        lastError = nil,
    }
end

local function handleResourceStop(resourceName)
    if resourceName ~= 'oxmysql' or not repository or repository.Name ~= 'oxmysql' then return end
    local memory = MemoryRepository.New()
    memory:Initialize()
    repository = memory
    status.mode = 'memory'
    restorePending = true
    mutationGeneration = mutationGeneration + 1
    for _, record in ipairs(FailureEngine and FailureEngine.GetAll and FailureEngine.GetAll() or {}) do
        local row = serializeFailure(record)
        if row then queueFailureSave(row) end
    end
    for _, record in ipairs(TelecomAudit and TelecomAudit.GetAll and TelecomAudit.GetAll() or {}) do
        local row = serializeAudit(record)
        if row then queueAudit(row) end
    end
    for _, record in ipairs(SubscriberRegistry and SubscriberRegistry.GetAll
        and SubscriberRegistry.GetAll() or {}) do
        local row = serializeSubscriber(record)
        if row then queueSubscriberSave(row) end
    end
    logWarn('oxmysql stopped; persistence switched to memory mode')
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == 'oxmysql' then TelecomPersistence.Recover() end
    end)
    AddEventHandler('onResourceStop', handleResourceStop)
end
