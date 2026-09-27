"""BlueZ helpers: reach devices that are known but not advertising.

Why this exists. ``BleakClient("80:AC:C8:5D:AB:CF")`` does not use BlueZ's
device cache: on Linux it calls ``BleakScanner.find_device_by_address``, which
runs a *fresh discovery scan* and fails with ``BleakDeviceNotFoundError`` when
the address is not currently advertising.

A connected peripheral stops advertising, and BlueZ may hold an ACL link open
(or auto-reconnect to a remembered strip). So the "obvious" way to connect is
exactly the case that fails, and it fails right after a reconnect attempt -
the moment the service most needs to work.

BlueZ does keep a ``org.bluez.Device1`` object for every device it has seen,
with a D-Bus object path. Passing that path to bleak (as ``BLEDevice.details``)
skips discovery entirely and connects straight to the known device.

Everything here degrades quietly: on non-Linux platforms, or if D-Bus is
unavailable, the callers fall back to bleak's own discovery.
"""

from __future__ import annotations

import logging
import sys
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger(__name__)

SERVICE_NAME = "org.bluez"
OBJECT_MANAGER_PATH = "/"
# The standard object-manager interface BlueZ implements; it is *not*
# namespaced under org.bluez.
OBJECT_MANAGER_INTERFACE = "org.freedesktop.DBus.ObjectManager"
DEVICE_INTERFACE = "org.bluez.Device1"


@dataclass(frozen=True)
class KnownDevice:
    """A device BlueZ has an object for, advertising or not."""

    address: str
    name: str | None
    path: str
    props: dict[str, Any] = field(default_factory=dict)

    @property
    def connected(self) -> bool:
        return bool(self.props.get("Connected"))

    @property
    def services_resolved(self) -> bool:
        return bool(self.props.get("ServicesResolved"))


def is_available() -> bool:
    """True on platforms where this module can do anything useful."""
    return sys.platform.startswith("linux")


async def list_known_devices() -> list[KnownDevice]:
    """Every ``Device1`` object BlueZ currently exposes; empty on failure."""
    if not is_available():
        return []

    try:
        objects = await _managed_objects()
    except Exception as exc:  # pragma: no cover - depends on the host
        logger.debug("could not read BlueZ managed objects: %s", exc)
        return []

    devices: list[KnownDevice] = []
    for path, interfaces in objects.items():
        props = interfaces.get(DEVICE_INTERFACE)
        if not props:
            continue
        address = props.get("Address")
        if not address:
            continue
        devices.append(
            KnownDevice(
                address=str(address),
                name=props.get("Name") or props.get("Alias"),
                path=path,
                props=dict(props),
            )
        )
    return devices


async def find_known_device(address: str) -> KnownDevice | None:
    """Looks up one device by address in BlueZ's object tree."""
    wanted = address.strip().lower()
    for device in await list_known_devices():
        if device.address.lower() == wanted:
            return device
    return None


async def _managed_objects() -> dict[str, dict[str, dict[str, Any]]]:
    """Reads ``org.bluez``'s object manager once, on a short-lived bus.

    This sends a raw D-Bus method call rather than going through a proxy:
    it avoids depending on BlueZ's introspection data for ``/``, which is not
    always complete, and keeps the failure path to a single explicit check.
    """
    from dbus_fast import BusType, Message, MessageType, unpack_variants
    from dbus_fast.aio import MessageBus

    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        reply = await bus.call(
            Message(
                destination=SERVICE_NAME,
                path=OBJECT_MANAGER_PATH,
                interface=OBJECT_MANAGER_INTERFACE,
                member="GetManagedObjects",
            )
        )
        if reply.message_type == MessageType.ERROR:
            raise RuntimeError(f"GetManagedObjects failed: {reply.error_name} {reply.body}")
        # Properties arrive wrapped in D-Bus Variants. Leaving them wrapped
        # would break both `Address` comparisons and `bool(props["Connected"])`
        # (a Variant is truthy whatever it holds).
        return unpack_variants(reply.body[0])
    finally:
        bus.disconnect()
