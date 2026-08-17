# Bridge integrations

Phone bridges are optional adapters around the public `gnsh-telecom` API. Telecom core never imports phone resources and does not require a phone resource to start.

## Central bridge platform

All core integration categories are registered through the central platform: `framework`, `inventory`, `target`, `dispatch` and `phone`. Providers declare a name, category, priority, optional resources, capabilities and lifecycle methods (`Detect`, `Initialize`, `Shutdown`, `HealthCheck`). Selection is deterministic by priority and provider name, with safe fallback when detection, initialization or health checks fail. Notify and progress are lightweight support registries because they are presentation helpers rather than gameplay state providers. The `Config.Bridges` table controls provider preferences, fallbacks and required integrations without changing the provider contracts.

Consumers can inspect the platform through the public exports:

```lua
local all = exports['gnsh-telecom']:GetBridgeStatus()
local phone = exports['gnsh-telecom']:GetBridgeStatus('phone')
local capabilities = exports['gnsh-telecom']:GetBridgeCapabilities('phone')
```

Provider start/stop events trigger lifecycle reconciliation. Missing optional providers report `OPTIONAL`; a provider exception is isolated and reported as `FAILED` without stopping the telecom core.

## Bridge configuration and health

Configure all integration categories from one table:

```lua
Config.Bridges = {
    Framework = { provider = 'auto', fallback = 'standalone' },
    Inventory = { provider = 'auto', required = false },
    Target = { provider = 'auto', fallback = 'native' },
    Phone = { provider = 'auto', requireEnforcement = false },
    Dispatch = { provider = 'auto', required = false },
    Notify = { provider = 'auto', fallback = 'native' },
    Progress = { provider = 'auto', fallback = 'native' },
}
```

`provider = 'auto'` preserves deterministic provider priority. An explicit provider is tried first, then its configured fallback. When a legacy field such as `Config.Framework` or `Config.InventoryBridge` is explicitly set, it remains effective while the corresponding bridge-table provider is `auto`; an explicit `Config.Bridges` provider takes precedence. `required = true` prevents startup when that category has no healthy provider. Phone integrations can use `requireEnforcement = true` to require a `FULL` or `FUNCTIONAL` support level. Optional categories report `OPTIONAL` and do not stop telecom core.

At startup the server logs an integration summary such as:

```text
Integration Summary
Framework : QBCore ACTIVE
Phone     : generic ACTIVE
Compatibility : OK
```

The same data is available through `BridgeManager.GetIntegrationSummary()`, including per-category provider, state, fallback and capability information. `GetBridgeStatus()` also exposes the selected configuration and whether a fallback was used.

## Notify, progress and dispatch support bridges

Support calls use a provider-neutral contract:

```lua
NotifyBridge.Notify(source, kind, message, data)
ProgressBridge.StartProgress(source, action, durationMs, options)
DispatchBridge.CreateAlert(data)
```

`kind` is one of `info`, `success`, `warning` or `error`. Payloads are copied and bounded at the bridge boundary. Notify and progress provider exceptions fall back to the native provider when possible. The native notify provider emits the resource client event and displays through the standard `chat:addMessage` event; the native progress provider emits the standard `progress` event.

Progress is presentation-only. `StartProgress` never creates a server timer or accepts a client completion signal. Server workflows must keep ownership of duration, cancellation and completion validation.

Notify and progress selection is automatic and can be made explicit:

```lua
Config.Bridges.Notify.provider = 'auto'       -- auto, ox, framework or native
Config.Bridges.Progress.provider = 'auto'     -- auto, ox or native
```

The legacy `Config.NotifyBridge` and `Config.ProgressBridge` fields remain supported for compatibility. The Ox provider uses the documented `lib.notify`, `lib.progressBar` and `lib.progressCircle` entry points. Server requests are routed through resource-owned client events so a missing or failing Ox client can fall back to native presentation. Dispatch remains optional: no provider is installed by default, while native and custom adapters can be selected explicitly.

Custom dispatch can be configured before startup or installed at runtime:

```lua
Config.CustomDispatch = {
    name = 'my-dispatch',
    CreateAlert = function(data)
        return MyDispatch.CreateAlert(data)
    end,
}
-- Or: DispatchBridge.SetCustomAdapter(Config.CustomDispatch)
```

When the central table selects this adapter explicitly, set
`Config.Bridges.Dispatch.provider` to the adapter `name` (the default is
`custom-dispatch`).

`DispatchBridge.Alert(data)` remains available for existing integrations and delegates to `CreateAlert` when that is the only method supplied.

## Framework bridges

Framework selection is automatic by default and supports standalone, QBCore, Qbox, ESX and custom providers:

```lua
Config.Framework = 'auto'
-- explicit values: standalone, qbcore, qbox, esx or custom
```

Every framework bridge exposes the same server-side contract:

```lua
FrameworkBridge.GetPlayer(source)
FrameworkBridge.GetStablePlayerId(source)
FrameworkBridge.GetJob(source)
FrameworkBridge.HasJob(source, jobs)
FrameworkBridge.IsAdmin(source)
FrameworkBridge.GetCharacterName(source)
FrameworkBridge.AddMoney(source, account, amount)       -- optional
FrameworkBridge.RemoveMoney(source, account, amount)    -- optional
```

Telecom Core does not require money capabilities. Missing players, exports or optional methods fail closed and do not stop the resource. Framework resource start/stop events trigger provider reconciliation.

Custom frameworks can provide functions through configuration before the resource starts:

```lua
Config.Framework = 'custom'
Config.CustomFramework = {
    GetPlayer = function(source) return MyFramework.GetPlayer(source) end,
    GetStablePlayerId = function(source) return MyFramework.GetIdentifier(source) end,
    GetJob = function(source) return MyFramework.GetJob(source) end,
    HasJob = function(source, jobs) return MyFramework.HasJob(source, jobs) end,
    IsAdmin = function(source) return MyFramework.IsAdmin(source) end,
    GetCharacterName = function(source) return MyFramework.GetName(source) end,
    -- AddMoney / RemoveMoney are optional.
}
```

Custom callbacks are isolated with protected calls. They must return validated server-side values; client input must never decide permission, identity or money outcomes.

## Inventory bridges

Inventory selection is automatic by default and supports standalone, `ox_inventory`, `qb-inventory`, `qs-inventory` and custom providers:

```lua
Config.InventoryBridge = 'auto'
-- explicit values: standalone, ox, qb, qs or custom
```

The server-side inventory contract is:

```lua
InventoryBridge.HasItem(source, item, amount)
InventoryBridge.RemoveItem(source, item, amount)
InventoryBridge.AddItem(source, item, amount, metadata)
InventoryBridge.CanCarry(source, item, amount)
InventoryBridge.GetItemCount(source, item)
```

Item-free actions continue without an inventory provider. Item-required actions fail closed, and destructive operations require an explicit provider success result. Technician repairs and sabotage consume items only on the server; repair rollback refunds through the same provider contract.

Custom inventory callbacks can be configured before the resource starts:

```lua
Config.InventoryBridge = 'custom'
Config.CustomInventory = {
    HasItem = function(source, item, amount) return MyInventory:HasItem(source, item, amount) end,
    RemoveItem = function(source, item, amount, metadata) return MyInventory:RemoveItem(source, item, amount, metadata) end,
    AddItem = function(source, item, amount, metadata) return MyInventory:AddItem(source, item, amount, metadata) end,
    CanCarry = function(source, item, amount) return MyInventory:CanCarry(source, item, amount) end,
    GetItemCount = function(source, item) return MyInventory:GetCount(source, item) end,
}
```

## Target and native interaction bridges

Target interactions are optional. The bridge selects `ox_target`, `qb-target`, a configured custom adapter, or the native prompt/key fallback:

```lua
Config.TargetBridge = 'auto'
-- explicit values: native, ox, qb or custom
```

The provider-neutral client contract is:

```lua
TargetBridge.AddEntityInteraction(id, entity, options)
TargetBridge.AddModelInteraction(id, models, options)
TargetBridge.AddZoneInteraction(id, zone, options)
TargetBridge.RemoveInteraction(id, handle)
```

`options` contains intent callbacks such as `onSelect`; callbacks may submit a bounded request, but they must not decide tower state, permissions, incidents, sessions or inventory outcomes. The server validates the source, tower record, player distance, technician job/permission, incident assignment and session state before changing gameplay. When no target resource is available, the native provider uses the configured distance, prompt and key fields and invokes the same client intent callback.

Custom target adapters can be configured before startup:

```lua
Config.TargetBridge = 'custom'
Config.CustomTarget = {
    AddEntityInteraction = function(id, entity, options)
        return MyTarget:AddEntity(id, options)
    end,
    AddModelInteraction = function(id, models, options)
        return MyTarget:AddModels(models, options)
    end,
    AddZoneInteraction = function(id, zone, options)
        return MyTarget:AddZone(id, zone, options)
    end,
    RemoveInteraction = function(id, handle)
        return MyTarget:Remove(id, handle)
    end,
}
```

## Configuration

Use automatic detection by default:

```lua
Config.PhoneBridge = 'auto'
```

Supported explicit values:

```lua
Config.PhoneBridge = 'generic'
Config.PhoneBridge = 'lbphone'
Config.PhoneBridge = 'npwd'
Config.PhoneBridge = 'qs'
Config.PhoneBridge = 'custom'
```

Automatic detection checks started resources in this order: LB Phone, NPWD, QS Smartphone. If no resource is available, generic is selected. Missing or failed adapters never stop telecom core.

Detection is re-evaluated when a supported phone resource starts or stops, so the telecom resource may be started before the phone resource. Stopping an active phone dependency safely returns the active adapter to generic.

## Phone enforcement support levels

Phone providers report an honest support level and capability map through `PhoneBridges.GetStatus()` and `GetPhoneBridgeStatus()`:

| Level | Meaning |
| --- | --- |
| `FULL` | signal UI, call/SMS/data gates, call lifecycle and network-change hooks are all integrated |
| `FUNCTIONAL` | signal UI and call/SMS/data gates are integrated; provider lifecycle remains outside this resource |
| `DISPLAY` | signal UI/network state can be displayed, but unsupported provider operations fail closed |

The current providers are intentionally conservative:

- `generic`: `FUNCTIONAL`; uses the server-authoritative telecom service policy.
- `lbphone`: `FUNCTIONAL`; adds documented phone-item and busy-call checks, and maps connection changes to LB service bars on the client.
- `npwd`: `FUNCTIONAL` on the server; uses the documented busy-player export in addition to telecom service gates.
- `qs`: `DISPLAY`; stable generic call/SMS interception surfaces are not assumed, so its provider gates return `provider_gate_unsupported` rather than pretending to enforce them.

The adapters call documented provider exports only. They do not monkey-patch phone internals, rewrite provider databases or change third-party resources. `CanCall`/`CanSendSMS`/`HasDataConnection` remain core network-policy queries; the provider-aware exports are `CanStartCall`, `CanSendPhoneSMS` and `CanUsePhoneData`.

## Bridge interface

Every adapter exposes these methods:

```lua
bridge:HasSignal(source)
bridge:GetSignalStrength(source)
bridge:GetSignalLevel(source)
bridge:GetNetworkType(source)
bridge:GetConnectedTower(source)
bridge:GetNetworkState(source)
bridge:CanCall(source)
bridge:CanStartCall(source)
bridge:CanSendSMS(source)
bridge:HasDataConnection(source)
bridge:CanUseData(source)
bridge:CanUseService(source, service)
```

Methods delegate to public telecom exports. Adapters must not access `Connections`, `Services`, tower runtime state or signal internals directly.

## Custom adapter

Create a custom adapter in a local bridge file loaded after the generic bridge. Register it with the bridge registry:

```lua
local adapter = PhoneBridges.CreateResourceAdapter('myphone', { 'my-phone' })
PhoneBridges.Register(adapter)
```

Custom adapters should override only integration-specific detection or lifecycle behavior. Use the public API returned by `PhoneBridges.GetTelecomAPI()` for network decisions. Do not calculate signal or service policy inside the phone adapter.

A separate phone resource should consume the public exports documented in [API.md](API.md) directly instead of accessing the internal bridge registry.

If a custom adapter is selected explicitly, it must return `true` from `Initialize()` after its dependency is available. Returning `false` or throwing an error causes a safe generic fallback and an integration-specific server log.
