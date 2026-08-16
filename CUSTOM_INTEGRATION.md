# Custom integration

Consume telecom through public exports and server events. Do not access `Connections`, `TowerState`, `FailureEngine` or internal tower tables from another resource.

```lua
local available, service = exports['gnsh-telecom']:CanUseService(source, 'data')
local state = exports['gnsh-telecom']:GetNetworkState(source)
```

The optional framework, inventory, target and dispatch bridges expose adapter setters. A custom integration should fail gracefully when its dependency is absent and should never let a client choose a final telecom state.
