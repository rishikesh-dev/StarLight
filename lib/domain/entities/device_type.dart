// SPDX-License-Identifier: Apache-2.0

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
  other('other', 'Other', Icons.device_unknown),
  // New capabilities for universal device support
  microcontroller('microcontroller', 'Microcontroller', Icons.memory),
  relay('relay', 'Relay', Icons.electrical_services),
  display('display', 'Display', Icons.display_settings),
  custom('custom', 'Custom', Icons.device_unknown);

  const DeviceType(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}
