"""Packet encoder for the MR Star BLE LED controller.

Every packet starts with 0xBC and ends with 0x55. The functions below are a
port of ``lib/core/ble/protocol_encoder.dart`` so both implementations emit
identical bytes, and they were re-checked line by line against the APK's
``MyApplication.f1775m.d(new byte[]{...})`` call sites.

Packet inventory in the APK, and where each one lives here:

======================================  =================================
APK call                                function
======================================  =================================
``BC 01 01 [00|01] 55``                 :func:`power_on` / :func:`power_off`
``BC 02 01 [order] 55``                  :func:`set_line_order`
``BC 03 02 [hi] [lo] 55``                :func:`set_led_count`
``BC 04 06 VH VL SH SL 00 00 55``        :func:`color_from_hsv`
``BC 05 06 PH PL 00 00 00 00 55``        :func:`brightness`
``BC 06 02 [id/255] [id%255] 55``        :func:`set_mode`  (new to the core)
``BC 07 01 [00|01] 55``                  :func:`set_color_picker`
``BC 08 01 [speed] 55``                  :func:`speed`
``BC 09 06 VH VL SH SL 00 00 55``        :func:`set_visualizer_color` (new)
``BC 0F 01 [00|01] 55``                  :func:`mic_toggle`
``BC 11 01 [mode] 55``                   :func:`mic_mode`
``BC 12 01 [level] 55``                  :func:`mic_sensitivity`
======================================  =================================

Not implemented on purpose: the timer commands (0x0C "clear", 0x0D "set" from
``TimerFragment``) and the 0x13 packet from ``e1/c.b``. Their payloads are
only partly legible in the decompiled output, and Phase 17 defers automation.
Guessing them would violate the "do not invent commands" rule.
"""

from __future__ import annotations

from app.protocol import color as color_module
from app.protocol import constants, scales

__all__ = [
    "power_on",
    "power_off",
    "set_power",
    "color_from_rgb",
    "color_from_hsv",
    "brightness",
    "set_brightness_percent",
    "speed",
    "set_speed_percent",
    "set_led_count",
    "set_line_order",
    "set_mode",
    "set_visualizer_color",
    "mic_toggle",
    "mic_mode",
    "mic_sensitivity",
    "set_color_picker",
    "to_hex",
]


# --- helpers --------------------------------------------------------------


def _encode16_be(value: int) -> bytes:
    """Big-endian 16-bit, matching Java's ``value / 256`` and ``value % 256``."""
    value &= 0xFFFF
    return bytes([(value >> 8) & 0xFF, value & 0xFF])


def _byte(value: int) -> int:
    return value & 0xFF


def _packet(body: list[int]) -> bytes:
    return bytes([constants.START_BYTE, *body, constants.END_BYTE])


def to_hex(data: bytes) -> str:
    """``BC 01 01 00 55`` style dump, mirroring ``HexUtils.toHexString``."""
    return " ".join(f"{byte:02X}" for byte in data)


# --- core commands --------------------------------------------------------


def power_on() -> bytes:
    """Power ON: ``BC 01 01 00 55`` (AdjustFragment line 153)."""
    return _packet([constants.CMD_POWER, constants.SUB_POWER, 0x00])


def power_off() -> bytes:
    """Power OFF: ``BC 01 01 01 55`` (AdjustFragment line 155)."""
    return _packet([constants.CMD_POWER, constants.SUB_POWER, 0x01])


def set_power(on: bool) -> bytes:
    """Power packet for a boolean, without the caller needing the byte values.

    The APK's switch sends 0 when checked and 1 when unchecked, so ON is 0x00.
    """
    return power_on() if on else power_off()


def color_from_rgb(red: int, green: int, blue: int) -> bytes:
    """Color packet computed from RGB via the APK's own conversion."""
    value1, value2 = color_module.compute_color_values(red, green, blue)
    return color_from_hsv(value1, value2)


def color_from_hsv(value1: int, value2: int) -> bytes:
    """``BC 04 06 VH VL SH SL 00 00 55`` with pre-computed HSV values."""
    return bytes(
        [
            constants.START_BYTE,
            constants.CMD_COLOR,
            constants.SUB_COLOR,
            *_encode16_be(value1),
            *_encode16_be(value2),
            0x00,
            0x00,
            constants.END_BYTE,
        ]
    )


def brightness(progress: int) -> bytes:
    """``BC 05 06 PH PL 00 00 00 00 55`` in protocol units (0-1000).

    Values below 3 are clamped, exactly as ``e1/d.java`` and ``e1/h.java`` do.
    """
    value = progress
    if value < constants.BRIGHTNESS_PROTOCOL_MIN:
        value = constants.BRIGHTNESS_PROTOCOL_MIN
    return bytes(
        [
            constants.START_BYTE,
            constants.CMD_BRIGHTNESS,
            constants.SUB_BRIGHTNESS,
            *_encode16_be(value),
            0x00,
            0x00,
            0x00,
            0x00,
            constants.END_BYTE,
        ]
    )


def set_brightness_percent(percent: int) -> bytes:
    """Brightness packet from a user-facing 0-100 percent value."""
    return brightness(scales.brightness_percent_to_protocol(percent))


# --- additional commands --------------------------------------------------


def speed(value: int) -> bytes:
    """``BC 08 01 [speed] 55``; the APK sends the SeekBar progress as-is."""
    return _packet([constants.CMD_SPEED, constants.SUB_SPEED, _byte(value)])


def set_speed_percent(percent: int) -> bytes:
    """Speed packet from a user-facing 0-100 percent value."""
    return speed(scales.speed_percent_to_byte(percent))


def set_led_count(count: int) -> bytes:
    """``BC 03 02 PH PL 55`` (c1/b.java)."""
    return bytes(
        [
            constants.START_BYTE,
            constants.CMD_LED_POINT,
            constants.SUB_LED_POINT,
            *_encode16_be(count),
            constants.END_BYTE,
        ]
    )


def set_line_order(order: int) -> bytes:
    """``BC 02 01 [order] 55`` (MainActivity line 121)."""
    return _packet([constants.CMD_LINE_ORDER, constants.SUB_LINE_ORDER, _byte(order)])


def set_mode(mode_id: int) -> bytes:
    """``BC 06 02 [id/255] [id%255] 55`` (ModeFragment.f0).

    ModeFragment encodes the value with a *divide by 255* pair rather than the
    256 pair used everywhere else, so that quirk is preserved deliberately.

    The command itself is verified. What the value means is not: the 117 mode
    names live in ``strings.xml`` as ``cmode1``..``cmode117`` and are resolved
    at runtime, and ``ModeFragment.P()`` did not decompile, so this is exposed
    as a raw, unverified operation.
    """
    if mode_id < 0:
        mode_id = 0
    return _packet(
        [
            constants.CMD_MODE,
            constants.SUB_MODE,
            _byte(mode_id // 255),
            _byte(mode_id % 255),
        ]
    )


def set_visualizer_color(value1: int, value2: int) -> bytes:
    """``BC 09 06 VH VL SH SL 00 00 55`` (f1/d.java line 96)."""
    return bytes(
        [
            constants.START_BYTE,
            constants.CMD_VISUALIZER_COLOR,
            constants.SUB_VISUALIZER_COLOR,
            *_encode16_be(value1),
            *_encode16_be(value2),
            0x00,
            0x00,
            constants.END_BYTE,
        ]
    )


def mic_toggle(on: bool) -> bytes:
    """``BC 0F 01 [0|1] 55`` (SegmentedButtonGroup / MicroPhoneFragment)."""
    return _packet(
        [constants.CMD_MIC_TOGGLE, constants.SUB_MIC_TOGGLE, 0x01 if on else 0x00]
    )


def mic_mode(mode: int) -> bytes:
    """``BC 11 01 [mode] 55``; the APK sends 1, 2, 3 or 4."""
    return _packet([constants.CMD_MIC_MODE, constants.SUB_MIC_MODE, _byte(mode)])


def mic_sensitivity(level: int) -> bytes:
    """``BC 12 01 [level] 55`` (e1/f.java)."""
    return _packet(
        [constants.CMD_MIC_SENSITIVITY, constants.SUB_MIC_SENSITIVITY, _byte(level)]
    )


def set_color_picker(enabled: bool) -> bytes:
    """``BC 07 01 [00|01] 55`` (e1/c.a).

    Polarity is deliberately not asserted here. ``e1/c.a(boolean)`` sends 0x00
    when its boolean is true and 0x01 when false, but the meaning of that
    boolean (checked vs. enabled) depends on the LSwitch callback, which did
    not decompile. This function therefore takes the raw byte semantics.
    """
    return _packet([constants.CMD_PICKER, constants.SUB_PICKER, 0x01 if enabled else 0x00])
