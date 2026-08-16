BridgeRegistry = BridgeRegistry or {}

local entries = {}
local sequence = 0

local function categoryEntries(category)
    entries[category] = entries[category] or {}
    return entries[category]
end

function BridgeRegistry.Register(contract)
    local normalized, errorMessage = BridgeContracts.Normalize(contract)
    if not normalized then return false, errorMessage end

    local category = categoryEntries(normalized.category)
    local replaced = category[normalized.name] ~= nil
    sequence = sequence + 1
    category[normalized.name] = {
        provider = normalized,
        sequence = sequence,
    }
    return true, normalized, replaced
end

function BridgeRegistry.Get(category, name)
    local bucket = entries[category]
    local entry = bucket and bucket[name]
    return entry and entry.provider or nil
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

function BridgeRegistry.Unregister(category, name)
    local bucket = entries[category]
    if not bucket or bucket[name] == nil then return nil end
    local provider = bucket[name].provider
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
