"""Error hierarchy for StarLight Core.

Kept in one module so the API layer can map every failure to a JSON response
without importing half the package.
"""

from __future__ import annotations


class StarLightError(Exception):
    """Base class for every error this service raises."""


class BleError(StarLightError):
    """Something went wrong on the BLE link."""


class DeviceNotFoundError(BleError):
    """No device matched the configured address or name prefix."""


class NotConnectedError(BleError):
    """A command was issued while no device was connected."""


class ServiceNotFoundError(BleError):
    """The MR Star service (FFF0) was not present on the connected device.

    Carries the services that *were* discovered, because the original bug in
    the Flutter client was a UUID comparison against the wrong string form.
    """

    def __init__(self, wanted: str, available: list[str]) -> None:
        self.wanted = wanted
        self.available = available
        super().__init__(
            f"service {wanted} not found; discovered: "
            f"{', '.join(available) if available else '(none)'}"
        )


class CharacteristicNotFoundError(BleError):
    """A required characteristic (FFF3 write / FFF4 notify) was not present."""

    def __init__(self, wanted: str, available: list[str]) -> None:
        self.wanted = wanted
        self.available = available
        super().__init__(
            f"characteristic {wanted} not found; discovered: "
            f"{', '.join(available) if available else '(none)'}"
        )


class WriteTimeoutError(BleError):
    """A chunked write did not complete within the configured timeout."""


class FeatureNotAvailableError(StarLightError):
    """A whole feature is not implemented yet, and the API says so plainly.

    Used for the endpoints whose behaviour is defined by a later phase
    (scenes, presets). Returning 501 with a reason is friendlier and more
    honest than a 404, which would look like a routing mistake.
    """

    def __init__(self, feature: str, reason: str) -> None:
        self.feature = feature
        self.reason = reason
        super().__init__(f"{feature} is not available yet: {reason}")


class UnsupportedEffectError(StarLightError):
    """An effect was requested that the protocol does not verify yet.

    Phase 15 of the plan requires refusing to pretend an unverified effect
    works. The APK does have a mode-select command, but the mapping from its
    value to a named effect is not established, so named effects are rejected
    until that is proven. Use ``set_mode`` for raw, explicitly-unverified
    values.
    """

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__(

            f"effect {name!r} is not verified against the MR Star protocol; "
            "use a scene or set_color/set_brightness instead"
        )
