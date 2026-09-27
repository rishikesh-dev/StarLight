"""Light control endpoints.

Every mutating endpoint returns the *resulting* state, so a client never has to
guess what happened or issue a follow-up read. State is only reported as
changed if the BLE write actually succeeded - a failure comes back as an error
status and the state is untouched.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import ServiceDep
from app.api.schemas import (
    BrightnessIn,
    ColorIn,
    EffectIn,
    ErrorOut,
    LightStateOut,
    PowerIn,
    SceneIn,
    SpeedIn,
)
from app.errors import FeatureNotAvailableError

router = APIRouter(prefix="/light", tags=["light"])

ERROR_RESPONSES = {
    501: {"model": ErrorOut, "description": "Feature not verified/implemented."},
    503: {"model": ErrorOut, "description": "No device connected."},
}


@router.get("/state", response_model=LightStateOut)
async def get_state(service: ServiceDep) -> LightStateOut:
    """Current state; never touches the device."""
    return LightStateOut.from_state(service.state)


@router.post("/power", response_model=LightStateOut, responses=ERROR_RESPONSES)
async def set_power(payload: PowerIn, service: ServiceDep) -> LightStateOut:
    """Turns the strip on or off. Sends ``BC 01 01 [00|01] 55``."""
    return LightStateOut.from_state(await service.power(payload.on))


@router.post("/color", response_model=LightStateOut, responses=ERROR_RESPONSES)
async def set_color(payload: ColorIn, service: ServiceDep) -> LightStateOut:
    """Sets an RGB color, from channels or a hex string."""
    rgb = payload.to_rgb()
    return LightStateOut.from_state(await service.set_color(rgb.r, rgb.g, rgb.b))


@router.post("/brightness", response_model=LightStateOut, responses=ERROR_RESPONSES)
async def set_brightness(payload: BrightnessIn, service: ServiceDep) -> LightStateOut:
    """Sets brightness as a percent; the core applies the 0-1000 protocol scale."""
    return LightStateOut.from_state(await service.set_brightness(payload.value))


@router.post("/speed", response_model=LightStateOut, responses=ERROR_RESPONSES)
async def set_speed(payload: SpeedIn, service: ServiceDep) -> LightStateOut:
    """Sets animation speed as a percent; sends ``BC 08 01 [value] 55``."""
    return LightStateOut.from_state(await service.set_speed(payload.value))


@router.post(
    "/effect",
    response_model=LightStateOut,
    responses={
        **ERROR_RESPONSES,
        501: {
            "model": ErrorOut,
            "description": (
                "Named effects are not verified against the MR Star protocol. "
                "The mode command exists (BC 06 02 .. .. 55) but the mapping "
                "from its value to a named effect is not established."
            ),
        },
    },
)
async def set_effect(payload: EffectIn, service: ServiceDep) -> LightStateOut:
    """Named effects.

    Answers 501 by design: the plan forbids pretending an unverified effect
    works, so the refusal comes from the service rather than being faked here.
    ``LightService.set_mode`` is the raw escape hatch for protocol testing.
    """
    return LightStateOut.from_state(await service.set_effect(payload.name))


@router.post("/scene", response_model=LightStateOut, responses=ERROR_RESPONSES)
async def activate_scene(payload: SceneIn) -> LightStateOut:
    """Scene activation, which needs the scene store from Phase 14."""
    raise FeatureNotAvailableError(
        "scenes",
        "scene definitions and activation arrive in Phase 14; use power, "
        "color and brightness directly for now",
    )
