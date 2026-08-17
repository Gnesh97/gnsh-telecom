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

local function adapterDetected(adapter)
    if type(adapter) ~= 'table' then return false end
    if type(adapter.Detect) ~= 'function' then return true end
    local ok, detected = pcall(function() return adapter:Detect() end)
    return ok and detected == true
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
        local configured = Config and Config.Framework or 'auto'
        local order
        if configured ~= 'auto' then
            order = { configured, 'standalone' }
        else
            order = { 'qbox', 'qbcore', 'esx', 'custom', 'standalone' }
        end
        local detectedName
        for _, name in ipairs(order) do
            if adapters[name] and adapterAvailable(adapters[name])
                and adapterDetected(adapters[name]) then
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
        local current = BridgeManager.GetActive and BridgeManager.GetActive('framework')
        if current then
            activeName = current.name
            return current.name
        end
        activeName = detectedName
        return detectedName
    end

    local configured = Config and Config.Framework or 'auto'
    local order = configured ~= 'auto'
        and { configured, 'standalone' }
        or { 'qbox', 'qbcore', 'esx', 'custom', 'standalone' }
    for _, name in ipairs(order) do
        local adapter = adapters[name]
        if adapter and adapterAvailable(adapter) and adapterDetected(adapter) then
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

local function callActive(method, ...)
    local adapter = activeAdapter()
    if not adapter then return false, nil, 'bridge_unavailable' end

    if BridgeManager and type(BridgeManager.Call) == 'function' then
        return BridgeManager.Call('framework', method, ...)
    end

    if type(adapter[method]) ~= 'function' then
        return false, nil, 'capability_unavailable'
    end
    if BridgeLifecycle and BridgeLifecycle.Call then
        return BridgeLifecycle.Call(adapter, method, ...)
    end
    local args = { ... }
    return pcall(function() return adapter[method](adapter, table.unpack(args)) end)
end

local function jobDetails(job)
    if type(job) ~= 'table' then return job, 0 end
    return job.name or job.job, job.grade or job.grade_level or 0
end

local function jobMatches(job, jobs)
    local name = jobDetails(job)
    if type(name) ~= 'string'
        or (type(jobs) ~= 'table' and type(jobs) ~= 'string') then
        return false
    end
    if type(jobs) == 'string' then return name == jobs end
    if jobs[name] == true then return true end
    for _, allowed in ipairs(jobs) do
        if allowed == name then return true end
    end
    return false
end

local function playerData(player)
    if type(player) ~= 'table' then return nil end
    return player.PlayerData or player.playerData or player
end

local function adminFromPlayer(player)
    local data = playerData(player)
    if type(data) ~= 'table' then return nil end
    local permission = data.permission or data.group
    if permission == nil and type(data.metadata) == 'table' then
        permission = data.metadata.permission or data.metadata.group
    end
    if permission == nil and type(player) == 'table' then
        permission = player.permission or player.group
    end
    if type(permission) ~= 'string' then return nil end
    permission = permission:lower()
    return permission == 'admin' or permission == 'superadmin'
        or permission == 'god' or permission == 'owner'
end

local function characterNameFromPlayer(player)
    local data = playerData(player)
    local charinfo = data and (data.charinfo or data.character)
    if type(charinfo) == 'table' then
        local first = charinfo.firstname or charinfo.firstName or charinfo.first
        local last = charinfo.lastname or charinfo.lastName or charinfo.last
        if type(first) == 'string' and type(last) == 'string'
            and first ~= '' and last ~= '' then
            return first .. ' ' .. last
        end
        if type(first) == 'string' and first ~= '' then return first end
    end

    local first = data and (data.firstname or data.firstName)
    local last = data and (data.lastname or data.lastName)
    if type(first) == 'string' and type(last) == 'string'
        and first ~= '' and last ~= '' then
        return first .. ' ' .. last
    end
    if type(data) == 'table' and type(data.name) == 'string' and data.name ~= '' then
        return data.name
    end
    return nil
end

function FrameworkBridge.GetName()
    return FrameworkBridge.Detect()
end

function FrameworkBridge.GetJob(source)
    local ok, job = callActive('GetJob', source)
    if ok then return job end
    return nil
end

function FrameworkBridge.GetPlayer(source)
    local ok, player = callActive('GetPlayer', source)
    return ok and player or nil
end

function FrameworkBridge.GetStablePlayerId(source)
    local ok, identifier = callActive('GetStablePlayerId', source)
    if ok and type(identifier) == 'string'
        and identifier ~= '' and #identifier <= 128 then
        return identifier
    end
    return nil
end

function FrameworkBridge.HasJob(source, jobs)
    local ok, result = callActive('HasJob', source, jobs)
    if ok and type(result) == 'boolean' then return result end
    return jobMatches(FrameworkBridge.GetJob(source), jobs)
end

function FrameworkBridge.IsAdmin(source)
    local ok, result = callActive('IsAdmin', source)
    if ok and type(result) == 'boolean' then return result end
    return adminFromPlayer(FrameworkBridge.GetPlayer(source)) == true
end

function FrameworkBridge.GetCharacterName(source)
    local ok, name = callActive('GetCharacterName', source)
    if ok and type(name) == 'string' and name ~= '' then return name end
    return characterNameFromPlayer(FrameworkBridge.GetPlayer(source))
end

local function callMoney(method, source, account, amount)
    if type(account) ~= 'string' or account == ''
        or #account > 32
        or type(amount) ~= 'number' or amount ~= amount
        or amount == math.huge or amount == -math.huge
        or amount <= 0 or amount > 1000000000 then
        return false
    end
    local ok, result = callActive(method, source, account, amount)
    return ok and result == true
end

function FrameworkBridge.AddMoney(source, account, amount)
    return callMoney('AddMoney', source, account, amount)
end

function FrameworkBridge.RemoveMoney(source, account, amount)
    return callMoney('RemoveMoney', source, account, amount)
end

function FrameworkBridge.IsJobAllowed(source, jobs)
    local job = FrameworkBridge.GetJob(source)
    local name, grade = jobDetails(job)
    return jobMatches(job, jobs), name, grade
end

FrameworkBridge.Register('standalone', {
    GetPlayer = function() return nil end,
    GetJob = function() return nil end,
    HasJob = function() return false end,
    IsAdmin = function() return false end,
    GetCharacterName = function() return nil end,
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
