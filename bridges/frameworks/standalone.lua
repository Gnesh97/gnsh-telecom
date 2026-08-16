FrameworkBridge = FrameworkBridge or {}

local adapters = {}
local activeName

function FrameworkBridge.Register(name, adapter)
    if type(name) ~= 'string' or name == '' or type(adapter) ~= 'table' then return false end

    if BridgeManager and type(BridgeManager.Register) == 'function' then
        local contract = {}
        for key, value in pairs(adapter) do contract[key] = value end
        contract.name = name
        contract.category = 'framework'
        if contract.resources == nil and type(contract.resource) == 'string' then
            contract.resources = { contract.resource }
        end
        local ok, errorMessage = BridgeManager.Register(contract)
        if not ok then return false, errorMessage end
    end

    adapters[name] = adapter
    return true
end

local function resourceStarted(name)
    if type(name) ~= 'string' or name == '' or type(GetResourceState) ~= 'function' then
        return false
    end
    local ok, state = pcall(GetResourceState, name)
    return ok and state == 'started'
end

local function adapterAvailable(adapter)
    return type(adapter) == 'table'
        and (not adapter.resource or resourceStarted(adapter.resource))
end

local function selectAdapter(name)
    if activeName ~= name and Log and type(Log.info) == 'function' then
        Log.info('framework bridge selected', { bridge = name })
    end
    activeName = name
    return name
end

function FrameworkBridge.Detect()
    if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
        local order = { 'qbox', 'qbcore', 'esx', 'standalone' }
        local detectedName
        for _, name in ipairs(order) do
            if adapterAvailable(adapters[name]) then
                detectedName = name
                break
            end
        end
        detectedName = detectedName or 'standalone'

        local active = BridgeManager.GetActive and BridgeManager.GetActive('framework')
        if not active or active.name ~= detectedName then
            local ok, provider = BridgeManager.InitializeCategory(
                'framework',
                detectedName,
                true
            )
            if ok and provider then
                activeName = provider.name
                return provider.name
            end
        end
        activeName = detectedName
        return detectedName
    end

    local order = { 'qbox', 'qbcore', 'esx', 'standalone' }
    for _, name in ipairs(order) do
        local adapter = adapters[name]
        if adapterAvailable(adapter) then
            return selectAdapter(name)
        end
    end
    return selectAdapter('standalone')
end

local function activeAdapter()
    if BridgeManager and type(BridgeManager.GetActive) == 'function' then
        FrameworkBridge.Detect()
        return BridgeManager.GetActive('framework') or adapters[activeName]
    end
    return adapters[FrameworkBridge.Detect()]
end

function FrameworkBridge.GetName()
    return FrameworkBridge.Detect()
end

function FrameworkBridge.GetJob(source)
    local adapter = activeAdapter()
    if adapter and type(adapter.GetJob) == 'function' then
        local ok, job
        if BridgeLifecycle and BridgeLifecycle.Call then
            ok, job = BridgeLifecycle.Call(adapter, 'GetJob', source)
        else
            ok, job = pcall(adapter.GetJob, source)
        end
        if ok then return job end
    end
    return nil
end

function FrameworkBridge.GetStablePlayerId(source)
    local adapter = activeAdapter()
    if adapter and type(adapter.GetStablePlayerId) == 'function' then
        local ok, identifier
        if BridgeLifecycle and BridgeLifecycle.Call then
            ok, identifier = BridgeLifecycle.Call(adapter, 'GetStablePlayerId', source)
        else
            ok, identifier = pcall(adapter.GetStablePlayerId, source)
        end
        if ok and type(identifier) == 'string'
            and identifier ~= '' and #identifier <= 128 then
            return identifier
        end
    end
    return nil
end

function FrameworkBridge.IsJobAllowed(source, jobs)
    local job = FrameworkBridge.GetJob(source)
    local name = type(job) == 'table' and job.name or job
    local grade = type(job) == 'table' and (job.grade or job.grade_level) or 0
    return type(name) == 'string' and type(jobs) == 'table' and jobs[name] == true, name, grade
end

FrameworkBridge.Register('standalone', {
    GetJob = function() return nil end,
    GetStablePlayerId = function(_, source)
        if type(GetPlayerIdentifierByType) == 'function' then
            local ok, identifier = pcall(GetPlayerIdentifierByType, source, 'license')
            if ok and type(identifier) == 'string' and identifier ~= '' then
                return identifier
            end
        end

        if type(GetPlayerIdentifiers) == 'function' then
            local ok, identifiers = pcall(GetPlayerIdentifiers, source)
            if ok and type(identifiers) == 'table' then
                for _, identifier in ipairs(identifiers) do
                    if type(identifier) == 'string'
                        and identifier:sub(1, 8) == 'license:' then
                        return identifier
                    end
                end
            end
        end
        return nil
    end,
})
