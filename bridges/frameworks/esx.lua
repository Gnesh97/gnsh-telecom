local function getESX()
    if not exports then return nil end
    local exportOk, bridge = pcall(function() return exports.es_extended end)
    if not exportOk or not bridge then return nil end
    local ok, esx = pcall(function() return bridge:getSharedObject() end)
    return ok and esx or nil
end

local function getPlayer(source)
    local esx = getESX()
    if type(esx) ~= 'table' or type(esx.GetPlayerFromId) ~= 'function' then
        return nil
    end
    local ok, player = pcall(function() return esx.GetPlayerFromId(source) end)
    return ok and player or nil
end

local function callPlayerMethod(player, name, ...)
    if type(player) ~= 'table' or type(player[name]) ~= 'function' then
        return false, nil
    end
    local args = { ... }
    local ok, result = pcall(function() return player[name](table.unpack(args)) end)
    return ok, result
end

local function getJob(source)
    local player = getPlayer(source)
    local ok, job = callPlayerMethod(player, 'getJob')
    return ok and job or (player and player.job or nil)
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

local function isAdmin(source)
    local player = getPlayer(source)
    local ok, group = callPlayerMethod(player, 'getGroup')
    group = ok and group or (player and player.group)
    if type(group) ~= 'string' then return false end
    group = group:lower()
    return group == 'admin' or group == 'superadmin' or group == 'god'
end

local function getCharacterName(source)
    local player = getPlayer(source)
    local ok, name = callPlayerMethod(player, 'getName')
    if ok and type(name) == 'string' and name ~= '' then return name end
    local first = player and (player.firstName or player.firstname)
    local last = player and (player.lastName or player.lastname)
    if type(first) == 'string' and type(last) == 'string'
        and first ~= '' and last ~= '' then
        return first .. ' ' .. last
    end
    return player and player.name or nil
end

local function callMoney(source, account, amount, add)
    local player = getPlayer(source)
    local methodNames = add
        and { 'addAccountMoney', 'addMoney' }
        or { 'removeAccountMoney', 'removeMoney' }
    for _, name in ipairs(methodNames) do
        local ok, result = callPlayerMethod(player, name, account, amount)
        if ok then return result ~= false end
    end
    return false
end

if FrameworkBridge and FrameworkBridge.Register then
    FrameworkBridge.Register('esx', {
        resource = 'es_extended',
        priority = 100,
        GetPlayer = function(_, source) return getPlayer(source) end,
        GetJob = function(_, source) return getJob(source) end,
        GetStablePlayerId = function(_, source)
            local player = getPlayer(source)
            if not player then return nil end
            if type(player.identifier) == 'string' and player.identifier ~= '' then
                return player.identifier
            end
            local ok, identifier = callPlayerMethod(player, 'getIdentifier')
            return ok and identifier or nil
        end,
        HasJob = function(_, source, jobs) return matchesJob(getJob(source), jobs) end,
        IsAdmin = function(_, source) return isAdmin(source) end,
        GetCharacterName = function(_, source) return getCharacterName(source) end,
        AddMoney = function(_, source, account, amount)
            return callMoney(source, account, amount, true)
        end,
        RemoveMoney = function(_, source, account, amount)
            return callMoney(source, account, amount, false)
        end,
    })
end
