MemoryRepository = MemoryRepository or {}

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function MemoryRepository.New()
    local repository = {
        Name = 'memory',
        initialized = false,
        schemaVersion = 0,
        failures = {},
        audits = {},
        subscribers = {},
    }

    function repository:Initialize()
        self.initialized = true
        return true
    end

    function repository:IsAvailable()
        return self.initialized
    end

    function repository:EnsureSchemaTable()
        return self.initialized, self.initialized and nil or 'repository_not_initialized'
    end

    function repository:GetSchemaVersion()
        if not self.initialized then return false, nil, 'repository_not_initialized' end
        return true, self.schemaVersion
    end

    function repository:ApplyMigration(migration)
        if not self.initialized then return false, 'repository_not_initialized' end
        if type(migration) ~= 'table' or type(migration.version) ~= 'number' then
            return false, 'migration_invalid'
        end
        self.schemaVersion = migration.version
        return true
    end

    function repository:LoadFailures()
        if not self.initialized then return false, nil, 'repository_not_initialized' end
        local rows = {}
        for _, id in ipairs(sortedKeys(self.failures)) do
            rows[#rows + 1] = copy(self.failures[id])
        end
        return true, rows
    end

    function repository:SaveFailure(row)
        if not self.initialized then return false, 'repository_not_initialized' end
        if type(row) ~= 'table' or type(row.id) ~= 'string' then return false, 'failure_row_invalid' end
        self.failures[row.id] = copy(row)
        return true
    end

    function repository:DeleteFailure(id)
        if not self.initialized then return false, 'repository_not_initialized' end
        if type(id) ~= 'string' or id == '' then return false, 'failure_id_invalid' end
        self.failures[id] = nil
        return true
    end

    function repository:LoadSubscribers()
        if not self.initialized then return false, nil, 'repository_not_initialized' end
        local rows = {}
        for _, playerId in ipairs(sortedKeys(self.subscribers)) do
            rows[#rows + 1] = copy(self.subscribers[playerId])
        end
        return true, rows
    end

    function repository:SaveSubscriber(row)
        if not self.initialized then return false, 'repository_not_initialized' end
        if type(row) ~= 'table' or type(row.player_id) ~= 'string' then
            return false, 'subscriber_row_invalid'
        end
        self.subscribers[row.player_id] = copy(row)
        return true
    end

    function repository:DeleteSubscriber(playerId)
        if not self.initialized then return false, 'repository_not_initialized' end
        if type(playerId) ~= 'string' or playerId == '' then
            return false, 'subscriber_player_id_invalid'
        end
        self.subscribers[playerId] = nil
        return true
    end

    function repository:LoadAudit(limit)
        if not self.initialized then return false, nil, 'repository_not_initialized' end
        local rows = {}
        for _, row in pairs(self.audits) do rows[#rows + 1] = copy(row) end
        table.sort(rows, function(left, right)
            if left.timestamp ~= right.timestamp then return left.timestamp > right.timestamp end
            return tostring(left.id) > tostring(right.id)
        end)
        local boundedLimit = tonumber(limit) or #rows
        boundedLimit = math.max(0, math.floor(boundedLimit))
        while #rows > boundedLimit do table.remove(rows) end
        return true, rows
    end

    function repository:AppendAudit(row)
        if not self.initialized then return false, 'repository_not_initialized' end
        if type(row) ~= 'table' or type(row.id) ~= 'string' then return false, 'audit_row_invalid' end
        self.audits[row.id] = copy(row)
        return true
    end

    function repository:PruneAudit(limit)
        if not self.initialized then return false, 'repository_not_initialized' end
        local boundedLimit = tonumber(limit) or 200
        boundedLimit = math.max(1, math.min(1000, math.floor(boundedLimit)))
        local rows = {}
        for id, row in pairs(self.audits) do
            rows[#rows + 1] = { id = id, timestamp = row.timestamp }
        end
        table.sort(rows, function(left, right)
            if left.timestamp ~= right.timestamp then return left.timestamp > right.timestamp end
            return tostring(left.id) > tostring(right.id)
        end)
        for index = boundedLimit + 1, #rows do self.audits[rows[index].id] = nil end
        return true
    end

    function repository:Flush()
        return self.initialized
    end

    function repository:Close()
        self.initialized = false
        return true
    end

    return repository
end
