// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_event.dart';
import 'package:starlight/presentation/bloc/scene/scene_state.dart';
import 'package:starlight/presentation/pages/home/widgets/home_section_header.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Compact scene previews driven by real [Scene] entities.
///
/// Persisted scenes render in a restrained horizontal row on charcoal tiles,
/// differentiated only by a small accent taken from what the scene actually
/// does. With no scenes stored the section shows exactly one concise empty
/// state with a Create Scene action — no duplicate messages, no oversized
/// card. Each tile executes the real scene through the single BLE owner, and
/// a run always reports per-device results, which stay on screen until
/// dismissed so a partial failure cannot scroll past unnoticed.
class HomeScenes extends StatelessWidget {
  final void Function(String sceneId) onRunScene;

  const HomeScenes({super.key, required this.onRunScene});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<SceneBloc, SceneState>(
      builder: (context, state) {
        switch (state) {
          case SceneLoading():
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HomeSectionHeader(title: 'Scenes', subtitle: 'Loading…'),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const _SceneSkeleton(),
                ),
              ],
            );
          case SceneError(:final message):
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HomeSectionHeader(title: 'Scenes'),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 20,
                          color: tokens.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: tokens.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              context.read<SceneBloc>().add(const LoadScenes()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          case SceneLoaded():
            return _LoadedScenes(state: state, onRunScene: onRunScene);
          default:
            // SceneInitial (loading has not started yet): render nothing
            // rather than flashing an empty state that is not real.
            return const SizedBox.shrink();
        }
      },
    );
  }
}

class _LoadedScenes extends StatelessWidget {
  final SceneLoaded state;
  final void Function(String sceneId) onRunScene;

  const _LoadedScenes({required this.state, required this.onRunScene});

  @override
  Widget build(BuildContext context) {
    final scenes = state.ordered;
    final runningSceneId = state.runningSceneId;
    final lastReport = state.lastReport;
    final lastReportSceneId = state.lastReportSceneId;
    final isEmpty = scenes.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Scenes',
          subtitle: isEmpty ? null : 'Tap to run a scene',
          trailing: isEmpty ? null : _CountPill(count: scenes.length),
        ),
        const SizedBox(height: 12),
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _EmptyScenes(
              onCreate: () {
                Navigator.of(context).pushNamed('/scenes');
              },
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < scenes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  _SceneTile(
                    scene: scenes[i],
                    running: runningSceneId == scenes[i].id,
                    onRun: onRunScene,
                    isLastReport: lastReportSceneId == scenes[i].id,
                  ),
                ],
              ],
            ),
          ),
        if (lastReport != null && lastReportSceneId != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _LastRunBanner(
              report: lastReport,
              onDismiss: () =>
                  context.read<SceneBloc>().add(const ClearSceneReport()),
            ),
          ),
        ],
      ],
    );
  }
}

/// A compact, tappable tile for one persisted scene.
///
/// The differentiation is restrained: the tile stays on the theme's charcoal
/// surface and only a small accent (the colour the scene will actually set,
/// or the theme accent for non-colour scenes) hints at what it does.
class _SceneTile extends StatelessWidget {
  final Scene scene;
  final bool running;
  final void Function(String sceneId) onRun;
  final bool isLastReport;

  const _SceneTile({
    required this.scene,
    required this.running,
    required this.onRun,
    this.isLastReport = false,
  });

  /// A small accent derived from what the scene actually does (never
  /// decorative): the colour it sets, or a neutral accent for other actions.
  Color _accentColor(AppTokens tokens) {
    if (scene.actions.isEmpty) return tokens.primary;
    final action = scene.actions.first;
    switch (action.action) {
      case 'color':
        if (action.value is Map) {
          final map = Map<String, dynamic>.from(action.value as Map);
          final r = (map['red'] as int?) ?? 0;
          final g = (map['green'] as int?) ?? 0;
          final b = (map['blue'] as int?) ?? 0;
          return Color.fromARGB(255, r, g, b);
        }
        return tokens.primary;
      case 'brightness':
        return tokens.warning;
      case 'power':
        return tokens.success;
      default:
        return tokens.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = _accentColor(tokens);

    return Semantics(
      label: 'Run scene ${scene.name}',
      button: true,
      enabled: !running,
      selected: isLastReport,
      child: Opacity(
        opacity: running ? 0.7 : 1,
        child: SizedBox(
          width: 132,
          height: 84,
          child: Material(
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isLastReport ? tokens.primary : tokens.border,
                width: isLastReport ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: running ? null : () => onRun(scene.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            scene.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: tokens.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (running)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (isLastReport)
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: tokens.success,
                          )
                        else
                          Icon(Icons.play_arrow, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          running ? 'Running' : 'Run',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: tokens.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneSkeleton extends StatelessWidget {
  const _SceneSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Container(
              width: 132,
              height: 84,
              decoration: BoxDecoration(
                color: tokens.surfaceHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tokens.border),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;

  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: tokens.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The single, concise empty state for Home's Scenes section.
class _EmptyScenes extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyScenes({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, color: tokens.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No scenes yet',
              style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 13.5),
            ),
          ),
          // Scales down rather than overflowing on very narrow screens or
          // large text scales (the label stays readable, never clipped).
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Scene'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastRunBanner extends StatelessWidget {
  final ExecutionReport report;
  final VoidCallback onDismiss;

  const _LastRunBanner({required this.report, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isSuccess = report.allSucceeded;
    final color = isSuccess ? tokens.success : tokens.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Last run: ${report.summary}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (report.results.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _detailText(report),
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }

  String _detailText(ExecutionReport report) {
    final failed = report.results.where((r) => !r.success).length;
    if (failed == 0) return 'All actions succeeded.';
    return '$failed of ${report.results.length} target(s) failed.';
  }
}
