"""UUID matching tests, ported from ``test/uuid_utils_test.dart``.

These guard the regression that broke the Flutter client: comparing a
short-form UUID ("fff0") against a full 128-bit constant never matches, which
surfaced as ``ServiceNotFoundException`` immediately after a successful
connect.
"""

from __future__ import annotations

from app.ble import uuids
from app.protocol import constants


class TestNormalize:
    def test_expands_a_16_bit_uuid(self) -> None:
        assert uuids.normalize_uuid("fff0") == "0000fff000001000800000805f9b34fb"

    def test_expands_an_uppercase_32_bit_uuid(self) -> None:
        assert uuids.normalize_uuid("0000FFF3") == "0000fff300001000800000805f9b34fb"

    def test_keeps_a_full_uuid_and_strips_dashes(self) -> None:
        assert (
            uuids.normalize_uuid("0000FFF4-0000-1000-8000-00805F9B34FB")
            == "0000fff400001000800000805f9b34fb"
        )

    def test_is_idempotent(self) -> None:
        once = uuids.normalize_uuid("fff0")
        assert uuids.normalize_uuid(once) == once


class TestMatch:
    def test_short_form_matches_the_full_constant(self) -> None:
        assert uuids.uuids_match("fff0", constants.SERVICE_UUID)

    def test_matches_the_characteristic_constants(self) -> None:
        assert uuids.uuids_match("fff3", constants.WRITE_CHAR_UUID)
        assert uuids.uuids_match("fff4", constants.NOTIFY_CHAR_UUID)
        assert uuids.uuids_match("2902", constants.CCC_DESCRIPTOR_UUID)

    def test_is_case_insensitive(self) -> None:
        assert uuids.uuids_match("FFF0", constants.SERVICE_UUID)

    def test_different_uuids_do_not_match(self) -> None:
        assert not uuids.uuids_match("fff1", constants.SERVICE_UUID)
        assert not uuids.uuids_match("fff3", constants.NOTIFY_CHAR_UUID)

    def test_custom_128_bit_uuid_does_not_match(self) -> None:
        assert not uuids.uuids_match(
            "12345678-1234-5678-1234-56789abcdef0", constants.SERVICE_UUID
        )
