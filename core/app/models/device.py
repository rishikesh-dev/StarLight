"""Connected/visible BLE device model.

Shaped so several strips can coexist (Phase 16): every device carries its own
id, address, connection state and light state, and the API addresses them by
id rather than assuming one hard-coded unit.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class DeviceInfo(BaseModel):
    """A BLE device as seen by the service."""

    id: str = Field(description="Stable id; the BLE address in practice.")
    name: str | None = None
    address: str = ""
    rssi: int | None = None
    connected: bool = False
    is_mr_star: bool = Field(
        default=False,
        description="True when the advertised name matches the configured prefix.",
    )
