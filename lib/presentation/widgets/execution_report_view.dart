// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Renders an [ExecutionReport] as one row per device.
///
/// This is the only place a group or scene run is summarised, and it always
/// breaks the run down per device — a partial failure is presented as exactly
/// that, never as an overall success.
class ExecutionReportView extends StatelessWidget {
  final ExecutionReport report;
  final String? title;

  const ExecutionReportView({super.key, required this.report, this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    if (report.isEmpty) {
      return _Panel(
        accent: tokens.onSurfaceVariant,
        title: 'Nothing to run',
        subtitle: 'There were no targets to send this command to.',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title ?? report.summary,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${report.successCount} of ${report.results.length} target(s) '
            'accepted the command.',
            style: TextStyle(fontSize: 12, color: tokens.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final result in report.results) _ResultRow(result: result),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final DeviceActionResult result;

  const _ResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final (icon, color) = switch (result.outcome) {
      ExecutionOutcome.success => (Icons.check_circle, tokens.success),
      ExecutionOutcome.unsupported => (Icons.block, tokens.warning),
      ExecutionOutcome.notConnected => (Icons.link_off, tokens.warning),
      ExecutionOutcome.unavailable => (Icons.help_outline, tokens.warning),
      ExecutionOutcome.invalid => (Icons.error_outline, tokens.error),
      ExecutionOutcome.superseded => (
        Icons.fast_forward,
        tokens.onSurfaceVariant,
      ),
      ExecutionOutcome.failed => (Icons.error_outline, tokens.error),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_verb(result.outcome)} ${result.action}'
                  '${result.message == null ? '' : ' — ${result.message}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _verb(ExecutionOutcome outcome) => switch (outcome) {
    ExecutionOutcome.success => 'sent',
    ExecutionOutcome.unsupported => 'not supported:',
    ExecutionOutcome.notConnected => 'skipped:',
    ExecutionOutcome.unavailable => 'unavailable:',
    ExecutionOutcome.invalid => 'rejected:',
    ExecutionOutcome.superseded => 'not reached:',
    ExecutionOutcome.failed => 'failed:',
  };
}

class _Panel extends StatelessWidget {
  final Color accent;
  final String title;
  final String subtitle;

  const _Panel({
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
