# Contributing to StarLight

Thank you for considering a contribution. This document explains how to set up the development environment, the quality gates every change must pass, how to report issues, and the architectural invariants that must be preserved.

## Development Prerequisites

- **Flutter SDK** ≥ 3.13 (tested with 3.13+)
- **Dart SDK** ≥ 3.13 (bundled with Flutter)
- **Android SDK** ≥ API 21 for BLE testing on Android
- **No external services** required — no database, cloud, MQTT broker, or backend

```bash
# Verify Flutter installation
flutter doctor -v

# Get dependencies
flutter pub get

# Run quality gates locally before pushing
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

All commands run from the repository root (`/home/richi/Desktop/Projects/StarLight` or your clone).

## Quality Gates (CI Requirements)

Every PR must pass these checks locally before submission:

| Check | Command | Must Pass |
|-------|---------|-----------|
| Formatting | `dart format --set-exit-if-changed lib test` | Zero changes |
| Static analysis | `flutter analyze` | Zero errors; warnings acceptable but should be addressed |
| Tests | `flutter test` | All 519 tests pass |
| Debug build | `flutter build apk --debug` | Successful APK output |

**Do not weaken, skip, or delete tests to achieve a passing result.** If a test fails, the implementation is wrong — fix the code, not the test.

## Reporting Bugs

Use the GitHub issue template (`.github/ISSUE_TEMPLATE/bug_report.md`). Include:

1. **Steps to reproduce** — minimal, deterministic sequence
2. **Expected vs actual behaviour** — what the code does vs what it should do
3. **Device and OS** — Android version, iOS version (if applicable), MR Star controller firmware if known
4. **Logs** — `flutter logs` output or `AppLog` lines from the debug build
5. **BLE context** — Were you connected? Scanning? Reconnecting? What was the `BleState`?

If the bug involves a BLE command, note the `DeviceCapability` and whether a custom profile was assigned/verified.

## Proposing Features

Use the GitHub issue template (`.github/ISSUE_TEMPLATE/feature_request.md`). Explain:

1. **User problem** — what workflow is missing or painful
2. **Proposed solution** — high-level, not a PR description
3. **Architectural impact** — does it touch BLE ownership, command routing, capability gating, or profile verification?
4. **Hardware validation plan** — if the feature sends new BLE commands, how will you verify them on a physical device?

Features that introduce **new BLE commands, new device capabilities, or new transport protocols** must include a hardware validation plan. Code-path completeness is not hardware validation.

## Hardware-Testing Expectations

StarLight communicates with physical BLE hardware. The repository distinguishes:

- **Code-path complete** — Dart compiles, analysis passes, unit/widget tests exercise the logic
- **Hardware-validated** — A physical MR Star controller (or custom GATT device) confirmed the wire protocol, effect rendering, timing, and edge cases

**Current status:** The MR Star protocol and 11 effect mode IDs are derived from a decompiled APK. **No hardware validation has been performed for this repository.**

When you contribute changes that affect the wire protocol (`ProtocolEncoder`, `BleGattProfileExecutor`, custom profile command templates, effect mode IDs):

1. Test on a physical device if possible
2. Document the test results in the PR (what worked, what didn't, packet captures if available)
3. If you cannot test on hardware, state this explicitly — the change will be marked "code-path complete, hardware validation pending"

The Effects Studio and Device Detail pages already label unverified effects and capabilities honestly. Preserve this honesty.

## Architectural Invariants (Must Preserve)

These are not style preferences — they are correctness requirements. Any PR that violates them will be rejected.

### 1. Single BLE Owner
`BleDataSource` is the **only** component that opens a BLE session and writes to the GATT characteristic. All commands (light, scene, group, effect, profile verification) route through:
```
LightBloc/SceneBloc/GroupCubit/ProfileCubit
    → CommandRouter (capability check + verification gate)
    → BleGattProfileExecutor (custom profile encoding)
    → BleDataSource (serialized write queue)
```
No other path to the wire is permitted.

### 2. Serialized Command Execution
`BleDataSource` queues writes. Concurrent commands are ordered, never parallel. Do not add parallel write paths.

### 3. Capability Checks Gate Every Control
`DeviceCapability` determines which UI controls are shown and which commands are accepted. The UI **never** shows a control the active route cannot execute. `CommandRouter` enforces this at the domain layer.

### 4. Profile Verification Before Use
Custom `DeviceProfile`s are verified against the live GATT table before enabling their controls. Until verified, the built-in MR Star path is used. The verification result is surfaced in the UI (Settings → Device profiles, Device Detail → Profile section).

### 5. No Fake State
The UI reflects confirmed `BleState`/`LightState`/`SceneState`. Disconnected, unavailable, and error states are explicit. No optimistic updates; a failed write leaves state untouched.

### 6. Unknown Effects Are Rejected
`effectByCommandName` returns `null` for unknown effects. There is **no silent fallback** to `Solid` (mode 0). Callers must treat `null` as an explicit failure.

### 7. Preview-Only Effects Never Send Commands
Custom effects marked `requiresAddressable: true` (Meteor, Starlight) are available for software preview only. The UI disables the play button and explains why. No command is sent for these effects.

## Code Style

- Follow `flutter_lints` (configured in `analysis_options.yaml`)
- `avoid_print: false` is set — use `AppLog` for structured logging
- No comments unless they explain *why* (protocol details, concurrency rules, safety constraints, non-obvious behaviour)
- Prefer `const` constructors, `final` fields, initializing formals
- Use `Equatable` for value objects in `domain/entities/`

## Pull Request Process

1. Fork and create a feature branch
2. Make changes with clear, atomic commits
3. Run all quality gates locally (format, analyze, test, build)
4. Open a PR using the template (`.github/PULL_REQUEST_TEMPLATE.md`)
5. CI runs the same gates; PR cannot merge until all pass
6. Address review feedback; maintainers will verify architectural invariants

## Third-Party Dependencies

Adding a new dependency requires:
- License compatibility (current deps: MIT, BSD-3-Clause, Apache-2.0)
- Justification in the PR description
- No GPL or copyleft dependencies

## License

StarLight is licensed under the Apache License 2.0. By contributing, you agree that your contributions will be licensed under the same terms (Apache-2.0), consistent with Section 5 of the Apache License. No separate CLA or DCO is required.

## Questions?

Open a GitHub Discussion or issue. For security concerns, see the security policy (if one exists) or email the maintainer directly.

---

**Reminder:** StarLight has no license yet. Public visibility does not grant reuse rights. See `LICENSE_DECISION.md` for the pending license comparison.