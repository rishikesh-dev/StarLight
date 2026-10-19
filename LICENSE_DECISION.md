# License Decision — Maintainer Notes

**Status:** **Apache-2.0 selected and implemented.** The maintainer has explicitly approved Apache-2.0 adoption. The LICENSE and NOTICE files have been created, SPDX headers added to source files, and README updated.

## Comparison for StarLight

| Criterion | MIT | Apache-2.0 | GPL-3.0 |
|-----------|-----|------------|---------|
| **Permissiveness** | Maximum — allows proprietary derivatives | High — allows proprietary derivatives with patent grant | Copyleft — derivatives must be GPL-compatible |
| **Patent grant** | Implicit (uncertain in some jurisdictions) | Explicit, broad patent grant from contributors | Explicit, but only within GPL ecosystem |
| **Attribution** | Preserve copyright/license notice | Preserve copyright/license notice + NOTICE file if present | Preserve copyright/license notice + source offer |
| **Compatibility** | Compatible with everything | Compatible with most permissive licenses; GPLv3 compatible | Only compatible with GPL-compatible licenses |
| **Commercial adoption** | Highest — used by Flutter, Dart, most pub packages | High — used by Android, Kubernetes, TensorFlow | Lower — deters proprietary embedding |
| **Contribution dynamics** | Low friction, no legal obligation to share changes | Low friction, patent protection for contributors | Requires sharing changes; may deter some corporate contributors |
| **Enforcement** | Copyright only | Copyright + patent | Copyright + copyleft (legal leverage) |
| **Third-party deps** | All current deps (flutter_bloc, flutter_blue_plus, shared_preferences, equatable, rxdart, permission_handler, mocktail, bloc_test, flutter_lints) are permissive (MIT/BSD/Apache) — compatible with any choice | Same | Compatible (permissive deps can be used in GPL project) |

## Recommendation (Accepted)

**Apache-2.0** is the best fit for StarLight because:

1. **Explicit patent grant** — BLE/Bluetooth implementations can touch patented territory (GATT profiles, LED control methods). Apache-2.0 protects contributors and users.
2. **Permissive but not maximal** — Allows commercial/proprietary use (like MIT) but adds the patent grant that MIT lacks.
3. **Ecosystem alignment** — Flutter itself uses BSD-3-Clause; Dart SDK uses BSD; the pub ecosystem is overwhelmingly MIT/BSD/Apache. Apache-2.0 is fully compatible.
4. **Future-proofing** — If StarLight ever adds a plugin system or SDK, Apache-2.0's patent grant reduces risk for downstream adopters.
5. **NOTICE file support** — If third-party attributions grow, Apache-2.0's NOTICE mechanism is standard.

**Do not choose GPL-3.0** unless the goal is to legally require all derivatives to remain open source. This would conflict with the permissive dependency ecosystem and likely limit adoption.

**Do not choose MIT** if patent protection matters. The implicit patent grant in MIT is jurisdiction-dependent and weaker than Apache-2.0's explicit grant.

## Implementation Summary (Completed)

- [x] Select license: **Apache-2.0** (maintainer approved)
- [x] Create `LICENSE` file with full official Apache License 2.0 text
- [x] Create `NOTICE` file with accurate third-party attributions
- [x] Add SPDX headers (`// SPDX-License-Identifier: Apache-2.0`) to all original StarLight source files in `lib/`
- [x] Update `README.md` to state Apache-2.0 selected, point to LICENSE and NOTICE
- [x] `pubspec.yaml` — No `license` field added (Dart/Flutter pubspec schema does not formally support a top-level `license` field; SPDX in README and source headers is the standard approach)

## Provenance Notes

- Single Git author: `rishikesh-dev <rishikeshdeveloperrichi@gmail.com>` (all commits in current history)
- No existing copyright headers in source files prior to this change
- No evidence of third-party code copied into the repository without attribution
- All direct dependencies are permissively licensed (MIT, BSD-3-Clause, Apache-2.0) and compatible
- Android launcher icons are default Flutter SDK assets (BSD-3-Clause)
- Material Icons font bundled by Flutter build system (Apache-2.0)
- MR Star protocol derived from decompiled APK for interoperability; encoder/decoder are original implementations