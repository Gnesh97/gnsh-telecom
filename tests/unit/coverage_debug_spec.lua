local function makeCoverageDebugTower(id)
    return {
        id = id,
        coords = vector3(0, 0, 0),
        coverage = { radius = 100, minimum = 10 },
        technologies = { '4G' },
        capacity = { maximum = 100 },
    }
end

local function resetCoverageDebugState()
    Connections.Clear()
    FailureEngine.Reset()
    TowerRegistry.Init({})
    SpatialIndex.Rebuild({})
    Config.Features.CoverageDebug = false
end

TEST('coverage debug is disabled by default', function()
    local previousFeature = Config.Features.CoverageDebug
    Config.Features.CoverageDebug = false
    ASSERT_FALSE(TelecomCoverageDebug.IsEnabled())
    Config.Features.CoverageDebug = previousFeature
end)

TEST('coverage heatmap bands use the documented thresholds', function()
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(100), 'GREEN')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(80), 'GREEN')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(79), 'YELLOW')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(55), 'YELLOW')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(54), 'ORANGE')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(30), 'ORANGE')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(29), 'RED')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(1), 'RED')
    ASSERT_EQ(TelecomCoverageDebug.GetHeatmapBand(0), 'BLACK')
end)

TEST('coverage heatmap grid is deterministic and bounded', function()
    local points, errorCode = TelecomCoverageDebug.BuildGrid({
        minX = 0,
        maxX = 250,
        minY = 0,
        maxY = 250,
        z = 30,
    }, 125, 9)

    ASSERT_TRUE(points, errorCode)
    ASSERT_EQ(#points, 9)
    ASSERT_EQ(points[1].x, 0)
    ASSERT_EQ(points[1].y, 0)
    ASSERT_EQ(points[9].x, 250)
    ASSERT_EQ(points[9].y, 250)

    local bounded, limitError = TelecomCoverageDebug.BuildGrid({
        minX = 0,
        maxX = 1000,
        minY = 0,
        maxY = 1000,
        z = 30,
    }, 25, 100)
    ASSERT_EQ(bounded, nil)
    ASSERT_EQ(limitError, 'sample_limit_exceeded')
end)

TEST('global coverage grid spans the map within a bounded sample limit', function()
    local points, errorCode = TelecomCoverageDebug.BuildGlobalGrid()

    ASSERT_TRUE(points, errorCode)
    ASSERT_TRUE(#points > 500)
    ASSERT_TRUE(#points <= 1024)

    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    for _, point in ipairs(points) do
        minX = math.min(minX, point.x)
        maxX = math.max(maxX, point.x)
        minY = math.min(minY, point.y)
        maxY = math.max(maxY, point.y)
    end

    ASSERT_TRUE(minX <= -4000)
    ASSERT_TRUE(maxX >= 4000)
    ASSERT_TRUE(minY <= -4000)
    ASSERT_TRUE(maxY >= 8000)
end)

TEST('coverage sample uses real candidates without mutating connection state', function()
    resetCoverageDebugState()
    TowerRegistry.Init({ makeCoverageDebugTower('COVERAGE_DEBUG_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local sample = TelecomCoverageDebug.SampleLocation(vector3(0, 0, 0), 7)
    ASSERT_TRUE(sample)
    ASSERT_EQ(sample.towerId, 'COVERAGE_DEBUG_TOWER')
    ASSERT_EQ(sample.band, 'GREEN')
    ASSERT_EQ(Connections.Get(7), nil)

    resetCoverageDebugState()
end)

TEST('signal inspector projects capacity effects for an unconnected candidate', function()
    resetCoverageDebugState()
    TowerRegistry.Init({ makeCoverageDebugTower('INSPECTOR_TOWER') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))
    ASSERT_TRUE(TowerState.Update('INSPECTOR_TOWER', {
        congestion = Enums.CongestionState.OVERLOADED,
        loadPercent = 100,
        capacityEffects = { signalMultiplier = 0.65 },
        backhaulStatus = Enums.BackhaulState.ONLINE,
    }))

    local previousPed = rawget(_G, 'GetPlayerPed')
    local previousCoords = rawget(_G, 'GetEntityCoords')
    GetPlayerPed = function() return 1 end
    GetEntityCoords = function() return vector3(0, 0, 0) end

    local ok, errorMessage = pcall(function()
        local report = TelecomCoverageDebug.InspectSignal(7)
        ASSERT_TRUE(report and report.breakdown)
        ASSERT_EQ(report.breakdown.rawSignal, 100)
        ASSERT_EQ(report.breakdown.finalSignal, 65)
        ASSERT_EQ(report.breakdown.capacityPenalty, 35)
        ASSERT_EQ(report.breakdown.loadPercent, 100)
        ASSERT_EQ(report.breakdown.congestion, Enums.CongestionState.OVERLOADED)
    end)

    rawset(_G, 'GetPlayerPed', previousPed)
    rawset(_G, 'GetEntityCoords', previousCoords)
    resetCoverageDebugState()
    if not ok then error(errorMessage, 0) end
end)

TEST('signal watch formatter keeps movement snapshots compact and analyzable', function()
    local line = TelecomCoverageDebug.FormatSignalWatch({
        source = 7,
        coords = { x = 12.34, y = -56.78, z = 90.12 },
        connectedTower = 'WATCH_TOWER',
        connectedSector = 'WATCH_TOWER-S1',
        selectedTower = 'WATCH_TOWER',
        selectedSector = 'WATCH_TOWER-S1',
        candidateCount = 2,
        state = {
            signal = 73.4,
            rawSignal = 80.0,
            signalLevel = 'GOOD',
            technology = '4G',
            congestion = 'NORMAL',
            loadPercent = 12,
            backhaulStatus = 'ONLINE',
            environment = {
                category = 'URBAN',
                zoneId = 'DOWNTOWN',
                multiplier = 0.8,
            },
        },
        candidates = {
            {
                rank = 1,
                towerId = 'WATCH_TOWER',
                sectorId = 'WATCH_TOWER-S1',
                distance = 120,
                signal = 73.4,
                score = 70.1,
                technology = '4G',
            },
        },
        breakdown = {
            distance = 120,
            radius = 850,
            distanceSignal = 73.4,
            distancePenalty = 26.6,
            rawSignal = 80.0,
            finalSignal = 73.4,
            environmentMultiplier = 0.8,
            environmentPenalty = 14.68,
            failureMultiplier = 1,
            failurePenalty = 0,
            interferenceMultiplier = 1,
            interferencePenalty = 0,
            capacityMultiplier = 1,
            capacityPenalty = 0,
            loadPercent = 12,
            congestion = 'NORMAL',
            backhaulStatus = 'ONLINE',
        },
    })

    ASSERT_TRUE(type(line) == 'string')
    ASSERT_TRUE(line:find('signal_watch source=7', 1, true) ~= nil)
    ASSERT_TRUE(line:find('coords=(12.34,-56.78,90.12)', 1, true) ~= nil)
    ASSERT_TRUE(line:find('signal=73.40', 1, true) ~= nil)
    ASSERT_TRUE(line:find('selectedSignal=73.40 selectedRaw=80.00', 1, true) ~= nil)
    ASSERT_TRUE(line:find('tower=WATCH_TOWER/WATCH_TOWER-S1', 1, true) ~= nil)
    ASSERT_TRUE(line:find('distance=120.00/850.00', 1, true) ~= nil)
    ASSERT_TRUE(line:find('candidate#1=WATCH_TOWER/WATCH_TOWER-S1', 1, true) ~= nil)
end)

TEST('signal inspector breakdown follows configured distance falloff', function()
    resetCoverageDebugState()
    TowerRegistry.Init({ makeCoverageDebugTower('FALLOFF_INSPECTOR') })
    ASSERT_TRUE(SpatialIndex.Rebuild(TowerRegistry.GetAll()))

    local previousPed = rawget(_G, 'GetPlayerPed')
    local previousCoords = rawget(_G, 'GetEntityCoords')
    GetPlayerPed = function() return 1 end
    GetEntityCoords = function() return vector3(50, 0, 0) end

    local ok, errorMessage = pcall(function()
        local report = TelecomCoverageDebug.InspectSignal(7)
        local exponent = Config.Signal.DistanceFalloffExponent
        local expected = 100 * (1 - (0.5 ^ exponent))
        ASSERT_TRUE(report and report.breakdown)
        ASSERT_TRUE(math.abs(report.breakdown.distanceSignal - expected) < 0.01)
    end)

    rawset(_G, 'GetPlayerPed', previousPed)
    rawset(_G, 'GetEntityCoords', previousCoords)
    resetCoverageDebugState()
    if not ok then error(errorMessage, 0) end
end)

TEST('coverage debug commands register as bounded development tools', function()
    local previousRegister = rawget(_G, 'RegisterCommand')
    local registered = {}
    RegisterCommand = function(name, handler) registered[name] = handler end

    local ok, errorCode = TelecomCoverageDebug.RegisterCommands()
    ASSERT_TRUE(ok, errorCode)
    ASSERT_TRUE(type(registered.telecom_heatmap) == 'function')
    ASSERT_TRUE(type(registered.telecom_signal_inspect) == 'function')
    ASSERT_TRUE(type(registered.telecom_signal_watch) == 'function')

    rawset(_G, 'RegisterCommand', previousRegister)
end)

TEST('client heatmap chunks create and clear radius blips', function()
    local previous = {
        AddBlipForRadius = rawget(_G, 'AddBlipForRadius'),
        SetBlipColour = rawget(_G, 'SetBlipColour'),
        SetBlipAlpha = rawget(_G, 'SetBlipAlpha'),
        SetBlipHighDetail = rawget(_G, 'SetBlipHighDetail'),
        SetBlipAsShortRange = rawget(_G, 'SetBlipAsShortRange'),
        RemoveBlip = rawget(_G, 'RemoveBlip'),
    }
    local calls = { radius = {}, colors = {}, alpha = {}, removed = 0 }

    AddBlipForRadius = function(x, y, z, radius)
        calls.radius[#calls.radius + 1] = { x = x, y = y, z = z, radius = radius }
        return #calls.radius
    end
    SetBlipColour = function(_, color) calls.colors[#calls.colors + 1] = color end
    SetBlipAlpha = function(_, alpha) calls.alpha[#calls.alpha + 1] = alpha end
    SetBlipHighDetail = function() end
    SetBlipAsShortRange = function() end
    RemoveBlip = function() calls.removed = calls.removed + 1 end

    local ok, errorMessage = pcall(function()
        TelecomClientCoverageDebug.Clear()
        local accepted = TelecomClientCoverageDebug.SetHeatmapChunk({
            requestId = 11,
            mode = 'current',
            chunkIndex = 1,
            totalChunks = 2,
            sampleCount = 3,
            spacing = 125.0,
            samples = {
                { x = 1, y = 2, z = 3, signal = 90, band = 'GREEN' },
                { x = 126, y = 2, z = 3, signal = 45, band = 'ORANGE' },
            },
        })
        ASSERT_TRUE(accepted)
        ASSERT_EQ(#TelecomClientCoverageDebug.GetStatus().samples, 2)
        ASSERT_EQ(calls.radius[1].radius, 90.0)
        ASSERT_EQ(calls.alpha[1], 92)

        accepted = TelecomClientCoverageDebug.SetHeatmapChunk({
            requestId = 11,
            mode = 'current',
            chunkIndex = 2,
            totalChunks = 2,
            sampleCount = 3,
            spacing = 125.0,
            samples = {
                { x = 251, y = 2, z = 3, signal = 0, band = 'BLACK' },
            },
        })
        ASSERT_TRUE(accepted)
        local status = TelecomClientCoverageDebug.GetStatus()
        ASSERT_TRUE(status.complete)
        ASSERT_EQ(status.receivedChunks, 2)
        ASSERT_EQ(status.blipCount, 3)

        local duplicate, duplicateError = TelecomClientCoverageDebug.SetHeatmapChunk({
            requestId = 11,
            chunkIndex = 2,
            totalChunks = 2,
            samples = {},
        })
        ASSERT_FALSE(duplicate)
        ASSERT_EQ(duplicateError, 'duplicate_heatmap_chunk')

        TelecomClientCoverageDebug.Clear()
        ASSERT_EQ(TelecomClientCoverageDebug.GetStatus().sampleCount, 0)
        ASSERT_EQ(calls.removed, 3)
    end)

    for name, value in pairs(previous) do rawset(_G, name, value) end
    if not ok then error(errorMessage, 0) end
end)
