"""BLE layer: the only code in StarLight allowed to touch the controller.

Importing this package pulls in ``bleak``; the protocol and service layers do
not, so they stay testable without a BLE stack.
"""
