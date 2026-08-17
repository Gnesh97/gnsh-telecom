BridgeCapabilities = BridgeCapabilities or {}

local aliases = {
    additem = 'AddItem',
    addentityinteraction = 'AddEntityInteraction',
    addmodelinteraction = 'AddModelInteraction',
    addzoneinteraction = 'AddZoneInteraction',
    addtowertarget = 'AddTowerTarget',
    alert = 'Alert',
    canadditem = 'CanAddItem',
    cancarry = 'CanCarry',
    cancall = 'CanCall',
    canuseservice = 'CanUseService',
    getcharactername = 'GetCharacterName',
    getconnectedtower = 'GetConnectedTower',
    getitemcount = 'GetItemCount',
    getjob = 'GetJob',
    getnetworkstate = 'GetNetworkState',
    getnetworktype = 'GetNetworkType',
    getplayer = 'GetPlayer',
    getsignallevel = 'GetSignalLevel',
    getsignalstrength = 'GetSignalStrength',
    getstableplayerid = 'GetStablePlayerId',
    hasdata = 'HasDataConnection',
    hasdataservice = 'HasDataConnection',
    hasitem = 'HasItem',
    hasjob = 'HasJob',
    isadmin = 'IsAdmin',
    removeitem = 'RemoveItem',
    removeinteraction = 'RemoveInteraction',
    removetowertarget = 'RemoveTowerTarget',
    removemoney = 'RemoveMoney',
    addmoney = 'AddMoney',
}

local knownByCategory = {
    framework = {
        'GetPlayer',
        'GetStablePlayerId',
        'GetJob',
        'HasJob',
        'IsAdmin',
        'GetCharacterName',
        'AddMoney',
        'RemoveMoney',
    },
    inventory = { 'HasItem', 'RemoveItem', 'AddItem', 'CanCarry', 'GetItemCount' },
    target = {
        'AddEntityInteraction',
        'AddModelInteraction',
        'AddZoneInteraction',
        'RemoveInteraction',
        'AddTowerTarget',
        'RemoveTowerTarget',
    },
    dispatch = { 'Alert' },
    phone = {
        'HasSignal',
        'GetSignalStrength',
        'GetSignalLevel',
        'GetNetworkType',
        'GetConnectedTower',
        'GetNetworkState',
        'CanCall',
        'CanSendSMS',
        'HasDataConnection',
        'CanUseService',
    },
}

local function trim(value)
    return value:match('^%s*(.-)%s*$')
end

local function canonicalize(value)
    if type(value) ~= 'string' then return nil end
    local name = trim(value)
    if name == '' or #name > 64 then return nil end
    local key = name:lower():gsub('[%s_%-]', '')
    return aliases[key] or name
end

local function add(result, value)
    local name = canonicalize(value)
    if not name then return false end
    result[name] = true
    return true
end

function BridgeCapabilities.Normalize(capabilities)
    if capabilities == nil then return {} end
    if type(capabilities) ~= 'table' then
        return nil, 'capabilities must be a table'
    end

    local result = {}
    for key, value in pairs(capabilities) do
        if type(key) == 'number' then
            if not add(result, value) then
                return nil, 'capabilities must contain non-empty strings'
            end
        elseif value == true and not add(result, key) then
            return nil, 'capabilities must contain non-empty string keys'
        end
    end
    return result
end

function BridgeCapabilities.Infer(category, provider, declared)
    local result, errorMessage = BridgeCapabilities.Normalize(declared)
    if not result then return nil, errorMessage end

    for _, method in ipairs(knownByCategory[category] or {}) do
        if type(provider[method]) == 'function' then
            result[method] = true
        end
    end
    return result
end

function BridgeCapabilities.Copy(capabilities)
    local copy = {}
    for name, enabled in pairs(capabilities or {}) do
        if enabled == true then copy[name] = true end
    end
    return copy
end

function BridgeCapabilities.Known(category)
    local result = {}
    for _, name in ipairs(knownByCategory[category] or {}) do
        result[#result + 1] = name
    end
    return result
end
