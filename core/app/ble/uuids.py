"""UUID normalization for GATT lookups.

This exists because of a real bug in the Flutter client: it compared
``characteristic.uuid.toString()`` against the full 128-bit constant, but
FlutterBluePlus renders a 16-bit UUID in its shortest form ("fff0"), so the
comparison could never match and the connection died with
"Service not found: 0000fff0-...".

Normalizing both sides to the full lowercase 128-bit form - and comparing
those - is the fix. The same helper is used here so the service cannot
reintroduce the bug, and it is unit-tested against the same cases as the Dart
``UuidUtils``.
"""

from __future__ import annotations

BASE_SUFFIX = "00001000800000805f9b34fb"


def normalize_uuid(value: str) -> str:
    """Expands a short or long UUID to the lowercase 128-bit form.

    ``fff0`` and ``0000FFF0-0000-1000-8000-00805F9B34FB`` both normalize to
    ``0000fff000001000800000805f9b34fb``. Anything that is not 4 or 8 hex
    digits after stripping dashes is returned as-is (lowercased), which makes
    the function idempotent.
    """
    hex_only = value.replace("-", "").strip().lower()
    if len(hex_only) == 4:
        return "0000" + hex_only + BASE_SUFFIX
    if len(hex_only) == 8:
        return hex_only + BASE_SUFFIX
    return hex_only


def uuids_match(left: str, right: str) -> bool:
    """True when two UUIDs denote the same value, whatever form each is in."""
    return normalize_uuid(left) == normalize_uuid(right)
