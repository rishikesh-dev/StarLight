---
name: Pull Request
about: Submit changes for review
title: "[PR] "
labels: []
assignees: []
---

## Summary
What does this PR change? One or two sentences.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Refactor (no behaviour change)
- [ ] Documentation
- [ ] Test improvement
- [ ] Build/CI configuration

## Related Issues
Closes #<issue-number> (if applicable)

## Quality Gates (Run Locally Before Submitting)
- [ ] `dart format --set-exit-if-changed lib test` — zero changes
- [ ] `flutter analyze` — zero errors
- [ ] `flutter test` — all 519 tests pass
- [ ] `flutter build apk --debug` — successful build

## Architectural Invariant Check
Confirm this PR does **not** violate any of the following:

- [ ] **Single BLE owner** — all commands route through `CommandRouter` → `BleGattProfileExecutor` → `BleDataSource`
- [ ] **Serialized execution** — no parallel write paths added
- [ ] **Capability checks** — UI never shows a control the active route cannot execute
- [ ] **Profile verification** — custom profiles verified before use; unverified falls back to built-in
- [ ] **No fake state** — UI reflects confirmed state; disconnected/error states explicit
- [ ] **Unknown effects rejected** — no silent fallback to `Solid` (mode 0)
- [ ] **Preview-only effects** — never send commands; UI explains why

## Hardware Validation
If this PR affects the wire protocol (protocol encoder, custom profile commands, effect mode IDs, new capabilities):

- [ ] Tested on physical MR Star controller — describe results in Testing Notes
- [ ] Tested on custom GATT device — describe results in Testing Notes
- [ ] **Code-path complete only; hardware validation pending** — explicitly acknowledged

## Testing Notes
How did you verify the change? Include:
- Unit/widget tests added or modified
- Manual testing steps
- Hardware test results (if applicable)
- Edge cases considered

## Screenshots (if UI changed)
Before / after screenshots or screen recording.

## Checklist
- [ ] Code follows `flutter_lints` and project conventions
- [ ] No narrative/development-diary comments added
- [ ] Protocol details, concurrency rules, safety constraints explained where non-obvious
- [ ] No new dependencies added without justification
- [ ] No secrets, credentials, or generated artifacts committed
- [ ] `CHANGELOG.md` updated (if one exists) or release notes added to PR description
- [ ] License compliance: new code carries `// SPDX-License-Identifier: Apache-2.0` header; no incompatible dependencies introduced