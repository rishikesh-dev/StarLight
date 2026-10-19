"""Tests for the JARVIS integration surface (/jarvis/*).

These tests pin the capability-aware contract JARVIS depends on:
explicit success flags, real state, real capabilities, no invented data.
"""

from __future__ import annotations

import pytest

from app.api import jarvis
from app.main import create_app
from app.services.light_service import LightService
from tests.fakes import FakeTransport

pytest.importorskip("bleak")

from fastapi.testclient import TestClient  # noqa: E402


class StubDevice:
    """Minimal stand-in for LightDevice as seen by the jarvis routes."""

    def __init__(self, device_id="dev-1", connected=True, is_mr_star=True):
        self.id = device_id
        self.name = "GATT--DEMO"
        self.address = "AA:BB:CC:DD:EE:FF"
        self.connected = connected
        self.is_mr_star = is_mr_star


class StubManager:
    def __init__(self, devices):
        self.devices = devices

    def get(self, device_id=None):
        if device_id is None:
            # Mirrors BleManager: no id means "the active device".
            return self.devices[0] if self.devices else None
        for d in self.devices:
            if d.id == device_id:
                return d
        return None


def _client(devices=None, service=None):
    devices = [StubDevice()] if devices is None else devices
    manager = StubManager(devices)
    service = service or LightService(FakeTransport())
    app = create_app(manager=manager, service=service)
    return TestClient(app)


def test_list_devices_advertises_verified_capabilities_only():
    client = _client()
    body = client.get("/jarvis/devices/").json()
    assert body["success"] is True
    assert len(body["devices"]) == 1
    dev = body["devices"][0]
    assert dev["type"] == "light"
    # Only capabilities the service can actually execute.
    assert dev["capabilities"] == ["power", "brightness", "color", "speed"]
    assert "effect" not in dev["capabilities"]
    assert "colorTemperature" not in dev["capabilities"]


def test_list_devices_unknown_type_gets_power_only():
    client = _client(devices=[StubDevice(device_id="x", is_mr_star=False)])
    body = client.get("/jarvis/devices/").json()
    assert body["devices"][0]["type"] == "unknown"
    assert body["devices"][0]["capabilities"] == ["power"]


def test_get_device_includes_state():
    client = _client()
    body = client.get("/jarvis/devices/dev-1/").json()
    assert body["success"] is True
    assert body["device"]["id"] == "dev-1"
    assert body["device"]["state"]["connected"] is True


def test_get_device_not_found():
    client = _client()
    body = client.get("/jarvis/devices/nope/").json()
    assert body == {"success": False, "error": "device_not_found"}


def test_get_state_requires_connection():
    client = _client(devices=[StubDevice(connected=False)])
    body = client.get("/jarvis/devices/dev-1/state").json()
    assert body == {"success": False, "error": "not_connected"}


def test_command_power_updates_state():
    client = _client()
    body = client.post(
        "/jarvis/devices/dev-1/command", params={"capability": "power", "value": "false"}
    ).json()
    assert body["success"] is True
    assert body["new_state"]["power"] is False


def test_command_brightness_updates_state():
    client = _client()
    body = client.post(
        "/jarvis/devices/dev-1/command",
        params={"capability": "brightness", "value": "42"},
    ).json()
    assert body["success"] is True
    assert body["new_state"]["brightness"] == 42


def test_command_color_updates_state():
    client = _client()
    body = client.post(
        "/jarvis/devices/dev-1/command",
        params={"capability": "color", "value": "#00FF00"},
    ).json()
    assert body["success"] is True
    assert body["new_state"]["color"].lower() == "#00ff00"


def test_command_unsupported_capability_is_rejected():
    client = _client()
    body = client.post(
        "/jarvis/devices/dev-1/command", params={"capability": "effect", "value": "strobe"}
    ).json()
    assert body == {"success": False, "error": "capability_not_supported"}


def test_command_on_disconnected_device_is_rejected():
    client = _client(devices=[StubDevice(connected=False)])
    body = client.post(
        "/jarvis/devices/dev-1/command", params={"capability": "power", "value": "true"}
    ).json()
    assert body == {"success": False, "error": "not_connected"}


def test_command_failure_is_never_reported_as_success():
    """A failing transport write must surface as success=false."""

    class BoomTransport(FakeTransport):
        async def write(self, data):
            raise RuntimeError("link down")

    client = _client(service=LightService(BoomTransport()))
    body = client.post(
        "/jarvis/devices/dev-1/command", params={"capability": "power", "value": "true"}
    ).json()
    assert body["success"] is False
    assert body["error"] == "command_failed"
    assert "link down" in body["message"]


def test_scenes_and_automations_do_not_invent_data():
    client = _client()
    assert client.get("/jarvis/scenes/").json() == {"success": True, "scenes": []}
    assert client.get("/jarvis/automations/").json() == {
        "success": True,
        "automations": [],
    }
    activate = client.post("/jarvis/scenes/anything/activate").json()
    assert activate["success"] is False
    assert activate["error"] == "not_implemented"


def test_health_reports_counts():
    client = _client()
    body = client.get("/jarvis/health/").json()
    assert body["success"] is True
    assert body["devices_total"] == 1
    assert body["devices_connected"] == 1
    assert "light_state" in body


def test_capabilities_constant_matches_light_service_support():
    # power/brightness/color/speed are implemented by LightService; effect is
    # deliberately refused (UnsupportedEffectError) and must not be advertised.
    assert jarvis.MR_STAR_CAPABILITIES == ["power", "brightness", "color", "speed"]
