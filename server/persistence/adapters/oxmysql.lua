OxmysqlRepository = OxmysqlRepository or {}

local schemaTableStatement = [[CREATE TABLE IF NOT EXISTS telecom_schema (
    version INT NOT NULL PRIMARY KEY,
    applied_at BIGINT NOT NULL
)]]

local function getExport()
    if exports == nil then return nil end
    local ok, value = pcall(function() return exports.oxmysql end)
    return ok and value or nil
end

local function canCallExport(adapter, methodName)
    if adapter == nil then return false end
    local ok, method = pcall(function() return adapter[methodName] end)
    return ok and type(method) == 'function'
end

local function exportAvailable()
    if type(GetResourceState) ~= 'function'
        or GetResourceState('oxmysql') ~= 'started' then
        return false
    end
    local adapter = getExport()
    return canCallExport(adapter, 'query_async')
        and canCallExport(adapter, 'update_async')
end

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function OxmysqlRepository.IsAvailable()
    return exportAvailable()
end

function OxmysqlRepository.New(options)
    options = type(options) == 'table' and options or {}
    local repository = {
        Name = 'oxmysql',
        initialized = false,
        availableOverride = options.available,
        injected = {
            query = options.query,
            execute = options.execute,
        },
    }

    function repository:_available()
        if type(self.availableOverride) == 'boolean' then return self.availableOverride end
        return exportAvailable()
    end

    function repository:Initialize()
        self.initialized = self:_available()
        return self.initialized, self.initialized and nil or 'oxmysql_unavailable'
    end

    function repository:IsAvailable()
        return self.initialized and self:_available()
    end

    function repository:_call(kind, query, params)
        if not self:IsAvailable() then return false, nil, 'oxmysql_unavailable' end
        local injected = self.injected[kind]
        if type(injected) == 'function' then
            local ok, result, errorCode = pcall(injected, query, params or {})
            if not ok then return false, nil, tostring(result) end
            if result == nil then return false, nil, errorCode or 'database_result_empty' end
            if result == false then return false, nil, errorCode or 'database_query_failed' end
            if kind == 'query' and type(result) ~= 'table' then
                return false, nil, 'database_result_invalid'
            end
            if kind == 'execute'
                and type(result) ~= 'number'
                and type(result) ~= 'boolean' then
                return false, nil, 'database_result_invalid'
            end
            return true, result
        end

        local adapter = getExport()
        local methodName = kind == 'query' and 'query_async' or 'update_async'
        if not canCallExport(adapter, methodName) then
            return false, nil, 'oxmysql_export_unavailable'
        end
        local ok, result = pcall(function()
            return adapter[methodName](adapter, query, params or {})
        end)
        if not ok then return false, nil, tostring(result) end
        if result == nil then return false, nil, 'database_result_empty' end
        if kind == 'query' and type(result) ~= 'table' then
            return false, nil, 'database_result_invalid'
        end
        if kind == 'execute'
            and type(result) ~= 'number'
            and type(result) ~= 'boolean' then
            return false, nil, 'database_result_invalid'
        end
        return true, result
    end

    function repository:EnsureSchemaTable()
        local ok, _, errorCode = self:_call('execute', schemaTableStatement, {})
        return ok, errorCode
    end

    function repository:GetSchemaVersion()
        local ok, rows, errorCode = self:_call(
            'query',
            'SELECT version FROM telecom_schema ORDER BY version DESC LIMIT 1',
            {}
        )
        if not ok then return false, nil, errorCode end
        if type(rows) ~= 'table' or #rows == 0 then return true, 0 end
        local version = tonumber(rows[1].version)
        if not version or version < 0 or version ~= math.floor(version) then
            return false, nil, 'schema_version_invalid'
        end
        return true, version
    end

    function repository:ApplyMigration(migration)
        if type(migration) ~= 'table' or type(migration.version) ~= 'number'
            or type(migration.statements) ~= 'table' then
            return false, 'migration_invalid'
        end
        for _, statement in ipairs(migration.statements) do
            local ok, _, errorCode = self:_call('execute', statement, {})
            if not ok then return false, errorCode or 'migration_statement_failed' end
        end
        local ok, _, errorCode = self:_call(
            'execute',
            [[INSERT INTO telecom_schema (version, applied_at)
              VALUES (?, ?)
              ON DUPLICATE KEY UPDATE applied_at = VALUES(applied_at)]],
            { migration.version, type(os.time) == 'function' and os.time() or 0 }
        )
        return ok, errorCode
    end

    function repository:LoadFailures()
        local ok, rows, errorCode = self:_call(
            'query',
            [[SELECT id, tower_id, failure_type, active, created_at, source,
                     reason, metadata_json, updated_at
                FROM telecom_failures
               WHERE active = 1
               ORDER BY id ASC]],
            {}
        )
        if not ok then return false, nil, errorCode end
        return true, copy(type(rows) == 'table' and rows or {})
    end

    function repository:SaveFailure(row)
        if type(row) ~= 'table' then return false, 'failure_row_invalid' end
        local ok, _, errorCode = self:_call(
            'execute',
            [[INSERT INTO telecom_failures
                (id, tower_id, failure_type, active, created_at, source,
                 reason, metadata_json, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON DUPLICATE KEY UPDATE
                tower_id = VALUES(tower_id),
                failure_type = VALUES(failure_type),
                active = VALUES(active),
                created_at = VALUES(created_at),
                source = VALUES(source),
                reason = VALUES(reason),
                metadata_json = VALUES(metadata_json),
                updated_at = VALUES(updated_at)]],
            {
                row.id, row.tower_id, row.failure_type, row.active,
                row.created_at, row.source, row.reason, row.metadata_json,
                row.updated_at,
            }
        )
        return ok, errorCode
    end

    function repository:DeleteFailure(id)
        local ok, _, errorCode = self:_call(
            'execute', 'DELETE FROM telecom_failures WHERE id = ?', { id }
        )
        return ok, errorCode
    end

    function repository:LoadAudit(limit)
        local boundedLimit = tonumber(limit) or 200
        boundedLimit = math.max(1, math.min(1000, math.floor(boundedLimit)))
        local ok, rows, errorCode = self:_call(
            'query',
            [[SELECT id, source, action, details_json, timestamp
                FROM telecom_audit
               ORDER BY timestamp DESC, id DESC
               LIMIT ?]],
            { boundedLimit }
        )
        if not ok then return false, nil, errorCode end
        return true, copy(type(rows) == 'table' and rows or {})
    end

    function repository:AppendAudit(row)
        if type(row) ~= 'table' then return false, 'audit_row_invalid' end
        local ok, _, errorCode = self:_call(
            'execute',
            [[INSERT INTO telecom_audit (id, source, action, details_json, timestamp)
              VALUES (?, ?, ?, ?, ?)
              ON DUPLICATE KEY UPDATE
                source = VALUES(source),
                action = VALUES(action),
                details_json = VALUES(details_json),
                timestamp = VALUES(timestamp)]],
            { row.id, row.source, row.action, row.details_json, row.timestamp }
        )
        return ok, errorCode
    end

    function repository:PruneAudit(limit)
        local boundedLimit = tonumber(limit) or 200
        boundedLimit = math.max(1, math.min(1000, math.floor(boundedLimit)))
        local ok, _, errorCode = self:_call(
            'execute',
            [[DELETE FROM telecom_audit
               WHERE id NOT IN (
                   SELECT id FROM (
                       SELECT id FROM telecom_audit
                       ORDER BY timestamp DESC, id DESC
                       LIMIT ?
                   ) AS retained_audit
               )]],
            { boundedLimit }
        )
        return ok, errorCode
    end

    function repository:Flush()
        return self:IsAvailable()
    end

    function repository:Close()
        self.initialized = false
        return true
    end

    return repository
end
