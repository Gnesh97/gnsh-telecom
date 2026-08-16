PersistenceRepository = PersistenceRepository or {}

function PersistenceRepository.Create(config)
    config = type(config) == 'table' and config or {}
    local adapter = config.adapter or 'auto'
    if adapter == 'memory' then return MemoryRepository.New(), nil end

    if (adapter == 'auto' or adapter == 'oxmysql')
        and OxmysqlRepository and OxmysqlRepository.IsAvailable
        and OxmysqlRepository.IsAvailable() then
        return OxmysqlRepository.New(), nil
    end

    return MemoryRepository.New(), adapter == 'oxmysql' and 'oxmysql_unavailable' or nil
end
