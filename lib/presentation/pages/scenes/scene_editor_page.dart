// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_event.dart';
import 'package:starlight/presentation/bloc/scene/scene_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/theme/rgb_color_x.dart';

import 'scene_action_editor.dart';

/// Create/edit screen for a scene (route `/scene-editor`).
///
/// The editor is deliberately plain: it stores *intent* ("set this device to
/// 40% brightness"), never protocol bytes or UUIDs. Validation lives in the
/// domain layer ([SceneAction.validationError]) so the editor, the save path
/// and the executor always agree on what a usable action is.
class SceneEditorPage extends StatefulWidget {
  final Scene? scene;

  const SceneEditorPage({super.key, this.scene});

  /// Pushes the editor, keeping the existing [SceneBloc] alive behind it.
  static Future<void> open(BuildContext context, {Scene? scene}) async {
    final bloc = context.read<SceneBloc>();
    if (scene == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BlocProvider<SceneBloc>.value(
            value: bloc,
            child: const SceneEditorPage(),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider<SceneBloc>.value(
          value: bloc,
          child: SceneEditorPage(scene: scene),
        ),
      ),
    );
  }

  @override
  State<SceneEditorPage> createState() => _SceneEditorPageState();
}

class _SceneEditorPageState extends State<SceneEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late List<SceneAction> _actions;
  bool _saving = false;

  bool get _isNew => widget.scene == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.scene?.name ?? '');
    _description = TextEditingController(text: widget.scene?.description ?? '');
    _actions = [...?widget.scene?.actions];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _addAction() async {
    final action = await showModalBottomSheet<SceneAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SceneActionEditorSheet(),
    );
    if (action == null) return;
    setState(() => _actions.add(action));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a scene name.');
      return;
    }
    final bloc = context.read<SceneBloc>();
    setState(() => _saving = true);

    if (_isNew) {
      bloc.add(
        CreateScene(
          name: name,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        ),
      );
    } else {
      bloc.add(
        SaveScene(
          widget.scene!.copyWith(
            name: name,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            actions: _actions,
          ),
        ),
      );
    }

    // The bloc owns validation and persistence; wait for it to settle before
    // leaving so a rejected scene keeps the user's work on screen.
    final result = await bloc.stream.firstWhere(
      (state) => state is SceneLoaded || state is SceneError,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result is SceneError ||
        (result is SceneLoaded && result.error != null)) {
      final message = result is SceneError
          ? result.message
          : (result as SceneLoaded).error!;
      _showMessage(message);
      return;
    }
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmLeave() async {
    final name = _name.text.trim();
    final description = _description.text.trim();
    final originalName = widget.scene?.name ?? '';
    final originalDescription = widget.scene?.description ?? '';
    final unchanged =
        name == originalName &&
        description == originalDescription &&
        _sameActions();

    if (unchanged || _saving) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this scene have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  bool _sameActions() {
    final original = widget.scene?.actions ?? const <SceneAction>[];
    if (original.length != _actions.length) return false;
    for (var i = 0; i < original.length; i++) {
      if (original[i] != _actions[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New scene' : 'Edit scene'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmLeave,
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Scene name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 140,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addAction,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add action'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Actions run in order, one after another.',
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_actions.isEmpty)
              _EmptyActions(onAdd: _addAction)
            else
              for (var i = 0; i < _actions.length; i++)
                _ActionRow(
                  action: _actions[i],
                  position: i,
                  onMoveUp: i == 0 ? null : () => _move(i, i - 1),
                  onMoveDown: i == _actions.length - 1
                      ? null
                      : () => _move(i, i + 1),
                  onRemove: () => _remove(i),
                  onEdit: () => _editAction(i),
                ),
          ],
        ),
      ),
    );
  }

  void _move(int from, int to) {
    setState(() {
      final action = _actions.removeAt(from);
      _actions.insert(to, action);
    });
  }

  void _remove(int index) {
    setState(() => _actions.removeAt(index));
  }

  Future<void> _editAction(int index) async {
    final updated = await showModalBottomSheet<SceneAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SceneActionEditorSheet(initial: _actions[index]),
    );
    if (updated == null) return;
    setState(() => _actions[index] = updated);
  }
}

class _ActionRow extends StatelessWidget {
  final SceneAction action;
  final int position;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _ActionRow({
    required this.action,
    required this.position,
    this.onMoveUp,
    this.onMoveDown,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final error = action.validationError;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: error == null ? tokens.border : tokens.error,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${position + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${actionLabel(action.action)} · '
                        '${describeValue(action)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        error ??
                            (action.targetsGroup
                                ? 'Group target'
                                : 'Device target'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: error == null
                              ? tokens.onSurfaceVariant
                              : tokens.error,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move up',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          onPressed: onMoveUp,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Move down',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          onPressed: onMoveDown,
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Remove action',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: tokens.error,
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Human label for an action name.
String actionLabel(String action) => switch (action) {
  'power' => 'Power',
  'brightness' => 'Brightness',
  'color' => 'Colour',
  'effect' => 'Effect',
  'speed' => 'Effect speed',
  'colorTemperature' => 'Colour temperature',
  _ => action,
};

/// Short, honest description of an action's parameter.
String describeValue(SceneAction action) => switch (action.action) {
  'power' => action.value == true ? 'on' : 'off',
  'brightness' => '${((action.value as int? ?? 0) / 10).round()}%',
  'speed' => '${action.value ?? 0}',
  'colorTemperature' => '${action.value ?? 0}K',
  'color' => _describeColor(action.value),
  'effect' => _describeEffect(action.value),
  _ => '${action.value}',
};

String _describeEffect(Object? value) {
  if (value is! String) return 'invalid effect';
  return effectByCommandName(value)?.name ?? value;
}

String _describeColor(Object? value) {
  if (value is! Map) return 'invalid colour';
  final read = (String key) {
    final raw = value[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return -1;
  };

  final r = read('red');
  final g = read('green');
  final b = read('blue');
  if (r < 0 || g < 0 || b < 0) return 'invalid colour';
  return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

class _EmptyActions extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyActions({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Icon(Icons.playlist_add, size: 32, color: tokens.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'This scene has no actions yet, so running it would do nothing.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add action'),
          ),
        ],
      ),
    );
  }
}

/// Colour swatch used by the action editor.
///
/// Named to avoid colliding with Flutter's own `ColorSwatch`.
class SceneColorSwatch extends StatelessWidget {
  final int red;
  final int green;
  final int blue;
  final double size;

  const SceneColorSwatch({
    super.key,
    required this.red,
    required this.green,
    required this.blue,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final color = RGBColor(red, green, blue).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.tokens.border),
      ),
    );
  }
}
