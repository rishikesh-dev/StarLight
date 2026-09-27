"""Manager tests: device targeting and the reconnect watcher.

These need ``bleak`` (the manager imports its scanner), so the module skips
cleanly on a machine without the BLE stack installed.
"""

from __future__ import annotations

import asyncio

import pytest

pytest.importorskip("bleak")

from app.ble import bluez
from app.ble.device import LightDevice
from app.ble.manager import BleManager
from app.config.settings import Settings
from app.models.device import DeviceInfo


class WatchedTransport:
    """Transport stub that exposes a disconnect signal, like the real one."""

    def __init__(self) -> None:
        self.connected = True
        self.disconnected_event = asyncio.Event()
        self.writes: list[bytes] = []

    @property
    def description(self) -> str:
        return "watched"

    async def connect(self) -> None:
        self.connected = True

    async def disconnect(self) -> None:
        self.connected = False

    async def write(self, data: bytes) -> None:
        self.writes.append(data)

    def on_notification(self, handler: object) -> None:
        self._handler = handler


def run(coro: object) -> object:
    return asyncio.run(coro)  # type: ignore[arg-type]


class TestTargeting:
    def test_pinned_address_wins_without_scanning(self, monkeypatch: pytest.MonkeyPatch) -> None:
        manager = BleManager(Settings(device_address="80:AC:C8:5D:AB:CF"))

        async def fail_scan(*_args: object, **_kwargs: object) -> list[DeviceInfo]:
            raise AssertionError("scan should not be needed for a pinned address")

        monkeypatch.setattr(manager, "scan", fail_scan)

        target = run(manager.find_target())

        assert target.id == "80:AC:C8:5D:AB:CF"
        assert target.is_mr_star is True

    def test_bluez_cache_is_checked_before_scanning(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """A connected strip stops advertising, so discovery would miss it."""
        manager = BleManager(Settings(device_name_prefix="GATT--DEMO"))

        async def known() -> list[bluez.KnownDevice]:
            return [
                bluez.KnownDevice(
                    address="80:AC:C8:5D:AB:CF",
                    name="GATT--DEMO",
                    path="/org/bluez/hci0/dev_80_AC_C8_5D_AB_CF",
                    props={"Connected": True},
                )
            ]

        async def fail_scan(*_args: object, **_kwargs: object) -> list[DeviceInfo]:
            raise AssertionError("scan should not be needed when BlueZ knows the device")

        monkeypatch.setattr(bluez, "list_known_devices", known)
        monkeypatch.setattr(manager, "scan", fail_scan)

        target = run(manager.find_target())

        assert target.id == "80:AC:C8:5D:AB:CF"
        assert target.connected is True

    def test_falls_back_to_scanning_when_bluez_does_not_know_it(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        manager = BleManager(Settings(device_name_prefix="GATT--DEMO"))

        async def no_known() -> list[bluez.KnownDevice]:
            return []

        async def scan(*_args: object, **_kwargs: object) -> list[DeviceInfo]:
            return [
                DeviceInfo(
                    id="AA:BB:CC:DD:EE:FF",
                    name="GATT--DEMO",
                    address="AA:BB:CC:DD:EE:FF",
                    rssi=-40,
                    is_mr_star=True,
                )
            ]

        monkeypatch.setattr(bluez, "list_known_devices", no_known)
        monkeypatch.setattr(manager, "scan", scan)

        assert run(manager.find_target()).id == "AA:BB:CC:DD:EE:FF"

    def test_missing_device_raises(self, monkeypatch: pytest.MonkeyPatch) -> None:
        from app.errors import DeviceNotFoundError

        manager = BleManager(Settings(device_name_prefix="GATT--DEMO"))

        async def no_known() -> list[bluez.KnownDevice]:
            return []

        async def scan(*_args: object, **_kwargs: object) -> list[DeviceInfo]:
            return []

        monkeypatch.setattr(bluez, "list_known_devices", no_known)
        monkeypatch.setattr(manager, "scan", scan)

        with pytest.raises(DeviceNotFoundError):
            run(manager.find_target())


class TestWatchLoop:
    def test_disconnect_signal_is_consumed_once(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Guards a tight loop: an un-consumed event would re-enter forever."""

        async def scenario() -> int:
            manager = BleManager(Settings(reconnect_enabled=True))
            transport = WatchedTransport()
            device = LightDevice(DeviceInfo(id="dev", address="dev"), transport)
            manager._devices["dev"] = device  # noqa: SLF001 - deliberate seam

            # Count entries into the recovery path, not connect() calls:
            # ensure_connected deliberately no-ops while the link is still up.
            reconnects: list[str | None] = []

            async def fake_ensure(device_id: str | None = None) -> LightDevice:
                reconnects.append(device_id)
                return device

            monkeypatch.setattr(manager, "ensure_connected", fake_ensure)

            transport.disconnected_event.set()  # simulate a drop
            task = manager.watch("dev")
            await asyncio.sleep(0.05)
            task.cancel()
            return len(reconnects)

        # Exactly one: a signal that is not consumed would loop forever.
        assert run(scenario()) == 1

    def test_watcher_stops_when_reconnect_is_disabled(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        async def scenario() -> int:
            manager = BleManager(Settings(reconnect_enabled=False))
            transport = WatchedTransport()
            manager._devices["dev"] = LightDevice(  # noqa: SLF001
                DeviceInfo(id="dev", address="dev"), transport
            )

            calls: list[str | None] = []

            async def fake_connect(device_id: str | None = None, **_kwargs: object) -> LightDevice:
                calls.append(device_id)
                return manager.get("dev")  # type: ignore[return-value]

            monkeypatch.setattr(manager, "connect", fake_connect)

            transport.disconnected_event.set()
            task = manager.watch("dev")
            await asyncio.sleep(0.05)
            assert task.done()
            return len(calls)

        assert run(scenario()) == 0

    def test_observed_reconnect_backs_off_through_the_schedule(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        manager = BleManager(Settings(reconnect_backoff_s=(0.0, 0.0)))
        attempts: list[float] = []

        async def fake_connect(device_id: str | None = None, **_kwargs: object) -> None:
            attempts.append(1.0)
            raise RuntimeError("still gone")

        monkeypatch.setattr(manager, "connect", fake_connect)

        assert run(manager.ensure_connected("dev")) is None
        assert len(attempts) == 2  # one attempt per backoff entry
