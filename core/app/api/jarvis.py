"""JARVIS integration: capability-aware device control interface.

JARVIS talks to StarLight through this local, permission-controlled surface.
It only sees the device registry, capabilities and state — never protocol
details. Every response carries an explicit ``success`` flag; failures never
look like successes.

Capabilities are advertised only when the service can actually execute them.
``effect`` and ``colorTemperature`` are deliberately absent: ``LightService``
refuses them today (unverified against real hardware).
"""

from __future__ import annotations

from fastapi import APIRouter, Request

router = APIRouter(prefix="/jarvis", tags=["jarvis"])

#: Capabilities that are actually executable through this service right now.
MR_STAR_CAPABILITIES = ["power", "brightness", "color", "speed"]
UNKNOWN_CAPABILITIES = ["power"]


def _manager(r: Request):
    return r.app.state.manager


def _service(r: Request):
    return r.app.state.service


def _capabilities(is_mr_star: bool) -> list[str]:
    return MR_STAR_CAPABILITIES if is_mr_star else UNKNOWN_CAPABILITIES


def _describe_device(d) -> dict:
    return {
        "id": d.id,
        "name": d.name,
        "address": d.address,
        "connected": d.connected,
        "type": "light" if d.is_mr_star else "unknown",
        "capabilities": _capabilities(d.is_mr_star),
    }


def _state_of(service, d) -> dict:
    """Current light state, or a safe disconnected snapshot."""
    if d is None or not d.connected:
        return {"power": False, "brightness": 0, "color": "#000000", "connected": False}
    try:
        st = service.state
        return {
            "power": st.power,
            "brightness": st.brightness,
            "color": st.hex,
            "effect": st.effect,
            "speed": st.speed,
            "connected": st.connected,
        }
    except Exception:
        return {"power": False, "brightness": 0, "color": "#000000", "connected": False}


@router.get("/devices/")
async def list_devices(r: Request) -> dict:
    """List every registered device with its advertised capabilities."""
    return {
        "success": True,
        "devices": [_describe_device(d) for d in _manager(r).devices],
    }


@router.get("/devices/{id}/")
async def get_device(id: str, r: Request) -> dict:
    """Inspect one device: description, capabilities and current state."""
    d = _manager(r).get(id)
    if not d:
        return {"success": False, "error": "device_not_found"}
    payload = _describe_device(d)
    payload["state"] = _state_of(_service(r), d)
    return {"success": True, "device": payload}


@router.get("/devices/{id}/state")
async def get_state(id: str, r: Request) -> dict:
    """Read the current state of a connected device."""
    d = _manager(r).get(id)
    if not d:
        return {"success": False, "error": "device_not_found"}
    if not d.connected:
        return {"success": False, "error": "not_connected"}
    return {"success": True, "device_id": id, "state": _state_of(_service(r), d)}


@router.post("/devices/{id}/command")
async def cmd(id: str, r: Request, capability: str, value: str | None = None) -> dict:
    """Execute one capability command and return the resulting state.

    The request is validated against the registered device's advertised
    capabilities. A failure is always reported as ``success: false`` with an
    explicit error code — never as a fake success.
    """
    d = _manager(r).get(id)
    if not d:
        return {"success": False, "error": "device_not_found"}
    if not d.connected:
        return {"success": False, "error": "not_connected"}
    if capability not in _capabilities(d.is_mr_star):
        return {"success": False, "error": "capability_not_supported"}

    service = _service(r)
    try:
        if capability == "power":
            new_state = await service.power(value == "true")
        elif capability == "brightness":
            new_state = await service.set_brightness(int(value))
        elif capability == "color":
            new_state = await service.set_hex(value or "#000000")
        elif capability == "speed":
            new_state = await service.set_speed(int(value))
        else:  # pragma: no cover - guarded by the capability check above
            return {"success": False, "error": "capability_not_supported"}
    except Exception as e:  # noqa: BLE001 - surface any device failure explicitly
        return {"success": False, "error": "command_failed", "message": str(e)}

    return {
        "success": True,
        "device_id": id,
        "capability": capability,
        "new_state": {
            "power": new_state.power,
            "brightness": new_state.brightness,
            "color": new_state.hex,
            "effect": new_state.effect,
            "speed": new_state.speed,
            "connected": new_state.connected,
        },
    }


@router.get("/scenes/")
async def scenes(r: Request) -> dict:
    """Scenes are not implemented in the core yet — return an empty list.

    Never return invented scenes: JARVIS would report them as available.
    """
    return {"success": True, "scenes": []}


@router.post("/scenes/{id}/activate")
async def act_scene(id: str, r: Request) -> dict:
    """Scene activation is not implemented in the core yet (501)."""
    return {"success": False, "error": "not_implemented", "scene_id": id}


@router.get("/automations/")
async def autos(r: Request) -> dict:
    """Automations are not implemented in the core yet — return an empty list."""
    return {"success": True, "automations": []}


@router.get("/health/")
async def health(r: Request) -> dict:
    """Connectivity summary for JARVIS diagnostics."""
    m = _manager(r)
    return {
        "success": True,
        "status": "healthy",
        "devices_connected": sum(1 for d in m.devices if d.connected),
        "devices_total": len(m.devices),
        "light_state": _state_of(_service(r), m.get()),
    }
