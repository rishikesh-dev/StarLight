// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_group.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/presentation/bloc/group/group_cubit.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Picks one action for a scene: which device or group it targets, what it
/// does, and with which value.
///
/// Only actions the chosen target actually supports are offered, so a scene
/// cannot be built around a command that would be rejected at run time. Values
/// are ordinary user concepts (brightness percentage, on/off, a colour) — no
/// protocol identifiers are exposed.
class SceneActionEditorSheet extends StatefulWidget {
  final SceneAction? initial;

  const SceneActionEditorSheet({super.key, this.initial});

  @override
  State<SceneActionEditorSheet> createState() => _SceneActionEditorSheetState();
}

class _SceneActionEditorSheetState extends State<SceneActionEditorSheet> {
  String? _deviceId;
  String? _groupId;
  String _action = 'power';

  bool _power = true;
  int _brightness = 1000;
  int _speed = 50;
  int _kelvin = 4000;
  int _red = 255;
  int _green = 255;
  int _blue = 255;
  String? _effectCommand;

  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _deviceId = initial.deviceId;
    _groupId = initial.groupId;
    _action = initial.action;
    _loadValue(initial.action, initial.value);
  }

  void _loadValue(String action, Object? value) {
    switch (action) {
      case 'power':
        _power = value == true;
      case 'brightness':
        if (value is int) _brightness = value.clamp(0, 1000);
      case 'speed':
        if (value is int) _speed = value.clamp(0, 100);
      case 'colorTemperature':
        if (value is int) _kelvin = value.clamp(1000, 10000);
      case 'color':
        final rgb = _readColor(value);
        if (rgb != null) {
          _red = rgb.$1;
          _green = rgb.$2;
          _blue = rgb.$3;
        }
      case 'effect':
        if (value is String) _effectCommand = value;
    }
  }

  static (int, int, int)? _readColor(Object? value) {
    if (value is! Map) return null;
    int? channel(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      if (raw is num && raw == raw.roundToDouble()) return raw.toInt();
      return null;
    }

    final r = channel('red');
    final g = channel('green');
    final b = channel('blue');
    if (r == null || g == null || b == null) return null;
    return (r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final targets = _targets();
    final selected = _selectedTarget(targets);
    final actions = selected == null
        ? const <String>[]
        : _actionsFor(selected.capabilities);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.initial == null ? 'Add action' : 'Edit action',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                if (targets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Pair a device first — a scene needs something to control.',
                      style: TextStyle(color: tokens.onSurfaceVariant),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: selected?.key,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Target',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final target in targets)
                        DropdownMenuItem<String>(
                          value: target.key,
                          child: Text(
                            target.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (key) {
                      final target = targets.firstWhere((t) => t.key == key);
                      setState(() {
                        _error = null;
                        if (target.isGroup) {
                          _groupId = target.id;
                          _deviceId = null;
                        } else {
                          _deviceId = target.id;
                          _groupId = null;
                        }
                        // Keep the action only if this target supports it.
                        if (!_actionsFor(target.capabilities)
                            .contains(_action)) {
                          _action =
                              _actionsFor(target.capabilities).firstOrNull ??
                              _action;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (actions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Nothing this target can do is available as a scene '
                        'action.',
                        style: TextStyle(color: tokens.warning, fontSize: 13),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in actions)
                          ChoiceChip(
                            label: Text(_labelOf(action)),
                            selected: _action == action,
                            onSelected: (_) => setState(() {
                              _action = action;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  _valueEditor(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(color: tokens.error, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: selected == null || actions.isEmpty
                      ? null
                      : _submit,
                  child: Text(
                    widget.initial == null ? 'Add action' : 'Save action',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Targets ---------------------------------------------------------------

  List<_Target> _targets() {
    final devices = context.read<DeviceRegistryCubit>().state.devices;
    final groups = context.read<GroupCubit>().state.groups;

    final deviceTargets = [
      for (final device in devices)
        _Target(
          key: 'device:${device.id}',
          id: device.id,
          label: device.name,
          isGroup: false,
          capabilities: device.capabilities.toSet(),
        ),
    ];
    final registry = context.read<DeviceRegistryCubit>().state;
    final groupTargets = [
      for (final group in groups)
        _Target(
          key: 'group:${group.id}',
          id: group.id,
          label: '${group.name} (group)',
          isGroup: true,
          capabilities: _commonCapabilities(group, registry),
        ),
    ];

    // Keep the current selection first so the dropdown does not jump when the
    // list is rebuilt.
    return [...deviceTargets, ...groupTargets];
  }

  static Set<DeviceCapability> _commonCapabilities(
    DeviceGroup group,
    DeviceRegistryState registry,
  ) {
    final members = [for (final id in group.deviceIds) registry.byId(id)];
    if (members.isEmpty || members.any((m) => m == null)) {
      return const {};
    }
    var common = members.first!.capabilities.toSet();
    for (final member in members.skip(1)) {
      common = common.intersection(member!.capabilities.toSet());
    }
    return common;
  }

  _Target? _selectedTarget(List<_Target> targets) {
    if (_groupId != null) {
      for (final target in targets) {
        if (target.isGroup && target.id == _groupId) return target;
      }
    }
    if (_deviceId != null) {
      for (final target in targets) {
        if (!target.isGroup && target.id == _deviceId) return target;
      }
    }
    return targets.isEmpty ? null : targets.first;
  }

  // --- Actions ---------------------------------------------------------------

  /// Display order of the actions a target may offer.
  static const List<DeviceCapability> _actionOrder = [
    DeviceCapability.power,
    DeviceCapability.brightness,
    DeviceCapability.color,
    DeviceCapability.effect,
    DeviceCapability.speed,
    DeviceCapability.colorTemperature,
  ];

  static const Map<DeviceCapability, String> _actionForCapability = {
    DeviceCapability.power: 'power',
    DeviceCapability.brightness: 'brightness',
    DeviceCapability.color: 'color',
    DeviceCapability.effect: 'effect',
    DeviceCapability.speed: 'speed',
    DeviceCapability.colorTemperature: 'colorTemperature',
  };

  static List<String> _actionsFor(Set<DeviceCapability> capabilities) => [
    for (final capability in _actionOrder)
      if (capabilities.contains(capability)) _actionForCapability[capability]!,
  ];

  static String _labelOf(String action) => switch (action) {
    'power' => 'Power',
    'brightness' => 'Brightness',
    'color' => 'Colour',
    'effect' => 'Effect',
    'speed' => 'Speed',
    'colorTemperature' => 'Colour temperature',
    _ => action,
  };

  // --- Values ----------------------------------------------------------------

  Widget _valueEditor() {
    switch (_action) {
      case 'power':
        return SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('On')),
            ButtonSegment(value: false, label: Text('Off')),
          ],
          selected: {_power},
          onSelectionChanged: (selection) =>
              setState(() => _power = selection.first),
        );
      case 'brightness':
        return _SliderRow(
          label: 'Brightness',
          value: (_brightness / 10).round().toDouble(),
          max: 100,
          display: '${(_brightness / 10).round()}%',
          onChanged: (v) => setState(() => _brightness = (v * 10).round()),
        );
      case 'speed':
        return _SliderRow(
          label: 'Effect speed',
          value: _speed.toDouble(),
          max: 100,
          display: '$_speed',
          onChanged: (v) => setState(() => _speed = v.round()),
        );
      case 'colorTemperature':
        return _SliderRow(
          label: 'Colour temperature',
          value: _kelvin.toDouble(),
          min: 1000,
          max: 10000,
          display: '${_kelvin}K',
          onChanged: (v) => setState(() => _kelvin = v.round()),
        );
      case 'color':
        return _ColorEditor(
          red: _red,
          green: _green,
          blue: _blue,
          onChanged: (r, g, b) => setState(() {
            _red = r;
            _green = g;
            _blue = b;
          }),
        );
      case 'effect':
        return _EffectEditor(
          selected: _effectCommand,
          onChanged: (value) => setState(() => _effectCommand = value),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _submit() {
    final action = SceneAction(
      deviceId: _groupId == null ? _deviceId : null,
      groupId: _groupId,
      action: _action,
      value: _rawValue(),
    );
    final error = action.validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(action);
  }

  Object? _rawValue() => switch (_action) {
    'power' => _power,
    'brightness' => _brightness,
    'speed' => _speed,
    'colorTemperature' => _kelvin,
    'color' => {'red': _red, 'green': _green, 'blue': _blue},
    'effect' => _EffectEditor.resolve(_effectCommand),
    _ => null,
  };
}

class _Target {
  final String key;
  final String id;
  final String label;
  final bool isGroup;
  final Set<DeviceCapability> capabilities;

  const _Target({
    required this.key,
    required this.id,
    required this.label,
    required this.isGroup,
    required this.capabilities,
  });
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: tokens.onSurfaceVariant),
              ),
            ),
            Text(
              display,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorEditor extends StatelessWidget {
  final int red;
  final int green;
  final int blue;
  final void Function(int, int, int) onChanged;

  const _ColorEditor({
    required this.red,
    required this.green,
    required this.blue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, red, green, blue),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.border),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '#${red.toRadixString(16).padLeft(2, '0')}'
                      '${green.toRadixString(16).padLeft(2, '0')}'
                      '${blue.toRadixString(16).padLeft(2, '0')}'
                  .toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ChannelSlider(
          label: 'Red',
          value: red.toDouble(),
          color: Colors.red,
          onChanged: (v) => onChanged(v.round(), green, blue),
        ),
        _ChannelSlider(
          label: 'Green',
          value: green.toDouble(),
          color: Colors.green,
          onChanged: (v) => onChanged(red, v.round(), blue),
        ),
        _ChannelSlider(
          label: 'Blue',
          value: blue.toDouble(),
          color: Colors.blue,
          onChanged: (v) => onChanged(red, green, v.round()),
        ),
      ],
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: tokens.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: color),
            child: Slider(value: value, max: 255, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _EffectEditor extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onChanged;

  const _EffectEditor({required this.selected, required this.onChanged});

  /// Only hardware-native patterns can be selected through the device-mode
  /// command path, so StarLight's custom effects are deliberately not offered.
  static List<EffectDefinition> get options => [
    for (final effect in kMrStarEffects)
      if (effect.commandName != null) effect,
  ];

  /// The command name to store for [selected].
  ///
  /// A legacy name is migrated to the canonical command for the mode it
  /// always selected; any other unknown value is preserved verbatim rather
  /// than being replaced by a different effect. See
  /// [resolveEffectCommandName] for the full policy.
  static String? resolve(String? selected) =>
      resolveEffectCommandName(selected);

  /// The value to show in the dropdown.
  ///
  /// `null` when the stored value is not a known effect, because the dropdown
  /// may only hold values that are actually selectable. The stored value
  /// itself is still preserved by [resolve].
  static String? dropdownValue(String? selected) {
    final resolved = resolve(selected);
    if (resolved == null) return null;
    for (final effect in options) {
      if (effect.commandName == resolved) return resolved;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final list = options;
    if (list.isEmpty) {
      return Text(
        'This device has no hardware effects to choose from.',
        style: TextStyle(color: context.tokens.onSurfaceVariant),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: dropdownValue(selected),
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Effect',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final effect in list)
          DropdownMenuItem<String>(
            value: effect.commandName,
            child: Text(
              effect.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
