# Regional backhaul guide

Phase 37 models the transport path as tower → aggregation → regional POP →
core. `Config.Features.Backhaul` enables the module. An empty topology keeps
the legacy implicit-online behavior; configured topologies are server
authoritative.

## Configuration

```lua
Config.Backhaul = {
    routeCacheTtlMs = 5000,
    maxRouteCacheEntries = 256,
    maxRecomputeNodes = 128,
    maxPathHops = 64,
    maxRegionalTowers = 128,
    coreNodes = { 'CORE-A', 'CORE-B' },
    towerNodes = {
        TOWER_A = 'AGG-A',
    },
    towerRegions = {
        TOWER_A = 'REGION-NORTH',
    },
    regions = {
        {
            id = 'REGION-NORTH',
            popNode = 'POP-NORTH',
            towerIds = { 'TOWER_A' },
        },
    },
    nodes = {
        { id = 'AGG-A', type = 'AGGREGATION' },
        { id = 'POP-NORTH', type = 'REGIONAL_POP' },
        { id = 'CORE-A', type = 'CORE' },
    },
    links = {
        { id = 'LINK-TOWER-A', from = 'TOWER_A', to = 'AGG-A' },
        { id = 'LINK-POP-A', from = 'AGG-A', to = 'POP-NORTH' },
        { id = 'LINK-CORE-A', from = 'POP-NORTH', to = 'CORE-A' },
    },
}
```

Valid node types are `TOWER`, `AGGREGATION`, `REGIONAL_POP` and `CORE`.
Bidirectional links are the default; set `bidirectional = false` for a
directed link. Link states are `ONLINE`, `DEGRADED` and `OFFLINE`; node
states are `ONLINE` and `OFFLINE`.

## Routing interfaces

```lua
BackhaulRouting.FindRoute(towerId, options)
BackhaulRouting.GetTowerStatus(towerId)
BackhaulRouting.GetRegionalStatus(regionId)
BackhaulRouting.RecomputeAffected(rootNodeId)
```

`FindRoute` returns a deterministic primary path and, when available, a
link-disjoint backup path. Online paths are preferred over degraded paths,
then fewer hops, then lexical node order. Offline nodes and links are never
used. Cycles are bounded by `maxPathHops` and per-path visited-node tracking.

Tower status is `ONLINE` when the primary route is healthy, `DEGRADED` when it
contains degraded links, and `OFFLINE` when no route reaches a configured
core. Regional status aggregates bounded tower statuses; a POP outage scopes
to the towers that depend on that region unless a valid alternate route
exists.

Route cache entries are defensive copies and are bounded by
`maxRouteCacheEntries`. Node/link state changes invalidate only cached paths
that include the affected node or link endpoints. `RecomputeAffected` removes
those paths and recomputes at most `maxRecomputeNodes` entries. Restoration
uses the same invalidation path, so recovered links and nodes become eligible
without a resource restart.
