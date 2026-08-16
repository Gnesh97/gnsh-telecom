-- Development-only example topology. Do not add this file to the production manifest.
ConfigExampleTowers = {
    {
        id = 'TEST_TOWER_A',
        coords = vector3(1988.33, 3733.77, 32.43),
        coverage = {
            radius = 1000.0,
            minimum = 10.0,
        },
        technologies = { '4G', '5G' },
        capacity = {
            maximum = 100,
        },
    },
    {
        id = 'TEST_TOWER_B',
        coords = vector3(1336.12, 3556.3, 34.91),
        coverage = {
            radius = 1000.0,
            minimum = 10.0,
        },
        technologies = { '4G' },
        capacity = {
            maximum = 100,
        },
    },
}

ConfigExampleBackhaul = {
    routeCacheTtlMs = 5000,
    coreNodes = { 'CORE-01' },
    towerNodes = {
        TEST_TOWER_A = 'AGG-01',
        TEST_TOWER_B = 'AGG-02',
    },
    nodes = {
        { id = 'AGG-01', type = 'AGGREGATION' },
        { id = 'AGG-02', type = 'AGGREGATION' },
        { id = 'CORE-01', type = 'CORE' },
    },
    links = {
        { id = 'LINK-A', from = 'TEST_TOWER_A', to = 'AGG-01', type = 'FIBER' },
        { id = 'LINK-B', from = 'TEST_TOWER_B', to = 'AGG-02', type = 'FIBER' },
        { id = 'LINK-CORE-A', from = 'AGG-01', to = 'CORE-01', type = 'FIBER' },
        { id = 'LINK-CORE-B', from = 'AGG-02', to = 'CORE-01', type = 'FIBER' },
    },
}
