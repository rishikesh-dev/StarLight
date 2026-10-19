// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/core/utils/hex_utils.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

class HardwareLabPage extends StatefulWidget {
  const HardwareLabPage({super.key});
  static const String routeName = '/hardware-lab';

  @override
  State<HardwareLabPage> createState() => _HardwareLabPageState();
}

class _HardwareLabPageState extends State<HardwareLabPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _currentModeId = 0;
  int _autoStepDelaySec = 2;
  bool _autoStepping = false;
  final Map<int, String> _modeNotes = {};
  final Map<int, bool> _modeVerified = {};
  int _lastColorTime = 0;
  int _speedTestModeId = 0;
  int _lastSpeedTime = 0;
  final List<_LogEntry> _log = [];
  late final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hardware Lab')),
        body: const Center(
          child: Text('Hardware Lab is only available in debug builds.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardware Lab'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Native Modes'),
            Tab(text: 'Color Test'),
            Tab(text: 'Speed Test'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _clearLog,
            tooltip: 'Clear log',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _NativeModeTab(
                  currentModeId: _currentModeId,
                  autoStepDelaySec: _autoStepDelaySec,
                  autoStepping: _autoStepping,
                  modeNotes: _modeNotes,
                  modeVerified: _modeVerified,
                  noteController: _noteController,
                  onPrev: _prevMode,
                  onNext: _nextMode,
                  onJump: _jumpToMode,
                  onAutoStepToggle: _toggleAutoStep,
                  onDelayChanged: (v) => setState(() => _autoStepDelaySec = v),
                  onSaveNote: _saveNote,
                  onToggleVerified: _toggleVerified,
                  onExportNotes: _exportNotes,
                  onSendMode: _sendNativeMode,
                ),
                _ColorTestTab(
                  onSendColor: _sendColorTuple,
                  lastTime: _lastColorTime,
                ),
                _SpeedTestTab(
                  modeId: _speedTestModeId,
                  onModeChanged: (v) => setState(() => _speedTestModeId = v),
                  onSendSpeed: _sendSpeed,
                  lastTime: _lastSpeedTime,
                ),
              ],
            ),
          ),
          _PacketLogView(log: _log, onClear: _clearLog),
        ],
      ),
    );
  }

  void _logPacket(String label, Uint8List bytes) {
    final entry = _LogEntry(
      time: DateTime.now(),
      label: label,
      hex: HexUtils.toHexString(bytes),
    );
    setState(() {
      _log.insert(0, entry);
      if (_log.length > 200) _log.removeLast();
    });
    AppLog.debug('HWLAB: $label → ${entry.hex}');
  }

  void _clearLog() => setState(() => _log.clear());

  Future<void> _sendBytes(Uint8List bytes, String label) async {
    final router = context.read<LightBloc>().router;
    try {
      await router.send(
        DeviceCommand(type: 'raw', parameters: {'bytes': bytes}),
      );
      _logPacket(label, bytes);
    } catch (e) {
      _logPacket(
        'ERROR: $label',
        Uint8List.fromList(utf8.encode(e.toString())),
      );
    }
  }

  void _sendNativeMode(int modeId) {
    _sendBytes(ProtocolEncoder.setMode(modeId), 'setMode($modeId)');
  }

  void _sendColor(int r, int g, int b) {
    _sendBytes(ProtocolEncoder.colorFromRGB(r, g, b), 'color($r,$g,$b)');
    _lastColorTime = DateTime.now().millisecondsSinceEpoch;
  }

  void _sendColorTuple((int, int, int) rgb) {
    _sendColor(rgb.$1, rgb.$2, rgb.$3);
  }

  void _sendSpeed(int speed) {
    _sendBytes(ProtocolEncoder.setSpeed(speed), 'speed($speed)');
    _lastSpeedTime = DateTime.now().millisecondsSinceEpoch;
  }

  void _toggleAutoStep() {
    if (_autoStepping) {
      setState(() => _autoStepping = false);
      return;
    }
    setState(() => _autoStepping = true);
    _autoStepLoop();
  }

  Future<void> _autoStepLoop() async {
    while (_autoStepping) {
      if (!mounted) break;
      _sendNativeMode(_currentModeId);
      await Future.delayed(Duration(seconds: _autoStepDelaySec));
      if (!_autoStepping) break;
      setState(() => _currentModeId = (_currentModeId + 1) % 131);
    }
  }

  void _prevMode() => setState(() {
    _currentModeId = (_currentModeId - 1) % 131;
    if (_currentModeId < 0) _currentModeId += 131;
  });

  void _nextMode() =>
      setState(() => _currentModeId = (_currentModeId + 1) % 131);

  void _jumpToMode(int id) => setState(() => _currentModeId = id.clamp(0, 130));

  void _saveNote() =>
      setState(() => _modeNotes[_currentModeId] = _noteController.text);
  void _toggleVerified() => setState(
    () => _modeVerified[_currentModeId] =
        !(_modeVerified[_currentModeId] ?? false),
  );
  void _exportNotes() {
    final map = <String, dynamic>{};
    for (final e in _modeNotes.entries) {
      map[e.key.toString()] = {
        'note': e.value,
        'verified': _modeVerified[e.key] ?? false,
      };
    }
    AppLog.info('HWLAB EXPORT:\n${JsonEncoder.withIndent("  ").convert(map)}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notes exported to debug console')),
    );
  }
}

String _modeName(int id) {
  return switch (id) {
    0 => 'Solid',
    1 => 'Fireworks',
    2 => 'Rainbow',
    3 => 'Breath',
    4 => 'Scan',
    5 => 'Flash',
    6 => 'Police',
    7 => 'Chase',
    8 => 'Comet',
    9 => 'Lava',
    10 => 'Ocean',
    _ => 'Mode $id',
  };
}

class _NativeModeTab extends StatelessWidget {
  final int currentModeId;
  final int autoStepDelaySec;
  final bool autoStepping;
  final Map<int, String> modeNotes;
  final Map<int, bool> modeVerified;
  final TextEditingController noteController;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onJump;
  final VoidCallback onAutoStepToggle;
  final ValueChanged<int> onDelayChanged;
  final VoidCallback onSaveNote;
  final VoidCallback onToggleVerified;
  final VoidCallback onExportNotes;
  final ValueChanged<int> onSendMode;

  const _NativeModeTab({
    required this.currentModeId,
    required this.autoStepDelaySec,
    required this.autoStepping,
    required this.modeNotes,
    required this.modeVerified,
    required this.noteController,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
    required this.onAutoStepToggle,
    required this.onDelayChanged,
    required this.onSaveNote,
    required this.onToggleVerified,
    required this.onExportNotes,
    required this.onSendMode,
  });

  @override
  Widget build(BuildContext context) {
    final verified = modeVerified[currentModeId] ?? false;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModeCard(context, verified),
          const SizedBox(height: 16),
          _buildNotesCard(context, verified),
          const SizedBox(height: 16),
          _buildQuickRefCard(context),
        ],
      ),
    );
  }

  Widget _buildModeCard(BuildContext context, bool verified) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: onPrev,
                  tooltip: 'Previous',
                ),
                Text(
                  'Mode $currentModeId',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: onNext,
                  tooltip: 'Next',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                  onPressed: () => onSendMode(currentModeId),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: Icon(autoStepping ? Icons.pause : Icons.play_arrow),
                  label: Text(autoStepping ? 'Stop Auto' : 'Auto Step'),
                  onPressed: onAutoStepToggle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Jump to: '),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (v) => onJump(int.tryParse(v) ?? 0),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Delay (s): '),
                SizedBox(
                  width: 60,
                  child: DropdownButton<int>(
                    value: autoStepDelaySec,
                    items: [1, 2, 3, 4, 5]
                        .map(
                          (e) => DropdownMenuItem(value: e, child: Text('$e')),
                        )
                        .toList(),
                    onChanged: (v) => onDelayChanged(v!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context, bool verified) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(value: verified, onChanged: (_) => onToggleVerified()),
                const Text('Verified on hardware'),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'What did the strip do?',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSaveNote(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Note'),
                  onPressed: onSaveNote,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export JSON'),
                  onPressed: onExportNotes,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRefCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quick Reference (from APK)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                  _ModeChip(
                    id: id,
                    name: _modeName(id),
                    selected: id == currentModeId,
                    onTap: () => onJump(id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final int id;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.id,
    required this.name,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text('$id: $name'),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: Theme.of(context).colorScheme.primaryContainer,
  );
}

class _ColorTestTab extends StatelessWidget {
  final ValueChanged<(int, int, int)> onSendColor;
  final int lastTime;
  const _ColorTestTab({required this.onSendColor, required this.lastTime});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Solid Color Test', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Sends colorFromRGB() packets. The controller uses HSV internally.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (name, r, g, b) in [
              ('Red', 255, 0, 0),
              ('Green', 0, 255, 0),
              ('Blue', 0, 0, 255),
              ('White', 255, 255, 255),
            ])
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Color.fromRGBO(r, g, b, 1),
                  minimumSize: const Size(120, 80),
                ),
                onPressed: () => onSendColor((r, g, b)),
                child: Text(name),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (lastTime > 0)
          Text(
            'Last sent: ${DateTime.fromMillisecondsSinceEpoch(lastTime).toLocal()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

class _SpeedTestTab extends StatelessWidget {
  final int modeId;
  final ValueChanged<int> onModeChanged;
  final ValueChanged<int> onSendSpeed;
  final int lastTime;
  const _SpeedTestTab({
    required this.modeId,
    required this.onModeChanged,
    required this.onSendSpeed,
    required this.lastTime,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Speed Test', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Select a mode first, then send speed values 0–255.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Mode: '),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<int>(
                value: modeId,
                items: List.generate(
                  11,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text('$i: ${_modeName(i)}'),
                  ),
                ),
                onChanged: (v) => onModeChanged(v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in [0, 25, 50, 100, 150, 200, 255])
              OutlinedButton(
                onPressed: () => onSendSpeed(s),
                child: Text('$s'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (lastTime > 0)
          Text(
            'Last sent: ${DateTime.fromMillisecondsSinceEpoch(lastTime).toLocal()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

class _PacketLogView extends StatelessWidget {
  final List<_LogEntry> log;
  final VoidCallback onClear;
  const _PacketLogView({required this.log, required this.onClear});
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.surfaceHigh,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Text(
                  'Packet Log (${log.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: tokens.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear'),
                  onPressed: onClear,
                ),
              ],
            ),
          ),
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Text(
                      'No packets yet',
                      style: TextStyle(color: tokens.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: log.length,
                    itemBuilder: (context, index) {
                      final e = log[index];
                      return SelectableText(
                        '[${e.time.toLocal().toString().substring(11, 23)}] ${e.label}: ${e.hex}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: tokens.onSurface,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry {
  final DateTime time;
  final String label;
  final String hex;
  _LogEntry({required this.time, required this.label, required this.hex});
}
