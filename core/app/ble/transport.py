"""The transport seam.

``LightService`` and every client-facing layer depend on this protocol, never
on ``bleak``. That keeps the service unit-testable with a fake transport and
keeps the BLE stack swappable.
"""

from __future__ import annotations

from typing import Awaitable, Callable, Protocol, runtime_checkable

NotificationHandler = Callable[[bytes], None]


@runtime_checkable
class LightTransport(Protocol):
    """Minimal contract a BLE (or fake) connection must fulfil."""

    @property
    def connected(self) -> bool:
        """Whether the link is currently usable."""

    @property
    def description(self) -> str:
        """Human-readable device description for logs and the API."""

    async def connect(self) -> None:
        """Establishes the link and resolves the MR Star characteristics."""

    async def disconnect(self) -> None:
        """Closes the link; must be safe to call when already disconnected."""

    async def write(self, data: bytes) -> None:
        """Writes a packet, chunking and serializing as the protocol needs."""

    def on_notification(self, handler: NotificationHandler | None) -> None:
        """Registers (or clears) the callback for inbound notifications."""


async def noop() -> None:
    """Placeholder coroutine used by tests that need a do-nothing awaitable."""
    return None
