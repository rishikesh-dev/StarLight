import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_event.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Minimal scene creation page.
class SceneCreatePage extends StatefulWidget {
  const SceneCreatePage({super.key});

  @override
  State<SceneCreatePage> createState() => _SceneCreatePageState();
}

class _SceneCreatePageState extends State<SceneCreatePage> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Scene'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _nameController.text.isEmpty
                ? null
                : () {
                    final scene = Scene(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: _nameController.text,
                      actions: const [],
                      createdAt: DateTime.now(),
                    );
                    context.read<SceneBloc>().add(SaveScene(scene));
                    Navigator.of(context).pop();
                  },
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Scene name',
                border: const EdgeInsets.all(12),
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) {
                if (v.isNotEmpty) {
                  final scene = Scene(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: v,
                    actions: const [],
                    createdAt: DateTime.now(),
                  );
                  context.read<SceneBloc>().add(SaveScene(scene));
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
