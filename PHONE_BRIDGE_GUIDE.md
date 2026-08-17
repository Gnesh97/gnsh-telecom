# Phone bridge guide

Phone resources are consumers, not dependencies. Use the public API documented in [API.md](API.md) or the existing adapters documented in [BRIDGES.md](BRIDGES.md). The dated compatibility evidence and promotion rules are in [COMPATIBILITY.md](COMPATIBILITY.md).

The phone adapter tests validate provider contracts with pure-Lua doubles. A
detected resource, a registered adapter, or a passing contract test is not live
runtime support evidence. Until a real FiveM run records the provider version,
resource lifecycle, connected clients, capabilities, and limitations, the
matrix status remains `EXPERIMENTAL`.

Recommended integration flow:

1. Query `GetNetworkState(source)` when the phone opens.
2. Use `CanStartCall`, `CanSendPhoneSMS` or `CanUsePhoneData` when the selected phone provider must participate in the gate; use `CanCall`, `CanSendSMS`, `HasDataConnection` or `CanUseService` for core network policy only.
3. Subscribe to `gnsh-telecom:serviceChanged`, `gnsh-telecom:towerChanged` and `gnsh-telecom:signalLevelChanged` for UI updates.
4. Treat the returned state as a defensive snapshot and re-query before important actions.

Inspect `GetPhoneBridgeStatus()` before presenting provider-specific controls. `FULL`, `FUNCTIONAL` and `DISPLAY` are internal adapter capability levels, not universal compatibility labels and not guesses based only on resource detection. A `DISPLAY` provider may deliberately reject a call, SMS or data gate with `provider_gate_unsupported`.

Do not calculate distance, select towers or read the persistence layer from the phone resource.
