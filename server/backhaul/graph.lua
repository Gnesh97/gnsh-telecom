BackhaulGraph = BackhaulGraph or {}

local adjacency = {}
local version = 0

local function enabled()
    return Config and Config.Features and Config.Features.Backhaul == true
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function addEdge(from, to, link)
    adjacency[from] = adjacency[from] or {}
    adjacency[from][#adjacency[from] + 1] = { to = to, link = copy(link) }
end

function BackhaulGraph.Rebuild()
    adjacency = {}
    local configuredNodes = copy(Config.Backhaul.nodes or {})
    local towerMappings = Config.Backhaul.towerNodes or {}
    for _, tower in ipairs(Config.Towers or {}) do
        if type(towerMappings[tower.id]) == 'string' then
            configuredNodes[#configuredNodes + 1] = {
                id = tower.id,
                type = 'TOWER',
            }
        end
    end
    for _, nodeId in ipairs(Config.Backhaul.coreNodes or {}) do
        configuredNodes[#configuredNodes + 1] = {
            id = nodeId,
            type = 'CORE',
        }
    end
    if BackhaulNodes and BackhaulNodes.Initialize then
        BackhaulNodes.Initialize(configuredNodes)
    end
    if BackhaulLinks and BackhaulLinks.Initialize then
        BackhaulLinks.Initialize(Config.Backhaul.links or {})
    end
    for _, link in ipairs(BackhaulLinks.GetAll and BackhaulLinks.GetAll() or {}) do
        addEdge(link.from, link.to, link)
        if link.bidirectional ~= false then addEdge(link.to, link.from, link) end
    end
    version = version + 1
    return true, { version = version, nodes = #((BackhaulNodes.GetAll and BackhaulNodes.GetAll()) or {}), links = #((BackhaulLinks.GetAll and BackhaulLinks.GetAll()) or {}) }
end

function BackhaulGraph.Invalidate()
    version = version + 1
    for _, edges in pairs(adjacency) do
        for _, edge in ipairs(edges) do
            local current = BackhaulLinks and BackhaulLinks.Get
                and BackhaulLinks.Get(edge.link.id)
            if current then edge.link = current end
        end
    end
end

function BackhaulGraph.GetVersion()
    return version
end

function BackhaulGraph.GetNeighbors(nodeId)
    return copy(adjacency[nodeId] or {})
end

function BackhaulGraph.Initialize()
    if not enabled() then return true, { disabled = true } end
    return BackhaulGraph.Rebuild()
end
