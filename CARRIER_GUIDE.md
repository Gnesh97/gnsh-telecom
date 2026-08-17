# Carrier and roaming guide

This guide targets release candidate `0.1.0-rc.1`. Carrier behavior is covered
by synthetic contract tests; live provider/runtime certification remains
tracked in [COMPATIBILITY.md](COMPATIBILITY.md).

Carrier simulation is opt-in. The legacy single-network behavior remains active
when `Config.Features.Carriers` is `false`.

## Enable operators

```lua
Config.Features.Carriers = true
Config.Carriers = {
    {
        id = 'carrier_a',
        name = 'Carrier A',
        technologies = { '4G', '5G' },
        roamingPartners = { 'carrier_b' },
        priority = 20,
        branding = { color = '#2d7ff9' },
    },
    {
        id = 'carrier_b',
        name = 'Carrier B',
        technologies = { '4G' },
        roamingPartners = { 'carrier_a' },
        priority = 10,
    },
}
```

Towers and sectors may restrict the effective operator pool with a `carriers`
array. If a tower does not declare a pool, all registered carriers are eligible.
An empty sector declaration inherits its tower pool. Unknown declarations are
validated at startup and an invalid-only declaration falls back to the global
registered pool for runtime resilience.

## Subscribers and roaming

```lua
SubscriberRegistry.Set(source, {
    playerId = 'license:example',
    simId = 'sim-1001',
    carrierId = 'carrier_a',
    roamingAllowed = true,
    serviceClass = 'standard',
})
```

The subscriber's home carrier is selected when it is available on the current
candidate. If the home carrier is unavailable, the selector checks the home's
registered `roamingPartners` and chooses the highest-priority compatible partner
with deterministic ID tie-breaking. `roamingAllowed = false` prevents that
fallback. A subscriber without a record follows the normal carrier selection
path.

`SubscriberRegistry.Get(source)` returns the active session record. A
`playerDropped` event removes the active source binding; the durable SIM record
is retained for a later stable-identity rebind. Use
`SubscriberRegistry.Delete(sourceOrPlayerId)` when the durable record must also
be removed.

## Persistence and NOC

When `Config.Persistence.enabled` is enabled, subscriber records are stored in
`telecom_subscribers` and restored after restart. The schema version is now 2;
the migration creates the table idempotently. The NOC exposes active subscriber
entities with home/current carrier, roaming state, SIM, and service class
metadata when the carrier feature is enabled.

Carrier availability changes trigger connection reevaluation, so active
subscribers move between home and partner networks without waiting for the next
position update.
