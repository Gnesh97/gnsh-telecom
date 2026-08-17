TelecomClientCoverageDebug = TelecomClientCoverageDebug or {}

local blips = {}
local state = {
    requestId = nil,
    mode = nil,
    region = nil,
    spacing = nil,
    totalChunks = 0,
    receivedChunks = 0,
    sampleCount = 0,
    complete = false,
    samples = {},
}
local receivedChunks = {}

local BAND_COLORS = {
    GREEN = 2,
    YELLOW = 5,
    ORANGE = 17,
    RED = 1,
    BLACK = 40,
}

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

local function validRequestId(value)
    return finite(value) and value >= 1 and value == math.floor(value)
end

local function validPoint(value)
    return type(value) == 'table'
        and finite(value.x) and finite(value.y) and finite(value.z)
end

local function clearBlips()
    if type(RemoveBlip) == 'function' then
        for _, blip in ipairs(blips) do RemoveBlip(blip) end
    end
    blips = {}
end

local function resetState()
    state = {
        requestId = nil,
        mode = nil,
        region = nil,
        spacing = nil,
        totalChunks = 0,
        receivedChunks = 0,
        sampleCount = 0,
        complete = false,
        samples = {},
    }
    receivedChunks = {}
end

local function mapRadius(spacing)
    local value = tonumber(spacing) or 125.0
    if not finite(value) then value = 125.0 end
    return math.max(25.0, value * 0.72)
end

local function createRadiusBlip(sample, spacing)
    if type(AddBlipForRadius) ~= 'function' then return nil end

    local blip = AddBlipForRadius(
        sample.x + 0.0,
        sample.y + 0.0,
        sample.z + 0.0,
        mapRadius(spacing) + 0.0
    )
    if not blip then return nil end

    local color = BAND_COLORS[sample.band] or BAND_COLORS.BLACK
    if type(SetBlipColour) == 'function' then SetBlipColour(blip, color) end
    if type(SetBlipAlpha) == 'function' then SetBlipAlpha(blip, 92) end
    if type(SetBlipHighDetail) == 'function' then SetBlipHighDetail(blip, true) end
    if type(SetBlipAsShortRange) == 'function' then SetBlipAsShortRange(blip, true) end
    return blip
end

local function status()
    return {
        requestId = state.requestId,
        mode = state.mode,
        region = state.region,
        spacing = state.spacing,
        totalChunks = state.totalChunks,
        receivedChunks = state.receivedChunks,
        sampleCount = state.sampleCount,
        complete = state.complete,
        blipCount = #blips,
        samples = copy(state.samples),
    }
end

function TelecomClientCoverageDebug.Clear()
    clearBlips()
    resetState()
    return true
end

function TelecomClientCoverageDebug.SetHeatmapChunk(payload)
    if type(payload) ~= 'table' or not validRequestId(payload.requestId) then
        return false, 'invalid_heatmap_payload'
    end

    local chunkIndex = tonumber(payload.chunkIndex)
    local totalChunks = tonumber(payload.totalChunks)
    if not finite(chunkIndex) or chunkIndex < 1
        or chunkIndex ~= math.floor(chunkIndex)
        or not finite(totalChunks) or totalChunks < 1
        or totalChunks ~= math.floor(totalChunks)
        or totalChunks > 2048 or chunkIndex > totalChunks then
        return false, 'invalid_heatmap_chunk'
    end

    if state.requestId ~= payload.requestId then
        TelecomClientCoverageDebug.Clear()
        state.requestId = payload.requestId
        state.mode = type(payload.mode) == 'string' and payload.mode or nil
        state.region = type(payload.region) == 'string' and payload.region or nil
        state.spacing = finite(tonumber(payload.spacing))
            and tonumber(payload.spacing) or 125.0
        state.totalChunks = totalChunks
        state.sampleCount = finite(tonumber(payload.sampleCount))
            and math.max(0, math.floor(tonumber(payload.sampleCount))) or 0
    elseif state.totalChunks ~= totalChunks then
        return false, 'heatmap_chunk_mismatch'
    end

    if receivedChunks[chunkIndex] then return false, 'duplicate_heatmap_chunk' end
    receivedChunks[chunkIndex] = true
    state.receivedChunks = state.receivedChunks + 1

    local samples = type(payload.samples) == 'table' and payload.samples or {}
    local maximum = Config and Config.CoverageDebug
        and tonumber(Config.CoverageDebug.maxSamples) or 512
    maximum = finite(maximum) and math.max(1, math.floor(maximum)) or 512
    for _, sample in ipairs(samples) do
        if #state.samples >= maximum then break end
        if validPoint(sample) then
            local normalized = {
                x = sample.x,
                y = sample.y,
                z = sample.z,
                signal = finite(sample.signal) and clamp(sample.signal, 0, 100) or 0,
                signalLevel = sample.signalLevel,
                band = BAND_COLORS[sample.band] and sample.band or 'BLACK',
                towerId = sample.towerId,
                sectorId = sample.sectorId,
                score = sample.score,
                candidateCount = sample.candidateCount,
            }
            state.samples[#state.samples + 1] = normalized
            local blip = createRadiusBlip(normalized, state.spacing)
            if blip then blips[#blips + 1] = blip end
        end
    end

    state.complete = state.receivedChunks >= state.totalChunks
    return true, status()
end

function TelecomClientCoverageDebug.GetStatus()
    return status()
end

if type(AddEventHandler) == 'function' and Constants and Constants.Events then
    if type(RegisterNetEvent) == 'function' then
        RegisterNetEvent(Constants.Events.COVERAGE_DEBUG_HEATMAP)
        RegisterNetEvent(Constants.Events.COVERAGE_DEBUG_HEATMAP_CLEAR)
    end

    AddEventHandler(Constants.Events.COVERAGE_DEBUG_HEATMAP, function(payload)
        TelecomClientCoverageDebug.SetHeatmapChunk(payload)
    end)
    AddEventHandler(Constants.Events.COVERAGE_DEBUG_HEATMAP_CLEAR, function()
        TelecomClientCoverageDebug.Clear()
    end)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onClientResourceStop', function(resourceName)
        if type(GetCurrentResourceName) ~= 'function'
            or resourceName == GetCurrentResourceName() then
            TelecomClientCoverageDebug.Clear()
        end
    end)
end
