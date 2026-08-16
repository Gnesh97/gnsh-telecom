TelecomPermissions = TelecomPermissions or {}

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= math.floor(number) or number < 0 then return nil end
    return number
end

local function isConsoleSource(source)
    if normalizeSource(source) == 0 then return true end
    if type(source) ~= 'string' then return false end

    local label = source:lower()
    return label == 'console' or label == 'server'
end

function TelecomPermissions.IsConsole(source)
    return isConsoleSource(source)
end

function TelecomPermissions.GetAdminAce()
    local debug = Config and Config.Debug
    return debug and debug.adminAce or nil
end

local function getAdminAces()
    local configured = TelecomPermissions.GetAdminAce()
    local aces = {}

    local function addAce(ace)
        if type(ace) ~= 'string' or ace == '' then return end
        for _, existing in ipairs(aces) do
            if existing == ace then return end
        end
        aces[#aces + 1] = ace
    end

    addAce(configured)
    addAce('admin')
    addAce('god')
    addAce('command')

    return aces
end

local function isAceAllowed(source, ace)
    local candidates = { source, tostring(source) }

    for index, candidate in ipairs(candidates) do
        local duplicate = index == 2 and candidates[1] == candidate
        if not duplicate then
            local ok, allowed = pcall(IsPlayerAceAllowed, candidate, ace)
            if ok and allowed == true then return true end
        end
    end

    return false
end

function TelecomPermissions.IsAdmin(source)
    if TelecomPermissions.IsConsole(source) then return true end

    local number = normalizeSource(source)
    if not number then return false end

    if type(IsPlayerAceAllowed) ~= 'function' then return false end

    for _, ace in ipairs(getAdminAces()) do
        if isAceAllowed(number, ace) then return true end
    end
    return false
end

function TelecomPermissions.RequireAdmin(source)
    if TelecomPermissions.IsAdmin(source) then return true end
    return false, 'not_authorized'
end
