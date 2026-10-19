// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

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
    final tokens = context.tokens;
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
                ? tokens.success.withValues(alpha: 0.18)
                : tokens.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(
              color: effectiveIsOn
                  ? tokens.success
                  : isConnected
                  ? tokens.primary
                  : tokens.disabled,
              width: 3,
            ),
            boxShadow: effectiveIsOn
                ? [
                    BoxShadow(
                      color: tokens.success.withValues(alpha: 0.45),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            effectiveIsOn ? Icons.power : Icons.power_off,
            size: 40,
            color: effectiveIsOn
                ? tokens.success
                : isConnected
                ? tokens.primary
                : tokens.disabled,
          ),
        ),
      ),
    );
  }
}
