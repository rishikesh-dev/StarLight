"""Runtime settings, read from the environment.

The device is identified by ``device_name_prefix`` by default. An address may
be pinned for a specific unit, but it is never the only identifier - the plan
requires device identification to stay configurable so a second strip can be
added without a code change.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from app.protocol import constants

ENV_PREFIX = "STARLIGHT_"


def _env_str(name: str, default: str) -> str:
    return os.environ.get(f"{ENV_PREFIX}{name}", default)


def _env_optional_str(name: str) -> str | None:
    value = os.environ.get(f"{ENV_PREFIX}{name}", "").strip()
    return value or None


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(f"{ENV_PREFIX}{name}")
    if raw is None or not raw.strip():
        return default
    return int(raw)


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(f"{ENV_PREFIX}{name}")
    if raw is None or not raw.strip():
        return default
    return float(raw)


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(f"{ENV_PREFIX}{name}")
    if raw is None or not raw.strip():
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    """Service configuration."""

    # HTTP API (Phase 6).
    host: str = "127.0.0.1"
    port: int = 8765

    # Device selection.
    device_address: str | None = None
    device_name_prefix: str = constants.DEFAULT_DEVICE_NAME_PREFIX

    # Timeouts.
    scan_timeout_s: float = 10.0
    connect_timeout_s: float = 20.0
    write_timeout_s: float = 5.0

    # Reconnect behaviour (Phase 3 / systemd survival).
    reconnect_enabled: bool = True
    reconnect_backoff_s: tuple[float, ...] = field(
        default=(1.0, 2.0, 5.0, 10.0, 30.0)
    )

    # Connect on startup when a device is configured.
    auto_connect: bool = True

    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> Settings:
        """Builds settings from ``STARLIGHT_*`` environment variables."""
        return cls(
            host=_env_str("HOST", "127.0.0.1"),
            port=_env_int("PORT", 8765),
            device_address=_env_optional_str("DEVICE_ADDRESS"),
            device_name_prefix=_env_str(
                "DEVICE_NAME_PREFIX", constants.DEFAULT_DEVICE_NAME_PREFIX
            ),
            scan_timeout_s=_env_float("SCAN_TIMEOUT_S", 10.0),
            connect_timeout_s=_env_float("CONNECT_TIMEOUT_S", 20.0),
            write_timeout_s=_env_float("WRITE_TIMEOUT_S", 5.0),
            reconnect_enabled=_env_bool("RECONNECT", True),
            auto_connect=_env_bool("AUTO_CONNECT", True),
            log_level=_env_str("LOG_LEVEL", "INFO"),
        )
