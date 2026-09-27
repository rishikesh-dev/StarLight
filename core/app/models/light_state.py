"""The canonical light state.

This is the single state every client reads and writes (Phase 5). Units are
chosen so no client needs protocol knowledge:

* ``brightness`` is a percent (0-100); the 0-1000 protocol range is applied in
  :mod:`app.protocol.scales`.
* ``speed`` is a percent (0-100), which happens to equal the protocol byte
  because the APK's speed SeekBar has ``android:max="100"``.
* ``effect`` is ``None`` for a plain, non-animated color. Named effects are not
  accepted until Phase 15 proves the hardware mapping, so this field is only
  ever set to a value the service can verify.
* ``scene`` is the name of the last applied scene, purely informational here;
  scene definitions live in the scene service (Phase 14).

Defaults mirror the APK's own globals in ``MyApplication``: power on
(``f1780g = true``), brightness 1000 / 1000 = 100 percent (``f1781h = 1000``),
speed 50 percent (``f1782i = 50``), and red as the starting color.
"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

from app.protocol import color as color_module
from app.protocol import scales


class Rgb(BaseModel):
    """An RGB triple, 0-255 per channel."""

    r: int = 255
    g: int = 0
    b: int = 0

    @field_validator("r", "g", "b")
    @classmethod
    def _clamp(cls, value: int) -> int:
        return max(0, min(255, value))

    @classmethod
    def from_hex(cls, value: str) -> Rgb:
        """Parses ``#RRGGBB``, ``RRGGBB`` or the 3-digit ``#RGB`` form."""
        text = value.strip().lstrip("#")
        if len(text) == 3:
            text = "".join(channel * 2 for channel in text)
        if len(text) != 6:
            raise ValueError(f"invalid hex color: {value!r}")
        return cls(
            r=int(text[0:2], 16),
            g=int(text[2:4], 16),
            b=int(text[4:6], 16),
        )

    def to_hex(self) -> str:
        return color_module.rgb_to_hex(self.r, self.g, self.b)


class LightState(BaseModel):
    """The whole of what the service knows about the light."""

    power: bool = True
    brightness: int = scales.DEFAULT_BRIGHTNESS_PERCENT
    rgb: Rgb = Field(default_factory=Rgb)
    effect: str | None = None
    speed: int = scales.DEFAULT_SPEED_PERCENT
    scene: str | None = None
    connected: bool = False
    device: str | None = None

    @field_validator("brightness", "speed")
    @classmethod
    def _clamp_percent(cls, value: int) -> int:
        return scales.clamp_percent(value)

    @property
    def hex(self) -> str:
        return self.rgb.to_hex()
