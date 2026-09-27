"""``bleak``-backed transport: the one place that talks to the controller.

Behavioural parity with the APK matters here, because the controller firmware
was only ever exercised by that app:

* The write characteristic is FFF3 and the notify characteristic is FFF4 on
  service FFF0 (hard-coded in ``MyApplication.d(byte[])``).
* Payloads longer than 20 bytes are split into 20-byte chunks with a 200 ms
  gap between them (``eVar.f3532g = 20``, ``eVar.f3534i = 200L``).
* Writes are serialized: one packet at a time, in order.

UUID matching goes through :func:`app.ble.uuids.uuids_match` so a short-form
UUID from the BLE stack can never fail to match the full constant.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from bleak import BleakClient
from bleak.backends.device import BLEDevice
from bleak.exc import BleakError as BleakLibraryError

from app.ble import bluez, uuids
from app.ble.transport import LightTransport, NotificationHandler
from app.config.settings import Settings
from app.errors import (
    CharacteristicNotFoundError,
    NotConnectedError,
    ServiceNotFoundError,
    WriteTimeoutError,
)
from app.protocol import constants

logger = logging.getLogger(__name__)


class BleakConnection(LightTransport):
    """A single BLE link to an MR Star controller."""

    def __init__(
        self,
        address: str,
        settings: Settings | None = None,
        name: str | None = None,
    ) -> None:
        self._address = address
        self._name = name
        self._settings = settings or Settings()
        self._client: BleakClient | None = None
        self._write_char: str | None = None
        self._notify_char: str | None = None
        self._write_lock = asyncio.Lock()
        self._notification_handler: NotificationHandler | None = None
        self._disconnected = asyncio.Event()

    # --- introspection ----------------------------------------------------

    @property
    def address(self) -> str:
        return self._address

    @property
    def connected(self) -> bool:
        return bool(self._client and self._client.is_connected)

    @property
    def description(self) -> str:
        label = self._name or "MR Star device"
        return f"{label} ({self._address})"

    @property
    def disconnected_event(self) -> asyncio.Event:
        """Set as soon as the controller drops the link; used for reconnect."""
        return self._disconnected

    # --- lifecycle --------------------------------------------------------

    async def connect(self) -> None:
        """Connects, resolves FFF0/FFF3/FFF4 and subscribes to notifications."""
        if self.connected:
            return

        self._disconnected.clear()
        client = BleakClient(
            await self._connect_target(),
            disconnected_callback=self._handle_disconnect,
            timeout=self._settings.connect_timeout_s,
        )
        try:
            await client.connect()
        except BleakLibraryError as exc:
            raise NotConnectedError(f"failed to connect to {self.description}: {exc}") from exc

        self._client = client
        try:
            await self._resolve_characteristics()
            await self._subscribe()
        except Exception:
            # Do not leave a half-open link behind if discovery fails.
            await self.disconnect()
            raise

        logger.info("connected to %s", self.description)

    async def disconnect(self) -> None:
        """Closes the link; safe to call more than once."""
        client, self._client = self._client, None
        self._write_char = None
        self._notify_char = None
        if client is None:
            return
        try:
            if client.is_connected and self._notify_char:
                await client.stop_notify(self._notify_char)
        except (BleakLibraryError, ValueError) as exc:  # pragma: no cover - stack dependent
            logger.debug("stop_notify during disconnect failed: %s", exc)
        try:
            await client.disconnect()
        except BleakLibraryError as exc:  # pragma: no cover - stack dependent
            logger.debug("disconnect raised: %s", exc)

    async def _connect_target(self) -> str | BLEDevice:
        """Prefers BlueZ's cached device path over a discovery scan.

        Handing bleak a bare address makes it run a fresh scan, which fails for
        a strip that is already connected and therefore not advertising - the
        exact situation a reconnect hits. A known ``Device1`` path connects
        directly.
        """
        known = await bluez.find_known_device(self._address)
        if known is None:
            return self._address
        logger.debug(
            "using known BlueZ device %s at %s (connected=%s, services_resolved=%s)",
            known.address,
            known.path,
            known.connected,
            known.services_resolved,
        )
        return BLEDevice(
            known.address,
            known.name,
            {"path": known.path, "props": known.props},
        )

    async def _resolve_characteristics(self) -> None:
        """Finds the MR Star service and characteristics by normalized UUID."""
        client = self._require_client()
        services = list(client.services)
        available_services = [str(service.uuid) for service in services]
        logger.debug("discovered services: %s", available_services)

        target = next(
            (s for s in services if uuids.uuids_match(str(s.uuid), constants.SERVICE_UUID)),
            None,
        )
        if target is None:
            raise ServiceNotFoundError(constants.SERVICE_UUID, available_services)

        available_chars = [str(c.uuid) for c in target.characteristics]
        write_char = next(
            (
                c
                for c in target.characteristics
                if uuids.uuids_match(str(c.uuid), constants.WRITE_CHAR_UUID)
            ),
            None,
        )
        if write_char is None:
            raise CharacteristicNotFoundError(constants.WRITE_CHAR_UUID, available_chars)

        notify_char = next(
            (
                c
                for c in target.characteristics
                if uuids.uuids_match(str(c.uuid), constants.NOTIFY_CHAR_UUID)
            ),
            None,
        )
        if notify_char is None:
            raise CharacteristicNotFoundError(constants.NOTIFY_CHAR_UUID, available_chars)

        self._write_char = str(write_char.uuid)
        self._notify_char = str(notify_char.uuid)

    async def _subscribe(self) -> None:
        """Enables notifications on FFF4. bleak handles the CCCD itself."""
        client = self._require_client()
        assert self._notify_char is not None
        await client.start_notify(self._notify_char, self._handle_notification)

    # --- io ---------------------------------------------------------------

    async def write(self, data: bytes) -> None:
        """Writes a packet as 20-byte chunks, serialized and time-bounded."""
        client = self._require_client()
        if not self.connected or self._write_char is None:
            raise NotConnectedError("no connection to the controller")

        chunks = [
            data[offset : offset + constants.MAX_WRITE_CHUNK]
            for offset in range(0, len(data), constants.MAX_WRITE_CHUNK)
        ] or [b""]

        async with self._write_lock:
            try:
                async with asyncio.timeout(self._settings.write_timeout_s):
                    for index, chunk in enumerate(chunks):
                        await client.write_gatt_char(
                            self._write_char, chunk, response=False
                        )
                        if index + 1 < len(chunks):
                            await asyncio.sleep(constants.CHUNK_DELAY_S)
            except TimeoutError as exc:
                raise WriteTimeoutError(
                    f"write of {len(data)} bytes timed out after "
                    f"{self._settings.write_timeout_s}s"
                ) from exc
            except BleakLibraryError as exc:
                raise NotConnectedError(f"write failed: {exc}") from exc

    def on_notification(self, handler: NotificationHandler | None) -> None:
        self._notification_handler = handler

    # --- internals --------------------------------------------------------

    def _require_client(self) -> BleakClient:
        if self._client is None:
            raise NotConnectedError("not connected")
        return self._client

    def _handle_notification(self, _characteristic: Any, data: bytearray) -> None:
        handler = self._notification_handler
        if handler is not None:
            handler(bytes(data))

    def _handle_disconnect(self, _client: BleakClient) -> None:
        # bleak clears its own is_connected flag before invoking this, so the
        # only thing that can be reported here is "the link went away". Note
        # that BlueZ can emit a transient false/true pair while re-establishing
        # an ACL that another holder just dropped; the manager consumes the
        # signal and re-checks rather than assuming a hard failure.
        logger.warning("controller disconnected: %s", self.description)
        self._disconnected.set()
