"""Request/response models for the HTTP API.

Units are user-facing throughout: ``brightness`` and ``speed`` are percents
(0-100) and color may be given as channels or as a hex string. No client needs
to know that the wire protocol uses 0-1000 for brightness.

Errors share one shape so a script can branch on ``error`` and a human can read
``message``.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, model_validator

from app.models.device import DeviceInfo
from app.models.light_state import LightState, Rgb


class ErrorOut(BaseModel):
    """Every failure response, whatever the cause."""

    success: bool = False
    error: str = Field(description="Machine-readable code, e.g. 'not_connected'.")
    message: str = Field(description="Human-readable explanation.")
    details: dict[str, Any] | None = None


class RgbOut(BaseModel):
    r: int
    g: int
    b: int

    @classmethod
    def from_rgb(cls, rgb: Rgb) -> RgbOut:
        return cls(r=rgb.r, g=rgb.g, b=rgb.b)


class LightStateOut(BaseModel):
    """The canonical state, as every client sees it."""

    success: bool = True
    power: bool
    brightness: int = Field(description="Percent, 0-100.")
    color: str = Field(description="'#RRGGBB'.")
    rgb: RgbOut
    effect: str | None = None
    speed: int = Field(description="Percent, 0-100.")
    scene: str | None = None
    connected: bool
    device: str | None = None

    @classmethod
    def from_state(cls, state: LightState) -> LightStateOut:
        return cls(
            power=state.power,
            brightness=state.brightness,
            color=state.hex,
            rgb=RgbOut.from_rgb(state.rgb),
            effect=state.effect,
            speed=state.speed,
            scene=state.scene,
            connected=state.connected,
            device=state.device,
        )


class DeviceListOut(BaseModel):
    success: bool = True
    devices: list[DeviceInfo]
    active: str | None = Field(
        default=None, description="Id of the device commands currently go to."
    )


class DeviceActionOut(BaseModel):
    """Result of connect/disconnect, including the state afterwards."""

    success: bool = True
    device: DeviceInfo | None = None
    light: LightStateOut


# --- requests -------------------------------------------------------------


class PowerIn(BaseModel):
    on: bool


class BrightnessIn(BaseModel):
    value: int = Field(ge=0, le=100, description="Percent, 0-100.")


class SpeedIn(BaseModel):
    value: int = Field(ge=0, le=100, description="Percent, 0-100.")


class ColorIn(BaseModel):
    """Either all three channels, or a hex string such as ``#8E6CFF``."""

    r: int | None = Field(default=None, ge=0, le=255)
    g: int | None = Field(default=None, ge=0, le=255)
    b: int | None = Field(default=None, ge=0, le=255)
    hex: str | None = None

    @model_validator(mode="after")
    def _resolve(self) -> ColorIn:
        if self.hex is not None:
            # Validate eagerly so a bad string is a 422, not a 500 later.
            Rgb.from_hex(self.hex)
            return self
        channels = (self.r, self.g, self.b)
        if any(channel is None for channel in channels):
            raise ValueError("provide r, g and b, or a hex color")
        return self

    def to_rgb(self) -> Rgb:
        if self.hex is not None:
            return Rgb.from_hex(self.hex)
        return Rgb(r=self.r or 0, g=self.g or 0, b=self.b or 0)


class EffectIn(BaseModel):
    name: str


class SceneIn(BaseModel):
    name: str


class DeviceRefIn(BaseModel):
    """Optional device selector; omitted means the configured device."""

    address: str | None = None
