// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

/// Inline, non-blocking error strip used by the management pages.
///
/// Preferred over a bare snackbar when the message describes the state of the
/// list itself, so the reason stays visible while the user retries.
class ErrorBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onDismiss;

  const ErrorBanner({super.key, this.message, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: tokens.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: tokens.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tokens.error, fontSize: 13),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: tokens.error,
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
