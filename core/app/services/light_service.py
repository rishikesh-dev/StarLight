"""The single source of truth for light state.

Two rules shape this class:

1. **State follows a successful write.** Phase 11 is explicit that the UI must
   not fake a change. Every mutator here writes the packet first and only then
   updates the state, so a failed or timed-out write leaves the state exactly
   as it was and raises for the caller to surface.
2. **Unverified features are refused, not faked.** Phase 15 forbids pretending
   an effect works. Named effects raise ``UnsupportedEffectError`` until the
   mode mapping is proven; ``set_mode`` exists for raw experimentation and
   deliberately does not record an effect name.

The transport is injected, so the whole service is testable without BLE.
"""

from __future__ import annotations

import logging
from typing import Callable, Iterable

from app.ble.transport import LightTransport
from app.errors import NotConnectedError, UnsupportedEffectError
from app.models.light_state import LightState, Rgb
from app.protocol import decoder, encoder, scales

logger = logging.getLogger(__name__)

StateListener = Callable[[LightState], None]


class LightService:
    """Commands plus the canonical state for one controller."""

    def __init__(
        self,
        transport: LightTransport | None = None,
        device_id: str | None = None,
        state: LightState | None = None,
    ) -> None:
        self._transport = transport
        self._state = state or LightState(device=device_id)
        self._listeners: list[StateListener] = []
        self._last_command_hex: str | None = None
        self._last_notification_hex: str | None = None
        self._last_error: str | None = None
        if transport is not None:
            self._attach_transport(transport)
            # Reflect reality from the start: a service built around a live
            # transport must not report itself as disconnected until bind().
            self._state = self._state.model_copy(
                update={"connected": transport.connected}
            )

    # --- wiring -----------------------------------------------------------

    def bind(self, transport: LightTransport, device_id: str | None = None) -> None:
        """Attaches the transport once the manager has a live link."""
        self._attach_transport(transport)
        self._state = self._state.model_copy(
            update={"connected": transport.connected, "device": device_id}
        )
        self._publish()

    def _attach_transport(self, transport: LightTransport) -> None:
        self._transport = transport
        transport.on_notification(self._handle_notification)

    @property
    def transport(self) -> LightTransport | None:
        return self._transport

    def refresh_connection(self, connected: bool | None = None, device_id: str | None = None) -> None:
        """Re-reads link state; called after connect/disconnect or a drop."""
        if connected is None:
            connected = bool(self._transport and self._transport.connected)
        self._state = self._state.model_copy(
            update={
                "connected": connected,
                "device": device_id if device_id is not None else self._state.device,
            }
        )
        self._publish()

    # --- state ------------------------------------------------------------

    @property
    def state(self) -> LightState:
        """A copy, so callers cannot mutate the canonical state."""
        return self._state.model_copy(deep=True)

    def snapshot(self) -> dict[str, object]:
        """JSON-ready view used by the API and the CLI."""
        return self.state.model_dump()

    @property
    def diagnostics(self) -> dict[str, object]:
        """Debug data for developer mode (Phase 18)."""
        return {
            "device": self._state.device,
            "connected": self._state.connected,
            "last_command": self._last_command_hex,
            "last_notification": self._last_notification_hex,
            "last_error": self._last_error,
        }

    def subscribe(self, listener: StateListener) -> Callable[[], None]:
        """Registers a listener and returns an unsubscribe callable."""
        self._listeners.append(listener)

        def unsubscribe() -> None:
            if listener in self._listeners:
                self._listeners.remove(listener)

        return unsubscribe

    def _publish(self) -> None:
        payload = self.state
        for listener in list(self._listeners):
            try:
                listener(payload)
            except Exception:  # pragma: no cover - a bad listener must not break control
                logger.exception("state listener raised")

    # --- commands ---------------------------------------------------------

    async def power(self, on: bool) -> LightState:
        """Turns the strip on or off; state changes only if the write lands."""
        return await self._apply(encoder.set_power(on), power=on)

    async def set_color(self, red: int, green: int, blue: int) -> LightState:
        """Sets an RGB color via the APK's own RGB->HSV conversion."""
        rgb = Rgb(r=red, g=green, b=blue)
        return await self._apply(encoder.color_from_rgb(rgb.r, rgb.g, rgb.b), rgb=rgb)

    async def set_hex(self, value: str) -> LightState:
        """Sets a color from ``#RRGGBB``."""
        rgb = Rgb.from_hex(value)
        return await self.set_color(rgb.r, rgb.g, rgb.b)

    async def set_brightness(self, percent: int) -> LightState:
        """Sets brightness as a percent (0-100); the core applies the 0-1000 scale."""
        clamped = scales.clamp_percent(percent)
        return await self._apply(
            encoder.set_brightness_percent(clamped), brightness=clamped
        )

    async def set_speed(self, percent: int) -> LightState:
        """Sets animation speed as a percent (0-100)."""
        clamped = scales.clamp_percent(percent)
        return await self._apply(encoder.set_speed_percent(clamped), speed=clamped)

    async def set_effect(self, name: str | None) -> LightState:
        """Refuses named effects until the hardware mapping is proven.

        The APK does have a mode-select command, but the value-to-name mapping
        is not established, so accepting a name here would be inventing
        behaviour. ``set_mode`` is the escape hatch for raw values.
        """
        raise UnsupportedEffectError(name or "solid")

    async def set_mode(self, mode_id: int) -> LightState:
        """Sends a raw mode value (``BC 06 02 .. .. 55``), explicitly unverified.

        Deliberately does not set ``effect``: a successful write proves the
        packet was accepted, not which animation it selected.
        """
        return await self._apply(encoder.set_mode(mode_id))

    async def set_led_count(self, count: int) -> LightState:
        """Developer operation: tells the controller how many pixels to drive."""
        return await self._apply(encoder.set_led_count(count))

    async def set_scene(self, name: str, commands: Iterable[bytes]) -> LightState:
        """Applies a scene by writing its packets in order.

        Each packet is written synchronously in sequence; state is committed
        once, after all writes succeed, so a partially applied scene never
        lands in the canonical state.
        """
        packets = list(commands)
        transport = self._require_transport()
        for packet in packets:
            await transport.write(packet)
            self._last_command_hex = encoder.to_hex(packet)
        self._state = self._state.model_copy(update={"scene": name})
        self._publish()
        return self.state

    # --- internals --------------------------------------------------------

    async def _apply(self, packet: bytes, **changes: object) -> LightState:
        """Writes ``packet`` then commits ``changes``; never the other way round."""
        transport = self._require_transport()
        try:
            await transport.write(packet)
        except Exception as exc:
            self._last_error = str(exc)
            logger.warning("command failed, state left unchanged: %s", exc)
            raise
        self._last_command_hex = encoder.to_hex(packet)
        self._state = self._state.model_copy(update=changes)
        self._publish()
        return self.state

    def _require_transport(self) -> LightTransport:
        if self._transport is None or not self._transport.connected:
            raise NotConnectedError("no device connected")
        return self._transport

    def _handle_notification(self, data: bytes) -> None:
        """Records inbound frames; deliberately does not move state."""
        self._last_notification_hex = encoder.to_hex(data)
        packet = decoder.parse(data)
        logger.debug("rx %s", packet.describe())
