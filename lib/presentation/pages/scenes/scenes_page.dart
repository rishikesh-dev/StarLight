// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_event.dart';
import 'package:starlight/presentation/bloc/scene/scene_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/error_banner.dart';
import 'package:starlight/presentation/widgets/execution_report_view.dart';

import 'scene_editor_page.dart';

/// Scene list (route `/scenes`).
///
/// Every tile is a real, persisted scene whose actions are executed through the
/// single BLE owner. A run always reports per-device results, and the report
/// stays on screen until dismissed so a partial failure cannot scroll past
/// unnoticed.
class ScenesPage extends StatelessWidget {
  const ScenesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sceneBloc = context.read<SceneBloc>();

    return Scaffold(
      appBar: AppBar(title: const Text('Scenes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => SceneEditorPage.open(context),
        icon: const Icon(Icons.add),
        label: const Text('New scene'),
      ),
      body: BlocConsumer<SceneBloc, SceneState>(
        listenWhen: (a, b) => a.error != b.error && b.error != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!)));
        },
        builder: (context, state) {
          if (state is SceneLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is! SceneLoaded) {
            return _FatalState(
              message: state.error ?? 'Scenes are unavailable.',
            );
          }
          if (state.scenes.isEmpty) {
            return const _EmptyScenes();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ErrorBanner(message: state.error),
              if (state.lastReport != null) ...[
                ExecutionReportView(
                  report: state.lastReport!,
                  title: 'Last run · ${state.lastReport!.summary}',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => sceneBloc.add(const ClearSceneReport()),
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final scene in state.ordered)
                _SceneTile(
                  scene: scene,
                  running: state.isRunning(scene.id),
                  onChanged: () => sceneBloc.add(const LoadScenes()),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SceneTile extends StatelessWidget {
  final Scene scene;
  final bool running;
  final VoidCallback onChanged;

  const _SceneTile({
    required this.scene,
    required this.running,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final bloc = context.read<SceneBloc>();
    final actions = scene.actions.length;
    final targets = scene.targetCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.border),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (scene.favorite)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.star,
                              size: 15,
                              color: tokens.primary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            scene.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (scene.description != null &&
                        scene.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        scene.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 13,
                          color: tokens.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            actions == 0
                                ? 'No actions yet'
                                : '$actions action(s) · $targets target(s)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (running)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Run scene',
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: tokens.primary,
                  onPressed: () => bloc.add(RunScene(scene.id)),
                ),
              PopupMenuButton<String>(
                tooltip: 'Scene actions',
                onSelected: (value) async {
                  switch (value) {
                    case 'run':
                      bloc.add(RunScene(scene.id));
                    case 'edit':
                      await SceneEditorPage.open(context, scene: scene);
                      onChanged();
                    case 'duplicate':
                      bloc.add(DuplicateScene(scene.id));
                    case 'favorite':
                      bloc.add(ToggleSceneFavorite(scene.id));
                    case 'delete':
                      final confirmed = await _confirmDelete(context, scene);
                      if (confirmed) bloc.add(DeleteScene(scene.id));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'run', child: Text('Run')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicate'),
                  ),
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(
                      scene.favorite ? 'Remove favourite' : 'Add to favourites',
                    ),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool> _confirmDelete(BuildContext context, Scene scene) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${scene.name}"?'),
        content: const Text(
          'This removes the scene. Devices already changed by it are not '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _EmptyScenes extends StatelessWidget {
  const _EmptyScenes();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 44, color: tokens.primary),
            const SizedBox(height: 14),
            Text(
              'No scenes yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'A scene runs several actions together — for example turning every '
              'light on at a colour and brightness. You will see the result for '
              'each device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => SceneEditorPage.open(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create scene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FatalState extends StatelessWidget {
  final String message;

  const _FatalState({required this.message});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: tokens.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  context.read<SceneBloc>().add(const LoadScenes()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
