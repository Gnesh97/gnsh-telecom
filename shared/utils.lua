Utils = {}

function Utils.Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function Utils.DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[Utils.DeepCopy(key, seen)] = Utils.DeepCopy(item, seen)
    end
    return copy
end

function Utils.IsFiniteNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

function Utils.IsPoint(value)
    return (type(value) == 'table' or type(value) == 'userdata')
        and Utils.IsFiniteNumber(value.x)
        and Utils.IsFiniteNumber(value.y)
        and Utils.IsFiniteNumber(value.z)
end
