local function fakeMigrationRepository(initialVersion)
    local state = {
        version = initialVersion,
        ensureCalls = 0,
        applied = {},
        available = true,
    }
    local repository = {}

    function repository:IsAvailable()
        return state.available
    end

    function repository:EnsureSchemaTable()
        state.ensureCalls = state.ensureCalls + 1
        return state.available and true or false, state.available and nil or 'database_unavailable'
    end

    function repository:GetSchemaVersion()
        return state.available and true or false, state.version
    end

    function repository:ApplyMigration(migration)
        state.applied[#state.applied + 1] = migration.version
        state.version = migration.version
        return true
    end

    function repository:GetState()
        return state
    end

    return repository
end

TEST('persistence migrations are idempotent', function()
    local repository = fakeMigrationRepository(0)
    local ok, state = PersistenceMigrations.Run(repository)

    ASSERT_TRUE(ok)
    ASSERT_EQ(state.version, PersistenceMigrations.CurrentVersion)
    ASSERT_EQ(#repository:GetState().applied, 1)

    local repeatOk, repeatState = PersistenceMigrations.Run(repository)
    ASSERT_TRUE(repeatOk)
    ASSERT_EQ(repeatState.version, PersistenceMigrations.CurrentVersion)
    ASSERT_EQ(#repository:GetState().applied, 1)
end)

TEST('persistence migrations reject unsupported future versions and unavailable databases', function()
    local future = fakeMigrationRepository(PersistenceMigrations.CurrentVersion + 1)
    local futureOk, futureState = PersistenceMigrations.Run(future)
    ASSERT_FALSE(futureOk)
    ASSERT_EQ(futureState.error, 'unsupported_schema_version')

    local unavailable = fakeMigrationRepository(0)
    unavailable:GetState().available = false
    local unavailableOk, unavailableState = PersistenceMigrations.Run(unavailable)
    ASSERT_FALSE(unavailableOk)
    ASSERT_EQ(unavailableState.error, 'database_unavailable')
end)
