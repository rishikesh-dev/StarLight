import 'package:flutter/material.dart';

/// Large ON/OFF power toggle for the LED strip.
class PowerToggle extends StatelessWidget {
  final bool isOn;
  final bool isConnected;
  final ValueChanged<bool?> onChanged;

  const PowerToggle({
    super.key,
    required this.isOn,
    required this.isConnected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isOn ? 'ON' : 'OFF',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: isOn
                ? const Color(0xFF8E6CFF)
                : Colors.grey,
          ),
        ),
        Switch(
          value: isOn,
          onChanged: isConnected ? onChanged : null,
          activeThumbColor: const Color(0xFF8E6CFF),
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Colors.grey.shade800,
        ),
      ],
    );
  }
}
