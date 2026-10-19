// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Outcome of verifying a profile against a live device's GATT table.
enum ProfileVerificationStatus {
  /// Not yet attempted for the currently connected device.
  unverified,

  /// Every configured service/characteristic was found and has the required
  /// properties for the configured write mode.
  verified,

  /// Verification ran but the device did not match the configuration.
  failed,

  /// No device is connected, so verification could not run.
  notConnected,
}

/// The verification state of one profile against the currently connected
/// device. Never persisted: it is only ever a real observation of the live
/// GATT table.
class ProfileVerification extends Equatable {
  final ProfileVerificationStatus status;
  final String? message;
  final String? serviceUuid;
  final String? writeCharacteristicUuid;
  final String? notifyCharacteristicUuid;
  final bool supportsWriteWithResponse;
  final bool supportsWriteWithoutResponse;
  final bool supportsNotify;

  /// The write mode actually chosen after inspecting the characteristic
  /// properties (resolves [GattWriteMode.automatic]).
  final bool writeWithoutResponse;

  final DateTime? verifiedAt;

  const ProfileVerification({
    required this.status,
    this.message,
    this.serviceUuid,
    this.writeCharacteristicUuid,
    this.notifyCharacteristicUuid,
    this.supportsWriteWithResponse = false,
    this.supportsWriteWithoutResponse = false,
    this.supportsNotify = false,
    this.writeWithoutResponse = true,
    this.verifiedAt,
  });

  const ProfileVerification.unverified()
    : this(status: ProfileVerificationStatus.unverified);

  const ProfileVerification.notConnected()
    : this(
        status: ProfileVerificationStatus.notConnected,
        message: 'No device connected.',
      );

  factory ProfileVerification.failed(String message) => ProfileVerification(
    status: ProfileVerificationStatus.failed,
    message: message,
  );

  bool get isVerified => status == ProfileVerificationStatus.verified;

  /// A short human-readable summary for the UI.
  String get label => switch (status) {
    ProfileVerificationStatus.verified => 'Verified on this device',
    ProfileVerificationStatus.failed => 'Verification failed',
    ProfileVerificationStatus.notConnected => 'Not connected',
    ProfileVerificationStatus.unverified => 'Not verified',
  };

  @override
  List<Object?> get props => [
    status,
    message,
    serviceUuid,
    writeCharacteristicUuid,
    notifyCharacteristicUuid,
    supportsWriteWithResponse,
    supportsWriteWithoutResponse,
    supportsNotify,
    writeWithoutResponse,
    verifiedAt,
  ];
}
