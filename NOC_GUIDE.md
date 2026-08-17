# NOC guide

The Network Operations Center is a server-authoritative live view. Enable
`Config.Features.NOC` and grant either `Config.NOC.ace` or the resource's
admin permission. Players open it with `/telecomnoc`.

## Data flow

Opening the NOC creates a subscription and sends one full snapshot. Runtime
changes are sent as cursor-ordered delta events. The client requests a full
reconciliation when a cursor gap is detected, and the server also performs a
lower-frequency reconciliation for active subscriptions. This keeps the
normal refresh path incremental instead of broadcasting the whole world every
refresh interval.

The full snapshot retains the legacy `towers`, `incidents`, `backhaul`,
`jammers` and `statistics` fields for compatibility. It also contains an
`entities` array. Every entity follows this extensible schema:

```lua
{
    entityType = 'tower', -- tower | sector | region | backhaul | carrier | incident | jammer
    entityId = 'LS-DT-04',
    state = {},
    metadata = {},
}
```

Phase 36 renders the currently supported tower, incident, backhaul and jammer
entities. New providers can add sectors, regions, carriers or other entity
types without changing the stream protocol.

## Server interface

```lua
NocServer.GetSnapshot(source)
NocServer.Subscribe(source)
NocServer.PublishDelta({
    changes = {
        {
            operation = 'upsert',
            entity = {
                entityType = 'sector',
                entityId = 'LS-DT-04-S1',
                state = { status = 'DEGRADED' },
                metadata = {},
            },
        },
    },
})
NocServer.Reconcile(source)
NocServer.Unsubscribe(source)
```

`RegisterEntity` and `RegisterEntityProvider` are available for trusted
server modules that own future entity types. Providers may return one entity
or an array of entities; malformed or oversized data is discarded.

The stream emits `NOC_STATE` for full/reconcile snapshots and `NOC_DELTA` for
incremental changes. `cursor` is monotonic per resource lifetime. Delta
messages are bounded by `Config.NOC.maxDeltaEntities`; entity rows,
subscriptions and publication rate are bounded by `maxEntities`,
`maxSubscriptions` and `maxDeltasPerSecond`.

## Operational display

The dashboard shows operational/degraded/offline tower counts, connected
devices, average load, critical congestion, active incidents, backhaul health,
tower health/load/failure state, live entity state and active jammers. The UI
escapes all server values before rendering them.

## Configuration and lifecycle

`Config.NOC.maxTowers` limits legacy tower rows and
`Config.NOC.maxEntities` limits the extensible entity list.
`reconcileIntervalMs` controls periodic reconciliation and
`subscriptionTtlMs` removes stale subscriptions. Closing the NUI sends an
unsubscribe event; player disconnects and resource shutdown also clean up the
subscription.

If NOC is disabled or permission is missing, no operational snapshot or delta
stream is sent. Optional backhaul, jammer and statistics modules may be
disabled independently; the NOC still returns a valid, bounded snapshot.
