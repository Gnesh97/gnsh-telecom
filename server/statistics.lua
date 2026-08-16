TelecomStatistics = TelecomStatistics or {}

local towerStats = {}
local totals = {
    handovers = 0,
    failuresCreated = 0,
    failuresCleared = 0,
    incidentsCreated = 0,
    incidentsResolved = 0,
    jammerEvents = 0,
    sabotageEvents = 0,
}
local running = false

local function enabled()
    return Config and Config.Features and Config.Features.Statistics == true
end

local function now()
    return type(os.time) == 'function' and os.time() or 0
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function tower(towerId)
    if type(towerId) ~= 'string' then return nil end
    towerStats[towerId] = towerStats[towerId] or {
        towerId = towerId,
        samples = 0,
        loadTotal = 0,
        peakLoad = 0,
        peakClients = 0,
        outageStartedAt = nil,
        outageDuration = 0,
        failures = {},
        handovers = 0,
    }
    return towerStats[towerId]
end

function TelecomStatistics.RecordConnection(previous, current)
    if not enabled() or type(current) ~= 'table' then return false end
    local currentTower = tower(current.towerId)
    if currentTower then
        currentTower.samples = currentTower.samples + 1
        local load = tonumber(current.loadPercent) or 0
        currentTower.loadTotal = currentTower.loadTotal + load
        currentTower.peakLoad = math.max(currentTower.peakLoad, load)
        local runtime = TowerRegistry.GetRuntimeState(current.towerId)
        currentTower.peakClients = math.max(currentTower.peakClients, runtime and runtime.connectedClients or 0)
    end
    if previous and previous.towerId and current.towerId
        and previous.towerId ~= current.towerId then
        totals.handovers = totals.handovers + 1
        local previousTower = tower(previous.towerId)
        if previousTower then previousTower.handovers = previousTower.handovers + 1 end
    end
    return true
end

function TelecomStatistics.RecordFailureCreated(failure)
    if not enabled() or type(failure) ~= 'table' then return false end
    totals.failuresCreated = totals.failuresCreated + 1
    local record = tower(failure.towerId)
    if record then record.failures[failure.type] = (record.failures[failure.type] or 0) + 1 end
    return true
end

function TelecomStatistics.RecordFailureCleared()
    if not enabled() then return false end
    totals.failuresCleared = totals.failuresCleared + 1
    return true
end

function TelecomStatistics.RecordIncidentCreated()
    if enabled() then totals.incidentsCreated = totals.incidentsCreated + 1 end
end

function TelecomStatistics.RecordIncidentResolved()
    if enabled() then totals.incidentsResolved = totals.incidentsResolved + 1 end
end

function TelecomStatistics.RecordJammer()
    if enabled() then totals.jammerEvents = totals.jammerEvents + 1 end
end

function TelecomStatistics.RecordSabotage()
    if enabled() then totals.sabotageEvents = totals.sabotageEvents + 1 end
end

function TelecomStatistics.GetSnapshot()
    if not enabled() then return { enabled = false } end
    local towers = {}
    for id, record in pairs(towerStats) do
        local item = copy(record)
        item.averageLoad = record.samples > 0 and record.loadTotal / record.samples or 0
        item.loadTotal = nil
        item.samples = nil
        towers[id] = item
    end
    return {
        enabled = true,
        generatedAt = now(),
        totals = copy(totals),
        towers = towers,
    }
end

function TelecomStatistics.Flush()
    if not enabled() then return false, 'statistics_disabled' end
    if Log and Log.debug then Log.debug('telecom statistics flush', TelecomStatistics.GetSnapshot()) end
    return true
end

function TelecomStatistics.Initialize()
    if not enabled() or running or type(CreateThread) ~= 'function' then return true end
    running = true
    CreateThread(function()
        while running do
            Wait((Config.Statistics and Config.Statistics.flushIntervalMs) or 60000)
            if running then TelecomStatistics.Flush() end
        end
    end)
    return true
end

function TelecomStatistics.Shutdown()
    running = false
    if enabled() then TelecomStatistics.Flush() end
end

function TelecomStatistics.Reset()
    running = false
    towerStats = {}
    for key in pairs(totals) do totals[key] = 0 end
end
