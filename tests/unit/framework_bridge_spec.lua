TEST('framework bridge follows supported resource lifecycle changes', function()
    local previousGetResourceState = GetResourceState
    local started = {}

    GetResourceState = function(name)
        if started[name] then return 'started' end
        return 'stopped'
    end

    started['qb-core'] = true
    ASSERT_EQ(FrameworkBridge.Detect(), 'qbcore')

    started['qb-core'] = nil
    started.qbx_core = true
    ASSERT_EQ(FrameworkBridge.Detect(), 'qbox')

    started.qbx_core = nil
    started.es_extended = true
    ASSERT_EQ(FrameworkBridge.Detect(), 'esx')

    started.es_extended = nil
    ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')

    GetResourceState = function()
        error('resource state unavailable')
    end
    ASSERT_EQ(FrameworkBridge.Detect(), 'standalone')

    GetResourceState = previousGetResourceState
end)
