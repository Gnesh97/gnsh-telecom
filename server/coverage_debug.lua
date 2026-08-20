TelecomCoverageDebug = TelecomCoverageDebug or {}

local registeredCommands = false
local jobsBySource = {}
local lastHeatmapAtBySource = {}
local signalWatchBySource = {}
local requestSequence = 0

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function finite(value)
    return Utils and Utils.IsFiniteNumber and Utils.IsFiniteNumber(value)
        or type(value) == 'number' and value == value
            and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or not finite(number) or number ~= math.floor(number) or number < 0 then
        return nil
    end
    return number
end

local function token(args, index)
    local value = type(args) == 'table' and args[index]
    return type(value) == 'string' and value or nil
end

local function lower(value)
    return type(value) == 'string' and value:lower() or nil
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

local function featureEnabled()
    local settings = Config and Config.CoverageDebug
    if type(settings) == 'table' and type(settings.convar) == 'string'
        and type(GetConvar) == 'function' then
        local value = tostring(GetConvar(settings.convar, '0')):lower()
        return value == '1' or value == 'true' or value == 'on'
    end

    -- FiveM always exposes GetConvar. The config fallback exists only for the
    -- framework-free unit harness where that native is intentionally absent.
    return Config and Config.Features and Config.Features.CoverageDebug == true
end

function TelecomCoverageDebug.IsEnabled()
    return featureEnabled()
end

local function settings()
    return Config and Config.CoverageDebug or {}
end

local function configuredNumber(name, fallback, minimum, maximum)
    local value = tonumber(settings()[name])
    if not finite(value) then value = fallback end
    return clamp(value, minimum, maximum)
end

local function configuredInteger(name, fallback, minimum, maximum)
    return math.floor(configuredNumber(name, fallback, minimum, maximum))
end

local function nowMs()
    if type(GetGameTimer) == 'function' then
        local value = tonumber(GetGameTimer())
        if finite(value) then return value end
    end
    if type(os.time) == 'function' then return os.time() * 1000 end
    return 0
end

function TelecomCoverageDebug.GetHeatmapBand(signal)
    local value = finite(signal) and clamp(signal, 0, 100) or 0
    local bands = settings().bands or {}
    local strong = finite(tonumber(bands.strong)) and tonumber(bands.strong) or 80
    local good = finite(tonumber(bands.good)) and tonumber(bands.good) or 55
    local moderate = finite(tonumber(bands.moderate))
        and tonumber(bands.moderate) or 30
    local weak = finite(tonumber(bands.weak)) and tonumber(bands.weak) or 1

    if value >= strong then return 'GREEN' end
    if value >= good then return 'YELLOW' end
    if value >= moderate then return 'ORANGE' end
    if value >= weak then return 'RED' end
    return 'BLACK'
end

local function validBounds(bounds)
    return type(bounds) == 'table'
        and finite(bounds.minX) and finite(bounds.maxX)
        and finite(bounds.minY) and finite(bounds.maxY)
        and finite(bounds.z)
        and bounds.maxX >= bounds.minX
        and bounds.maxY >= bounds.minY
end

function TelecomCoverageDebug.BuildGrid(bounds, spacing, maximum)
    if not validBounds(bounds) then return nil, 'invalid_bounds' end

    spacing = tonumber(spacing)
    maximum = tonumber(maximum)
    if not finite(spacing) or spacing <= 0 then return nil, 'invalid_spacing' end
    if not finite(maximum) or maximum < 1 then return nil, 'invalid_sample_limit' end

    spacing = clamp(spacing, 25.0, 500.0)
    maximum = math.floor(maximum)
    local xCount = math.floor((bounds.maxX - bounds.minX) / spacing) + 1
    local yCount = math.floor((bounds.maxY - bounds.minY) / spacing) + 1
    local count = xCount * yCount
    if count > maximum then return nil, 'sample_limit_exceeded' end

    local points = {}
    for yIndex = 0, yCount - 1 do
        local y = bounds.minY + yIndex * spacing
        for xIndex = 0, xCount - 1 do
            local x = bounds.minX + xIndex * spacing
            points[#points + 1] = { x = x, y = y, z = bounds.z }
        end
    end
    return points
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

local function environmentFor(source)
    local number = normalizeSource(source)
    if number and number > 0 and Connections and Connections.Get then
        local state = Connections.Get(number)
        return state and copy(state.environment) or nil
    end
    return nil
end

local function sampleLocation(coords, source, environmentContext)
    if not Utils.IsPoint(coords) or not Coverage or not Coverage.GetCandidates
        or not Selection or not Selection.Rank then
        return nil
    end

    local candidates = Coverage.GetCandidates(coords, environmentContext)
    local ranked = Selection.Rank(candidates, { source = source })
    local best = ranked[1]
    local signal = best and best.signal or 0
    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        signal = signal,
        signalLevel = Signal.GetLevel(signal),
        band = TelecomCoverageDebug.GetHeatmapBand(signal),
        towerId = best and best.towerId or nil,
        sectorId = best and best.sectorId or nil,
        score = best and best.score or nil,
        candidateCount = #ranked,
    }
end

function TelecomCoverageDebug.SampleLocation(coords, source, environmentContext)
    return copy(sampleLocation(coords, source, environmentContext))
end

local function regionBounds(name)
    local regions = settings().regions
    local bounds = type(regions) == 'table' and regions[name]
    return type(bounds) == 'table' and copy(bounds) or nil
end

local function globalBounds()
    local bounds = settings().globalBounds
    return type(bounds) == 'table' and copy(bounds) or nil
end

function TelecomCoverageDebug.BuildGlobalGrid()
    local bounds = globalBounds()
    if not bounds then return nil, 'global_bounds_unconfigured' end

    local spacing = configuredNumber('globalSpacing', 350.0, 100.0, 500.0)
    local maximum = configuredInteger('maxSamples', 1024, 1, 2048)
    return TelecomCoverageDebug.BuildGrid(bounds, spacing, maximum)
end

local function currentBounds(source)
    local coords, errorCode = playerCoords(source)
    if not coords then return nil, errorCode end
    local radius = configuredNumber('currentRadius', 750.0, 100.0, 2000.0)
    return {
        minX = coords.x - radius,
        maxX = coords.x + radius,
        minY = coords.y - radius,
        maxY = coords.y + radius,
        z = coords.z,
    }, coords
end

local function nextRequestId()
    requestSequence = requestSequence + 1
    if requestSequence > 2147483647 then requestSequence = 1 end
    return requestSequence
end

local function sendHeatmapClear(source)
    if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
        TriggerClientEvent(Constants.Events.COVERAGE_DEBUG_HEATMAP_CLEAR, source)
    end
end

local function runHeatmap(source, job, points, mode, regionName, spacing)
    local batchSize = configuredInteger('batchSize', 24, 1, 64)
    local totalChunks = math.ceil(#points / batchSize)
    local environmentContext = mode == 'current' and environmentFor(source) or nil
    spacing = spacing or configuredNumber('gridSpacing', 125.0, 25.0, 500.0)

    for offset = 1, #points, batchSize do
        if jobsBySource[source] ~= job then return end

        local samples = {}
        local limit = math.min(offset + batchSize - 1, #points)
        for index = offset, limit do
            local sample = sampleLocation(points[index], source, environmentContext)
            if sample then samples[#samples + 1] = sample end
        end

        if type(TriggerClientEvent) == 'function' and Constants and Constants.Events then
            TriggerClientEvent(Constants.Events.COVERAGE_DEBUG_HEATMAP, source, {
                requestId = job.id,
                mode = mode,
                region = regionName,
                chunkIndex = math.floor((offset - 1) / batchSize) + 1,
                totalChunks = totalChunks,
                sampleCount = #points,
                spacing = spacing,
                samples = samples,
            })
        end

        if type(Wait) == 'function' then Wait(0) end
    end

    if jobsBySource[source] == job then
        jobsBySource[source] = nil
        reply(source, ('coverage heatmap complete: mode=%s samples=%d')
            :format(mode, #points))
    end
end

local function startHeatmap(source, mode, regionName, points, spacing)
    sendHeatmapClear(source)

    if type(CreateThread) ~= 'function' then return false, 'sampling_unavailable' end

    local job = { id = nextRequestId() }
    jobsBySource[source] = job
    CreateThread(function()
        runHeatmap(source, job, points, mode, regionName, spacing)
    end)
    return true, job.id
end

local function canStartHeatmap(source)
    if jobsBySource[source] then return false, 'sampling_in_progress' end

    local now = nowMs()
    local cooldown = configuredInteger('cooldownMs', 1500, 0, 60000)
    local last = lastHeatmapAtBySource[source]
    if last and now - last < cooldown then return false, 'rate_limited' end

    lastHeatmapAtBySource[source] = now
    return true
end

local function commandHeatmap(source, args)
    local ok, errorCode = authorized(source)
    if not ok then reply(source, ('coverage heatmap rejected: %s'):format(errorCode)); return end
    if not featureEnabled() then
        reply(source, 'coverage heatmap rejected: coverage_tools_disabled')
        return
    end

    local action = lower(token(args, 1)) or 'help'
    if action == 'clear' then
        jobsBySource[source] = nil
        sendHeatmapClear(source)
        reply(source, 'coverage heatmap cleared')
        if TelecomAudit and TelecomAudit.Record then
            TelecomAudit.Record(source, 'coverage_heatmap_clear', {})
        end
        return
    end

    if action == 'help' then
        reply(source, '/telecom_heatmap current')
        reply(source, '/telecom_heatmap region downtown|sandy|paleto')
        reply(source, '/telecom_heatmap all')
        reply(source, '/telecom_heatmap clear')
        reply(source, '/telecom_signal_inspect [playerId]')
        return
    end

    local playerSource = normalizeSource(source)
    if not playerSource or playerSource == 0 then
        reply(source, 'coverage heatmap rejected: player_source_required')
        return
    end

    local bounds
    local regionName
    local spacing = configuredNumber('gridSpacing', 125.0, 25.0, 500.0)
    if action == 'current' then
        bounds, errorCode = currentBounds(playerSource)
        if not bounds then
            reply(source, ('coverage heatmap rejected: %s'):format(errorCode))
            return
        end
    elseif action == 'region' then
        regionName = lower(token(args, 2))
        bounds = regionName and regionBounds(regionName) or nil
        if not bounds then
            reply(source, 'coverage heatmap rejected: unknown_region')
            return
        end
    elseif action == 'all' then
        bounds = globalBounds()
        spacing = configuredNumber('globalSpacing', 350.0, 100.0, 500.0)
        if not bounds then
            reply(source, 'coverage heatmap rejected: global_bounds_unconfigured')
            return
        end
    else
        reply(source, 'coverage heatmap rejected: unknown_action')
        return
    end

    local points
    points, errorCode = TelecomCoverageDebug.BuildGrid(
        bounds,
        spacing,
        configuredInteger('maxSamples', 1024, 1, 2048)
    )
    if not points then
        reply(source, ('coverage heatmap rejected: %s'):format(errorCode))
        return
    end

    local allowed, limitError = canStartHeatmap(playerSource)
    if not allowed then
        reply(source, ('coverage heatmap rejected: %s'):format(limitError))
        return
    end

    local started, result = startHeatmap(playerSource, action, regionName, points, spacing)
    if not started then
        reply(source, ('coverage heatmap rejected: %s'):format(result))
        return
    end
    reply(source, ('coverage heatmap started: mode=%s samples=%d request=%s')
        :format(action, #points, tostring(result)))
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(playerSource, 'coverage_heatmap_start', {
            mode = action,
            region = regionName,
            samples = #points,
        })
    end
end

local function round(value)
    if not finite(value) then return nil end
    return math.floor(value * 100 + 0.5) / 100
end

local function towerRuntime(candidate)
    if type(candidate) ~= 'table' or type(candidate.towerId) ~= 'string' then return {} end
    if candidate.sectorId and TowerSectors and TowerSectors.GetRuntime then
        local runtime = TowerSectors.GetRuntime(candidate.towerId, candidate.sectorId)
        if runtime then return runtime end
    end
    return TowerRegistry and TowerRegistry.GetRuntimeState
        and TowerRegistry.GetRuntimeState(candidate.towerId) or {}
end

local function towerRadius(candidate)
    if type(candidate) ~= 'table' then return nil end
    if type(candidate.sector) == 'table' and finite(candidate.sector.coverageRadius) then
        return candidate.sector.coverageRadius
    end
    return candidate.tower and candidate.tower.coverage
        and candidate.tower.coverage.radius
end

local function signalBreakdown(candidate, coords, environmentContext, state)
    if type(candidate) ~= 'table' or type(candidate.tower) ~= 'table' then return nil end

    local base = Config and Config.Signal and tonumber(Config.Signal.Base) or 100
    base = finite(base) and base or 100
    local distance = candidate.distance or Signal.CalculateDistance(candidate.tower.coords, coords)
    local radius = towerRadius(candidate)
    local distanceSignal = 0
    if finite(distance) and finite(radius) and radius > 0 and distance < radius then
        local exponent = Signal and Signal.GetDistanceFalloffExponent
            and Signal.GetDistanceFalloffExponent() or 1.0
        exponent = finite(exponent) and exponent or 1.0
        local normalizedDistance = clamp(distance / radius, 0, 1)
        distanceSignal = clamp(
            base * (1 - normalizedDistance ^ exponent),
            0,
            100
        )
    end

    local environment = Signal.ResolveEnvironment(coords, environmentContext)
    local afterEnvironment = distanceSignal * (environment.multiplier or 1.0)
    local runtime = towerRuntime(candidate)
    local failureEffects = runtime.failureEffects or {}
    local failureMultiplier = finite(failureEffects.signalMultiplier)
        and failureEffects.signalMultiplier or 1.0
    local coverageMultiplier = finite(failureEffects.coverageMultiplier)
        and failureEffects.coverageMultiplier or 1.0
    local afterFailure = afterEnvironment * failureMultiplier * coverageMultiplier
    local technologies = candidate.sector and candidate.sector.technologies
        or candidate.tower.technologies
    local interference = Jammers and Jammers.GetEffect
        and Jammers.GetEffect(coords, technologies)
        or { multiplier = 1.0, active = false, jammers = {} }
    local afterInterference = afterFailure * (interference.multiplier or 1.0)
    local rawSignal = finite(candidate.signal) and candidate.signal or afterInterference
    local stateMatches = state and state.towerId == candidate.towerId
        and (state.sectorId or nil) == (candidate.sectorId or nil)
    local selectedCongestion = runtime.congestion
        or Enums.CongestionState.NORMAL
    local capacityEffects = stateMatches and state.capacityEffects
        or runtime.capacityEffects
    if (type(capacityEffects) ~= 'table' or not capacityEffects.signalMultiplier)
        and Capacity and Capacity.GetEffects then
        capacityEffects = Capacity.GetEffects(selectedCongestion)
    end
    local capacityMultiplier = type(capacityEffects) == 'table'
        and tonumber(capacityEffects.signalMultiplier) or 1.0
    if not finite(capacityMultiplier) then capacityMultiplier = 1.0 end
    local finalSignal
    if stateMatches and finite(state.signal) then
        finalSignal = state.signal
    elseif Capacity and Capacity.ApplySignal then
        finalSignal = Capacity.ApplySignal(rawSignal, selectedCongestion, capacityEffects)
    else
        finalSignal = clamp(rawSignal * capacityMultiplier, 0, 100)
    end

    local selectedLoad = runtime.loadPercent or 0
    local selectedBackhaul = runtime.backhaulStatus
        or candidate.tower.backhaul and candidate.tower.backhaul.status
        or Enums.BackhaulState.ONLINE
    if BackhaulRouting and BackhaulRouting.GetTowerStatus then
        selectedBackhaul = BackhaulRouting.GetTowerStatus(candidate.towerId)
            or selectedBackhaul
    end
    if stateMatches then
        selectedLoad = state.loadPercent or selectedLoad
        selectedCongestion = state.congestion or selectedCongestion
        selectedBackhaul = state.backhaulStatus or selectedBackhaul
    end

    return {
        distance = round(distance),
        radius = round(radius),
        distanceSignal = round(distanceSignal),
        distancePenalty = round(base - distanceSignal),
        environmentMultiplier = round(environment.multiplier),
        environmentSignal = round(afterEnvironment),
        environmentPenalty = round(distanceSignal - afterEnvironment),
        failureMultiplier = round(failureMultiplier * coverageMultiplier),
        failureSignal = round(afterFailure),
        failurePenalty = round(afterEnvironment - afterFailure),
        interferenceMultiplier = round(interference.multiplier),
        interferenceSignal = round(afterInterference),
        interferencePenalty = round(afterFailure - afterInterference),
        rawSignal = round(rawSignal),
        finalSignal = round(finalSignal),
        capacityMultiplier = round(capacityMultiplier),
        capacityPenalty = round(rawSignal - finalSignal),
        loadPercent = round(selectedLoad),
        congestion = selectedCongestion,
        backhaulStatus = selectedBackhaul,
        sectorPenalty = 0,
        sectorId = candidate.sectorId,
        environment = copy(environment),
        failureEffects = copy(failureEffects),
        interference = copy(interference),
    }
end

local function matchingCandidate(ranked, state)
    if type(state) ~= 'table' or type(state.towerId) ~= 'string' then return nil end
    for _, candidate in ipairs(ranked or {}) do
        if candidate.towerId == state.towerId
            and (candidate.sectorId or nil) == (state.sectorId or nil) then
            return candidate
        end
    end
    return nil
end

function TelecomCoverageDebug.InspectSignal(target)
    local source = normalizeSource(target)
    if not source or source == 0 then return nil, 'player_source_required' end
    local coords, errorCode = playerCoords(source)
    if not coords then return nil, errorCode end

    local state = Connections and Connections.Get and Connections.Get(source) or {}
    local environmentContext = state.environment
    local candidates = Coverage.GetCandidates(coords, environmentContext)
    local ranked = Selection.Rank(candidates, { source = source })
    local selected = matchingCandidate(ranked, state) or ranked[1]
    local summary = {}
    for index = 1, math.min(#ranked, 5) do
        local candidate = ranked[index]
        summary[#summary + 1] = {
            rank = index,
            towerId = candidate.towerId,
            sectorId = candidate.sectorId,
            distance = round(candidate.distance),
            signal = round(candidate.signal),
            score = round(candidate.score),
            technology = candidate.technology,
            scoreDetails = copy(candidate.scoreDetails),
        }
    end

    local breakdown = selected and signalBreakdown(
        selected,
        coords,
        environmentContext,
        state
    ) or nil
    return {
        source = source,
        coords = copy(coords),
        state = copy(state),
        connectedTower = state.towerId,
        connectedSector = state.sectorId,
        selectedTower = selected and selected.towerId or nil,
        selectedSector = selected and selected.sectorId or nil,
        candidates = summary,
        breakdown = breakdown,
        candidateCount = #ranked,
    }
end

local function formatNumber(value)
    return finite(value) and ('%.2f'):format(value) or 'n/a'
end

function TelecomCoverageDebug.FormatSignalWatch(report)
    if type(report) ~= 'table' then return 'signal_watch unavailable' end

    local state = type(report.state) == 'table' and report.state or {}
    local coords = type(report.coords) == 'table' and report.coords or {}
    local environment = type(state.environment) == 'table'
        and state.environment or {}
    local breakdown = type(report.breakdown) == 'table'
        and report.breakdown or {}
    local signal = state.signal
        or breakdown.finalSignal
    local rawSignal = state.rawSignal
        or breakdown.rawSignal
    local candidateParts = {}
    for _, candidate in ipairs(report.candidates or {}) do
        candidateParts[#candidateParts + 1] = ('candidate#%s=%s/%s d=%s s=%s score=%s tech=%s')
            :format(
                tostring(candidate.rank),
                tostring(candidate.towerId),
                tostring(candidate.sectorId),
                formatNumber(candidate.distance),
                formatNumber(candidate.signal),
                formatNumber(candidate.score),
                tostring(candidate.technology)
            )
    end
    if #candidateParts == 0 then candidateParts[1] = 'candidate#none' end

    local selectedTower = report.selectedTower or state.towerId
    local selectedSector = report.selectedSector or state.sectorId
    local band = TelecomCoverageDebug.GetHeatmapBand(signal)
    local parts = {
        ('signal_watch source=%s coords=(%s,%s,%s)')
            :format(
                tostring(report.source),
                formatNumber(coords.x),
                formatNumber(coords.y),
                formatNumber(coords.z)
            ),
        ('connected=%s/%s selected=%s/%s')
            :format(
                tostring(report.connectedTower),
                tostring(report.connectedSector),
                tostring(selectedTower),
                tostring(selectedSector)
            ),
        ('signal=%s raw=%s band=%s level=%s tech=%s')
            :format(
                formatNumber(signal),
                formatNumber(rawSignal),
                band,
                tostring(state.signalLevel),
                tostring(state.technology)
            ),
        ('env=%s/%s x%s candidates=%s')
            :format(
                tostring(environment.category),
                tostring(environment.zoneId),
                formatNumber(environment.multiplier),
                tostring(report.candidateCount or 0)
            ),
        ('tower=%s/%s distance=%s/%s falloffExp=%s distanceSignal=%s distancePenalty=%s')
            :format(
                tostring(selectedTower),
                tostring(selectedSector),
                formatNumber(breakdown.distance),
                formatNumber(breakdown.radius),
                formatNumber(Signal and Signal.GetDistanceFalloffExponent
                    and Signal.GetDistanceFalloffExponent()),
                formatNumber(breakdown.distanceSignal),
                formatNumber(breakdown.distancePenalty)
            ),
        ('envPenalty=%s failure=%sx failurePenalty=%s interference=%sx interferencePenalty=%s')
            :format(
                formatNumber(breakdown.environmentPenalty),
                formatNumber(breakdown.failureMultiplier),
                formatNumber(breakdown.failurePenalty),
                formatNumber(breakdown.interferenceMultiplier),
                formatNumber(breakdown.interferencePenalty)
            ),
        ('capacity=%sx capacityPenalty=%s load=%s congestion=%s sectorPenalty=%s backhaul=%s')
            :format(
                formatNumber(breakdown.capacityMultiplier),
                formatNumber(breakdown.capacityPenalty),
                formatNumber(breakdown.loadPercent or state.loadPercent),
                tostring(breakdown.congestion or state.congestion),
                formatNumber(breakdown.sectorPenalty),
                tostring(breakdown.backhaulStatus or state.backhaulStatus)
            ),
    }
    for _, candidatePart in ipairs(candidateParts) do parts[#parts + 1] = candidatePart end
    return table.concat(parts, ' ')
end

local function commandSignalInspect(source, args)
    local ok, errorCode = authorized(source)
    if not ok then reply(source, ('signal inspector rejected: %s'):format(errorCode)); return end
    if not featureEnabled() then
        reply(source, 'signal inspector rejected: coverage_tools_disabled')
        return
    end

    local target = token(args, 1) and tonumber(token(args, 1)) or source
    local report
    report, errorCode = TelecomCoverageDebug.InspectSignal(target)
    if not report then
        reply(source, ('signal inspector rejected: %s'):format(errorCode))
        return
    end

    local state = report.state or {}
    local breakdown = report.breakdown
    reply(source, ('signal inspector source=%s coords=(%s,%s,%s)')
        :format(
            tostring(report.source),
            formatNumber(report.coords.x),
            formatNumber(report.coords.y),
            formatNumber(report.coords.z)
        ))
    reply(source, ('connected tower=%s sector=%s signal=%s raw=%s level=%s tech=%s')
        :format(
            tostring(report.connectedTower),
            tostring(report.connectedSector),
            formatNumber(state.signal),
            formatNumber(state.rawSignal),
            tostring(state.signalLevel),
            tostring(state.technology)
        ))
    reply(source, ('environment=%s/%s multiplier=%s candidates=%d')
        :format(
            tostring(state.environment and state.environment.category),
            tostring(state.environment and state.environment.zoneId),
            formatNumber(state.environment and state.environment.multiplier),
            report.candidateCount
        ))

    for _, candidate in ipairs(report.candidates or {}) do
        reply(source, ('candidate#%d tower=%s sector=%s distance=%s signal=%s score=%s tech=%s')
            :format(
                candidate.rank,
                tostring(candidate.towerId),
                tostring(candidate.sectorId),
                formatNumber(candidate.distance),
                formatNumber(candidate.signal),
                formatNumber(candidate.score),
                tostring(candidate.technology)
            ))
    end

    if breakdown then
        reply(source, ('breakdown tower=%s distance=%sm/%sm distancePenalty=%s')
            :format(
                tostring(report.selectedTower),
                formatNumber(breakdown.distance),
                formatNumber(breakdown.radius),
                formatNumber(breakdown.distancePenalty)
            ))
        reply(source, ('environment=%s penalty=%s failure=%sx penalty=%s interference=%sx penalty=%s')
            :format(
                formatNumber(breakdown.environmentMultiplier),
                formatNumber(breakdown.environmentPenalty),
                formatNumber(breakdown.failureMultiplier),
                formatNumber(breakdown.failurePenalty),
                formatNumber(breakdown.interferenceMultiplier),
                formatNumber(breakdown.interferencePenalty)
            ))
        reply(source, ('capacity=%sx penalty=%s selectedLoad=%s selectedCongestion=%s sectorPenalty=%s selectedBackhaul=%s')
            :format(
                formatNumber(breakdown.capacityMultiplier),
                formatNumber(breakdown.capacityPenalty),
                formatNumber(breakdown.loadPercent),
                tostring(breakdown.congestion),
                formatNumber(breakdown.sectorPenalty),
                tostring(breakdown.backhaulStatus)
            ))
    else
        reply(source, 'breakdown no_service: no candidate tower covers this position')
    end

    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(source, 'coverage_signal_inspect', {
            target = report.source,
            towerId = report.selectedTower,
            candidateCount = report.candidateCount,
        })
    end
end

local function signalWatchInterval()
    return configuredInteger('signalWatchIntervalMs', 3000, 2000, 10000)
end

local function stopSignalWatch(source, reason)
    local number = normalizeSource(source)
    local watch = number and signalWatchBySource[number]
    if not watch then return false end

    signalWatchBySource[number] = nil
    if reason then reply(number, ('signal watch stopped: %s'):format(reason)) end
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(number, 'coverage_signal_watch_stop', { reason = reason })
    end
    return true
end

local function startSignalWatch(source)
    local number = normalizeSource(source)
    if not number or number == 0 then return false, 'player_source_required' end
    if signalWatchBySource[number] then return false, 'already_running' end
    if type(CreateThread) ~= 'function' or type(Wait) ~= 'function' then
        return false, 'watch_unavailable'
    end

    local watch = {
        source = number,
        intervalMs = signalWatchInterval(),
    }
    signalWatchBySource[number] = watch
    if TelecomAudit and TelecomAudit.Record then
        TelecomAudit.Record(number, 'coverage_signal_watch_start', {
            intervalMs = watch.intervalMs,
        })
    end

    CreateThread(function()
        while signalWatchBySource[number] == watch do
            local report, errorCode = TelecomCoverageDebug.InspectSignal(number)
            if not report then
                stopSignalWatch(number, errorCode or 'inspection_failed')
                break
            end

            reply(number, TelecomCoverageDebug.FormatSignalWatch(report))
            Wait(watch.intervalMs)
        end
    end)
    return true, watch.intervalMs
end

local function commandSignalWatch(source, args)
    local number = normalizeSource(source)
    if not number or number == 0 then
        reply(source, 'signal watch rejected: player_source_required')
        return
    end

    local ok, errorCode = authorized(source)
    if not ok then reply(source, ('signal watch rejected: %s'):format(errorCode)); return end
    if not featureEnabled() then
        reply(source, 'signal watch rejected: coverage_tools_disabled')
        return
    end

    local action = lower(token(args, 1)) or 'toggle'
    local running = signalWatchBySource[number] ~= nil
    if action == 'status' then
        if running then
            reply(number, ('signal watch status=RUNNING interval=%dms'):format(
                signalWatchBySource[number].intervalMs
            ))
        else
            reply(number, 'signal watch status=STOPPED')
        end
        return
    end

    if action == 'off' or action == 'stop'
        or action == 'toggle' and running then
        if stopSignalWatch(number) then
            reply(number, 'signal watch status=STOPPED')
        else
            reply(number, 'signal watch status=ALREADY_STOPPED')
        end
        return
    end

    if action ~= 'on' and action ~= 'start' and action ~= 'toggle' then
        reply(number, 'signal watch usage: /telecom_signal_watch [on|off|status]')
        return
    end

    local started, intervalOrError = startSignalWatch(number)
    if not started then
        if intervalOrError == 'already_running' then
            reply(number, ('signal watch status=ALREADY_RUNNING interval=%dms')
                :format(signalWatchBySource[number].intervalMs))
        else
            reply(number, ('signal watch rejected: %s'):format(intervalOrError))
        end
        return
    end
    reply(number, ('signal watch status=RUNNING interval=%dms; drive and collect F8 lines; stop with /telecom_signal_watch off')
        :format(intervalOrError))
end

function TelecomCoverageDebug.RegisterCommands()
    if registeredCommands then return false, 'commands_already_registered' end
    if type(RegisterCommand) ~= 'function' then return false, 'command_api_unavailable' end

    RegisterCommand('telecom_heatmap', function(source, args)
        commandHeatmap(source, args)
    end, false)
    RegisterCommand('telecom_signal_inspect', function(source, args)
        commandSignalInspect(source, args)
    end, false)
    RegisterCommand('telecom_signal_watch', function(source, args)
        commandSignalWatch(source, args)
    end, false)
    registeredCommands = true
    return true
end

TelecomCoverageDebug.RegisterCommands()

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function()
        local number = normalizeSource(source)
        if number then
            jobsBySource[number] = nil
            lastHeatmapAtBySource[number] = nil
            signalWatchBySource[number] = nil
        end
    end)
end
