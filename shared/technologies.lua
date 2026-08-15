Technologies = {
    EDGE = 'EDGE',
    THREE_G = '3G',
    FOUR_G = '4G',
    FIVE_G = '5G',
}

local supported = {
    [Technologies.EDGE] = true,
    [Technologies.THREE_G] = true,
    [Technologies.FOUR_G] = true,
    [Technologies.FIVE_G] = true,
}

function Technologies.IsSupported(value)
    return supported[value] == true
end

function Technologies.GetAll()
    return { 'EDGE', '3G', '4G', '5G' }
end
