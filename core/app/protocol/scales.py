"""User-facing value scales versus the protocol's internal ranges.

The plan is explicit that a client must never have to know the protocol's
numbers: the API, CLI and Flutter all speak percent, and this module is the
only place that converts.

Verified ranges (decompiled layouts, not guesses):

* brightness - ``fragment_adjust.xml`` sets ``android:max="1000"`` on
  ``sb_brightness``, so the protocol range is 0-1000 and a percent maps by
  multiplying by 10. ``e1/d.java`` clamps anything below 3 up to 3.
* speed - ``fragment_mode.xml`` sets ``android:max="100"`` on ``sb_speed`` and
  ``e1/g.java`` sends the SeekBar progress straight through, so speed is
  already a percent and maps 1:1 onto the protocol byte.
"""

from __future__ import annotations

from app.protocol import constants

DEFAULT_BRIGHTNESS_PERCENT = 100
DEFAULT_SPEED_PERCENT = 50


def clamp_percent(value: int) -> int:
    """Clamps a percent value into 0-100."""
    if value < 0:
        return 0
    if value > 100:
        return 100
    return value


def brightness_percent_to_protocol(percent: int) -> int:
    """Percent -> the 0-1000 value the brightness packet carries."""
    scaled = clamp_percent(percent) * (constants.BRIGHTNESS_PROTOCOL_MAX // 100)
    if scaled < constants.BRIGHTNESS_PROTOCOL_MIN:
        return constants.BRIGHTNESS_PROTOCOL_MIN
    return scaled


def brightness_protocol_to_percent(value: int) -> int:
    """The 0-1000 packet value -> percent, for decoding observed state.

    Rounds halves away from zero to match Dart's ``round()``; Python's builtin
    rounds halves to even, which would drift from the Flutter client.
    """
    percent = int((value / (constants.BRIGHTNESS_PROTOCOL_MAX / 100)) + 0.5)
    return clamp_percent(percent)


def speed_percent_to_byte(percent: int) -> int:
    """Percent -> the byte the speed packet carries (same range, 0-100)."""
    return clamp_percent(percent)
