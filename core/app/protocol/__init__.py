"""Protocol layer: packet encoding, decoding and value scales.

Pure standard library on purpose: the protocol must be testable without a BLE
stack installed, since it is the contract every client depends on.
"""
