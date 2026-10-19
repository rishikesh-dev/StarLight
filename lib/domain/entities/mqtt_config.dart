// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// MQTT broker connection configuration.
class MqttConfig extends Equatable {
  final String brokerHost;
  final int brokerPort;
  final String clientId;
  final String? username;
  final String? password;
  final bool useTls;
  final int keepAliveSeconds;
  final bool cleanSession;

  const MqttConfig({
    required this.brokerHost,
    this.brokerPort = 1883,
    this.clientId = '',
    this.username,
    this.password,
    this.useTls = false,
    this.keepAliveSeconds = 60,
    this.cleanSession = true,
  });

  factory MqttConfig.fromMap(Map<String, dynamic> map) {
    return MqttConfig(
      brokerHost: map['brokerHost'] as String,
      brokerPort: map['brokerPort'] as int? ?? 1883,
      clientId: map['clientId'] as String? ?? '',
      username: map['username'] as String?,
      password: map['password'] as String?,
      useTls: map['useTls'] as bool? ?? false,
      keepAliveSeconds: map['keepAliveSeconds'] as int? ?? 60,
      cleanSession: map['cleanSession'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'brokerHost': brokerHost,
      'brokerPort': brokerPort,
      'clientId': clientId,
      'username': username,
      'password': password,
      'useTls': useTls,
      'keepAliveSeconds': keepAliveSeconds,
      'cleanSession': cleanSession,
    };
  }

  MqttConfig copyWith({
    String? brokerHost,
    int? brokerPort,
    String? clientId,
    String? username,
    String? password,
    bool? useTls,
    int? keepAliveSeconds,
    bool? cleanSession,
  }) {
    return MqttConfig(
      brokerHost: brokerHost ?? this.brokerHost,
      brokerPort: brokerPort ?? this.brokerPort,
      clientId: clientId ?? this.clientId,
      username: username ?? this.username,
      password: password ?? this.password,
      useTls: useTls ?? this.useTls,
      keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
      cleanSession: cleanSession ?? this.cleanSession,
    );
  }

  @override
  List<Object?> get props => [
    brokerHost,
    brokerPort,
    clientId,
    username,
    password,
    useTls,
    keepAliveSeconds,
    cleanSession,
  ];
}
