TelecomInteractions = TelecomInteractions or {}

local installed = {}
local providerResources = {
    ox_target = true,
    ['qb-target'] = true,
}

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    return value
end
local function validTower(tower)
    return type(tower) == 'table'
        and type(tower.id) == 'string'
        and tower.id ~= ''
        and #tower.id <= 64
        and Utils and Utils.IsPoint and Utils.IsPoint(tower.coords)
end

local function interactionOptions(towerId)
    local distance = Config and Config.Technician
        and tonumber(Config.Technician.interactionDistance) or 5.0
    return {
        {
            name = 'gnsh_telecom_diagnose',
            label = 'Diagnose telecom tower',
            icon = 'fa-solid fa-screwdriver-wrench',
            distance = distance,
            key = 38,
            onSelect = function()
                return TechnicianClient and TechnicianClient.RequestTower
                    and TechnicianClient.RequestTower('diagnose', towerId)
            end,
        },
        {
            name = 'gnsh_telecom_begin_repair',
            label = 'Begin tower repair',
            icon = 'fa-solid fa-tower-broadcast',
            distance = distance,
            key = 38,
            onSelect = function()
                return TechnicianClient and TechnicianClient.RequestTower
                    and TechnicianClient.RequestTower('begin', towerId)
            end,
        },
    }
end

local function zoneForTower(tower)
    local radius = tonumber(tower.interactionRadius)
        or Config and Config.Technician
        and tonumber(Config.Technician.interactionDistance)
        or 5.0
    return {
        name = 'gnsh_telecom_' .. tower.id,
        coords = tower.coords,
        radius = radius,
        length = radius * 2.0,
        width = radius * 2.0,
        heading = tonumber(tower.heading) or 0.0,
        distance = radius,
    }
end

function TelecomInteractions.InstallTower(tower)
    if not validTower(tower) then return false, 'tower_required' end
    if not TargetBridge or type(TargetBridge.AddZoneInteraction) ~= 'function' then
        return false, 'target_bridge_unavailable'
    end

    local id = 'tower:' .. tower.id
    if installed[id] then
        TargetBridge.RemoveInteraction(id)
    end
    local options = interactionOptions(tower.id)
    local ok, handleOrError = TargetBridge.AddZoneInteraction(
        id,
        zoneForTower(tower),
        options
    )
    if not ok then return false, handleOrError end

    installed[id] = {
        id = id,
        tower = {
            id = tower.id,
            coords = copy(tower.coords),
            interactionRadius = tower.interactionRadius,
            heading = tower.heading,
        },
        zone = zoneForTower(tower),
        options = options,
        handle = handleOrError,
    }
    return true, handleOrError
end

function TelecomInteractions.RemoveTower(towerId)
    if type(towerId) ~= 'string' or towerId == '' or #towerId > 64 then
        return false, 'tower_id_required'
    end
    local id = 'tower:' .. towerId
    local record = installed[id]
    if not record then return false, 'interaction_not_found' end
    local ok, errorMessage = TargetBridge.RemoveInteraction(id, record.handle)
    installed[id] = nil
    if not ok then return false, errorMessage end
    return true
end

function TelecomInteractions.GetInstalled(towerId)
    if type(towerId) ~= 'string' then return nil end
    local id = towerId:sub(1, 6) == 'tower:' and towerId or 'tower:' .. towerId
    return installed[id] and copy(installed[id]) or nil
end

function TelecomInteractions.ListInstalled()
    return copy(installed)
end

function TelecomInteractions.InstallTowers(towers)
    if type(towers) ~= 'table' then return false, 'towers_required' end
    local installedCount = 0
    for _, tower in ipairs(towers) do
        local ok = TelecomInteractions.InstallTower(tower)
        if ok then installedCount = installedCount + 1 end
    end
    return true, installedCount
end

function TelecomInteractions.Reinstall()
    if TargetBridge and type(TargetBridge.Refresh) == 'function' then
        TargetBridge.Refresh()
    end
    local records = {}
    for _, record in pairs(installed) do records[#records + 1] = copy(record.tower) end
    for _, tower in ipairs(records) do
        TelecomInteractions.InstallTower(tower)
    end
    return true
end

local function installConfiguredTowers()
    if not Config or not Config.Features or Config.Features.Technician ~= true then return end
    if type(Config.Towers) == 'table' then
        TelecomInteractions.InstallTowers(Config.Towers)
    end
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onClientResourceStart', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            installConfiguredTowers()
        elseif providerResources[resourceName] then
            if TargetBridge then TargetBridge.HandleResourceStart(resourceName) end
            TelecomInteractions.Reinstall()
        end
    end)
    AddEventHandler('onClientResourceStop', function(resourceName)
        if providerResources[resourceName] then
            if TargetBridge then TargetBridge.HandleResourceStop(resourceName) end
            TelecomInteractions.Reinstall()
        end
    end)
end
