TelecomDeploymentEditorServer = TelecomDeploymentEditorServer or {}

local registeredCommands = false
local capturesById = {}
local previewBySource = {}
local enabledBySource = {}
local draftsVisibleBySource = {}
local productionVisibleBySource = {}

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number ~= math.floor(number) or number < 0 then
        return nil
    end
    return number
end

local function token(args, index)
    local value = type(args) == 'table' and args[index]
    return type(value) == 'string' and value or nil
end

local function finite(value)
    return Utils and Utils.IsFiniteNumber and Utils.IsFiniteNumber(value)
        or type(value) == 'number' and value == value
            and value ~= math.huge and value ~= -math.huge
end

local function featureEnabled()
    if TelecomDeploymentEditor and TelecomDeploymentEditor.IsEnabled
        and TelecomDeploymentEditor.IsEnabled(Config) then
        return true
    end

    local tools = Config and Config.DeploymentTools
    if type(tools) ~= 'table' or type(tools.convar) ~= 'string'
        or type(GetConvar) ~= 'function' then
        return false
    end

    local value = tostring(GetConvar(tools.convar, '0')):lower()
    return value == '1' or value == 'true' or value == 'on'
end

local function authorized(source)
    if not TelecomPermissions or not TelecomPermissions.RequireAdmin then
        return false, 'security_unavailable'
    end
    return TelecomPermissions.RequireAdmin(source)
end

local function reply(source, message)
    local number = normalizeSource(source)
    if number and number > 0 and type(TriggerClientEvent) == 'function'
        and Constants and Constants.Events and Constants.Events.DEBUG_MESSAGE then
        TriggerClientEvent(Constants.Events.DEBUG_MESSAGE, number, message)
    elseif type(print) == 'function' then
        print(('[gnsh-telecom] %s'):format(tostring(message)))
    end
end

local function record(source, action, details)
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source, action, details)
    end
end

local function sourceReady(source, playerRequired)
    if not featureEnabled() then return false, 'deployment_tools_disabled' end
    local ok, errorCode = authorized(source)
    if not ok then return false, errorCode end

    local number = normalizeSource(source)
    if playerRequired and (not number or number == 0) then
        return false, 'player_source_required'
    end
    return true, number
end

local function playerCoords(source)
    local number = normalizeSource(source)
    if not number or number == 0 then return nil, 'player_source_required' end
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return nil, 'position_unavailable'
    end

    local ped = GetPlayerPed(number)
    if not ped or ped == 0 then return nil, 'player_ped_unavailable' end
    local coords = GetEntityCoords(ped)
    if not Utils.IsPoint(coords) then return nil, 'player_position_unavailable' end
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function playerHeading(source)
    local number = normalizeSource(source)
    if not number or number == 0 or type(GetPlayerPed) ~= 'function'
        or type(GetEntityHeading) ~= 'function' then
        return nil
    end

    local ped = GetPlayerPed(number)
    if not ped or ped == 0 then return nil end
    local heading = GetEntityHeading(ped)
    return finite(heading) and heading or nil
end

local function captureCount()
    local count = 0
    for _ in pairs(capturesById) do count = count + 1 end
    return count
end

local function captureLimit()
    local tools = Config and Config.DeploymentTools
    local maximum = type(tools) == 'table' and tools.maxCaptures or 64
    return type(maximum) == 'number' and math.floor(maximum) or 64
end

local function setMapValue(current, key, value)
    local nextValues = {}
    for existingKey, existingValue in pairs(current) do
        nextValues[existingKey] = existingValue
    end
    if value == nil then
        nextValues[key] = nil
    else
        nextValues[key] = value
    end
    return nextValues
end

local function findSite(siteId)
    if not TelecomDeploymentEditor or not TelecomDeploymentEditor.FindSite then return nil end
    return TelecomDeploymentEditor.FindSite(siteId, Config)
end

local function selectedSite(source, siteId)
    local site = findSite(siteId)
    if not site then return nil, 'unknown_site' end

    local number = normalizeSource(source)
    local preview = number and previewBySource[number]
    if preview and preview.siteId == site.id
        and TelecomDeploymentEditor.SelectArchetype then
        local selected, errorCode = TelecomDeploymentEditor.SelectArchetype(
            site,
            preview.class,
            Config
        )
        if not selected then return nil, errorCode end
        site = selected
    end
    return site
end

local function sendPreview(source, site)
    local number = normalizeSource(source)
    if not number or number == 0 or type(TriggerClientEvent) ~= 'function'
        or not Constants or not Constants.Events then return end

    local payload = copy(site)
    local capture = capturesById[payload.id]
    local draft = TelecomDeploymentEditor.FindDraft(payload.id, Config)
    if capture then
        payload.class = capture.class
        payload.coverageZone = capture.coverageZone
        payload.purpose = capture.purpose
        payload.technologies = copy(capture.technologies)
        payload.coords = copy(capture.coords)
        payload.heading = capture.heading
        payload.captured = true
    elseif draft then
        payload.coords = copy(draft.coords)
        payload.heading = draft.heading
        payload.draft = true
    end
    local archetype = Config.TowerArchetypes and Config.TowerArchetypes[payload.class] or {}
    payload.coverageRadius = archetype.coverageRadius
    payload.capacity = archetype.capacity
    TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_PREVIEW, number, payload)
end

local function draftPayloads()
    local payloads = {}
    for _, site in ipairs(Config.DeploymentSites or {}) do
        local draft = TelecomDeploymentEditor.FindDraft(site.id, Config)
        if draft then
            local payload = copy(site)
            local capture = capturesById[site.id]
            if capture then
                payload.class = capture.class
                payload.coverageZone = capture.coverageZone
                payload.purpose = capture.purpose
                payload.technologies = copy(capture.technologies)
            end
            payload.coords = copy(capture and capture.coords or draft.coords)
            payload.heading = capture and capture.heading or draft.heading
            local archetype = Config.TowerArchetypes
                and Config.TowerArchetypes[payload.class] or {}
            payload.coverageRadius = archetype.coverageRadius
            payload.capacity = archetype.capacity
            payload.draft = capture == nil
            payload.captured = capture ~= nil
            payloads[#payloads + 1] = payload
        end
    end
    return payloads
end

local function productionPayloads()
    local payloads = {}
    if not TowerRegistry or not TowerRegistry.GetAll then return payloads end

    for _, tower in ipairs(TowerRegistry.GetAll()) do
        local coverage = type(tower) == 'table' and tower.coverage or nil
        local radius = type(coverage) == 'table' and tonumber(coverage.radius) or nil
        if type(tower) == 'table' and type(tower.id) == 'string'
            and Utils.IsPoint(tower.coords)
            and radius and radius > 0 then
            payloads[#payloads + 1] = {
                id = tower.id,
                coords = copy(tower.coords),
                coverageRadius = radius,
                class = tower.class,
                coverageZone = tower.coverageZone,
                purpose = tower.purpose,
                production = true,
            }
        end
    end

    table.sort(payloads, function(left, right)
        return left.id < right.id
    end)
    return payloads
end

local function enableEditor(number, value)
    enabledBySource = setMapValue(enabledBySource, number, value == true)
    if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
        TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_TOGGLE, number, value == true)
    end
end

local function clearPreview(number)
    previewBySource = setMapValue(previewBySource, number, nil)
    if not draftsVisibleBySource[number] and not productionVisibleBySource[number] then
        enableEditor(number, false)
    end
    if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
        TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_CLEAR, number)
    end
end

local function commandEditor(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower editor rejected: %s'):format(numberOrError)); return end

    local nextValue = enabledBySource[numberOrError] ~= true
    enableEditor(numberOrError, nextValue)
    if not nextValue then
        previewBySource = setMapValue(previewBySource, numberOrError, nil)
        draftsVisibleBySource = setMapValue(draftsVisibleBySource, numberOrError, nil)
        productionVisibleBySource = setMapValue(productionVisibleBySource, numberOrError, nil)
    end
    reply(source, ('tower editor enabled=%s'):format(tostring(nextValue)))
    record(numberOrError, 'deployment_editor_toggle', { enabled = nextValue })
end

local function commandList(source)
    local ok, errorCode = sourceReady(source, false)
    if not ok then reply(source, ('tower catalog rejected: %s'):format(errorCode)); return end

    reply(source, 'tower deployment catalog:')
    local lines = TelecomDeploymentEditor.FormatSiteList(Config)
    for _, line in ipairs(lines) do reply(source, line) end
    reply(source, ('catalog sites=%d; no coordinates are authoritative until captured')
        :format(#lines))
    record(source, 'deployment_catalog_list', { count = #lines })
end

local function commandPreview(source, args)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower preview rejected: %s'):format(numberOrError)); return end

    local siteId = token(args, 1)
    local site, errorCode = selectedSite(numberOrError, siteId)
    if not site then
        reply(source, ('tower preview rejected: %s'):format(errorCode or 'site_id_required'))
        return
    end

    previewBySource = setMapValue(previewBySource, numberOrError, {
        siteId = site.id,
        class = site.class,
        coverageZone = site.coverageZone,
    })
    enableEditor(numberOrError, true)
    sendPreview(numberOrError, site)
    local archetype = Config.TowerArchetypes[site.class]
    local draft = TelecomDeploymentEditor.FindDraft(site.id, Config)
    local mode = draft and 'draft marker shown on map; move to the verified location'
        or 'marker follows you; move to the verified location'
    reply(source, ('preview=%s class=%s radius=%s; %s')
        :format(site.id, site.class, tostring(archetype and archetype.coverageRadius), mode))
    record(numberOrError, 'deployment_preview', { siteId = site.id, class = site.class })
end

local function commandArchetype(source, args)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower archetype rejected: %s'):format(numberOrError)); return end

    local siteId = token(args, 1)
    local class = token(args, 2)
    local site = findSite(siteId)
    if not site then reply(source, 'tower archetype rejected: unknown_site'); return end
    local selected, errorCode = TelecomDeploymentEditor.SelectArchetype(site, class, Config)
    if not selected then
        reply(source, ('tower archetype rejected: %s'):format(errorCode));
        return
    end

    previewBySource = setMapValue(previewBySource, numberOrError, {
        siteId = selected.id,
        class = selected.class,
        coverageZone = selected.coverageZone,
    })
    enableEditor(numberOrError, true)
    sendPreview(numberOrError, selected)
    reply(source, ('preview=%s class=%s; archetype selected')
        :format(selected.id, selected.class))
    record(numberOrError, 'deployment_archetype_select', {
        siteId = selected.id,
        class = selected.class,
    })
end

local function commandDrafts(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower drafts rejected: %s'):format(numberOrError)); return end
    if type(TriggerClientEvent) ~= 'function' or not Constants or not Constants.Events then
        reply(source, 'tower drafts rejected: client_event_unavailable')
        return
    end

    local payloads = draftPayloads()
    draftsVisibleBySource = setMapValue(draftsVisibleBySource, numberOrError, true)
    TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS, numberOrError, payloads)
    reply(source, ('drafts shown=%d; move to a marker and capture its site id')
        :format(#payloads))
    record(numberOrError, 'deployment_drafts_show', { count = #payloads })
end

local function commandClearDrafts(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower drafts clear rejected: %s'):format(numberOrError)); return end
    draftsVisibleBySource = setMapValue(draftsVisibleBySource, numberOrError, nil)
    if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
        TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS_CLEAR, numberOrError)
    end
    reply(source, 'tower draft markers cleared')
    record(numberOrError, 'deployment_drafts_clear', {})
end

local function commandProduction(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then
        reply(source, ('production tower map rejected: %s'):format(numberOrError))
        return
    end
    if type(TriggerClientEvent) ~= 'function' or not Constants or not Constants.Events then
        reply(source, 'production tower map rejected: client_event_unavailable')
        return
    end

    local payloads = productionPayloads()
    productionVisibleBySource = setMapValue(productionVisibleBySource, numberOrError, true)
    enableEditor(numberOrError, true)
    TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_PRODUCTION, numberOrError, payloads)
    reply(source, ('production towers shown=%d; map coverage uses Config.Towers runtime data')
        :format(#payloads))
    record(numberOrError, 'deployment_production_show', { count = #payloads })
end

local function commandClearProduction(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then
        reply(source, ('production tower map clear rejected: %s'):format(numberOrError))
        return
    end

    productionVisibleBySource = setMapValue(productionVisibleBySource, numberOrError, nil)
    if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
        TriggerClientEvent(
            Constants.Events.DEPLOYMENT_EDITOR_PRODUCTION_CLEAR,
            numberOrError
        )
    end
    reply(source, 'production tower map cleared')
    record(numberOrError, 'deployment_production_clear', {})
end

local function commandCapture(source, args)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower capture rejected: %s'):format(numberOrError)); return end

    local siteId = token(args, 1)
    local site, errorCode = selectedSite(numberOrError, siteId)
    if not site then
        reply(source, ('tower capture rejected: %s'):format(errorCode or 'site_id_required'))
        return
    end

    local coords
    coords, errorCode = playerCoords(numberOrError)
    if not coords then
        reply(source, ('tower capture rejected: %s'):format(errorCode));
        return
    end

    local capture
    capture, errorCode = TelecomDeploymentEditor.BuildCapture(
        site,
        coords,
        playerHeading(numberOrError),
        Config
    )
    if not capture then
        reply(source, ('tower capture rejected: %s'):format(errorCode));
        return
    end

    local existing = capturesById[capture.id]
    if not existing and captureCount() >= captureLimit() then
        reply(source, 'tower capture rejected: capture_limit_reached')
        return
    end

    capturesById = setMapValue(capturesById, capture.id, capture)
    if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
        TriggerClientEvent(Constants.Events.DEPLOYMENT_CAPTURE_RESULT, numberOrError, copy(capture))
        if draftsVisibleBySource[numberOrError] then
            TriggerClientEvent(Constants.Events.DEPLOYMENT_EDITOR_DRAFTS, numberOrError, draftPayloads())
        end
    end
    reply(source, ('captured=%s coords=vector3(%0.2f, %0.2f, %0.2f) class=%s')
        :format(capture.id, coords.x, coords.y, coords.z, capture.class))
    record(numberOrError, 'deployment_capture', {
        siteId = capture.id,
        class = capture.class,
        coverageZone = capture.coverageZone,
        coords = capture.coords,
        heading = capture.heading,
    })
end

local function commandNearest(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower nearest rejected: %s'):format(numberOrError)); return end

    local coords, errorCode = playerCoords(numberOrError)
    if not coords then
        reply(source, ('tower nearest rejected: %s'):format(errorCode));
        return
    end

    local nearest = TelecomDeploymentEditor.NearestCapture(capturesById, coords)
    if nearest then
        reply(source, ('nearest captured=%s distance=%0.2f class=%s')
            :format(nearest.id, nearest.distance, nearest.class))
        return
    end

    if TowerRegistry and TowerRegistry.GetAll then
        nearest = TelecomDeploymentEditor.NearestCapture(TowerRegistry.GetAll(), coords)
    end
    if not nearest then
        reply(source, 'nearest tower=none')
        return
    end
    reply(source, ('nearest production=%s distance=%0.2f')
        :format(nearest.id, nearest.distance))
end

local function commandExport(source)
    local ok, errorCode = sourceReady(source, false)
    if not ok then reply(source, ('tower export rejected: %s'):format(errorCode)); return end

    local lines, exportErrors = TelecomDeploymentEditor.FormatExport(capturesById, Config)
    if not lines then
        reply(source, 'tower export rejected: invalid_capture')
        for _, message in ipairs(exportErrors or {}) do reply(source, message) end
        return
    end
    for _, line in ipairs(lines) do reply(source, line) end
    reply(source, ('exported captures=%d; copy into config/towers.lua only after verification')
        :format(captureCount()))
    record(source, 'deployment_export', { count = captureCount() })
end

local function commandRemovePreview(source)
    local ok, numberOrError = sourceReady(source, true)
    if not ok then reply(source, ('tower preview removal rejected: %s'):format(numberOrError)); return end

    clearPreview(numberOrError)
    reply(source, 'tower preview removed')
    record(numberOrError, 'deployment_preview_remove', {})
end

local function commandRemoveCapture(source, args)
    local ok, numberOrError = sourceReady(source, false)
    if not ok then reply(source, ('tower capture removal rejected: %s'):format(numberOrError)); return end

    local siteId = token(args, 1)
    if not siteId or not capturesById[siteId] then
        reply(source, 'tower capture removal rejected: unknown_capture')
        return
    end
    capturesById = setMapValue(capturesById, siteId, nil)
    local currentPreview = previewBySource[numberOrError]
    if currentPreview and currentPreview.siteId == siteId then
        local site = selectedSite(numberOrError, siteId)
        if site then sendPreview(numberOrError, site) end
    end
    if draftsVisibleBySource[numberOrError]
        and type(TriggerClientEvent) == 'function'
        and Constants and Constants.Events then
        TriggerClientEvent(
            Constants.Events.DEPLOYMENT_EDITOR_DRAFTS,
            numberOrError,
            draftPayloads()
        )
    end
    reply(source, ('capture removed=%s'):format(siteId))
    record(source, 'deployment_capture_remove', { siteId = siteId })
end

local function commandHelp(source)
    local ok, errorCode = sourceReady(source, false)
    if not ok then reply(source, ('tower editor rejected: %s'):format(errorCode)); return end
    local commands = {
        '/telecom_tower_editor',
        '/telecom_tower_list',
        '/telecom_tower_preview <siteId>',
        '/telecom_tower_archetype <siteId> <class>',
        '/telecom_tower_drafts',
        '/telecom_tower_clear_drafts',
        '/telecom_tower_production',
        '/telecom_tower_clear_production',
        '/telecom_tower_capture <siteId>',
        '/telecom_tower_nearest',
        '/telecom_tower_export',
        '/telecom_tower_remove_preview',
        '/telecom_tower_remove_capture <siteId>',
    }
    for _, command in ipairs(commands) do reply(source, command) end
end

function TelecomDeploymentEditorServer.Reset()
    capturesById = {}
    previewBySource = {}
    enabledBySource = {}
    draftsVisibleBySource = {}
    productionVisibleBySource = {}
end

function TelecomDeploymentEditorServer.GetCaptures()
    return TelecomDeploymentEditor.ListCaptures(capturesById)
end

function TelecomDeploymentEditorServer.IsEnabled()
    return featureEnabled()
end

function TelecomDeploymentEditorServer.RegisterCommands()
    if registeredCommands then return false, 'commands_already_registered' end
    if not featureEnabled() then return false, 'deployment_tools_disabled' end
    if type(RegisterCommand) ~= 'function' then return false, 'command_api_unavailable' end

    RegisterCommand('telecom_tower_editor', commandEditor, false)
    RegisterCommand('telecom_tower_list', commandList, false)
    RegisterCommand('telecom_tower_preview', commandPreview, false)
    RegisterCommand('telecom_tower_archetype', commandArchetype, false)
    RegisterCommand('telecom_tower_drafts', commandDrafts, false)
    RegisterCommand('telecom_tower_clear_drafts', commandClearDrafts, false)
    RegisterCommand('telecom_tower_production', commandProduction, false)
    RegisterCommand('telecom_tower_clear_production', commandClearProduction, false)
    RegisterCommand('telecom_tower_capture', commandCapture, false)
    RegisterCommand('telecom_tower_nearest', commandNearest, false)
    RegisterCommand('telecom_tower_export', commandExport, false)
    RegisterCommand('telecom_tower_remove_preview', commandRemovePreview, false)
    RegisterCommand('telecom_tower_remove_capture', commandRemoveCapture, false)
    RegisterCommand('telecom_tower_help', commandHelp, false)
    registeredCommands = true
    return true
end

TelecomDeploymentEditorServer.RegisterCommands()

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        local number = normalizeSource(source)
        if number then
            previewBySource = setMapValue(previewBySource, number, nil)
            enabledBySource = setMapValue(enabledBySource, number, nil)
            draftsVisibleBySource = setMapValue(draftsVisibleBySource, number, nil)
            productionVisibleBySource = setMapValue(productionVisibleBySource, number, nil)
        end
    end)
end
