---
name: Feature Request
about: Propose a new feature or enhancement for StarLight
title: "[Feature] "
labels: ["enhancement"]
assignees: []
---

## User Problem
What workflow is missing, painful, or limited today? Describe from the user's perspective.

## Proposed Solution
High-level description of the feature. Not a PR design doc — just the "what" and "why".

## Architectural Impact
Does this change touch any of the following? (Check all that apply)

- [ ] **BLE ownership** — new path to the GATT characteristic
- [ ] **Command routing** — `CommandRouter`, `BleGattProfileExecutor`, `BleDataSource`
- [ ] **Capability gating** — new `DeviceCapability` or changed capability checks
- [ ] **Profile verification** — custom profile validation logic
- [ ] **Effect system** — new effects, effect engine, custom effect player
- [ ] **Persistence** — new `SharedPreferences` keys, data models, migrations
- [ ] **Navigation/UI** — new pages, routes, or significant UX changes
- [ ] **None of the above** — purely additive, no architectural impact

## Hardware Validation Plan
If this feature sends **new BLE commands**, defines **new device capabilities**, or introduces a **new transport protocol**:

1. **How will you test on a physical device?**
2. **What packets do you expect on the wire?**
3. **How will you verify the device behaves correctly?** (visual confirmation, packet capture, etc.)

If you cannot test on hardware, state: **"Code-path complete only; hardware validation pending."**

## Alternatives Considered
Briefly describe other approaches you considered and why they were rejected.

## Additional Context
Sketches, mockups, related issues, or references to similar implementations.