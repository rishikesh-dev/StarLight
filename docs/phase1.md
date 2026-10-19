# Phase 1 — Foundation

Status: **complete**. Flutter `analyze` clean, 54 Flutter tests passing,
129 Python tests passing.

## What Phase 1 was for

Audit the existing Flutter + Python monorepo, make the MR Star lighting
control flow work end to end, define the universal device/capability model
and the shared command/event contracts, and fix all compile/runtime errors —
so Phases 2–6 build on a working base.

## Audit findings (starting state)

- **Flutter**: 115 analyzer issues, 78 of them compile errors. Four dead
  duplicate adapter files that could not compile. Pages wired to missing
  routes/blocs; several pages rendered hardcoded fake data.
- **Python**: `core/app/main.py` had an `IndentationError` (lights router
  never mounted), `core/app/api/jarvis.py` called methods that did not exist
  (`set_power`, `set_color_hex`), pytest collection failed. No test for the
  JARVIS surface.
- **Contracts**: no shared command/result type — repositories threw on
  failure; no event stream for connection/state changes.
- **BLE ownership**: `StarLightBleAdapter` and `BleDataSource` both opened
  sessions; nothing guaranteed a single connection per device.

## Architecture decisions

### Single BLE ownership

`BleDataSource` (`lib/data/datasources/ble_datasource.dart`) is the **only**
component that touches a BLE session. Its connection/notification stream
controllers are app-lifetime broadcast controllers: subscribers may register
before any connect; `disconnect()` emits `disconnected` but does not close
them; only the scan controller closes.

`StarLightBleAdapter` was rewritten as a thin translation layer: it turns
`DeviceCommand`s into MR Star packets and delegates all actual I/O to an
injected shared `BleDataSource`. `app.dart` (composition root) creates one
`BleDataSource` and injects it into both `BleRepositoryImpl` and the adapter,
so the app can never hold two sessions to the same peripheral.

### Command contract

`DeviceRepository.executeCommand(DeviceCommand)` returns a `CommandResult`
(success flag + error code + message). Expected failures — `device_not_found`,
`not_connected`, `no_adapter`, `unsupported_command`, `transport_error` — are
**returned**, never thrown. Callers (blocs, pages) surface failures explicitly;
nothing silently claims success.

### Event contract

`DeviceRepository.events` is a `Stream<DeviceEvent>` with
`DeviceEventKind` = `connected` / `disconnected` / `stateChanged`.
`DeviceRepositoryImpl` guarantees exactly one `disconnected` event per
disconnect, even if the adapter stays silent. `LightBloc` consumes
`ConnectionChanged` events to propagate link state to the UI, and cancels
its subscription in `close()`.

### Device/capability model

- `Device` carries a capability list; the MR Star is registered with
  `["power", "brightness", "color", "speed"]`.
- `effect` and `colorTemperature` are **deliberately omitted**: not verified
  against hardware. Unverified capabilities are never advertised.
- JARVIS (`core/app/api/jarvis.py`) advertises the same verified set;
  scenes/automations return empty lists (never invented data), and scene
  activation returns `not_implemented`.

### UI honesty

- Automations page: "add" button shows a SnackBar ("coming in Phase 5")
  instead of pushing a missing route; the enable/disable switch is disabled
  until the automation engine exists.
- Home page: static "Scenes" section renamed to "Color Presets" (it lists
  presets); preset chips are tappable (`SelectPreset`); "Add Device" navigates
  to `/add-device`.
- Scenes page is bloc-driven with real activation results and delete
  confirmation.

## Deleted code

Four dead, uncompilable duplicate adapter files removed (ESP32 adapters will
be rebuilt cleanly in Phase 4):

- `lib/data/adapters/esp32_adapter.dart`
- `lib/data/adapters/protocol_adapter.dart`
- `lib/domain/adapters/protocol_adapter.dart`
- `lib/domain/adapters/esp32_adapter.dart`

`lib/domain/adapters/device_adapter.dart` is **THE** adapter interface.

## Key files

| Area | File |
| --- | --- |
| Composition root | `lib/app.dart` |
| BLE session owner | `lib/data/datasources/ble_datasource.dart` |
| Command→packet translation | `lib/data/adapters/starlight_ble_adapter.dart` |
| Registry, CommandResult, events | `lib/data/repositories/device_repository_impl.dart` |
| Command contract | `lib/domain/repositories/device_repository.dart` |
| Event contract | `lib/domain/entities/device_event.dart` |
| Connect/persist/registry wiring | `lib/presentation/bloc/ble/ble_bloc.dart` |
| Connection propagation | `lib/presentation/bloc/light/light_bloc.dart` |
| JARVIS surface (Python) | `core/app/api/jarvis.py` |
| Contract tests | `test/device_repository_test.dart`, `test/light_bloc_test.dart` |

## Test coverage added

- `test/device_repository_test.dart` — command contract (explicit failures,
  no throw), event contract (single disconnect event), persistence round-trip.
- `test/light_bloc_test.dart` — connection propagation, failure surfacing as
  `LightError`, preset loading.
- `core/tests/test_jarvis.py` — JARVIS capability advertisement and explicit
  failure shapes.

## Known follow-ups (intentional, documented in code)

1. **Startup auto-connect** not implemented — permission timing needs a user
   flow first.
2. `DeviceRepositoryImpl.hasPermissions` / `requestPermissions` / `stopScan`
   are TODO stubs (return `true` / no-op) — real permission handling is
   platform-specific and deferred.
3. `_effectNameToModeId` map is unverified against hardware — effect names
   must not be advertised until checked (Phase 2+).
4. Home "Favorites" section is still a static placeholder — becomes
   registry-driven in Phase 3.
5. `flutter run` / on-hardware verification of the full MR Star flow is a
   Phase 2 item (BLE needs a physical device).

## Verification commands

```bash
export PATH="$HOME/Documents/flutter/bin:$PATH"
flutter analyze          # No issues found!
flutter test             # 54 tests passed

cd core && .venv/bin/python -m pytest -q   # 129 passed
```
