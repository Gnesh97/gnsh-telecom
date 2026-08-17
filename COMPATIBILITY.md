# Universal Compatibility Matrix

Date of this evidence packet: 2026-08-17

## Certification status

The compatibility specs run the production bridge contracts with deterministic
pure-Lua provider doubles. This workspace has no running FiveM server and no
connected clients, so live provider versions, resource startup order, and
restart behavior were not captured.

Accordingly, every row below is intentionally `EXPERIMENTAL`. No provider is
marked `SUPPORTED` or `FULLY SUPPORTED` from detection or synthetic tests.

Allowed matrix labels are exactly:

`FULLY SUPPORTED`, `SUPPORTED`, `PARTIAL`, `EXPERIMENTAL`, `UNSUPPORTED`

## Matrix

| Runtime combination | Label | Provider/resource set | Result |
| --- | --- | --- | --- |
| Standalone + no phone | EXPERIMENTAL | `standalone`; no phone resource | Contract fallback passes; live certification pending |
| QBCore + phone + inventory + target | EXPERIMENTAL | `qb-core`, `lb-phone`, `qb-inventory`, `qb-target` | Contract adapters resolve; live certification pending |
| Qbox + phone + inventory + target | EXPERIMENTAL | `qbx_core`, `npwd`, `ox_inventory`, `ox_target` | Contract adapters resolve; live certification pending |
| ESX + phone + inventory + target | EXPERIMENTAL | `es_extended`, `qs-smartphone`, `ox_inventory`, `ox_target` | Contract adapters resolve; live certification pending |
| Phone starts after telecom | EXPERIMENTAL | `lb-phone` | Generic fallback reconciles to the phone adapter in the contract harness |
| Phone stops while telecom runs | EXPERIMENTAL | `lb-phone` | Active adapter returns to generic in the contract harness |
| Inventory restart | EXPERIMENTAL | `qb-inventory` / `ox_inventory` | Central lifecycle path is exercised; live restart pending |
| Target restart | EXPERIMENTAL | `qb-target` / `ox_target` | Central lifecycle path is exercised; live restart pending |
| Framework restart | EXPERIMENTAL | `qb-core` / `qbx_core` / `es_extended` | Re-selection path is exercised; live restart pending |
| Notify restart | EXPERIMENTAL | `ox_lib` | Native presentation fallback is exercised; live restart pending |
| Progress restart | EXPERIMENTAL | `ox_lib` | Native presentation fallback is exercised; live restart pending |
| LB Phone provider contract | EXPERIMENTAL | `lb-phone` / `lbphone` | Functional capability contract is exercised; live provider evidence pending |
| NPWD provider contract | EXPERIMENTAL | `npwd` | Functional capability contract is exercised; live provider evidence pending |
| QS provider contract | EXPERIMENTAL | `qs-smartphone` / `qs` | Display-only downgrade contract is exercised; live provider evidence pending |

## Evidence records

Every record was produced by `tests/compat/*.lua` and loaded by
`tests/run.lua`. The final runner, including the release gate, completed with
323 passed and 0 failed.

| Record | Provider version | Test date | Capabilities verified | Capabilities unavailable |
| --- | --- | --- | --- | --- |
| Standalone + no phone | NOT CAPTURED | 2026-08-17 | Standalone fallback, generic phone fallback, core API availability | Live FiveM runtime |
| QBCore combination | NOT CAPTURED | 2026-08-17 | Framework contract, `qb` inventory/target registration, phone registration | Live exports, startup order, connected client |
| Qbox combination | NOT CAPTURED | 2026-08-17 | Framework contract, `ox` inventory/target registration, phone registration | Live exports, startup order, connected client |
| ESX combination | NOT CAPTURED | 2026-08-17 | Framework contract, inventory/target registration, phone registration | Live exports, startup order, connected client |
| Phone start/stop | NOT CAPTURED | 2026-08-17 | Generic fallback and provider reconciliation | Live resource restart and client state |
| Inventory/target/framework restarts | NOT CAPTURED | 2026-08-17 | Central lifecycle reconciliation and safe re-selection path | Live resource restart and provider exports |
| Notify/progress restarts | NOT CAPTURED | 2026-08-17 | Native presentation fallback | Live `ox_lib` restart and client rendering |
| LB Phone | NOT CAPTURED | 2026-08-17 | Signal UI and call/SMS/data gate contract | Live LB Phone exports and lifecycle |
| NPWD | NOT CAPTURED | 2026-08-17 | Signal UI and documented busy-call gate contract | Live NPWD exports and lifecycle |
| QS Smartphone | NOT CAPTURED | 2026-08-17 | Signal UI and display-only downgrade | Live QS Smartphone exports and lifecycle |

For each record, the result is “contract checks pass; live certification
pending” and the limitation is that resource state and exports were represented
by pure-Lua test doubles. Detection is not treated as support evidence.

## Live-runtime promotion gate

To promote a row to `SUPPORTED`, record all of the following in a new evidence
packet:

1. Framework, phone, inventory, target, notify, and progress resource names and
   exact versions.
2. A real FiveM server run with connected clients and the actual resource load
   order.
3. The required startup and restart sequences, including phone-after-telecom,
   phone stop, inventory, target, framework, notify, and progress restarts.
4. Capabilities that passed, capabilities that were unavailable, observable
   failures, and known limitations.
5. Logs or repeatable runtime test output tied to the provider/version record.

`FULLY SUPPORTED` additionally requires live evidence for every declared
capability of the provider. Until then, compatibility documentation must retain
the `EXPERIMENTAL` label.

## Commands

```text
lua tests/run.lua
```

The compatibility files are:

- `tests/compat/standalone_spec.lua`
- `tests/compat/qbcore_spec.lua`
- `tests/compat/qbox_spec.lua`
- `tests/compat/esx_spec.lua`
- `tests/compat/phone_spec.lua`
- `tests/compat/provider_lifecycle_spec.lua`
