NocServer = NocServer or {}

local function enabled()
    return Config and Config.Features and Config.Features.NOC == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

function NocServer.HasAccess(source)
    if not enabled() then return false, 'noc_disabled' end
    if TelecomPermissions and TelecomPermissions.IsAdmin and TelecomPermissions.IsAdmin(source) then
        return true
    end
    local ace = Config.NOC and Config.NOC.ace
    if type(IsPlayerAceAllowed) == 'function' and type(ace) == 'string' then
        local ok, allowed = pcall(IsPlayerAceAllowed, source, ace)
        if ok and (allowed == true or allowed == 1) then return true end
    end
    return false, 'not_authorized'
end

function NocServer.GetSnapshot(source)
    local allowed, errorCode = NocServer.HasAccess(source)
    if not allowed then return false, errorCode end

    local towers = TelecomDebug and TelecomDebug.ListTowers and TelecomDebug.ListTowers() or {}
    local maxTowers = Config.NOC and tonumber(Config.NOC.maxTowers) or 200
    local limited = {}
    local counts = {
        operational = 0,
        degraded = 0,
        offline = 0,
        connectedClients = Connections and Connections.Count and Connections.Count() or 0,
        averageLoad = 0,
        criticalCongestion = 0,
    }
    local loadTotal = 0
    for index, tower in ipairs(towers) do
        if index <= maxTowers then limited[#limited + 1] = tower end
        local runtime = tower.runtime or {}
        local state = runtime.state
        if state == Enums.TowerState.OFFLINE or state == Enums.TowerState.DESTROYED then
            counts.offline = counts.offline + 1
        elseif state == Enums.TowerState.DEGRADED or state == Enums.TowerState.MAINTENANCE then
            counts.degraded = counts.degraded + 1
        else
            counts.operational = counts.operational + 1
        end
        loadTotal = loadTotal + (tonumber(runtime.loadPercent) or 0)
        if runtime.congestion == Enums.CongestionState.CRITICAL
            or runtime.congestion == Enums.CongestionState.OVERLOADED then
            counts.criticalCongestion = counts.criticalCongestion + 1
        end
    end
    if #towers > 0 then counts.averageLoad = loadTotal / #towers end

    local features = Config and Config.Features or {}
    local snapshot = {
        generatedAt = type(os.time) == 'function' and os.time() or 0,
        counts = counts,
        towers = limited,
        incidents = IncidentManager and IncidentManager.GetSnapshot
            and IncidentManager.GetSnapshot() or { incidents = {}, counts = {} },
        backhaul = features.Backhaul == true and BackhaulRouting and BackhaulRouting.GetSnapshot
            and BackhaulRouting.GetSnapshot() or {},
        jammers = features.Jammers == true and Jammers and Jammers.GetAll
            and Jammers.GetAll() or {},
        statistics = TelecomStatistics and TelecomStatistics.GetSnapshot
            and TelecomStatistics.GetSnapshot() or {},
    }
    if NocServer.BuildEntities then snapshot.entities = NocServer.BuildEntities(snapshot) end
    return true, snapshot
end

if type(RegisterNetEvent) == 'function' then RegisterNetEvent(Constants.Events.NOC_REQUEST) end
if type(AddEventHandler) == 'function' then
    AddEventHandler(Constants.Events.NOC_REQUEST, function()
        local sourceId = source
        local limited = TelecomRateLimit and TelecomRateLimit.Allow
            and TelecomRateLimit.Allow(sourceId, 'noc', 1000, 2)
        if not limited then return end
        if NocServer.Subscribe then
            local ok, result = NocServer.Subscribe(sourceId)
            if not ok and type(TriggerClientEvent) == 'function' then
                TriggerClientEvent(Constants.Events.NOC_STATE, sourceId, {
                    ok = false,
                    error = result,
                })
            end
        else
            local ok, result = NocServer.GetSnapshot(sourceId)
            if type(TriggerClientEvent) == 'function' then
                TriggerClientEvent(Constants.Events.NOC_STATE, sourceId, {
                    ok = ok,
                    snapshot = ok and copy(result) or nil,
                    error = ok and nil or result,
                })
            end
        end
    end)
end
