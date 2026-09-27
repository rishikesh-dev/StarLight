"""Device endpoints: what is around, what is connected, and how to change it."""

from __future__ import annotations

from fastapi import APIRouter, Query

from app.api.deps import ManagerDep, ServiceDep, SettingsDep
from app.api.schemas import (
    DeviceActionOut,
    DeviceListOut,
    DeviceRefIn,
    ErrorOut,
    LightStateOut,
)
from app.services.light_service import LightService

router = APIRouter(prefix="/device", tags=["device"])

ERROR_RESPONSES = {
    404: {"model": ErrorOut, "description": "No matching device found."},
    503: {"model": ErrorOut, "description": "BLE link unavailable."},
}


@router.get("", response_model=DeviceListOut, responses=ERROR_RESPONSES)
async def list_devices(
    manager: ManagerDep,
    settings: SettingsDep,
    scan: bool = Query(
        default=False,
        description=(
            "Run a fresh scan. Off by default because a connected strip stops "
            "advertising, so BlueZ's cache is the useful source in that case."
        ),
    ),
) -> DeviceListOut:
    """Lists devices: BlueZ's cache plus, optionally, a fresh scan."""
    devices = await manager.scan() if scan else manager.devices
    active = manager.get()
    return DeviceListOut(
        devices=devices,
        active=active.id if active is not None else settings.device_address,
    )


@router.post("/connect", response_model=DeviceActionOut, responses=ERROR_RESPONSES)
async def connect(
    manager: ManagerDep,
    service: ServiceDep,
    payload: DeviceRefIn | None = None,
) -> DeviceActionOut:
    """Connects, then binds the service so commands have somewhere to go.

    With no body the configured device is used: a pinned address first, then
    the advertised name prefix, then BlueZ's cache.
    """
    device = await manager.connect(payload.address if payload else None)
    service.bind(device.transport, device.id)
    manager.watch(device.id)
    return DeviceActionOut(device=device.info, light=_light(service))


@router.post("/disconnect", response_model=DeviceActionOut, responses=ERROR_RESPONSES)
async def disconnect(
    manager: ManagerDep,
    service: ServiceDep,
    payload: DeviceRefIn | None = None,
) -> DeviceActionOut:
    """Closes the link and stops the watcher.

    The service keeps the last device id so clients can see which device was
    bound, but reports ``connected: false``.
    """
    await manager.disconnect(payload.address if payload else None)
    service.refresh_connection(connected=False)
    return DeviceActionOut(device=None, light=_light(service))


def _light(service: LightService) -> LightStateOut:
    return LightStateOut.from_state(service.state)
