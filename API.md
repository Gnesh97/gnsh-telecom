# gnsh-telecom Public API

Schema version: `1.0` (`Constants.ApiVersion`). API is server-side, framework-independent and safe to use without a phone resource.

## Exports

Call exports from another resource with:

```lua
local strength = exports['gnsh-telecom']:GetSignalStrength(source)
```

All exports accept a player `source` unless noted otherwise.

| Export | Return | No connection / invalid source |
| --- | --- | --- |
| `HasSignal(source)` | `boolean` | `false` |
| `GetSignalStrength(source)` | signal number `0..100` | `0` |
| `GetSignalLevel(source)` | signal level string | `NO_SERVICE` |
| `GetNetworkType(source)` | technology string or `nil` | `nil` |
| `GetConnectedTower(source)` | tower ID string or `nil` | `nil` |
| `GetNetworkState(source)` | defensive state table or `nil` | `nil` |
| `CanCall(source)` | `available, serviceState` | `false, serviceState` |
| `CanSendSMS(source)` | `available, serviceState` | `false, serviceState` |
| `HasDataConnection(source)` | `available, serviceState` | `false, serviceState` |
| `CanUseService(source, service)` | `available, serviceState` | `false, serviceState` |
| `CanStartCall(source)` | selected phone provider gate, `available, serviceState` | `false, serviceState` |
| `CanSendPhoneSMS(source)` | selected phone provider SMS gate, `available, serviceState` | `false, serviceState` |
| `CanUsePhoneData(source)` | selected phone provider data gate, `available, serviceState` | `false, serviceState` |
| `GetPhoneNetworkState(source)` | selected phone provider network snapshot | `nil` |
| `GetPhoneBridgeStatus()` | selected phone provider and support level | display status |
| `GetTowerState(towerId)` | defensive tower runtime state or `nil` | `nil` |
| `GetIncidentSnapshot()` | incident list and status counts | empty snapshot |
| `GetBackhaulStatus(towerId)` | `ONLINE`, `DEGRADED` or `OFFLINE` | `ONLINE` when the optional graph is disabled |
| `GetStatistics()` | defensive aggregate telemetry snapshot | `{ enabled = false }` |
| `GetBridgeStatus([category])` | defensive bridge status map or category status | optional categories report `OPTIONAL` |
| `GetBridgeCapabilities(category)` | normalized capability map for the active provider | `{}` when unavailable |

`serviceState` includes `available`, `reason` and `blockedBy` when available. Typical fallback reasons:

- `player_not_connected` — no current connection state.
- `unknown_service` — service name is not configured.
- `connection_unavailable` — connection manager is unavailable.

`GetNetworkState` returns a copy, never the internal connection table. It includes `apiVersion` and may include `towerId`, `signal`, `rawSignal`, `signalLevel`, `technology`, `services`, `congestion`, capacity fields and environment metadata.

## Integration events

Events are emitted server-side when connection state changes. Subscribe with `AddEventHandler`:

```lua
AddEventHandler('gnsh-telecom:towerChanged', function(source, current, previous)
    -- update dependent resource state
end)
```

Event names:

- `gnsh-telecom:connectionChanged`
- `gnsh-telecom:signalChanged`
- `gnsh-telecom:signalLevelChanged`
- `gnsh-telecom:towerChanged`
- `gnsh-telecom:networkTypeChanged`
- `gnsh-telecom:serviceChanged`
- `gnsh-telecom:handover`
- `gnsh-telecom:incidentChanged`

Every event receives `source`, `current` and `previous`. Payload tables are defensive copies. `current` is `nil` after disconnect; `previous` is `nil` on the first connection. Specific events fire only when their corresponding field changes.

`gnsh-telecom:handover` is emitted when a connected player moves from one serving tower to another after handover hysteresis. `gnsh-telecom:incidentChanged` is emitted with the tower ID as the first argument and incident snapshots as the second and third arguments. These optional events are silent when their feature is disabled.

Core state remains server-authoritative. Consumers must treat event payloads as snapshots and use exports for current queries.

Bridge status is grouped by `framework`, `inventory`, `target`, `dispatch` and `phone`. A category status reports the active provider, health state, initialized/available flags, provider priorities and normalized capabilities. Phone status additionally reports `supportLevel` (`FULL`, `FUNCTIONAL` or `DISPLAY`) and a `support` map. Provider failures are isolated and do not stop the telecom core.

Presentation and dispatch helpers are exposed through provider-neutral bridge calls rather than core state exports:

```lua
NotifyBridge.Notify(source, kind, message, data)
ProgressBridge.StartProgress(source, action, durationMs, options)
DispatchBridge.CreateAlert(data)
```

Notify and progress inputs are bounded and copied. Progress only tells the client what to display; server-side sessions, timers and completion checks remain authoritative. Dispatch is optional and safely returns `false, 'dispatch_adapter_unavailable'` when no provider is configured. `DispatchBridge.Alert(data)` remains a backwards-compatible alias.
