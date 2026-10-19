// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/notification_format.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/services/profile_validator.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Creates or edits a custom BLE GATT device profile.
///
/// Validation mirrors [ProfileValidator] so the editor cannot save a profile
/// the executor would refuse. Only the capabilities the app can genuinely
/// execute are offered.
class ProfileEditorPage extends StatefulWidget {
  /// The profile to edit, or null to create a new one.
  final DeviceProfile? profile;

  const ProfileEditorPage({super.key, this.profile});

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _service;
  late final TextEditingController _write;
  late final TextEditingController _notify;
  late final TextEditingController _powerOn;
  late final TextEditingController _powerOff;
  late final TextEditingController _brightness;
  late final TextEditingController _color;
  late final TextEditingController _brightnessMin;
  late final TextEditingController _brightnessMax;

  final Set<DeviceCapability> _capabilities = {};
  final List<_RuleDraft> _rules = [];
  GattWriteMode _writeMode = GattWriteMode.automatic;

  Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.name ?? '');
    _service = TextEditingController(text: p?.serviceUuid ?? '');
    _write = TextEditingController(text: p?.writeCharacteristicUuid ?? '');
    _notify = TextEditingController(text: p?.notifyCharacteristicUuid ?? '');
    _powerOn = TextEditingController(text: p?.commands.powerOn?.toText() ?? '');
    _powerOff = TextEditingController(
      text: p?.commands.powerOff?.toText() ?? '',
    );
    _brightness = TextEditingController(
      text: p?.commands.brightness?.toText() ?? '',
    );
    _color = TextEditingController(text: p?.commands.color?.toText() ?? '');
    _brightnessMin = TextEditingController(
      text: (p?.commands.brightnessMin ?? 0).toString(),
    );
    _brightnessMax = TextEditingController(
      text: (p?.commands.brightnessMax ?? 255).toString(),
    );
    _writeMode = p?.writeMode ?? GattWriteMode.automatic;
    _capabilities.addAll(p?.capabilities ?? const <DeviceCapability>{});
    for (final rule in p?.notifications?.rules ?? const <NotificationRule>[]) {
      _rules.add(_RuleDraft.fromRule(rule));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _service,
      _write,
      _notify,
      _powerOn,
      _powerOff,
      _brightness,
      _color,
      _brightnessMin,
      _brightnessMax,
    ]) {
      c.dispose();
    }
    for (final rule in _rules) {
      rule.dispose();
    }
    super.dispose();
  }

  CommandTemplate? _parseTemplate(
    String source,
    String field,
    Set<ProfileValue> allowed,
    Map<String, String> errors,
  ) {
    final result = CommandTemplate.parse(source, allowed: allowed);
    if (result.template == null) {
      errors[field] = result.error ?? 'Enter a valid command.';
    }
    return result.template;
  }

  Future<void> _save() async {
    final errors = <String, String>{};

    CommandTemplate? powerOn;
    CommandTemplate? powerOff;
    CommandTemplate? brightness;
    CommandTemplate? color;

    if (_capabilities.contains(DeviceCapability.power)) {
      powerOn = _parseTemplate(_powerOn.text, 'powerOn', const {
        ProfileValue.checksum,
      }, errors);
      powerOff = _parseTemplate(_powerOff.text, 'powerOff', const {
        ProfileValue.checksum,
      }, errors);
    }
    if (_capabilities.contains(DeviceCapability.brightness)) {
      brightness = _parseTemplate(_brightness.text, 'brightness', const {
        ProfileValue.brightness,
        ProfileValue.checksum,
      }, errors);
    }
    if (_capabilities.contains(DeviceCapability.color)) {
      color = _parseTemplate(_color.text, 'color', const {
        ProfileValue.red,
        ProfileValue.green,
        ProfileValue.blue,
        ProfileValue.checksum,
      }, errors);
    }

    final brightnessMin = int.tryParse(_brightnessMin.text.trim());
    final brightnessMax = int.tryParse(_brightnessMax.text.trim());
    if (_capabilities.contains(DeviceCapability.brightness) &&
        (brightnessMin == null || brightnessMax == null)) {
      errors['brightnessRange'] = 'Enter whole numbers.';
    }

    final rules = <NotificationRule>[];
    for (final draft in _rules) {
      final rule = draft.toRule();
      if (rule == null) {
        errors['notifications'] = 'Each rule needs a byte offset and scale.';
      } else {
        rules.add(rule);
      }
    }

    final profile = DeviceProfile(
      id: widget.profile?.id ?? '',
      name: _name.text.trim(),
      serviceUuid: _service.text.trim(),
      writeCharacteristicUuid: _write.text.trim(),
      notifyCharacteristicUuid: _notify.text.trim().isEmpty
          ? null
          : _notify.text.trim(),
      writeMode: _writeMode,
      capabilities: Set.of(_capabilities),
      commands: GattCommandSet(
        powerOn: powerOn,
        powerOff: powerOff,
        brightness: brightness,
        color: color,
        brightnessMin: brightnessMin ?? 0,
        brightnessMax: brightnessMax ?? 255,
      ),
      notifications: rules.isEmpty ? null : NotificationFormat(rules),
    );

    for (final e in ProfileValidator.validate(profile)) {
      errors.putIfAbsent(e.field, () => e.message);
    }

    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _saving = false;
      });
      return;
    }

    setState(() {
      _saving = true;
      _errors = {};
    });

    final result = await context.read<ProfileCubit>().saveProfile(profile);
    if (!mounted) return;

    if (result.isSaved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _errors = {
        ...result.fieldErrors,
        if (result.error != null) 'form': result.error!,
      };
    });
  }

  void _addRule() {
    final used = _rules.map((r) => r.target).toSet();
    var target = NotificationTarget.power;
    for (final t in NotificationTarget.values) {
      if (!used.contains(t)) {
        target = t;
        break;
      }
    }
    setState(() => _rules.add(_RuleDraft.blank(target)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'New profile' : 'Edit profile'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _sectionLabel('Basics'),
          _textField('name', 'Profile name', _name),
          _textField(
            'serviceUuid',
            'Service UUID',
            _service,
            hint: 'fff0 or a full 128-bit UUID',
          ),
          _textField(
            'writeCharacteristicUuid',
            'Write characteristic UUID',
            _write,
          ),
          _textField(
            'notifyCharacteristicUuid',
            'Notify characteristic UUID (optional)',
            _notify,
          ),
          _sectionLabel('Capabilities'),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                DeviceCapability.power: 'Power',
                DeviceCapability.brightness: 'Brightness',
                DeviceCapability.color: 'Colour',
              }.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: _capabilities.contains(entry.key),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _capabilities.add(entry.key);
                    } else {
                      _capabilities.remove(entry.key);
                    }
                  }),
                ),
            ],
          ),
          if (_errors['capabilities'] != null)
            _errorText(_errors['capabilities']!),
          _sectionLabel('Write mode'),
          DropdownButton<GattWriteMode>(
            value: _writeMode,
            isExpanded: true,
            onChanged: (value) =>
                setState(() => _writeMode = value ?? GattWriteMode.automatic),
            items: [
              for (final mode in GattWriteMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
          ),
          if (_capabilities.contains(DeviceCapability.power)) ...[
            _sectionLabel('Power commands'),
            _textField(
              'powerOn',
              'Power ON command',
              _powerOn,
              hint: 'A0 01',
              mono: true,
            ),
            _textField(
              'powerOff',
              'Power OFF command',
              _powerOff,
              hint: 'A0 00',
              mono: true,
            ),
          ],
          if (_capabilities.contains(DeviceCapability.brightness)) ...[
            _sectionLabel('Brightness'),
            _textField(
              'brightness',
              'Brightness command',
              _brightness,
              hint: 'A0 {brightness} or 01 {brightness:u16le}',
              mono: true,
            ),
            Row(
              children: [
                Expanded(
                  child: _textField(
                    'brightnessRange',
                    'Minimum',
                    _brightnessMin,
                    number: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField(
                    'brightnessRange',
                    'Maximum',
                    _brightnessMax,
                    number: true,
                  ),
                ),
              ],
            ),
          ],
          if (_capabilities.contains(DeviceCapability.color)) ...[
            _sectionLabel('Colour'),
            _textField(
              'color',
              'Colour command',
              _color,
              hint: 'FF {red} {green} {blue} {checksum}',
              mono: true,
            ),
          ],
          _sectionLabel('Notifications (optional)'),
          Text(
            'Decode what the controller reports back. Byte offsets are '
            'zero-based.',
            style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
          ),
          if (_errors['notifications'] != null)
            _errorText(_errors['notifications']!),
          const SizedBox(height: 8),
          for (var i = 0; i < _rules.length; i++) _ruleCard(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addRule,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add notification rule'),
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Advanced'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Command template syntax',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Two hex digits (e.g. 0A) = one literal byte\n'
                  '• {brightness} {red} {green} {blue} insert live values\n'
                  '• {brightness:u16le} / {red:u16be} for a two-byte value\n'
                  '• {checksum} is the XOR of all previous bytes and must be '
                  'last\n'
                  'Colour and power values are single bytes.',
                  style: TextStyle(
                    color: tokens.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save profile'),
          ),
          if (_errors['form'] != null) _errorText(_errors['form']!),
        ],
      ),
    );
  }

  Widget _textField(
    String fieldKey,
    String label,
    TextEditingController controller, {
    String? hint,
    bool number = false,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: number ? TextInputType.number : null,
        style: mono ? const TextStyle(fontFamily: 'monospace') : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          errorText: _errors[fieldKey],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.tokens.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _errorText(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        message,
        style: TextStyle(color: context.tokens.error, fontSize: 12),
      ),
    );
  }

  Widget _ruleCard(int index) {
    final draft = _rules[index];
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<NotificationTarget>(
                  value: draft.target,
                  isExpanded: true,
                  onChanged: (value) =>
                      setState(() => draft.target = value ?? draft.target),
                  items: [
                    for (final target in NotificationTarget.values)
                      DropdownMenuItem(
                        value: target,
                        child: Text(target.label),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => setState(() {
                  _rules.removeAt(index).dispose();
                }),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextField(
                  controller: draft.offset,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Offset',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: draft.scale,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Scale',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<NumericWidth>(
                  value: draft.width,
                  isExpanded: true,
                  onChanged: (value) =>
                      setState(() => draft.width = value ?? draft.width),
                  items: [
                    for (final width in NumericWidth.values)
                      DropdownMenuItem(value: width, child: Text(width.id)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleDraft {
  NotificationTarget target;
  NumericWidth width;
  final TextEditingController offset;
  final TextEditingController scale;
  final TextEditingController onThreshold;

  _RuleDraft({
    required this.target,
    required this.width,
    String offset = '',
    String scale = '1',
    String onThreshold = '1',
  }) : offset = TextEditingController(text: offset),
       scale = TextEditingController(text: scale),
       onThreshold = TextEditingController(text: onThreshold);

  factory _RuleDraft.blank(NotificationTarget target) =>
      _RuleDraft(target: target, width: NumericWidth.u8, offset: '2');

  factory _RuleDraft.fromRule(NotificationRule rule) => _RuleDraft(
    target: rule.target,
    width: rule.width,
    offset: rule.byteOffset.toString(),
    scale: rule.scale.toString(),
    onThreshold: rule.onThreshold.toString(),
  );

  NotificationRule? toRule() {
    final parsedOffset = int.tryParse(offset.text.trim());
    final parsedScale = double.tryParse(scale.text.trim());
    if (parsedOffset == null || parsedScale == null) return null;
    return NotificationRule(
      target: target,
      byteOffset: parsedOffset,
      width: width,
      scale: parsedScale,
      onThreshold: int.tryParse(onThreshold.text.trim()) ?? 1,
    );
  }

  void dispose() {
    offset.dispose();
    scale.dispose();
    onThreshold.dispose();
  }
}
