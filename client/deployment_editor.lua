TelecomClientDeploymentEditor = TelecomClientDeploymentEditor or {}

local enabled = false
local rendering = false
local preview
local lastCapture
local draftMarkers = {}
local previewBlip
local previewRadiusBlip
local startRendering

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

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function isPoint(value)
    local valueType = type(value)
    local supportsCoordinates = valueType == 'table'
        or valueType == 'userdata'
        or valueType == 'vector3'
    return supportsCoordinates
        and isFiniteNumber(value.x)
        and isFiniteNumber(value.y)
        and isFiniteNumber(value.z)
end

local function removeBlip(blip)
    if blip and type(RemoveBlip) == 'function' then RemoveBlip(blip) end
end

local function clearPreviewBlips()
    removeBlip(previewBlip)
    removeBlip(previewRadiusBlip)
    previewBlip = nil
    previewRadiusBlip = nil
end

local function setBlipName(blip, name)
    if not blip or type(BeginTextCommandSetBlipName) ~= 'function'
        or type(AddTextComponentSubstringPlayerName) ~= 'function'
        or type(EndTextCommandSetBlipName) ~= 'function' then
        return
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(name))
    EndTextCommandSetBlipName(blip)
end

local function formatRadius(radius)
    if not isFiniteNumber(radius) or radius <= 0 then return 'n/a' end
    return ('%dm'):format(math.floor(radius + 0.5))
end

local function createBlips(coords, radius, label, colour)
    if not isPoint(coords) then return nil, nil end
    local markerBlip
    local radiusBlip

    if type(AddBlipForCoord) == 'function' then
        markerBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
        if type(SetBlipSprite) == 'function' then SetBlipSprite(markerBlip, 1) end
        if type(SetBlipColour) == 'function' then SetBlipColour(markerBlip, colour or 3) end
        if type(SetBlipScale) == 'function' then SetBlipScale(markerBlip, 0.75) end
        if type(SetBlipAsShortRange) == 'function' then SetBlipAsShortRange(markerBlip, false) end
        setBlipName(markerBlip, label)
    end
    if type(AddBlipForRadius) == 'function' and isFiniteNumber(radius) and radius > 0 then
        radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
        if type(SetBlipColour) == 'function' then SetBlipColour(radiusBlip, colour or 3) end
        if type(SetBlipAlpha) == 'function' then SetBlipAlpha(radiusBlip, 180) end
        -- Keep the native radius blip's default display mode. Applying
        -- SetBlipDisplay to a radius blip can suppress its pause-map area.
        if type(SetBlipHighDetail) == 'function' then SetBlipHighDetail(radiusBlip, true) end
        if type(SetBlipAsShortRange) == 'function' then SetBlipAsShortRange(radiusBlip, false) end
        setBlipName(radiusBlip, ('%s | coverage %s'):format(label, formatRadius(radius)))
    end
    return markerBlip, radiusBlip
end

local function clearDraftBlips()
    for _, entry in pairs(draftMarkers) do
        removeBlip(entry.blip)
        removeBlip(entry.radiusBlip)
    end
    draftMarkers = {}
end

local function draftList()
    local result = {}
    for _, entry in pairs(draftMarkers) do
        result[#result + 1] = copy(entry.data)
    end
    table.sort(result, function(left, right)
        return tostring(left.id) < tostring(right.id)
    end)
    return result
end

local function setDrafts(values)
    clearDraftBlips()
    for _, value in ipairs(values or {}) do
        if type(value) == 'table' and type(value.id) == 'string' and isPoint(value.coords) then
            local data = copy(value)
            local blip, radiusBlip = createBlips(
                data.coords,
                tonumber(data.coverageRadius),
                ('Telecom draft: %s'):format(data.id),
                data.captured and 2 or 3
            )
            draftMarkers[data.id] = {
                data = data,
                blip = blip,
                radiusBlip = radiusBlip,
            }
        end
    end
    if next(draftMarkers) then
        enabled = true
        startRendering()
    elseif not preview then
        enabled = false
    end
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
    if not enabled then return end

    local coords
    if type(preview) == 'table' and isPoint(preview.coords) then
        coords = preview.coords
    else
        coords = playerPosition()
    end

    if type(preview) == 'table' and coords then
        local radius = tonumber(preview.coverageRadius) or 25.0
        local heading = isFiniteNumber(preview.heading) and preview.heading or playerHeading()
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
                8.0, 8.0, 2.0,
                40, 170, 255, 90,
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

        local state = preview.captured and 'captured' or preview.draft and 'draft' or 'follow'
        drawText(coords, ('%s | %s | %s | radius=%s | heading=%0.1f')
            :format(
                tostring(preview.id),
                tostring(preview.class),
                state,
                formatRadius(radius),
                heading
            ))
    end

    local player = playerPosition()
    if not player then return end
    for _, entry in pairs(draftMarkers) do
        local marker = entry.data
        local deltaX = marker.coords.x - player.x
        local deltaY = marker.coords.y - player.y
        local deltaZ = marker.coords.z - player.z
        local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
        if distance <= 300.0 and type(DrawMarker) == 'function' then
            DrawMarker(
                1,
                marker.coords.x, marker.coords.y, marker.coords.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                5.0, 5.0, 4.0,
                marker.captured and 40 or 40,
                marker.captured and 220 or 170,
                marker.captured and 80 or 255,
                150,
                false, false, 2, false, nil, nil, false
            )
            drawText(marker.coords, ('%s | %s | map coverage=%s'):format(
                tostring(marker.id),
                marker.captured and 'captured anchor' or 'draft anchor',
                formatRadius(marker.coverageRadius)
            ))
        end
    end
end

startRendering = function()
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
    if not enabled then
        preview = nil
        clearPreviewBlips()
        clearDraftBlips()
    end
    if enabled then startRendering() end
    return true, enabled
end

function TelecomClientDeploymentEditor.SetPreview(value)
    clearPreviewBlips()
    preview = type(value) == 'table' and copy(value) or nil
    if preview then
        if isPoint(preview.coords) then
            previewBlip, previewRadiusBlip = createBlips(
                preview.coords,
                tonumber(preview.coverageRadius),
                ('Telecom preview: %s'):format(tostring(preview.id)),
                preview.captured and 2 or 3
            )
        end
        enabled = true
        startRendering()
    end
    return preview ~= nil
end

function TelecomClientDeploymentEditor.ClearPreview()
    preview = nil
    clearPreviewBlips()
    if not next(draftMarkers) then enabled = false end
    return true
end

function TelecomClientDeploymentEditor.SetDrafts(values)
    setDrafts(values)
    return #draftList()
end

function TelecomClientDeploymentEditor.ClearDrafts()
    clearDraftBlips()
    if not preview then enabled = false end
    return true
end

function TelecomClientDeploymentEditor.GetStatus()
    return {
        enabled = enabled,
        rendering = rendering,
        preview = copy(preview),
        lastCapture = copy(lastCapture),
        drafts = draftList(),
    }
end

if type(AddEventHandler) == 'function' and Constants and Constants.Events then
    if type(RegisterNetEvent) == 'function' then
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_TOGGLE)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_PREVIEW)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_CLEAR)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS)
        RegisterNetEvent(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS_CLEAR)
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
    AddEventHandler(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS, function(value)
        TelecomClientDeploymentEditor.SetDrafts(value)
    end)
    AddEventHandler(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS_CLEAR, function()
        TelecomClientDeploymentEditor.ClearDrafts()
    end)
    AddEventHandler(Constants.Events.DEPLOYMENT_CAPTURE_RESULT, function(value)
        lastCapture = type(value) == 'table' and copy(value) or nil
        if type(value) ~= 'table' or type(value.id) ~= 'string' or not isPoint(value.coords) then
            return
        end
        local entry = draftMarkers[value.id]
        if entry then
            entry.data.coords = copy(value.coords)
            entry.data.heading = value.heading
            entry.data.captured = true
            entry.data.draft = false
            TelecomClientDeploymentEditor.SetDrafts(draftList())
        end
        if preview and preview.id == value.id then
            preview.coords = copy(value.coords)
            preview.heading = value.heading
            preview.captured = true
            preview.draft = false
            TelecomClientDeploymentEditor.SetPreview(preview)
        end
    end)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onClientResourceStop', function(resourceName)
        local currentResource = type(GetCurrentResourceName) == 'function'
            and GetCurrentResourceName() or nil
        if currentResource and resourceName ~= currentResource then return end
        enabled = false
        rendering = false
        preview = nil
        clearPreviewBlips()
        clearDraftBlips()
    end)
end
