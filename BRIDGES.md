# Phone bridges

Phone bridges are optional adapters around the public `gnsh-telecom` API. Telecom core never imports phone resources and does not require a phone resource to start.

## Central bridge platform

All integration categories are registered through the central platform: `framework`, `inventory`, `target`, `dispatch` and `phone`. Providers declare a name, category, priority, optional resources, capabilities and lifecycle methods (`Detect`, `Initialize`, `Shutdown`, `HealthCheck`). Selection is deterministic by priority and provider name, with safe fallback when detection, initialization or health checks fail.

Consumers can inspect the platform through the public exports:

```lua
local all = exports['gnsh-telecom']:GetBridgeStatus()
local phone = exports['gnsh-telecom']:GetBridgeStatus('phone')
local capabilities = exports['gnsh-telecom']:GetBridgeCapabilities('phone')
```

Provider start/stop events trigger lifecycle reconciliation. Missing optional providers report `OPTIONAL`; a provider exception is isolated and reported as `FAILED` without stopping the telecom core.

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
bridge:CanSendSMS(source)
bridge:HasDataConnection(source)
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
