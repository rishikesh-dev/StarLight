"""Protocol tests.

The packet assertions are copied from ``test/protocol_encoder_test.dart`` and
``test/color_conversion_test.dart`` so the Python core and the Flutter client
cannot drift apart. Anything only present in the core (the mode/visualizer
commands and the percent scales) is covered here as well.
"""

from __future__ import annotations

import pytest

from app.models.light_state import LightState, Rgb
from app.protocol import color as color_module
from app.protocol import constants, decoder, encoder, scales


class TestPackets:
    """Same vectors as the Dart suite."""

    def test_power_on(self) -> None:
        assert encoder.to_hex(encoder.power_on()) == "BC 01 01 00 55"

    def test_power_off(self) -> None:
        assert encoder.to_hex(encoder.power_off()) == "BC 01 01 01 55"

    def test_set_power_maps_on_to_zero(self) -> None:
        # The APK's switch sends 0 when checked, so ON is 0x00 -- not 0x01.
        assert encoder.set_power(True) == encoder.power_on()
        assert encoder.set_power(False) == encoder.power_off()

    def test_brightness_clamps_minimum_to_3(self) -> None:
        assert encoder.to_hex(encoder.brightness(0)) == "BC 05 06 00 03 00 00 00 00 55"

    def test_brightness_at_1000(self) -> None:
        assert encoder.to_hex(encoder.brightness(1000)) == "BC 05 06 03 E8 00 00 00 00 55"

    def test_color_from_rgb_red(self) -> None:
        assert encoder.to_hex(encoder.color_from_rgb(255, 0, 0)) == "BC 04 06 00 00 03 E8 00 00 55"

    def test_color_from_hsv(self) -> None:
        assert encoder.to_hex(encoder.color_from_hsv(0, 1000)) == "BC 04 06 00 00 03 E8 00 00 55"

    def test_led_count(self) -> None:
        assert encoder.to_hex(encoder.set_led_count(300)) == "BC 03 02 01 2C 55"

    def test_line_order(self) -> None:
        assert encoder.to_hex(encoder.set_line_order(2)) == "BC 02 01 02 55"

    def test_speed_byte(self) -> None:
        assert encoder.to_hex(encoder.speed(128)) == "BC 08 01 80 55"

    def test_mic_toggle_on(self) -> None:
        assert encoder.to_hex(encoder.mic_toggle(True)) == "BC 0F 01 01 55"

    def test_mic_toggle_off(self) -> None:
        assert encoder.to_hex(encoder.mic_toggle(False)) == "BC 0F 01 00 55"

    def test_color_picker(self) -> None:
        assert encoder.to_hex(encoder.set_color_picker(True)) == "BC 07 01 01 55"

    def test_empty_hex_dump(self) -> None:
        assert encoder.to_hex(b"") == ""


class TestNewCommands:
    """Commands found in the APK that the Flutter encoder does not have yet."""

    def test_mode_uses_divide_by_255_encoding(self) -> None:
        # ModeFragment.f0 encodes with /255 and %255, not the /256 pair used
        # by every other command. Preserved deliberately.
        assert encoder.to_hex(encoder.set_mode(5)) == "BC 06 02 00 05 55"

    def test_mode_rolls_over_at_255(self) -> None:
        assert encoder.to_hex(encoder.set_mode(255)) == "BC 06 02 01 00 55"

    def test_mode_negative_is_clamped(self) -> None:
        assert encoder.to_hex(encoder.set_mode(-3)) == "BC 06 02 00 00 55"

    def test_visualizer_color(self) -> None:
        assert (
            encoder.to_hex(encoder.set_visualizer_color(0x0102, 0x0304))
            == "BC 09 06 01 02 03 04 00 00 55"
        )

    def test_mic_mode(self) -> None:
        assert encoder.to_hex(encoder.mic_mode(3)) == "BC 11 01 03 55"

    def test_mic_sensitivity(self) -> None:
        assert encoder.to_hex(encoder.mic_sensitivity(50)) == "BC 12 01 32 55"


class TestColorConversion:
    """Mirrors color_conversion_test.dart against e2.e.B()."""

    @pytest.mark.parametrize(
        ("rgb", "hue", "sat"),
        [
            ((255, 0, 0), 0, 1000),
            ((0, 255, 0), 120, 1000),
            ((0, 0, 255), 240, 1000),
            ((255, 255, 0), 60, 1000),
            ((0, 255, 255), 180, 1000),
            ((255, 0, 255), 300, 1000),
        ],
    )
    def test_primaries(self, rgb: tuple[int, int, int], hue: int, sat: int) -> None:
        assert color_module.compute_color_values(*rgb) == (hue, sat)

    def test_saturation_is_forced_to_one_for_pure_colors(self) -> None:
        assert color_module.rgb_to_hsv(255, 0, 0)[1] == 1.0

    def test_white_reports_full_saturation(self) -> None:
        hue, saturation, _ = color_module.rgb_to_hsv(255, 255, 255)
        assert hue == 0
        assert saturation == 1.0

    def test_black_reports_full_saturation(self) -> None:
        hue, saturation, _ = color_module.rgb_to_hsv(0, 0, 0)
        assert hue == 0
        assert saturation == 1.0

    def test_warm_white_matches_the_dart_expectation(self) -> None:
        hue, saturation, _ = color_module.rgb_to_hsv(255, 245, 228)
        assert hue == pytest.approx(37.78, abs=3)
        assert saturation == pytest.approx(0.106, abs=0.01)

    def test_warm_white_values_truncate_like_java(self) -> None:
        value1, value2 = color_module.compute_color_values(255, 245, 228)
        assert (value1, value2) == (37, 105)


class TestScales:
    """User-facing percent versus the protocol's internal ranges."""

    def test_brightness_percent_to_protocol(self) -> None:
        assert scales.brightness_percent_to_protocol(50) == 500
        assert scales.brightness_percent_to_protocol(100) == 1000

    def test_brightness_zero_still_clamps_to_the_protocol_minimum(self) -> None:
        assert scales.brightness_percent_to_protocol(0) == constants.BRIGHTNESS_PROTOCOL_MIN

    def test_brightness_is_clamped_above_100_percent(self) -> None:
        assert scales.brightness_percent_to_protocol(250) == 1000

    def test_brightness_roundtrips(self) -> None:
        for percent in (0, 1, 10, 42, 99, 100):
            protocol = scales.brightness_percent_to_protocol(percent)
            expected = max(1, percent) if percent > 0 else 0
            assert scales.brightness_protocol_to_percent(protocol) >= expected - 1

    def test_speed_is_already_the_protocol_range(self) -> None:
        # fragment_mode.xml: sb_speed has android:max="100".
        assert scales.speed_percent_to_byte(73) == 73
        assert scales.speed_percent_to_byte(200) == 100

    def test_set_brightness_percent_packet(self) -> None:
        assert (
            encoder.to_hex(encoder.set_brightness_percent(100))
            == "BC 05 06 03 E8 00 00 00 00 55"
        )
        assert (
            encoder.to_hex(encoder.set_brightness_percent(0))
            == "BC 05 06 00 03 00 00 00 00 55"
        )


class TestDecoder:
    def test_parses_a_valid_frame(self) -> None:
        packet = decoder.parse(encoder.power_on())
        assert packet.valid
        assert packet.command == constants.CMD_POWER
        assert packet.sub == constants.SUB_POWER
        assert packet.payload == b"\x00"

    def test_rejects_a_frame_without_markers(self) -> None:
        assert not decoder.parse(b"\x01\x02\x03").valid

    def test_rejects_a_short_frame(self) -> None:
        assert not decoder.parse(b"\xbc\x01").valid

    def test_observed_rx_command_is_not_over_interpreted(self) -> None:
        description = decoder.parse(bytes([0xBC, 0x0B, 0x01, 0x00, 0x55])).describe()
        assert "unverified" in description


class TestStateModel:
    """The canonical state model and its user-facing scales."""

    def test_defaults_match_the_apk_globals(self) -> None:
        state = LightState()
        assert state.power is True
        assert state.brightness == 100  # f1781h = 1000 -> 100 percent
        assert state.speed == 50  # f1782i = 50
        assert state.rgb.to_hex() == "#FF0000"

    def test_brightness_and_speed_are_clamped(self) -> None:
        state = LightState(brightness=500, speed=-20)
        assert state.brightness == 100
        assert state.speed == 0

    def test_hex_parsing_accepts_both_forms(self) -> None:
        assert Rgb.from_hex("#8E6CFF") == Rgb(r=142, g=108, b=255)
        assert Rgb.from_hex("8e6cff") == Rgb(r=142, g=108, b=255)
        assert Rgb.from_hex("#fff") == Rgb(r=255, g=255, b=255)

    def test_hex_parsing_rejects_junk(self) -> None:
        with pytest.raises(ValueError):
            Rgb.from_hex("#12345")

    def test_channels_are_clamped(self) -> None:
        assert Rgb(r=300, g=-5, b=128) == Rgb(r=255, g=0, b=128)
