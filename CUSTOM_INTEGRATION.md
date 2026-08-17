# Custom integration

Consume telecom through public exports and server events. Do not access `Connections`, `TowerState`, `FailureEngine` or internal tower tables from another resource.

```lua
local available, service = exports['gnsh-telecom']:CanUseService(source, 'data')
local state = exports['gnsh-telecom']:GetNetworkState(source)
```

The optional framework, inventory, target and dispatch bridges expose adapter setters. A custom integration should fail gracefully when its dependency is absent and should never let a client choose a final telecom state.

## Custom Bridge SDK

Unsupported resources can register a provider at runtime without changing Telecom Core. The SDK is available from the server side after `gnsh-telecom` starts:

```lua
local ok, registration = exports['gnsh-telecom']:RegisterBridge('phone', {
    name = 'my-phone',
    resources = { 'my-phone-resource' },
    priority = 500,
    capabilities = { 'GetNetworkState' },
    Detect = function(self)
        return GetResourceState(self.resources[1]) == 'started'
    end,
    GetNetworkState = function(_, source)
        return MyPhone.GetNetworkState(source)
    end,
})
```

The supported categories are `framework`, `inventory`, `target`, `phone`, `dispatch`, `notify` and `progress`. Lifecycle callbacks are optional and protected by the SDK. Core bridge methods receive the provider as their first argument; `notify.Notify` and `progress.StartProgress` use their existing payload signatures.

Registration is accepted only from a valid, started invoking resource. Provider names are bounded identifiers, capabilities are normalized and must have function callbacks, and duplicate names—including built-in providers—are rejected. Registration activates the provider by default; pass `activate = false` to defer selection. A failed detection or health check leaves the provider registered and reports its unavailable/failed state rather than trusting an unvalidated callback result.

Only the resource that registered a provider can remove it:

```lua
local removed, errorMessage = exports['gnsh-telecom']:UnregisterBridge(
    'phone',
    'my-phone'
)
```

Use the read-only reporting exports to inspect ownership, lifecycle state and normalized capabilities without receiving provider callback functions:

```lua
local one = exports['gnsh-telecom']:GetBridgeRegistration('phone', 'my-phone')
local all = exports['gnsh-telecom']:GetBridgeRegistrations()
local status = exports['gnsh-telecom']:GetBridgeStatus('phone')
local capabilities = exports['gnsh-telecom']:GetBridgeCapabilities('phone')
```

When the owner resource stops, all of its SDK registrations are safely deregistered and active providers are shut down. Provider callbacks are isolated with protected calls; they must not mutate Telecom Core state, trust client-supplied final outcomes, or return unbounded/unvalidated data. See [`examples/custom_bridge.lua`](examples/custom_bridge.lua) for a complete external-resource template.
