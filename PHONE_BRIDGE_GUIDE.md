# Phone bridge guide

Phone resources are consumers, not dependencies. Use the public API documented in [API.md](API.md) or the existing adapters documented in [BRIDGES.md](BRIDGES.md).

Recommended integration flow:

1. Query `GetNetworkState(source)` when the phone opens.
2. Use `CanStartCall`, `CanSendPhoneSMS` or `CanUsePhoneData` when the selected phone provider must participate in the gate; use `CanCall`, `CanSendSMS`, `HasDataConnection` or `CanUseService` for core network policy only.
3. Subscribe to `gnsh-telecom:serviceChanged`, `gnsh-telecom:towerChanged` and `gnsh-telecom:signalLevelChanged` for UI updates.
4. Treat the returned state as a defensive snapshot and re-query before important actions.

Inspect `GetPhoneBridgeStatus()` before presenting provider-specific controls. `FULL`, `FUNCTIONAL` and `DISPLAY` are capability claims, not guesses based only on resource detection. A `DISPLAY` provider may deliberately reject a call, SMS or data gate with `provider_gate_unsupported`.

Do not calculate distance, select towers or read the persistence layer from the phone resource.
