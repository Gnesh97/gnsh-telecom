FrameworkBridge = FrameworkBridge or {}

local adapters = {}
local activeName

function FrameworkBridge.Register(name, adapter)
    if type(name) ~= 'string' or name == '' or type(adapter) ~= 'table' then return false end
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
    local order = { 'qbox', 'qbcore', 'esx', 'standalone' }
    for _, name in ipairs(order) do
        local adapter = adapters[name]
        if adapterAvailable(adapter) then
            return selectAdapter(name)
        end
    end
    return selectAdapter('standalone')
end

function FrameworkBridge.GetName()
    return FrameworkBridge.Detect()
end

function FrameworkBridge.GetJob(source)
    local adapter = adapters[FrameworkBridge.Detect()]
    if adapter and type(adapter.GetJob) == 'function' then
        local ok, job = pcall(adapter.GetJob, source)
        if ok then return job end
    end
    return nil
end

function FrameworkBridge.GetStablePlayerId(source)
    local adapter = adapters[FrameworkBridge.Detect()]
    if adapter and type(adapter.GetStablePlayerId) == 'function' then
        local ok, identifier = pcall(adapter.GetStablePlayerId, source)
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
    GetStablePlayerId = function(source)
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
