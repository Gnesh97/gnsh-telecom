Coverage = Coverage or {}

local function isUnavailable(tower)
    return tower.state == Enums.TowerState.MAINTENANCE
        or tower.state == Enums.TowerState.OFFLINE
        or tower.state == Enums.TowerState.DESTROYED
end

function Coverage.GetCandidates(coords, environmentContext)
    if not Utils.IsPoint(coords) or not SpatialIndex.GetNearbyTowers then
        return {}
    end

    local nearby = SpatialIndex.GetNearbyTowers(coords)
    local candidates = {}
    local seen = {}

    for _, tower in ipairs(nearby or {}) do
        if type(tower) == 'table' and not seen[tower.id]
            and not isUnavailable(tower) then
            local distance = Signal.CalculateDistance(tower.coords, coords)
            local signal = Signal.CalculateRaw(tower, coords, environmentContext)
            if distance and signal > 0 then
                seen[tower.id] = true
                candidates[#candidates + 1] = {
                    towerId = tower.id,
                    tower = Utils.DeepCopy(tower),
                    distance = distance,
                    signal = signal,
                }
            end
        end
    end

    table.sort(candidates, function(left, right)
        if left.signal == right.signal then
            return left.towerId < right.towerId
        end
        return left.signal > right.signal
    end)

    return candidates
end
