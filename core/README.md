# StarLight Core

The single owner of the MR Star BLE link. Flutter, the CLI and JARVIS are
clients of this service; none of them talk to the controller directly.

```
              ┌──────────────┐
              │    JARVIS    │
              └──────┬───────┘
                     │ HTTP
┌──────────────┐  ┌──▼──────────────┐
│   Terminal   │─▶│  StarLight Core │─┐
└──────────────┘  └──▲──────────────┘ │ BLE
                     │                ▼
              ┌──────┴───────┐   MR Star controller
              │ Flutter App  │   GATT--DEMO
              └──────────────┘   FFF0 / FFF3 / FFF4
```

## Layout

```
app/
  main.py                 FastAPI entrypoint, DI, error handlers
  errors.py               one exception hierarchy, mapped to JSON by the API layer
  api/
    schemas.py            request/response models
    lights.py             /light/* (power, color, brightness, speed, effect, scene)
    devices.py            /device (list, connect, disconnect)
    scenes.py             /scenes and /presets (explicit 501 until built)
    deps.py               shared FastAPI dependencies
  config/settings.py      STARLIGHT_* environment configuration
  protocol/
    constants.py          UUIDs, command ids, chunking, value ranges
    encoder.py            packet encoder (parity with the Flutter encoder)
    decoder.py            structural RX parsing only
    color.py              RGB -> HSV ported from e2.e.B()
    scales.py             percent <-> protocol value conversion
  models/
    light_state.py        the canonical state
    device.py             device metadata
  ble/
    manager.py            scan / find / connect / reconnect
    connection.py         the bleak implementation, APK-parity chunking
    device.py             device + transport pairing
    transport.py          the seam the service depends on
    uuids.py              short/long UUID normalization
  services/
    light_service.py      canonical state + all commands
tests/                    pytest suite (76 tests)
```

The protocol, models and service layers import nothing from `bleak`, so they
are testable on a machine without Bluetooth. Only `ble/` and `main.py` need it.

## Running

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt

python3 -m pytest -q                       # 76 tests
uvicorn app.main:app --host 127.0.0.1 --port 8765
curl -s 127.0.0.1:8765/health
```

### Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `STARLIGHT_HOST` | `127.0.0.1` | bind address |
| `STARLIGHT_PORT` | `8765` | bind port |
| `STARLIGHT_DEVICE_ADDRESS` | unset | pin a specific controller |
| `STARLIGHT_DEVICE_NAME_PREFIX` | `GATT--DEMO` | scan filter |
| `STARLIGHT_RECONNECT` | `true` | reconnect when the link drops |
| `STARLIGHT_AUTO_CONNECT` | `true` | connect on startup |
| `STARLIGHT_WRITE_TIMEOUT_S` | `5.0` | per-packet write budget |
| `STARLIGHT_LOG_LEVEL` | `INFO` | logging level |

The MAC is never the only identifier: leave `DEVICE_ADDRESS` unset and the
service finds the strip by advertised name, which is what a second strip or a
replacement unit needs.

## HTTP API

Default bind is `127.0.0.1:8765`. Interactive docs are at `/docs`.

| Method | Path | Body | Result |
| --- | --- | --- | --- |
| GET | `/health` | — | status, version, devices, light state |
| GET | `/device` | — | devices (`?scan=true` for a fresh scan) |
| POST | `/device/connect` | `{"address": "..."}` (optional) | connects and binds commands |
| POST | `/device/disconnect` | `{"address": "..."}` (optional) | closes the link |
| GET | `/light/state` | — | current state, no device I/O |
| POST | `/light/power` | `{"on": true}` | `BC 01 01 00 55` / `... 01 55` |
| POST | `/light/color` | `{"r":142,"g":108,"b":255}` or `{"hex":"#8E6CFF"}` | color packet |
| POST | `/light/brightness` | `{"value": 60}` (percent) | brightness packet |
| POST | `/light/speed` | `{"value": 73}` (percent) | speed packet |
| POST | `/light/effect` | `{"name": "rainbow"}` | **501** until verified |
| POST | `/light/scene` | `{"name": "coding"}` | **501** until Phase 14 |
| GET/POST | `/scenes`, `/presets`, `DELETE /scenes/{name}` | — | **501** until implemented |

```bash
curl -s 127.0.0.1:8765/light/state
curl -s -X POST 127.0.0.1:8765/light/power     -H 'Content-Type: application/json' -d '{"on":true}'
curl -s -X POST 127.0.0.1:8765/light/color     -H 'Content-Type: application/json' -d '{"hex":"#8E6CFF"}'
curl -s -X POST 127.0.0.1:8765/light/brightness -H 'Content-Type: application/json' -d '{"value":60}'
```

Every light endpoint answers with the *resulting* state, so a client never has
to follow up with a read:

```json
{"success":true,"power":true,"brightness":60,"color":"#8E6CFF",
 "rgb":{"r":142,"g":108,"b":255},"effect":null,"speed":50,
 "scene":null,"connected":true,"device":"80:AC:C8:5D:AB:CF"}
```

### Errors

One shape for every failure, including validation:

```json
{"success":false,"error":"not_connected","message":"no device connected","details":null}
```

| Error code | Status | Meaning |
| --- | --- | --- |
| `validation_error` | 422 | bad body, e.g. brightness `150` (rejected, not clamped) |
| `invalid_value` | 400 | malformed value that got past validation |
| `device_not_found` | 404 | nothing matched the configured device |
| `not_connected` | 503 | no live link |
| `ble_error` | 503 | the device rejected or lost the write |
| `write_timeout` | 504 | chunked write exceeded its budget |
| `service_not_found` / `characteristic_not_found` | 502 | device present, GATT unexpected; the response lists the UUIDs actually found |
| `unsupported_effect` / `not_implemented` | 501 | feature not verified/implemented yet |

A failed write is a 5xx **and** leaves the state untouched, so a client can
never observe a change the hardware did not accept.

## Protocol status

Everything below was re-checked against the decompiled APK at
`/home/jarvis/mrstar_decompiled` (AUTHORS NOTE: read-only reference, not part
of this repo).

| Area | Status |
| --- | --- |
| Power on/off `BC 01 01 [00|01] 55` | protocol verified |
| Color `BC 04 06 VH VL SH SL 00 00 55` | protocol verified |
| Brightness `BC 05 06 PH PL ... 55`, min 3 | protocol verified |
| Line order, LED count, speed, mic, picker | protocol verified |
| Mode select `BC 06 02 [id/255] [id%255] 55` | command verified, **value semantics unverified** |
| Visualizer color `BC 09 06 ...` | command verified, not yet exposed |
| Timer `BC 0C` / `BC 0D`, packet `BC 13` | not implemented, payload not legible |
| Named effects | **not verified — refused by design** |
| Hardware round trip | **tested on 2026-09-24 — see below** |

Value ranges are not guesses: `fragment_adjust.xml` sets `android:max="1000"`
on the brightness SeekBar and `fragment_mode.xml` sets `android:max="100"`
on the speed SeekBar, which is why the API speaks percent and the core applies
the 0-1000 scale internally.

## Hardware verification (2026-09-24)

Run against the real controller (`GATT--DEMO`, `80:AC:C8:5D:AB:CF`) through
`BleManager` + `LightService`. Result: **hardware tested** for the commands
below, with the observed packets confirmed on the wire path.

| Command | Packet sent | Result |
| --- | --- | --- |
| power ON | `BC 01 01 00 55` | lights on |
| power OFF | `BC 01 01 01 55` | lights off |
| color red / green / blue | `BC 04 06 .. .. .. .. 00 00 55` | correct color |
| color `#8E6CFF` | `BC 04 06 00 FD 02 40 00 00 55` | correct color |
| brightness 10 / 30 / 50 / 70 / 85 / 100 % | `BC 05 06 .. .. 00 00 00 00 55` | visibly dims/brightens |
| disconnect / reconnect | — | link closes and reopens cleanly |

GATT discovery reported exactly the expected layout, in *full* 128-bit form:

```
service  0000fff0-0000-1000-8000-00805f9b34fb
  char   0000fff4-0000-1000-8000-00805f9b34fb  notify        (desc 00002902)
  char   0000fff3-0000-1000-8000-00805f9b34fb  write-without-response, write
```

The controller sent **no notifications** in response to any of these commands,
which matches the APK only special-casing commands `0x0B`, `0x0C` and `0x50`.
Nothing in the service waits for a reply, so this is expected, not a gap.

### BlueZ findings worth keeping

These bit us during verification and are handled in `ble/bluez.py`:

* **A connected peripheral stops advertising**, so `BleakScanner` cannot find
  the strip while anything holds the link. `find_target()` therefore consults
  BlueZ's device cache first, and `connect()` hands bleak a `BLEDevice` with the
  D-Bus object path instead of a bare address — otherwise bleak runs a fresh
  scan and fails with `BleakDeviceNotFoundError` in exactly the situation a
  reconnect hits.
* The object-manager interface is **`org.freedesktop.DBus.ObjectManager`**, not
  `org.bluez.ObjectManager`.
* `GetManagedObjects` returns properties wrapped in D-Bus `Variant`s. Left
  wrapped, `Address` comparisons fail and `bool(props["Connected"])` is always
  true. They are unwrapped on read.
* In this environment a 10 s scan discovered nothing at all, even while the
  strip was not connected. **Connecting by configured address is the reliable
  path**; set `STARLIGHT_DEVICE_ADDRESS` if scanning is unreliable for you too.

## Design rules this code follows

* **State follows a successful write.** Nothing is updated optimistically; a
  failed write raises and leaves the state untouched, so the UI can never show
  a change the hardware did not accept.
* **Unverified features are refused, not faked.** `set_effect("rainbow")`
  raises `UnsupportedEffectError`; `set_mode()` is the raw escape hatch and
  deliberately does not record an effect name.
* **One protocol implementation.** `app/protocol/encoder.py` and the Dart
  `ProtocolEncoder` assert the same byte vectors in their respective suites.
* **Every client speaks percent.** No client needs to know about 0-1000.

## Phases

Done: 1 (audit, protocol verification), 2 (core extraction), 3 (BLE core),
plus the pinned test suite.

Done so far: 1 (audit + protocol verification), 2 (core extraction), 3 (BLE
core, hardware tested), 6 (REST API, exercised over HTTP against the strip).

Next: 4 (protocol parity in both clients), 5 (state model exposure), 7 (CLI),
8 (JARVIS tool), 9 (systemd), 10-15 (Flutter UI, power, brightness, color,
scenes, effects), 16-18 (multi-device, automation, developer mode), 19
(Flutter API client), 20 (hardware acceptance run).

Note for Phase 8: a JARVIS backend is already running on this machine
(`~/Documents/jarvis`, FastAPI on port 8000), so the `light_control` tool
should be added there and call this service over HTTP.
