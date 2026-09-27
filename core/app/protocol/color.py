"""RGB -> HSV conversion, mirroring the APK exactly.

Source: ``sources/e2/e.java``::

    public static float[] B(int i4, int i5, int i6) {
        float[] fArr = new float[3];
        Color.RGBToHSV(i4, i5, i6, fArr);
        if (fArr[1] > 1.0f || (fArr[0] == 0.0f && fArr[1] == 0.0f)) {
            fArr[1] = 1.0f;
        }
        return fArr;
    }

The saturation fix-up is not cosmetic: Android's ``Color.RGBToHSV`` can return
values a hair above 1.0, and it returns saturation 0 for grayscale. The
controller expects 1000 in both cases, so white/black become fully saturated.

This is a port of ``lib/core/utils/color_conversion.dart``; the Flutter tests
and the pytest suite assert the same vectors so the two stay in lockstep.
"""

from __future__ import annotations

_EPSILON = 1e-7


def _clamp_channel(value: int) -> int:
    if value < 0:
        return 0
    if value > 255:
        return 255
    return value


def rgb_to_hsv(red: int, green: int, blue: int) -> tuple[float, float, float]:
    """Returns ``(hue 0-360, saturation 0-1, value 0-1)``."""
    r = _clamp_channel(red) / 255.0
    g = _clamp_channel(green) / 255.0
    b = _clamp_channel(blue) / 255.0

    maximum = max(r, g, b)
    minimum = min(r, g, b)
    delta = maximum - minimum

    if delta < _EPSILON:
        hue = 0.0
    else:
        if maximum == r:
            hue = ((g - b) / delta) % 6.0
        elif maximum == g:
            hue = (b - r) / delta + 2.0
        else:
            hue = (r - g) / delta + 4.0
        hue *= 60.0
        if hue < 0.0:
            hue += 360.0

    saturation = 0.0 if maximum < _EPSILON else delta / maximum
    value = maximum

    # The e2.e.B() fix-up.
    if saturation > 1.0 or (hue == 0.0 and saturation == 0.0):
        saturation = 1.0

    return hue, saturation, value


def compute_color_values(red: int, green: int, blue: int) -> tuple[int, int]:
    """Returns the ``(value1, value2)`` pair the color packet carries.

    ``value1`` is hue truncated to an int, ``value2`` is saturation*1000
    truncated to an int, matching ``(int) B[0]`` and ``(int)(B[1] * 1000)``.
    """
    hue, saturation, _ = rgb_to_hsv(red, green, blue)
    return int(hue), int(saturation * 1000.0)


def rgb_to_hex(red: int, green: int, blue: int) -> str:
    """``#RRGGBB`` uppercase, mirroring ``RGBColor.toHexStr()``."""
    return "#{:02X}{:02X}{:02X}".format(
        _clamp_channel(red), _clamp_channel(green), _clamp_channel(blue)
    )
