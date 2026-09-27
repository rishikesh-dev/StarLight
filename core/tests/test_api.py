"""HTTP API tests.

Driven with FastAPI's TestClient over a fake transport, so the whole stack
except the Bluetooth radio is exercised. ``bleak`` is imported by the app's
manager, hence the skip guard.
"""

from __future__ import annotations

from typing import Any

import pytest

pytest.importorskip("bleak")

from fastapi.testclient import TestClient

from app.ble.device import LightDevice
from app.config.settings import Settings
from app.main import create_app
from app.models.device import DeviceInfo
from app.services.light_service import LightService
from tests.fakes import FakeTransport, fake_device_info


class StubManager:
    """Stands in for BleManager so device flows need no BLE at all."""

    def __init__(self, device: LightDevice | None = None) -> None:
        self._device = device
        self.watchers: list[str | None] = []

    @property
    def devices(self) -> list[DeviceInfo]:
        return [self._device.info] if self._device is not None else []

    def get(self, device_id: str | None = None) -> LightDevice | None:
        return self._device

    async def connect(self, device_id: str | None = None, **_: Any) -> LightDevice:
        if self._device is None:
            raise AssertionError("stub has no device to connect to")
        return self._device

    async def disconnect(self, device_id: str | None = None) -> None:
        self._device = None

    async def scan(self, timeout_s: float | None = None) -> list[DeviceInfo]:
        return self.devices

    def watch(self, device_id: str | None = None) -> None:
        self.watchers.append(device_id)

    async def close(self) -> None:
        return None


@pytest.fixture()
def transport() -> FakeTransport:
    return FakeTransport()


@pytest.fixture()
def client(transport: FakeTransport):
    """An app wired to a fake transport, with startup auto-connect disabled."""
    settings = Settings(auto_connect=False)
    app = create_app(
        settings=settings,
        manager=StubManager(),
        service=LightService(transport),
    )
    with TestClient(app) as test_client:
        yield test_client


class TestHealthAndState:
    def test_health(self, client: TestClient) -> None:
        response = client.get("/health")
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "ok"
        assert body["light"]["power"] is True

    def test_health_reports_light_in_the_same_shape_as_the_state_endpoint(
        self, client: TestClient
    ) -> None:
        # One parser for clients: /health's light block must match /light/state.
        assert client.get("/health").json()["light"] == client.get("/light/state").json()

    def test_state_defaults_match_the_apk(self, client: TestClient) -> None:
        response = client.get("/light/state")
        assert response.status_code == 200
        body = response.json()
        assert body["success"] is True
        assert body["power"] is True
        assert body["brightness"] == 100
        assert body["color"] == "#FF0000"
        assert body["rgb"] == {"r": 255, "g": 0, "b": 0}
        assert body["effect"] is None
        assert body["connected"] is True

    def test_state_read_never_writes(
        self, client: TestClient, transport: FakeTransport
    ) -> None:
        client.get("/light/state")
        assert transport.writes == []


class TestPower:
    def test_power_off(self, client: TestClient, transport: FakeTransport) -> None:
        response = client.post("/light/power", json={"on": False})
        assert response.status_code == 200
        assert response.json()["power"] is False
        assert transport.last_hex == "BC 01 01 01 55"

    def test_power_on(self, client: TestClient, transport: FakeTransport) -> None:
        response = client.post("/light/power", json={"on": True})
        assert response.status_code == 200
        assert response.json()["power"] is True
        assert transport.last_hex == "BC 01 01 00 55"

    def test_missing_field_is_a_validation_error(self, client: TestClient) -> None:
        assert client.post("/light/power", json={}).status_code == 422


class TestBrightness:
    def test_brightness_percent_becomes_protocol_units(
        self, client: TestClient, transport: FakeTransport
    ) -> None:
        response = client.post("/light/brightness", json={"value": 50})
        assert response.status_code == 200
        assert response.json()["brightness"] == 50
        assert transport.last_hex == "BC 05 06 01 F4 00 00 00 00 55"

    def test_out_of_range_is_rejected_not_clamped(
        self, client: TestClient, transport: FakeTransport
    ) -> None:
        response = client.post("/light/brightness", json={"value": 150})
        assert response.status_code == 422
        assert transport.writes == []
        # Validation failures use the same JSON shape as domain failures.
        body = response.json()
        assert body["success"] is False
        assert body["error"] == "validation_error"
        assert body["details"]["problems"][0]["field"] == "value"

    def test_negative_is_rejected(self, client: TestClient) -> None:
        assert client.post("/light/brightness", json={"value": -5}).status_code == 422


class TestColor:
    def test_color_from_channels(self, client: TestClient, transport: FakeTransport) -> None:
        response = client.post("/light/color", json={"r": 142, "g": 108, "b": 255})
        assert response.status_code == 200
        assert response.json()["color"] == "#8E6CFF"
        assert transport.last_hex == "BC 04 06 00 FD 02 40 00 00 55"

    def test_color_from_hex(self, client: TestClient, transport: FakeTransport) -> None:
        response = client.post("/light/color", json={"hex": "#8E6CFF"})
        assert response.status_code == 200
        assert response.json()["rgb"] == {"r": 142, "g": 108, "b": 255}
        assert transport.last_hex == "BC 04 06 00 FD 02 40 00 00 55"

    def test_partial_channels_are_rejected(self, client: TestClient) -> None:
        assert client.post("/light/color", json={"r": 10}).status_code == 422

    def test_empty_body_is_rejected(self, client: TestClient) -> None:
        assert client.post("/light/color", json={}).status_code == 422

    def test_bad_hex_is_rejected(self, client: TestClient, transport: FakeTransport) -> None:
        response = client.post("/light/color", json={"hex": "notacolor"})
        assert response.status_code == 422
        assert transport.writes == []


class TestSpeed:
    def test_speed_is_sent_as_a_byte(self, client: TestClient, transport: FakeTransport) -> None:
        response = client.post("/light/speed", json={"value": 73})
        assert response.status_code == 200
        assert response.json()["speed"] == 73
        assert transport.last_hex == "BC 08 01 49 55"


class TestUnverifiedFeatures:
    def test_effect_is_refused_with_a_reason(
        self, client: TestClient, transport: FakeTransport
    ) -> None:
        response = client.post("/light/effect", json={"name": "rainbow"})
        assert response.status_code == 501
        body = response.json()
        assert body["success"] is False
        assert body["error"] == "unsupported_effect"
        assert body["details"]["effect"] == "rainbow"
        assert transport.writes == []

    def test_scene_activation_reports_not_implemented(self, client: TestClient) -> None:
        response = client.post("/light/scene", json={"name": "coding"})
        assert response.status_code == 501
        assert response.json()["error"] == "not_implemented"
        assert response.json()["details"]["feature"] == "scenes"

    @pytest.mark.parametrize(
        ("method", "path"),
        [
            ("get", "/scenes"),
            ("post", "/scenes"),
            ("delete", "/scenes/coding"),
            ("get", "/presets"),
            ("post", "/presets"),
        ],
    )
    def test_scene_and_preset_routes_answer_501(
        self, client: TestClient, method: str, path: str
    ) -> None:
        # A well-formed body on purpose: the stubs must answer "not yet"
        # rather than failing validation for a feature that does not exist.
        call = getattr(client, method)
        response = (
            call(path, json={"name": "coding"}) if method == "post" else call(path)
        )
        assert response.status_code == 501
        assert response.json()["error"] == "not_implemented"


class TestErrorContract:
    def test_write_failure_is_reported_and_state_is_unchanged(
        self, transport: FakeTransport
    ) -> None:
        transport.fail = True
        app = create_app(
            settings=Settings(auto_connect=False),
            manager=StubManager(),
            service=LightService(transport),
        )
        with TestClient(app) as client:
            response = client.post("/light/power", json={"on": False})

        assert response.status_code == 503
        body = response.json()
        assert body["success"] is False
        assert body["error"] == "ble_error"
        assert body["message"] == "write rejected"

        # The command never landed, so the state must not claim otherwise.
        assert client.get("/light/state").json()["power"] is True

    def test_unbound_service_reports_not_connected(self) -> None:
        app = create_app(
            settings=Settings(auto_connect=False),
            manager=StubManager(),
            service=LightService(),
        )
        with TestClient(app) as client:
            response = client.post("/light/power", json={"on": True})

        assert response.status_code == 503
        assert response.json()["error"] == "not_connected"

    def test_disconnected_transport_reports_not_connected(self) -> None:
        app = create_app(
            settings=Settings(auto_connect=False),
            manager=StubManager(),
            service=LightService(FakeTransport(connected=False)),
        )
        with TestClient(app) as client:
            response = client.get("/light/state")
            assert response.status_code == 200
            assert response.json()["connected"] is False

    def test_unknown_route_is_a_plain_404(self, client: TestClient) -> None:
        assert client.get("/nope").status_code == 404


class TestDeviceEndpoints:
    def test_list_devices_is_empty_without_a_link(self, client: TestClient) -> None:
        response = client.get("/device")
        assert response.status_code == 200
        assert response.json()["devices"] == []

    def test_scan_flag_is_accepted(self, client: TestClient) -> None:
        assert client.get("/device?scan=true").status_code == 200

    def test_connect_binds_the_service_then_commands_work(self, transport: FakeTransport) -> None:
        device = LightDevice(fake_device_info(), transport)
        manager = StubManager(device)
        service = LightService()
        app = create_app(
            settings=Settings(auto_connect=False), manager=manager, service=service
        )

        with TestClient(app) as client:
            response = client.post("/device/connect", json={})
            assert response.status_code == 200
            body = response.json()
            assert body["device"]["name"] == "GATT--DEMO"
            assert body["light"]["connected"] is True
            assert manager.watchers == ["80:AC:C8:5D:AB:CF"]

            power = client.post("/light/power", json={"on": False})
            assert power.status_code == 200
            assert transport.last_hex == "BC 01 01 01 55"

    def test_connect_with_an_explicit_address(self, transport: FakeTransport) -> None:
        captured: dict[str, Any] = {}

        class RecordingManager(StubManager):
            async def connect(self, device_id: str | None = None, **_: Any) -> LightDevice:
                captured["address"] = device_id
                return await super().connect(device_id)

        app = create_app(
            settings=Settings(auto_connect=False),
            manager=RecordingManager(LightDevice(fake_device_info(), transport)),
            service=LightService(),
        )

        with TestClient(app) as client:
            response = client.post(
                "/device/connect", json={"address": "80:AC:C8:5D:AB:CF"}
            )

        assert response.status_code == 200
        assert captured["address"] == "80:AC:C8:5D:AB:CF"

    def test_disconnect_reports_disconnected(self, transport: FakeTransport) -> None:
        manager = StubManager(LightDevice(fake_device_info(), transport))
        app = create_app(
            settings=Settings(auto_connect=False),
            manager=manager,
            service=LightService(),
        )

        with TestClient(app) as client:
            client.post("/device/connect", json={})
            response = client.post("/device/disconnect", json={})

        assert response.status_code == 200
        body = response.json()
        assert body["light"]["connected"] is False
        # The last bound device is still reported, for diagnostics.
        assert body["light"]["device"] == "80:AC:C8:5D:AB:CF"
        assert body["device"] is None
