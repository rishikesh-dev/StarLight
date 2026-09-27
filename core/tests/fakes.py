"""Shared test doubles.

A ``LightTransport`` is small enough to fake completely, which is what keeps
the service and the HTTP API testable without a controller or a Bluetooth
adapter.
"""

from __future__ import annotations

from typing import Any

from app.errors import BleError, NotConnectedError
from app.models.device import DeviceInfo
from app.protocol import encoder


class FakeTransport:
    """Records writes and reports whatever connection state the test wants."""

    def __init__(self, *, connected: bool = True, fail: bool = False) -> None:
        self.connected = connected
        self.fail = fail
        self.writes: list[bytes] = []
        self.handler: Any = None
        self.connect_calls = 0

    @property
    def description(self) -> str:
        return "fake transport"

    async def connect(self) -> None:
        self.connect_calls += 1
        self.connected = True

    async def disconnect(self) -> None:
        self.connected = False

    async def write(self, data: bytes) -> None:
        if self.fail:
            raise BleError("write rejected")
        if not self.connected:
            raise NotConnectedError("not connected")
        self.writes.append(data)

    def on_notification(self, handler: Any) -> None:
        self.handler = handler

    @property
    def last_hex(self) -> str:
        return encoder.to_hex(self.writes[-1]) if self.writes else ""

    @property
    def written_hex(self) -> list[str]:
        return [encoder.to_hex(write) for write in self.writes]


def fake_device_info(address: str = "80:AC:C8:5D:AB:CF") -> DeviceInfo:
    return DeviceInfo(
        id=address,
        name="GATT--DEMO",
        address=address,
        rssi=-55,
        is_mr_star=True,
    )
