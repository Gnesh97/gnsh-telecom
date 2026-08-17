TelecomClientDeploymentEditor = TelecomClientDeploymentEditor or {}

local enabled = false
local rendering = false
local preview
local lastCapture

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function playerPosition()
    if type(PlayerPedId) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return nil
    end
    local ped = PlayerPedId()
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not Utils.IsPoint(coords) then return nil end
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function playerHeading()
    if type(PlayerPedId) ~= 'function' or type(GetEntityHeading) ~= 'function' then
        return 0
    end
    local heading = GetEntityHeading(PlayerPedId())
    return type(heading) == 'number' and heading or 0
end

local function drawText(coords, text)
    if type(SetDrawOrigin) ~= 'function'
        or type(BeginTextCommandDisplayText) ~= 'function'
        or type(AddTextComponentSubstringPlayerName) ~= 'function'
        or type(EndTextCommandDisplayText) ~= 'function'
        or type(ClearDrawOrigin) ~= 'function' then
        return
    end

    SetDrawOrigin(coords.x, coords.y, coords.z + 3.0, 0)
    if type(SetTextFont) == 'function' then SetTextFont(0) end
    if type(SetTextScale) == 'function' then SetTextScale(0.28, 0.28) end
    if type(SetTextColour) == 'function' then SetTextColour(255, 255, 255, 230) end
    if type(SetTextCentre) == 'function' then SetTextCentre(true) end
    if type(SetTextOutline) == 'function' then SetTextOutline() end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function render()
    if not enabled or type(preview) ~= 'table' then return end
    local coords = playerPosition()
    if not coords then return end

    local radius = tonumber(preview.coverageRadius) or 25.0
    local heading = playerHeading()
    local radians = math.rad(heading)
    local directionLength = math.min(radius, 150.0)
    local target = {
        x = coords.x + math.sin(radians) * directionLength,
        y = coords.y + math.cos(radians) * directionLength,
        z = coords.z + 1.0,
    }

    if type(DrawMarker) == 'function' then
        DrawMarker(
            1,
            coords.x, coords.y, coords.z - 1.0,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            radius * 2.0, radius * 2.0, 1.0,
            40, 170, 255, 40,
            false, false, 2, false, nil, nil, false
        )
    end
    if type(DrawLine) == 'function' then
        DrawLine(
            coords.x, coords.y, coords.z + 1.0,
            target.x, target.y, target.z,
            255, 210, 40, 255
        )
    end

    drawText(coords, ('%s | %s | radius=%s | heading=%0.1f')
        :format(
            tostring(preview.id),
            tostring(preview.class),
            tostring(preview.coverageRadius),
            heading
        ))
end

local function startRendering()
    if rendering or type(CreateThread) ~= 'function' then return end
    rendering = true
    CreateThread(function()
        while enabled do
            if type(Wait) == 'function' then Wait(0) end
            if enabled then render() end
        end
        rendering = false
    end)
end

function TelecomClientDeploymentEditor.SetEnabled(value)
    enabled = value == true
    if not enabled then preview = nil end
    if enabled then startRendering() end
    return true, enabled
end

function TelecomClientDeploymentEditor.SetPreview(value)
    preview = type(value) == 'table' and copy(value) or nil
    if preview then
        enabled = true
        startRendering()
    end
    return preview ~= nil
end

function TelecomClientDeploymentEditor.ClearPreview()
    preview = nil
    return true
end

function TelecomClientDeploymentEditor.GetStatus()
    return {
        enabled = enabled,
        rendering = rendering,
        preview = copy(preview),
        lastCapture = copy(lastCapture),
    }
end

if type(AddEventHandler) == 'function' and Constants and Constants.Events then
    if type(RegisterNetEvent) == 'function' then
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_TOGGLE)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_PREVIEW)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_CLEAR)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_CAPTURE_RESULT)
    end

    AddEventHandler(Constants.Events.DEPLOYMENT_EDITOR_TOGGLE, function(value)
        TelecomClientDeploymentEditor.SetEnabled(value)
    end)
    AddEventHandler(Constants.Events.DEPLOYMENT_EDITOR_PREVIEW, function(value)
        TelecomClientDeploymentEditor.SetPreview(value)
    end)
    AddEventHandler(Constants.Events.DEPLOYMENT_EDITOR_CLEAR, function()
        TelecomClientDeploymentEditor.ClearPreview()
    end)
    AddEventHandler(Constants.Events.DEPLOYMENT_CAPTURE_RESULT, function(value)
        lastCapture = type(value) == 'table' and copy(value) or nil
    end)
end
