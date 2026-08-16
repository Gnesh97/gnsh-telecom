# Phone bridge guide

Phone resources are consumers, not dependencies. Use the public API documented in [API.md](API.md) or the existing adapters documented in [BRIDGES.md](BRIDGES.md).

Recommended integration flow:

1. Query `GetNetworkState(source)` when the phone opens.
2. Use `CanCall`, `CanSendSMS`, `HasDataConnection` or `CanUseService` before the operation.
3. Subscribe to `gnsh-telecom:serviceChanged`, `gnsh-telecom:towerChanged` and `gnsh-telecom:signalLevelChanged` for UI updates.
4. Treat the returned state as a defensive snapshot and re-query before important actions.

Do not calculate distance, select towers or read the persistence layer from the phone resource.
