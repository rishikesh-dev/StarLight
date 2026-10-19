# StarLight

StarLight is a Flutter application for controlling MR Star Bluetooth LE LED strip controllers. It replaces the vendor app with a clean, open-source alternative that respects user privacy, requires no cloud account, and works entirely offline over Bluetooth Low Energy (BLE).

## Problem

The stock MR Star app requires an account, communicates with cloud services, and offers no transparency about the BLE protocol. StarLight provides a local-first controller that:

- Pairs and communicates directly with the MR Star controller over BLE (GATT service `FFF0`, write `FFF3`, notify `FFF4`)
- Exposes the full feature set the hardware protocol supports: power, brightness, colour (HSV), and the controller's built-in effect modes
- Adds StarLight's own algorithmic effects (custom effects) that stream colours over the same BLE link
- Supports device profiles so the same app can drive other BLE controllers without recompilation
- Organises devices into rooms, groups, and scenes — all persisted locally

## Current Capabilities

### Implemented and Tested
- **BLE pairing and connection** — Scan, pair, reconnect, forget; handles Android/iOS permission flows and adapter state
- **Core light controls** — Power, brightness (0–1000), colour via HSV derived from RGB (matching the vendor APK's conversion)
- **Device-native effects** — 11 MR Star controller modes (Solid, Rainbow, Fireworks, Breath, Scan, Flash, Police, Chase, Comet, Lava, Ocean) selected by mode ID; speed control (0–100 app range, byte field 0–255 on the wire)
- **Custom effects** — 9 StarLight algorithms (Aurora, Ember, Ocean Drift, Meteor, Prism Flow, Soft Breath, Color Bloom, Starlight) rendered in-app and streamed as global colours where the transport supports `DeviceCapability.color`; two effects (Meteor, Starlight) marked *preview only* because they need per-pixel output the transport cannot provide
- **Effects Studio** — Unified browser for device patterns and custom effects with live preview, parameter tuning (speed, intensity, palette), honest status chips (Preview / Sent / Playing / Preview only), and capability-gated send/play buttons
- **Device profiles** — Built-in MR Star profile plus user-defined GATT profiles (service/characteristic UUIDs, write mode, command templates for power/brightness/colour, notification format). Profiles are verified against the live GATT table before use; unverified profiles fall back to built-in behaviour
- **Rooms** — Create, rename, reorder, delete; assign/unassign devices; deletion reassigns or unassigns devices explicitly
- **Groups** — Logical device collections; one-tap command execution with per-device result reporting
- **Scenes** — Multi-action sequences (power, brightness, colour, effect, speed) targeting devices and/or groups; execution reports per-target success/failure; reports persist until dismissed
- **Persisted state** — All data (devices, rooms, groups, scenes, presets, profiles, assignments, theme) stored in `SharedPreferences`; survives app restarts
- **Theme system** — Light/dark/system with custom accent colour; tokens-driven UI
- **Diagnostics** — Connection state, GATT services/characteristics, profile verification details

### Planned / Not Implemented
- **Automation/scheduling** — Domain entities exist (`Automation`, `Schedule`) but no scheduler, UI, or background execution
- **WLED / MQTT integration** — Domain entities and adapters exist (`WLEDConfig`, `MQTTConfig`, `WLEDHttpAdapter`, `MQTTAdapter`) but are not wired into the UI or command flow; they are explicitly unavailable in Settings
- **Cloud sync / remote marketplace / accounts** — None; by design
- **Firmware update** — Not implemented
- **iOS-specific testing** — Developed and tested on Android; iOS support is theoretical (uses `flutter_blue_plus`)

## Supported Hardware and Protocols

| Hardware | Protocol | Validation Status |
|----------|----------|-------------------|
| MR Star LED controller (GATT service `FFF0`) | BLE GATT (write `FFF3`, notify `FFF4`) | **Code path complete**; protocol derived from decompiled APK. **Hardware validation pending** — the app has not been tested on a physical MR Star device in this repository. Effect mode IDs come from the APK (cmode1..cmode117); all 117 are exposed in the catalogue, and the wire value of a mode is its cmode number. |
| Custom BLE GATT controllers | BLE GATT (user-defined UUIDs + command templates) | **Code path complete**; profile verification gates usage. No physical validation performed. |

**Important distinction:** "Code path complete" means the Dart code compiles, passes static analysis, and unit/widget tests exercise the logic. "Hardware-validated" would require a physical device confirming the wire protocol, effect rendering, and timing. **No hardware validation has been performed for this repository.**

## Architecture

StarLight follows a clean architecture with clear module boundaries:

```
lib/
├── core/
│   ├── ble/              # BLE platform abstraction, protocol encoder/decoder, constants, lifecycle, permissions
│   ├── errors/           # Typed exceptions and failures
│   ├── http/             # HTTP client (for future WLED/MQTT)
│   └── utils/            # Colour conversion, hex/UUID utilities, logging
├── data/
│   ├── adapters/         # StarLightBleAdapter, BleGattProfileExecutor, WLEDHttpAdapter, MQTTAdapter
│   ├── datasources/      # SharedPreferences-backed sources for devices, rooms, groups, scenes, profiles, presets, favourites, theme
│   ├── models/           # Persistence models (JSON/SharedPreferences)
│   ├── repositories/     # Repository implementations
│   └── transport/        # WLED transport (unused)
├── domain/
│   ├── adapters/         # DeviceAdapter (BLE protocol abstraction)
│   ├── automation/       # Automation domain (planned)
│   ├── entities/         # Core entities: Device, Room, Group, Scene, Effect, DeviceProfile, BleDevice, capabilities, etc.
│   ├── repositories/     # Repository interfaces
│   ├── services/         # CommandRouter (single BLE owner, capability checks, verification gate), DeviceCommandDispatcher
│   └── usecases/         # Application use cases (execute scene/group, send commands, profile assignment, etc.)
└── presentation/
    ├── bloc/             # BLoC/Cubit state management (ble, light, scene, room, group, profile, theme, registry)
    ├── pages/            # Feature pages (home, add-device, device-detail, rooms, groups, scenes, effects, settings)
    ├── theme/            # AppTheme, AppTokens, RGBColor extensions
    ├── utils/            # Room icons
    └── widgets/          # Reusable UI components (colour picker, sliders, error banner, execution report, etc.)
```

**Key architectural invariants:**
- **Single BLE owner:** `BleRepositoryImpl` → `BleDataSource` is the only writer to the GATT characteristic. All commands (light, scene, group, effect, profile verification) route through `CommandRouter` → `BleGattProfileExecutor` → `BleDataSource`.
- **Serialized command execution:** `BleDataSource` queues writes; concurrent commands are ordered, not parallel.
- **Capability checks:** `DeviceCapability` gates every control. The UI never shows a control the active route cannot execute.
- **Profile verification:** Custom profiles are verified against the live GATT table before enabling their controls. Until verified, the built-in MR Star path is used.
- **No fake state:** The UI reflects confirmed `BleState`/`LightState`/`SceneState`; disconnected/unavailable states are explicit.

## Prerequisites and Development Environment

- **Flutter SDK** ≥ 3.13 (tested with 3.13+)
- **Dart SDK** ≥ 3.13 (bundled with Flutter)
- **Android SDK** ≥ API 21 (Android 5.0) for BLE support
- **iOS** ≥ 12 (theoretical; `flutter_blue_plus` supports it)
- **No external services** required (no database, no cloud, no MQTT broker)

## Commands

```bash
# Format check (CI gate)
dart format --set-exit-if-changed lib test

# Static analysis (CI gate)
flutter analyze

# Run all tests (519 tests as of this writing)
flutter test

# Build debug APK
flutter build apk --debug

# Build release APK
flutter build apk --release
```

All commands run from the repository root. The test suite covers protocol encoding/decoding, colour conversion, UUID utilities, BLE data sources, repository logic, BLoC behaviour, page/widget rendering, effect engine, custom effect player, profile validation, and navigation.

## Device Profile Configuration and Safety

- **Built-in MR Star profile** (`builtin.mrstar`) is immutable and always available. It uses the hard-coded `ProtocolEncoder` and UUIDs (`FFF0`/`FFF3`/`FFF4`).
- **Custom profiles** are created in Settings → Device profiles. Each profile defines:
  - Service UUID, write characteristic UUID, optional notify characteristic UUID
  - Write mode: Automatic / With response / Without response
  - Command templates for power on/off, brightness, colour (byte patterns with placeholders)
  - Optional notification format (parsing incoming bytes into device state)
  - Declared capabilities (subset of `DeviceCapability`: currently `power`, `brightness`, `color` are executable)
- **Verification:** Before a custom profile drives controls, it must be verified on the target device. The app writes a test command and/or reads the notify characteristic to confirm the profile matches the hardware. Unverified profiles show a warning and fall back to built-in behaviour.
- **Safety constraints:**
  - Brightness values are clamped to the profile's declared range before encoding
  - Speed values are validated against the wire field (0–255) and the app-advertised range (0–100)
  - Unknown effect names are rejected — no silent fallback to `Solid`
  - Preview-only custom effects never send commands; the UI disables the play button and explains why

## Effects

### Device-Native Effects (Hardware Patterns)
These are modes built into the MR Star controller firmware. StarLight selects them by mode ID; the controller renders the pattern. The app cannot render these, so the Effects Studio shows a **decorative static motif explicitly labelled "Pattern is rendered by the controller"**.

The catalogue holds **all 117 controller modes the MR Star APK declares** (`cmode1`…`cmode117`), transcribed verbatim from the APK's `res/values/strings.xml`, plus one app-level steady-colour entry:

| Effect ID | Name | Category | Speed Range | Protocol Mode ID |
|-----------|------|----------|-------------|------------------|
| `solid` | Solid | Static | — | 0 |
| `cmode1` | Automatic loop | Ambient | 0–100 | 1 |
| `cmode2` | Symphony | Ambient | 0–100 | 2 |
| `cmode3` | Colorful energy | Ambient | 0–100 | 3 |
| `cmode4` | Colorful jumps | Rhythm | 0–100 | 4 |
| … | … | … | 0–100 | … |
| `cmode117` | Yellow dots on white background running | Motion | 0–100 | 117 |

The full table, its source grouping and the per-mode category derivation live in `lib/domain/entities/effect.dart` and are pinned by `test/effects_catalogue_test.dart`.

**Protocol convention (verified, not assumed):** the decompiled `ModeFragment` shows that the wire value of a mode **is** its cmode number — the wheel maps every tab straight onto the cmode number (`Basic` 1–4/7/10/26–27/29–32, `Opening & closing` +35, `Transition` +45, `Running water` +55, `Tailing` +76, `Running` +84). `ProtocolEncoder.setMode` therefore needs no shift. Four pairs of modes genuinely share a display name in the APK (`cmode65`/`cmode68`, `cmode72`/`cmode74`, `cmode97`/`cmode112`, `cmode100`/`cmode114`); the duplicates are preserved, and the per-mode `id`/`commandName` (`cmodeN`) is what disambiguates them.

**Legacy names.** Before the catalogue was rebuilt, StarLight shipped its own labels for mode ids (`Fireworks`, `Rainbow`, `Breath`, `Scan`, `Flash`, `Police`, `Chase`, `Comet`, `Lava`, `Ocean`). Those names were never in the firmware — only the mode id they selected was real. Scenes saved with them keep working: a legacy name resolves to the mode it always selected (`kLegacyEffectCommandModeIds`), so the device does exactly what it did before, and the scene editor migrates the stored value to the canonical `cmodeN` on the next save. `Solid` is still a canonical name (mode 0). Any other unknown value is preserved verbatim and refused by the device at run time — it is never silently replaced by a different effect.

**Validation status:** Mode IDs and names come from the decompiled APK. **No physical device has confirmed these mode IDs produce the described patterns.** The Effects Studio presents them as "device patterns" with honest labelling.

### Custom Effects (StarLight Algorithms)
These are computed in Dart and streamed as a sequence of global colours over the BLE colour characteristic. They require `DeviceCapability.color` on the active route.

| Effect ID | Name | Category | Speed | Intensity | Palette | Preview Only |
|-----------|------|----------|-------|-----------|---------|--------------|
| `custom-aurora` | Aurora | Ambient | ✓ | ✓ | ✓ (aurora) | No |
| `custom-ember` | Ember | Ambient | ✓ | ✓ | ✓ (ember) | No |
| `custom-ocean-drift` | Ocean Drift | Ambient | ✓ | ✓ | ✓ (ocean) | No |
| `custom-meteor` | Meteor | Motion | ✓ | ✓ | ✓ (polar) | **Yes** |
| `custom-prism-flow` | Prism Flow | Motion | ✓ | ✓ | ✓ (neon) | No |
| `custom-soft-breath` | Soft Breath | Rhythm | ✓ | ✓ | — | No |
| `custom-color-bloom` | Color Bloom | Rhythm | ✓ | ✓ | ✓ (sunset) | No |
| `custom-starlight` | Starlight | Ambient | ✓ | ✓ | ✓ (polar) | **Yes** |

**Validation status:** Algorithms are unit-tested (`effect_engine_test.dart`, `custom_effect_renderer_test.dart`). **No physical device has confirmed the streamed colours match the preview.** Effects marked "Preview only" need per-pixel control the transport cannot provide; they are available for software preview only.

## Rooms, Groups, and Scenes

### Rooms
- Pure grouping over the device registry. Creating/renaming/reordering/deleting a room never touches device records.
- Deleting a room reassigns its devices to another room or leaves them unassigned — the user chooses explicitly.
- Devices are assigned to rooms via a bottom sheet with per-device dropdowns.

### Groups
- Logical convenience over existing devices. Membership is a list of device IDs.
- Group execution sends the same command to all members concurrently and reports per-device results.
- Missing devices (IDs not in the registry) are counted and shown in the group tile.

### Scenes
- Ordered list of actions: `PowerAction`, `BrightnessAction`, `ColorAction`, `EffectAction`, `SpeedAction`.
- Targets can be devices or groups.
- Execution runs through `DeviceCommandDispatcher` → `CommandRouter` → single BLE queue.
- Result is an `ExecutionReport` with per-target `ExecutionResult` (success, failure with reason, skipped).
- The last report persists in `SceneState` and is shown at the top of the Scenes page until dismissed.

## Current Limitations and Known Issues

1. **No hardware validation** — The MR Star protocol and effect mode IDs are derived from a decompiled APK. No physical device has been used to confirm wire compatibility, effect rendering, or timing.
2. **Effect speed range** — The app advertises 0–100; the wire field is 0–255. The controller's *usable* range is unverified.
3. **Custom profile capabilities** — Only `power`, `brightness`, `color` are executable today. Profiles declaring `effect`, `speed`, `palette`, etc. are rejected by the validator.
4. **WLED/MQTT code present but inactive** — Domain entities, adapters, and repositories exist but are not exposed in the UI. Settings explicitly marks them "Not implemented in this build".
5. **Automation entities exist but no scheduler** — `Automation`, `Schedule`, `Trigger`, `Condition`, `Action` are defined but no background execution or UI.
6. **iOS untested** — Developed on Android; iOS BLE permissions and background behaviour are theoretical.
7. **Analyzer warnings** — 17 issues (info/warnings): deprecated `connecting`/`disconnecting` states, unused imports, `curly_braces_in_flow_control_structures`, `prefer_initializing_formals`, `annotate_overrides`, `use_build_context_synchronously`, `prefer_function_declarations_over_variables`. No errors.
8. **Test count** — 519 tests pass. Previous baseline reported 520; the difference is likely a renamed or consolidated test (no test was intentionally removed).

## Contribution

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, formatting/analysis/test expectations, bug/feature reporting, hardware-testing expectations, and architectural constraints that must be preserved.

## License

StarLight is licensed under the **Apache License 2.0**. See [LICENSE](LICENSE) for the full license text and [NOTICE](NOTICE) for third-party attributions.

SPDX-License-Identifier: Apache-2.0

## Third-Party Attributions

- `flutter_blue_plus` — BLE communication (MIT)
- `flutter_bloc` / `bloc` — State management (MIT)
- `shared_preferences` — Local persistence (BSD-3-Clause)
- `equatable` — Value equality (MIT)
- `rxdart` — Reactive extensions (Apache-2.0)
- `permission_handler` — Runtime permissions (MIT)
- `mocktail` / `bloc_test` / `flutter_lints` — Dev dependencies (various permissive licenses)

See `pubspec.yaml` and `pubspec.lock` for complete dependency tree.