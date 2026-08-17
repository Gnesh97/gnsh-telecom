local function getQBCore()
    if not exports then return nil end
    local exportOk, bridge = pcall(function() return exports['qb-core'] end)
    if not exportOk or not bridge then return nil end
    local ok, core = pcall(function() return bridge:GetCoreObject() end)
    if not ok or type(core) ~= 'table' then return nil end
    return core
end

local function getPlayer(source)
    local core = getQBCore()
    local functions = core and core.Functions
    if type(functions) ~= 'table' or type(functions.GetPlayer) ~= 'function' then
        return nil
    end
    local ok, player = pcall(function() return functions.GetPlayer(source) end)
    return ok and player or nil
end

local function getJob(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.job or nil
end

local function matchesJob(job, jobs)
    local name = type(job) == 'table' and (job.name or job.job) or job
    if type(name) ~= 'string' then return false end
    if type(jobs) == 'string' then return name == jobs end
    if type(jobs) ~= 'table' then return false end
    if jobs[name] == true then return true end
    for _, allowed in ipairs(jobs) do
        if allowed == name then return true end
    end
    return false
end

local function getPermission(source)
    local core = getQBCore()
    local functions = core and core.Functions
    if type(functions) == 'table' and type(functions.HasPermission) == 'function' then
        for _, permission in ipairs({ 'admin', 'god' }) do
            local ok, result = pcall(function()
                return functions.HasPermission(source, permission)
            end)
            if ok and (result == true or result == permission) then return true end
        end
    end

    local player = getPlayer(source)
    local data = player and player.PlayerData
    local permission = data and (data.permission or data.group)
    return type(permission) == 'string'
        and (permission:lower() == 'admin' or permission:lower() == 'god'
            or permission:lower() == 'superadmin')
end

local function getCharacterName(source)
    local player = getPlayer(source)
    local data = player and player.PlayerData
    local charinfo = data and data.charinfo
    if type(charinfo) == 'table' then
        local first = charinfo.firstname or charinfo.firstName
        local last = charinfo.lastname or charinfo.lastName
        if type(first) == 'string' and type(last) == 'string'
            and first ~= '' and last ~= '' then
            return first .. ' ' .. last
        end
    end
    return data and data.name or nil
end

local function callPlayerFunction(source, name, ...)
    local player = getPlayer(source)
    local functions = player and player.Functions
    if type(functions) ~= 'table' or type(functions[name]) ~= 'function' then
        return false
    end
    local args = { ... }
    local ok, result = pcall(function() return functions[name](table.unpack(args)) end)
    return ok and result ~= false
end

if FrameworkBridge and FrameworkBridge.Register then
    FrameworkBridge.Register('qbcore', {
        resource = 'qb-core',
        priority = 200,
        GetPlayer = function(_, source) return getPlayer(source) end,
        GetJob = function(_, source) return getJob(source) end,
        GetStablePlayerId = function(_, source)
            local player = getPlayer(source)
            return player and player.PlayerData and player.PlayerData.citizenid or nil
        end,
        HasJob = function(_, source, jobs) return matchesJob(getJob(source), jobs) end,
        IsAdmin = function(_, source) return getPermission(source) end,
        GetCharacterName = function(_, source) return getCharacterName(source) end,
        AddMoney = function(_, source, account, amount)
            return callPlayerFunction(source, 'AddMoney', account, amount)
        end,
        RemoveMoney = function(_, source, account, amount)
            return callPlayerFunction(source, 'RemoveMoney', account, amount)
        end,
    })
end
