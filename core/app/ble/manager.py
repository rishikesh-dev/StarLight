"""Scanning, discovery and connection lifecycle.

The manager is the only place that creates transports, so it is also the only
place that knows how a controller is found: by configured address when one is
pinned, otherwise by the advertised name prefix. The MAC is never baked in.

Reconnect is intentionally simple and explicit (Phase 3): back off through the
configured schedule and re-establish the link, re-resolving services each time.
The reconnect loop is opt-in and started by :meth:`watch`, so tests and the
CLI can drive connect/disconnect deterministically.
"""

from __future__ import annotations

import asyncio
import logging

from bleak import BleakScanner

from app.ble import bluez
from app.ble.connection import BleakConnection
from app.ble.device import LightDevice
from app.config.settings import Settings
from app.errors import DeviceNotFoundError
from app.models.device import DeviceInfo

logger = logging.getLogger(__name__)


class BleManager:
    """Owns every known device and the link to each of them."""

    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or Settings()
        self._devices: dict[str, LightDevice] = {}
        self._watchers: list[asyncio.Task[None]] = []

    # --- introspection ----------------------------------------------------

    @property
    def devices(self) -> list[DeviceInfo]:
        return [device.info for device in self._devices.values()]

    def get(self, device_id: str | None = None) -> LightDevice | None:
        """Returns a device by id, or the only/first known one when omitted."""
        if device_id is None:
            if not self._devices:
                return None
            return next(iter(self._devices.values()))
        return self._devices.get(device_id)

    # --- scanning ---------------------------------------------------------

    async def scan(self, timeout_s: float | None = None) -> list[DeviceInfo]:
        """Scans for nearby devices, flagging any that look like MR Star units."""
        timeout = timeout_s if timeout_s is not None else self._settings.scan_timeout_s
        logger.info("scanning for %.1fs (name prefix %r)", timeout, self._settings.device_name_prefix)
        discovered = await BleakScanner.discover(timeout=timeout, return_adv=True)

        found: list[DeviceInfo] = []
        # A connected strip does not advertise, so fold in whatever BlueZ
        # already knows; otherwise `starlight devices` would hide the very
        # device the user is working with.
        seen = {address.lower() for address in discovered}
        for known in await bluez.list_known_devices():
            if known.address.lower() in seen:
                continue
            found.append(
                DeviceInfo(
                    id=known.address,
                    name=known.name,
                    address=known.address,
                    connected=known.connected,
                    is_mr_star=self._matches(known.name),
                )
            )

        for address, (device, advertisement) in discovered.items():
            name = advertisement.local_name or device.name
            found.append(
                DeviceInfo(
                    id=address,
                    name=name,
                    address=address,
                    rssi=advertisement.rssi,
                    connected=address in self._devices and self._devices[address].transport.connected,
                    is_mr_star=self._matches(name),
                )
            )
        found.sort(key=lambda item: (not item.is_mr_star, -(item.rssi or -999)))
        return found

    async def find_target(self, timeout_s: float | None = None) -> DeviceInfo:
        """Finds the configured device: pinned address first, then name prefix."""
        if self._settings.device_address:
            return DeviceInfo(
                id=self._settings.device_address,
                name=None,
                address=self._settings.device_address,
                is_mr_star=True,
            )

        # Check BlueZ's cache before scanning: a strip that is already
        # connected never shows up in discovery results.
        for known in await bluez.list_known_devices():
            if self._matches(known.name):
                return DeviceInfo(
                    id=known.address,
                    name=known.name,
                    address=known.address,
                    connected=known.connected,
                    is_mr_star=True,
                )

        for candidate in await self.scan(timeout_s):
            if candidate.is_mr_star:
                return candidate
        raise DeviceNotFoundError(
            f"no device with name prefix {self._settings.device_name_prefix!r} found"
        )

    # --- connection -------------------------------------------------------

    async def connect(
        self,
        device_id: str | None = None,
        *,
        timeout_s: float | None = None,
    ) -> LightDevice:
        """Connects to a known id, the configured device, or a fresh scan."""
        target_id = device_id or self._settings.device_address
        existing = self.get(target_id) if target_id in self._devices else None

        if existing is not None:
            if not existing.transport.connected:
                await existing.connect()
            return existing

        if target_id is None:
            target = await self.find_target(timeout_s)
            target_id, name = target.id, target.name
        else:
            name = None

        transport = BleakConnection(target_id, self._settings, name=name)
        device = LightDevice(
            DeviceInfo(id=target_id, name=name, address=target_id, is_mr_star=True),
            transport,
        )
        await device.connect()
        self._devices[target_id] = device
        return device

    async def disconnect(self, device_id: str | None = None) -> None:
        device = self.get(device_id)
        if device is not None:
            await device.disconnect()
        if device_id is not None:
            self._devices.pop(device_id, None)

    # --- reconnect --------------------------------------------------------

    async def ensure_connected(self, device_id: str | None = None) -> LightDevice | None:
        """Reconnects using the configured backoff schedule, once per schedule."""
        for delay in self._settings.reconnect_backoff_s:
            device = self.get(device_id)
            if device is not None and device.transport.connected:
                return device
            try:
                return await self.connect(device_id)
            except Exception as exc:
                logger.warning("reconnect attempt failed (%s); retrying in %.0fs", exc, delay)
                await asyncio.sleep(delay)
        return None

    def watch(self, device_id: str | None = None) -> asyncio.Task[None]:
        """Starts a background task that reconnects when the link drops."""
        task = asyncio.create_task(self._watch_loop(device_id))
        self._watchers.append(task)
        return task

    async def _watch_loop(self, device_id: str | None) -> None:
        while True:
            device = self.get(device_id)
            connection = getattr(device.transport, "disconnected_event", None) if device else None
            if connection is None:
                await asyncio.sleep(1.0)
                continue

            await connection.wait()
            # Consume the signal before acting. A real controller can report a
            # transient disconnect followed by an immediate re-established
            # link (observed on BlueZ when another holder drops the ACL and our
            # own Connect re-establishes it); leaving the event set would make
            # this loop re-enter without ever blocking again.
            connection.clear()

            if not self._settings.reconnect_enabled:
                return
            try:
                await self.ensure_connected(device_id)
            except Exception as exc:  # pragma: no cover - defensive
                logger.warning("reconnect failed: %s", exc)
            finally:
                connection.clear()

    async def close(self) -> None:
        """Cancels watchers and disconnects everything; used on shutdown."""
        for task in self._watchers:
            task.cancel()
        self._watchers.clear()
        for device_id in list(self._devices):
            await self.disconnect(device_id)

    def _matches(self, name: str | None) -> bool:
        if not name:
            return False
        return name.upper().startswith(self._settings.device_name_prefix.upper())
