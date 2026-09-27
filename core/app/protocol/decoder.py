"""Receive-path parsing.

Deliberately thin. The APK's own response handling lives in a small class that
re-dispatches command bytes 11, 12 and 80 (``MyApplication.d(byte[])``:
``bArr3[1] == 11 || bArr3[1] == 12 || bArr3[1] == 80``), but that class is not
among the decompiled sources and the payload layout is not established. So
this module structural-validates frames and reports what it can without
inventing meaning; anything richer waits until the response format is proven.

State changes are never derived from a notification. The plan (Phase 11)
requires the state to follow a *successful write*, not a guess about a reply.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.protocol import constants


@dataclass(frozen=True)
class Packet:
    """A structurally parsed frame from the controller."""

    raw: bytes
    valid: bool
    command: int | None = None
    sub: int | None = None
    payload: bytes = b""

    def to_hex(self) -> str:
        return " ".join(f"{byte:02X}" for byte in self.raw)

    def describe(self) -> str:
        """A log-friendly one-liner; never claims more than is known."""
        if not self.valid:
            return f"invalid frame ({self.raw.hex(' ')})"
        if self.command in constants.OBSERVED_RX_COMMANDS:
            return (
                f"observed rx command 0x{self.command:02X} "
                f"sub 0x{(self.sub or 0):02X} (semantics unverified)"
            )
        return f"command 0x{self.command:02X} sub 0x{(self.sub or 0):02X}"


def parse(data: bytes) -> Packet:
    """Structurally parses ``BC ... 55``; makes no claim about the payload."""
    if len(data) < 5:
        return Packet(raw=data, valid=False)
    if data[0] != constants.START_BYTE or data[-1] != constants.END_BYTE:
        return Packet(raw=data, valid=False, command=data[1] if len(data) > 1 else None)
    return Packet(
        raw=data,
        valid=True,
        command=data[1],
        sub=data[2],
        payload=bytes(data[3:-1]),
    )
