FrameworkBridge = FrameworkBridge or {}

local adapters = {}
local activeName

function FrameworkBridge.Register(name, adapter)
    if type(name) ~= 'string' or name == '' or type(adapter) ~= 'table' then return false end
    adapters[name] = adapter
    return true
end

local function resourceStarted(name)
    return type(GetResourceState) == 'function'
        and GetResourceState(name) == 'started'
end

function FrameworkBridge.Detect()
    if activeName and adapters[activeName] then return activeName end
    local order = { 'qbox', 'qbcore', 'esx', 'standalone' }
    for _, name in ipairs(order) do
        local adapter = adapters[name]
        if adapter and (not adapter.resource or resourceStarted(adapter.resource)) then
            activeName = name
            return name
        end
    end
    activeName = 'standalone'
    return activeName
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

function FrameworkBridge.IsJobAllowed(source, jobs)
    local job = FrameworkBridge.GetJob(source)
    local name = type(job) == 'table' and job.name or job
    local grade = type(job) == 'table' and (job.grade or job.grade_level) or 0
    return type(name) == 'string' and type(jobs) == 'table' and jobs[name] == true, name, grade
end

FrameworkBridge.Register('standalone', {
    GetJob = function() return nil end,
})
