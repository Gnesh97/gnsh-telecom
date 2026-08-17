BridgeRegistry = BridgeRegistry or {}

local entries = {}
local sequence = 0

local function categoryEntries(category)
    entries[category] = entries[category] or {}
    return entries[category]
end

function BridgeRegistry.Register(contract, options)
    local normalized, errorMessage = BridgeContracts.Normalize(contract)
    if not normalized then return false, errorMessage end

    options = type(options) == 'table' and options or {}
    local category = categoryEntries(normalized.category)
    local existing = category[normalized.name]
    if existing and options.rejectDuplicate == true then
        return false, 'bridge_duplicate'
    end
    if options.external == true and (type(options.ownerResource) ~= 'string'
        or options.ownerResource == '') then
        return false, 'bridge_owner_required'
    end

    local replaced = existing ~= nil
    sequence = sequence + 1
    category[normalized.name] = {
        provider = normalized,
        sequence = sequence,
        ownerResource = options.ownerResource,
        external = options.external == true,
    }
    return true, normalized, replaced
end

function BridgeRegistry.Get(category, name)
    local bucket = entries[category]
    local entry = bucket and bucket[name]
    return entry and entry.provider or nil
end

function BridgeRegistry.GetMetadata(category, name)
    local bucket = entries[category]
    local entry = bucket and bucket[name]
    if not entry then return nil end
    return {
        category = category,
        name = name,
        sequence = entry.sequence,
        ownerResource = entry.ownerResource,
        external = entry.external == true,
    }
end

function BridgeRegistry.List(category)
    local result = {}
    for _, entry in pairs(entries[category] or {}) do
        result[#result + 1] = entry.provider
    end
    table.sort(result, function(left, right)
        if left.priority ~= right.priority then return left.priority > right.priority end
        return left.name < right.name
    end)
    return result
end

function BridgeRegistry.Unregister(category, name, options)
    local bucket = entries[category]
    if not bucket or bucket[name] == nil then return nil end
    local entry = bucket[name]
    options = type(options) == 'table' and options or {}
    if options.ownerResource ~= nil and entry.ownerResource ~= options.ownerResource then
        return nil, 'bridge_owner_mismatch'
    end
    if options.externalOnly == true and entry.external ~= true then
        return nil, 'bridge_not_external'
    end
    local provider = entry.provider
    bucket[name] = nil
    return provider
end

function BridgeRegistry.Clear(category)
    if category ~= nil then
        entries[category] = {}
        return
    end
    entries = {}
    sequence = 0
end

function BridgeRegistry.Categories()
    local result = {}
    for category in pairs(BridgeContracts.Categories) do
        result[#result + 1] = category
    end
    table.sort(result)
    return result
end

function BridgeRegistry.Count(category)
    local count = 0
    for _ in pairs(entries[category] or {}) do count = count + 1 end
    return count
end
