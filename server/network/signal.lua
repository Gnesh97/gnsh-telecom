Signal = Signal or {}

local function isUnavailable(tower)
    local state = tower.state
    return state == Enums.TowerState.MAINTENANCE
        or state == Enums.TowerState.OFFLINE
        or state == Enums.TowerState.DESTROYED
end

local function getBaseSignal()
    local base = Config and Config.Signal and Config.Signal.Base
    if type(base) ~= 'number' or base ~= base or base == math.huge
        or base == -math.huge then
        return 100
    end
    return base
end

function Signal.CalculateDistance(left, right)
    if not Utils.IsPoint(left) or not Utils.IsPoint(right) then return nil end

    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Signal.CalculateRaw(tower, coords)
    if type(tower) ~= 'table' or not Utils.IsPoint(tower.coords)
        or not Utils.IsPoint(coords) or isUnavailable(tower) then
        return 0
    end

    local coverage = tower.coverage
    if type(coverage) ~= 'table' or type(coverage.radius) ~= 'number'
        or coverage.radius ~= coverage.radius or coverage.radius <= 0 then
        return 0
    end

    local distance = Signal.CalculateDistance(tower.coords, coords)
    if not distance or distance >= coverage.radius then return 0 end

    local distanceFactor = 1 - (distance / coverage.radius)
    local signal = getBaseSignal() * distanceFactor
    return Utils.Clamp(signal, 0, 100)
end

function Signal.GetLevel(signal)
    signal = Utils.Clamp(tonumber(signal) or 0, 0, 100)
    local levels = Config and Config.Signal and Config.Signal.Levels or {}
    local order = {
        'EXCELLENT',
        'GOOD',
        'NORMAL',
        'WEAK',
        'VERY_WEAK',
        'NO_SERVICE',
    }

    for _, name in ipairs(order) do
        local level = levels[name]
        if type(level) == 'table' and signal >= level.min then
            return name
        end
    end

    return Enums.SignalLevel.NO_SERVICE
end
