import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Scenes screen: visually attractive scene cards that activate device actions.
class ScenesPage extends StatelessWidget {
  const ScenesPage({super.key});

  static const List<Scene> _defaultScenes = [
    Scene(
      id: 'coding',
      name: 'Coding',
      iconName: 'code',
      actions: const [],
      createdAt: null,
    ),
    Scene(
      id: 'gaming',
      name: 'Gaming',
      iconName: 'sports_esports',
      actions: const [],
      createdAt: null,
    ),
    Scene(
      id: 'movie',
      name: 'Movie',
      iconName: 'movie',
      actions: const [],
      createdAt: null,
    ),
    Scene(
      id: 'night',
      name: 'Night',
      iconName: 'nightlight',
      actions: const [],
      createdAt: null,
    ),
    Scene(
      id: 'sunset',
      name: 'Sunset',
      iconName: 'wb_sunny',
      actions: const [],
      createdAt: null,
    ),
    Scene(
      id: 'morning',
      name: 'Morning',
      iconName: 'wb_sunny_outlined',
      actions: const [],
      createdAt: null,
    ),
  ];

  static const Map<String, Color> _sceneColors = {
    'coding': Color(0xFF8E6CFF),
    'gaming': Color(0xFFFF6B9D),
    'movie': Color(0xFF4A90E2),
    'night': Color(0xFF2C3E50),
    'sunset': Color(0xFFFF7E5F),
    'morning': Color(0xFFFECB71),
  };

  Color _colorFor(Scene scene) => _sceneColors[scene.id] ?? AppColors.primary;

  IconData _iconFor(String name) {
    return switch (name) {
      'code' => Icons.code,
      'sports_esports' => Icons.sports_esports,
      'movie' => Icons.movie,
      'nightlight' => Icons.nightlight,
      'wb_sunny' => Icons.wb_sunny,
      'wb_sunny_outlined' => Icons.wb_sunny_outlined,
      _ => Icons.auto_awesome,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).pushNamed('/scene-create'),
            tooltip: 'Create scene',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _defaultScenes.length,
        itemBuilder: (context, index) {
          final scene = _defaultScenes[index];
          final color = _colorFor(scene);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              label: 'Activate scene ${scene.name}',
              button: true,
              child: InkResponse(
                onTap: () {},
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 96,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        scene.iconName != null ? _iconFor(scene.iconName!) : Icons.auto_awesome,
                        color: color,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(scene.name, style: theme.textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(
                              '${scene.actions.length} action(s)',
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_arrow, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}