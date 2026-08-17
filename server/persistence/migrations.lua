PersistenceMigrations = PersistenceMigrations or {}

PersistenceMigrations.CurrentVersion = Constants
    and Constants.PersistenceSchemaVersion
    or 1

local fallbackStatements = {
    [[CREATE TABLE IF NOT EXISTS telecom_schema (
        version INT NOT NULL PRIMARY KEY,
        applied_at BIGINT NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS telecom_failures (
        id VARCHAR(64) NOT NULL PRIMARY KEY,
        tower_id VARCHAR(64) NOT NULL,
        failure_type VARCHAR(64) NOT NULL,
        active TINYINT NOT NULL,
        created_at BIGINT NOT NULL,
        source BIGINT NULL,
        reason VARCHAR(512) NULL,
        metadata_json TEXT NOT NULL,
        updated_at BIGINT NOT NULL,
        INDEX idx_telecom_failures_tower_active (tower_id, active)
    )]],
    [[CREATE TABLE IF NOT EXISTS telecom_audit (
        id VARCHAR(64) NOT NULL PRIMARY KEY,
        source BIGINT NOT NULL,
        action VARCHAR(128) NOT NULL,
        details_json TEXT NOT NULL,
        timestamp BIGINT NOT NULL,
        INDEX idx_telecom_audit_timestamp (timestamp, id)
    )]],
    [[CREATE TABLE IF NOT EXISTS telecom_subscribers (
        player_id VARCHAR(128) NOT NULL PRIMARY KEY,
        sim_id VARCHAR(64) NOT NULL UNIQUE,
        carrier_id VARCHAR(64) NOT NULL,
        roaming_allowed TINYINT NOT NULL,
        service_class VARCHAR(32) NOT NULL,
        INDEX idx_telecom_subscribers_carrier (carrier_id)
    )]],
}

local function trim(value)
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function statementsFromSql(content)
    local statements = {}
    for statement in content:gmatch('([^;]+);') do
        local normalized = trim(statement)
        if normalized ~= '' then statements[#statements + 1] = normalized end
    end
    return #statements > 0 and statements or fallbackStatements
end

local function getStatements()
    if type(LoadResourceFile) == 'function' and type(GetCurrentResourceName) == 'function' then
        local ok, content = pcall(LoadResourceFile,
            GetCurrentResourceName(), 'server/persistence/schema/001_initial.sql')
        if ok and type(content) == 'string' then return statementsFromSql(content) end
    end
    return fallbackStatements
end

function PersistenceMigrations.GetAll()
    return {
        {
            version = PersistenceMigrations.CurrentVersion,
            statements = getStatements(),
        },
    }
end

function PersistenceMigrations.Run(repository)
    if type(repository) ~= 'table' or type(repository.IsAvailable) ~= 'function'
        or not repository:IsAvailable() then
        return false, { error = 'database_unavailable', version = 0 }
    end

    if type(repository.EnsureSchemaTable) == 'function' then
        local ensured, ensureError = repository:EnsureSchemaTable()
        if not ensured then
            return false, { error = ensureError or 'schema_table_unavailable', version = 0 }
        end
    end

    if type(repository.GetSchemaVersion) ~= 'function' then
        return false, { error = 'schema_version_unsupported', version = 0 }
    end
    local versionOk, version, versionError = repository:GetSchemaVersion()
    if not versionOk then
        return false, { error = versionError or 'schema_version_unavailable', version = 0 }
    end
    version = tonumber(version) or 0
    if version < 0 or version ~= math.floor(version) then
        return false, { error = 'schema_version_invalid', version = version }
    end
    if version > PersistenceMigrations.CurrentVersion then
        return false, { error = 'unsupported_schema_version', version = version }
    end

    local applied = 0
    for _, migration in ipairs(PersistenceMigrations.GetAll()) do
        if migration.version > version then
            if type(repository.ApplyMigration) ~= 'function' then
                return false, { error = 'migration_unsupported', version = version }
            end
            local appliedOk, migrationError = repository:ApplyMigration(migration)
            if not appliedOk then
                return false, {
                    error = migrationError or 'migration_failed',
                    version = version,
                }
            end
            version = migration.version
            applied = applied + 1
        end
    end
    return true, { version = version, applied = applied }
end
