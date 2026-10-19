// SPDX-License-Identifier: Apache-2.0

/// Connection state for network devices (WLED, MQTT).
/// Network devices do not have a physical disconnect in the same way as BLE;
/// they report unreachable/offline states instead.
enum NetworkConnectionState { disconnected, connecting, connected, unreachable }
