"""A logical device: what it is, plus how to talk to it.

Nothing here is single-device specific - the manager keeps a collection of
these, which is what Phase 16 needs - but nothing forces multi-device
behaviour on clients that only care about one strip either.
"""

from __future__ import annotations

from app.ble.transport import LightTransport
from app.models.device import DeviceInfo


class LightDevice:
    """One controller: its ``DeviceInfo`` and its live transport."""

    def __init__(self, info: DeviceInfo, transport: LightTransport) -> None:
        self._info = info
        self._transport = transport

    @property
    def id(self) -> str:
        return self._info.id

    @property
    def info(self) -> DeviceInfo:
        """Current metadata, with ``connected`` kept in step with the link."""
        return self._info.model_copy(update={"connected": self._transport.connected})

    @property
    def transport(self) -> LightTransport:
        return self._transport

    async def connect(self) -> None:
        await self._transport.connect()

    async def disconnect(self) -> None:
        await self._transport.disconnect()
