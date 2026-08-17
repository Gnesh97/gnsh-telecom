TelecomSecurity = TelecomSecurity or {}

function TelecomSecurity.IsFiniteNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

function TelecomSecurity.NormalizeSource(source)
    local converted, number = pcall(tonumber, source)
    if not converted then return nil end
    if not TelecomSecurity.IsFiniteNumber(number)
        or number ~= math.floor(number) or number <= 0 then
        return nil
    end
    return number
end

function TelecomSecurity.IsNearPlayer(source, coords, maximumDistance)
    local number = TelecomSecurity.NormalizeSource(source)
    local pointOk, validPoint = false, false
    if type(Utils) == 'table' and type(Utils.IsPoint) == 'function' then
        pointOk, validPoint = pcall(Utils.IsPoint, coords)
    end
    if not number or not pointOk or not validPoint then
        return false, 'invalid_position'
    end
    if not TelecomSecurity.IsFiniteNumber(maximumDistance)
        or maximumDistance < 0 then
        return false, 'invalid_distance'
    end
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return false, 'position_unavailable'
    end
    local pedOk, ped = pcall(GetPlayerPed, number)
    if not pedOk then return false, 'player_ped_unavailable' end
    if not ped or ped == 0 then return false, 'player_ped_unavailable' end
    local coordsOk, actual = pcall(GetEntityCoords, ped)
    if not coordsOk then return false, 'player_position_unavailable' end
    if not Utils.IsPoint(actual) then return false, 'player_position_unavailable' end
    if not Signal or type(Signal.CalculateDistance) ~= 'function' then
        return false, 'position_unavailable'
    end
    local distanceOk, distance = pcall(Signal.CalculateDistance, actual, coords)
    if not distanceOk or not TelecomSecurity.IsFiniteNumber(distance) then
        return false, 'position_unavailable'
    end
    if distance > maximumDistance then return false, 'too_far' end
    return true, distance
end

function TelecomSecurity.ValidateTower(source, towerId, maximumDistance)
    if type(towerId) ~= 'string' or towerId == '' or #towerId > 128 then
        return false, 'tower_required'
    end
    local tower = TowerRegistry and TowerRegistry.Get and TowerRegistry.Get(towerId)
    if not tower then return false, 'unknown_tower' end
    local ok, distance = TelecomSecurity.IsNearPlayer(source, tower.coords, maximumDistance)
    if not ok then return false, distance end
    return true, tower, distance
end

function TelecomSecurity.RequireAdmin(source)
    if TelecomPermissions and TelecomPermissions.RequireAdmin then
        return TelecomPermissions.RequireAdmin(source)
    end
    return false, 'security_unavailable'
end

function TelecomSecurity.IsSafeString(value, maximumLength)
    return type(value) == 'string' and #value <= (maximumLength or 128)
end

function TelecomSecurity.IsSafeTable(value, maximumDepth, maximumFields, seen)
    if type(value) ~= 'table' then return false end
    maximumDepth = maximumDepth or 4
    maximumFields = maximumFields or 64
    if not TelecomSecurity.IsFiniteNumber(maximumDepth)
        or maximumDepth ~= math.floor(maximumDepth)
        or maximumDepth < 0 or maximumDepth > 8 then
        return false
    end
    if not TelecomSecurity.IsFiniteNumber(maximumFields)
        or maximumFields ~= math.floor(maximumFields)
        or maximumFields < 1 or maximumFields > 1024 then
        return false
    end
    if seen ~= nil and type(seen) ~= 'table' then return false end
    seen = seen or {}
    if getmetatable(value) ~= nil then return false end
    if seen[value] or maximumDepth < 0 then return false end
    seen[value] = true
    local fields = 0
    for key, item in pairs(value) do
        fields = fields + 1
        if fields > maximumFields or (type(key) ~= 'string' and type(key) ~= 'number') then
            seen[value] = nil
            return false
        end
        local itemType = type(item)
        if itemType == 'table' then
            if getmetatable(item) ~= nil then
                seen[value] = nil
                return false
            end
            if not TelecomSecurity.IsSafeTable(item, maximumDepth - 1, maximumFields, seen) then
                seen[value] = nil
                return false
            end
        elseif itemType == 'string' then
            if #item > 1024 then seen[value] = nil return false end
        elseif itemType == 'number' then
            if not TelecomSecurity.IsFiniteNumber(item) then seen[value] = nil return false end
        elseif itemType ~= 'boolean' and itemType ~= 'nil' then
            seen[value] = nil
            return false
        end
    end
    seen[value] = nil
    return true
end
