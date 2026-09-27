"""Protocol constants for the MR Star controller.

Every value here was read out of the decompiled APK (read-only reference at
/home/jarvis/mrstar_decompiled). The Flutter client's ``BleConstants`` and
``ProtocolEncoder`` are the in-repo mirror; this module is the same data for
the service that owns the BLE link.

Verified sources:
  sources/com/findn/MyApplication.java          -> UUIDs, chunking
  sources/res/layout/fragment_adjust.xml        -> brightness SeekBar max
  sources/res/layout/fragment_mode.xml          -> speed SeekBar max
  sources/e1/d.java, e1/h.java                  -> brightness packet + min clamp
  sources/e2/e.java                             -> color conversion
  sources/com/findn/ui/fragment/AdjustFragment.java
  sources/com/findn/ui/fragment/ModeFragment.java
  sources/e1/{c,f,g}.java, f1/d.java, c1/b.java
"""

from __future__ import annotations

# --- GATT -----------------------------------------------------------------
# MyApplication.d(byte[]) hardcodes these two, and l2/c.java holds the CCCD.
SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb"
WRITE_CHAR_UUID = "0000fff3-0000-1000-8000-00805f9b34fb"
NOTIFY_CHAR_UUID = "0000fff4-0000-1000-8000-00805f9b34fb"
CCC_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"

# --- Framing --------------------------------------------------------------
START_BYTE = 0xBC
END_BYTE = 0x55

# --- Command ids ----------------------------------------------------------
CMD_POWER = 0x01
CMD_LINE_ORDER = 0x02
CMD_LED_POINT = 0x03
CMD_COLOR = 0x04
CMD_BRIGHTNESS = 0x05
CMD_MODE = 0x06
CMD_PICKER = 0x07
CMD_SPEED = 0x08
CMD_VISUALIZER_COLOR = 0x09
CMD_TIMER_CLEAR = 0x0C
CMD_TIMER_SET = 0x0D
CMD_MIC_TOGGLE = 0x0F
CMD_MIC_MODE = 0x11
CMD_MIC_SENSITIVITY = 0x12
CMD_UNKNOWN_13 = 0x13

# --- Sub-command ids ------------------------------------------------------
SUB_POWER = 0x01
SUB_LINE_ORDER = 0x01
SUB_LED_POINT = 0x02
SUB_COLOR = 0x06
SUB_BRIGHTNESS = 0x06
SUB_MODE = 0x02
SUB_PICKER = 0x01
SUB_SPEED = 0x01
SUB_VISUALIZER_COLOR = 0x06
SUB_MIC_TOGGLE = 0x01
SUB_MIC_MODE = 0x01
SUB_MIC_SENSITIVITY = 0x01

# --- Write chunking -------------------------------------------------------
# MyApplication.d(byte[]): payloads over 20 bytes are split into 20-byte
# chunks with a 200 ms gap (eVar.f3532g = 20, eVar.f3534i = 200L).
MAX_WRITE_CHUNK = 20
CHUNK_DELAY_S = 0.2

# --- Value scales ---------------------------------------------------------
# fragment_adjust.xml / fragment_mode.xml: sb_brightness android:max="1000",
# sb_speed android:max="100".
BRIGHTNESS_PROTOCOL_MAX = 1000
BRIGHTNESS_PROTOCOL_MIN = 3  # e1/d.java: progress < 3 -> progress = 3
SPEED_PROTOCOL_MAX = 100

# --- Device identification ------------------------------------------------
# Used as a *prefix* filter while scanning. The MAC is never the only
# identifier; it comes from config when a specific unit must be targeted.
DEFAULT_DEVICE_NAME_PREFIX = "GATT--DEMO"

# --- Receive path ---------------------------------------------------------
# The APK's response parser re-dispatches these command bytes internally
# (MyApplication.d(byte[]), "bArr3[1] == 11 || 12 || 80"). Their payload
# semantics are not established, so the decoder only reports them.
OBSERVED_RX_COMMANDS = frozenset({0x0B, 0x0C, 0x50})

# --- Modes (Phase 15) -----------------------------------------------------
# The APK ships a catalogue of 117 named modes (strings.xml: cmode1..cmode117)
# selected with CMD_MODE. The catalogue is resolved at runtime through
# Resources.getIdentifier (see e1/c.c), so the name-to-value mapping is NOT
# proven; CMD_MODE is therefore available only as a raw, unverified call.
MODE_RESOURCE_PREFIX = "cmode"
MODE_RESOURCE_COUNT = 117
