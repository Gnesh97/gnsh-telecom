Coverage = Coverage or {}

local function isUnavailable(tower)
    return tower.state == Enums.TowerState.MAINTENANCE
        or tower.state == Enums.TowerState.OFFLINE
        or tower.state == Enums.TowerState.DESTROYED
end

local function getSectors(tower)
    if TowerSectors and TowerSectors.GetForTower then
        return TowerSectors.GetForTower(tower)
    end
    return tower.sectors or {}
end

local function sectorUnavailable(tower, sector)
    if TowerSectors and TowerSectors.IsAvailable
        and not TowerSectors.IsAvailable(tower.id, sector.id, sector) then
        return true
    end
    return sector.state == Enums.TowerState.MAINTENANCE
        or sector.state == Enums.TowerState.OFFLINE
        or sector.state == Enums.TowerState.DESTROYED
end

function Coverage.GetCandidates(coords, environmentContext)
    if not Utils.IsPoint(coords) or not SpatialIndex.GetNearbyTowers then
        return {}
    end

    local nearby = SpatialIndex.GetNearbyTowers(coords)
    local candidates = {}
    local seen = {}

    for _, tower in ipairs(nearby or {}) do
        if type(tower) == 'table' and not isUnavailable(tower) then
            local sectors = getSectors(tower)
            if #sectors > 0 then
                local matches = TowerSectors and TowerSectors.GetCoverage
                    and TowerSectors.GetCoverage(tower, coords) or {}
                for _, sector in ipairs(matches) do
                    local candidateKey = tower.id .. ':' .. sector.id
                    if not seen[candidateKey] and not sectorUnavailable(tower, sector) then
                        local signal = Signal.CalculateRaw(
                            tower, coords, environmentContext, sector
                        )
                        if signal > 0 then
                            seen[candidateKey] = true
                            candidates[#candidates + 1] = {
                                towerId = tower.id,
                                sectorId = sector.id,
                                tower = Utils.DeepCopy(tower),
                                sector = Utils.DeepCopy(sector),
                                distance = sector.distance
                                    or Signal.CalculateDistance(tower.coords, coords),
                                signal = signal,
                            }
                        end
                    end
                end
            elseif not seen[tower.id] then
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
    end

    table.sort(candidates, function(left, right)
        if left.signal == right.signal then
            if left.towerId == right.towerId then
                return tostring(left.sectorId or '') < tostring(right.sectorId or '')
            end
            return left.towerId < right.towerId
        end
        return left.signal > right.signal
    end)

    return candidates
end
