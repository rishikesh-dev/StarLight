import 'package:flutter/material.dart';

/// Large, obvious power button used in the controller and Home card.
class PowerButton extends StatelessWidget {
  final bool isOn;
  final bool isConnected;
  final VoidCallback? onTap;

  const PowerButton({
    super.key,
    required this.isOn,
    required this.isConnected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = isConnected && onTap != null;
    final effectiveIsOn = isConnected && isOn;

    return Semantics(
      label: isOn ? 'Turn off' : 'Turn on',
      button: true,
      enabled: enabled,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 50,
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: effectiveIsOn
                ? const Color(0xFF4CAF50).withValues(alpha: 0.18)
                : const Color(0xFF25252C),
            shape: BoxShape.circle,
            border: Border.all(
              color: effectiveIsOn
                  ? const Color(0xFF4CAF50)
                  : isConnected
                      ? const Color(0xFF8E6CFF)
                      : const Color(0xFF4A4A55),
              width: 3,
            ),
            boxShadow: effectiveIsOn
                ? [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.45),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            effectiveIsOn ? Icons.power : Icons.power_off,
            size: 40,
            color: effectiveIsOn
                ? const Color(0xFF4CAF50)
                : isConnected
                    ? const Color(0xFF8E6CFF)
                    : const Color(0xFF4A4A55),
          ),
        ),
      ),
    );
  }
}