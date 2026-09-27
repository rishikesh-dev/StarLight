"""Shared FastAPI dependencies.

Services are read off ``app.state`` so tests can build an app around a fake
transport without any BLE hardware.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request

from app.ble.manager import BleManager
from app.config.settings import Settings
from app.services.light_service import LightService


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_manager(request: Request) -> BleManager:
    return request.app.state.manager


def get_service(request: Request) -> LightService:
    return request.app.state.service


SettingsDep = Annotated[Settings, Depends(get_settings)]
ManagerDep = Annotated[BleManager, Depends(get_manager)]
ServiceDep = Annotated[LightService, Depends(get_service)]
