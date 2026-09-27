import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Type of device in the home automation system.
enum DeviceType {
  light('light', 'Light', Icons.light),
  plug('plug', 'Smart Plug', Icons.power),
  fan('fan', 'Fan', Icons.air),
  sensor('sensor', 'Sensor', Icons.sensors),
  tv('tv', 'TV', Icons.tv),
  switch_('switch', 'Switch', Icons.toggle_on),
  lamp('lamp', 'Lamp', Icons.lightbulb),
  other('other', 'Other', Icons.device_unknown);

  const DeviceType(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}