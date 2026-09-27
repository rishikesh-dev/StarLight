"""Service tests, focused on the rule that state follows a successful write.

The transport seam means none of this needs BLE hardware: a fake records the
packets and can be told to fail on demand.

Async tests are driven with ``asyncio.run`` rather than an async plugin so the
suite runs on any pytest install.
"""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from app.errors import BleError, NotConnectedError, UnsupportedEffectError
from app.models.light_state import LightState
from app.protocol import encoder
from app.services.light_service import LightService
from tests.fakes import FakeTransport


def run(coro: Any) -> Any:
    return asyncio.run(coro)


class TestPower:
    def test_power_off_writes_the_apk_packet(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.power(False))

        assert transport.last_hex == "BC 01 01 01 55"
        assert state.power is False

    def test_power_on_writes_the_apk_packet(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.power(True))

        assert transport.last_hex == "BC 01 01 00 55"
        assert state.power is True

    def test_failed_write_leaves_state_and_reports_the_error(self) -> None:
        transport = FakeTransport(fail=True)
        service = LightService(transport)

        with pytest.raises(BleError):
            run(service.power(False))

        # The whole point of Phase 11: no optimistic state update.
        assert service.state.power is True
        assert service.diagnostics["last_error"] == "write rejected"
        assert service.diagnostics["last_command"] is None

    def test_committing_never_happens_before_the_write(self) -> None:
        order: list[str] = []

        class OrderedTransport(FakeTransport):
            async def write(self, data: bytes) -> None:
                order.append("write")
                await super().write(data)

        service = LightService(OrderedTransport())
        service.subscribe(lambda _state: order.append("publish"))

        run(service.power(False))

        assert order == ["write", "publish"]


class TestColor:
    def test_set_color_uses_the_apk_conversion(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.set_color(255, 0, 0))

        assert transport.last_hex == "BC 04 06 00 00 03 E8 00 00 55"
        assert state.hex == "#FF0000"

    def test_set_hex(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.set_hex("#8E6CFF"))

        assert (state.rgb.r, state.rgb.g, state.rgb.b) == (142, 108, 255)
        assert state.hex == "#8E6CFF"
        assert transport.last_hex == "BC 04 06 00 FD 02 40 00 00 55"

    def test_channels_are_clamped_before_encoding(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.set_color(300, -4, 128))

        assert (state.rgb.r, state.rgb.g, state.rgb.b) == (255, 0, 128)


class TestBrightnessAndSpeed:
    def test_brightness_percent_is_converted_to_the_protocol_range(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.set_brightness(50))

        assert transport.last_hex == "BC 05 06 01 F4 00 00 00 00 55"
        assert state.brightness == 50

    def test_brightness_percent_is_clamped(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        assert run(service.set_brightness(150)).brightness == 100
        assert run(service.set_brightness(-10)).brightness == 0

    def test_speed_is_sent_as_a_byte(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.set_speed(73))

        assert transport.last_hex == "BC 08 01 49 55"
        assert state.speed == 73


class TestEffects:
    def test_named_effects_are_refused_rather_than_faked(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        with pytest.raises(UnsupportedEffectError):
            run(service.set_effect("rainbow"))

        assert transport.writes == []
        assert service.state.effect is None

    def test_raw_mode_is_allowed_but_records_no_effect(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        state = run(service.set_mode(5))

        assert transport.last_hex == "BC 06 02 00 05 55"
        assert state.effect is None


class TestScenes:
    def test_scene_writes_packets_in_order_and_commits_once(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)
        published: list[LightState] = []
        service.subscribe(published.append)

        run(
            service.set_scene(
                "coding",
                [
                    encoder.set_power(True),
                    encoder.set_brightness_percent(65),
                    encoder.color_from_rgb(142, 108, 255),
                ],
            )
        )

        assert [encoder.to_hex(write) for write in transport.writes] == [
            "BC 01 01 00 55",
            "BC 05 06 02 8A 00 00 00 00 55",
            # #8E6CFF is not a primary: hue 253, saturation 576.
            "BC 04 06 00 FD 02 40 00 00 55",
        ]
        assert len(published) == 1
        assert published[0].scene == "coding"


class TestConnectionHandling:
    def test_unbound_service_refuses_commands(self) -> None:
        service = LightService()

        with pytest.raises(NotConnectedError):
            run(service.power(True))

    def test_disconnected_transport_refuses_commands(self) -> None:
        service = LightService(FakeTransport(connected=False))

        with pytest.raises(NotConnectedError):
            run(service.power(True))

    def test_bind_marks_the_state_connected(self) -> None:
        service = LightService()

        service.bind(FakeTransport(), "80:AC:C8:5D:AB:CF")

        assert service.state.connected is True
        assert service.state.device == "80:AC:C8:5D:AB:CF"

    def test_refresh_connection_tracks_a_drop(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        transport.connected = False
        service.refresh_connection()

        assert service.state.connected is False

    def test_state_is_a_copy(self) -> None:
        service = LightService(FakeTransport())

        snapshot = service.state
        snapshot.power = False

        assert service.state.power is True


class TestNotifications:
    def test_inbound_frames_are_recorded_but_do_not_move_state(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)
        before = service.state

        transport.handler(bytes([0xBC, 0x0B, 0x01, 0x00, 0x55]))

        assert service.diagnostics["last_notification"] == "BC 0B 01 00 55"
        assert service.state == before


class TestListeners:
    def test_subscribe_and_unsubscribe(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)
        seen: list[bool] = []

        unsubscribe = service.subscribe(lambda state: seen.append(state.power))
        run(service.power(False))
        unsubscribe()
        run(service.power(True))

        assert seen == [False]

    def test_a_failing_listener_does_not_break_control(self) -> None:
        transport = FakeTransport()
        service = LightService(transport)

        def explode(_state: LightState) -> None:
            raise RuntimeError("listener bug")

        service.subscribe(explode)

        assert run(service.power(True)).power is True
