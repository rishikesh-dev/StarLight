// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/effect_palette.dart';
import 'package:starlight/domain/services/custom_effect_renderer.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Effects Studio (route `/effects`).
///
/// One honest surface for two genuinely different kinds of effect:
///
/// * **Device patterns** ([EffectKind.hardwareNative]) — modes built into the
///   controller. StarLight selects one and can only claim the write was *sent*;
///   it cannot render these, so the preview shows a labelled decorative motif.
/// * **Custom effects** ([EffectKind.custom]) — StarLight's own algorithms. The
///   preview renders the real algorithm live (software only, no BLE). Effects
///   that need per-pixel output are marked *preview only* and cannot be sent.
///
/// For single-zone RGB devices (like the MR Star controller), custom effects
/// appear as **temporal colour sequences** — the whole light changes colour
/// together. The preview shows this honestly: a single colour disc that
/// animates, not a spatial strip. Effects needing addressable pixels (Meteor,
/// Starlight) remain preview-only.
///
/// A selection shown as *applied* always comes from the confirmed [LightState],
/// never from a tap. The studio stays usable while disconnected (preview only).
class EffectsStudioPage extends StatefulWidget {
  const EffectsStudioPage({super.key});

  @override
  State<EffectsStudioPage> createState() => _EffectsStudioPageState();
}

const int _kDefaultCustomSpeed = 50;
const int _kDefaultCustomIntensity = 70;

/// Length of the preview loop. Renderer speed scales frequency internally.
const double _kPreviewLoopSeconds = 30;

class _EffectsStudioPageState extends State<EffectsStudioPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _preview;

  /// Local, preview-only selection override. Never treated as "applied".
  String? _selectedId;
  EffectKind? _kindFilter;
  EffectCategory? _categoryFilter;

  /// Id of the effect whose command/playback is in flight.
  String? _pendingId;

  int? _speedOverride;
  int? _intensityOverride;
  String? _paletteOverride;

  @override
  void initState() {
    super.initState();
    _preview = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  EffectDefinition _resolveSelection(LightState state) =>
      effectById(_selectedId) ??
      effectById(state.lightActiveEffectId) ??
      kCustomEffects.first;

  int _speedFor(LightState state, EffectDefinition effect) =>
      _speedOverride ??
      (effect.kind == EffectKind.custom
          ? _kDefaultCustomSpeed
          : (state.lightSpeed ?? 50));

  int _intensityFor(EffectDefinition effect) =>
      _intensityOverride ?? _kDefaultCustomIntensity;

  String? _paletteIdFor(EffectDefinition effect) =>
      _paletteOverride ?? effect.defaultPaletteId;

  void _select(EffectDefinition effect) {
    setState(() {
      _selectedId = effect.id;
      _speedOverride = null;
      _intensityOverride = null;
      _paletteOverride = effect.defaultPaletteId;
    });
    if (effect.kind == EffectKind.custom && !effect.requiresAddressable) {
      context.read<LightBloc>().add(
        ConfigureCustomEffect(
          speed: _kDefaultCustomSpeed,
          intensity: _kDefaultCustomIntensity,
          paletteId: effect.defaultPaletteId,
        ),
      );
    }
  }

  void _sendDevicePattern(EffectDefinition effect) {
    final commandName = effect.commandName;
    if (_pendingId != null || commandName == null) return;
    setState(() => _pendingId = effect.id);
    context.read<LightBloc>().add(ChangeEffect(commandName));
  }

  void _playCustom(EffectDefinition effect) {
    if (_pendingId != null) return;
    setState(() => _pendingId = effect.id);
    context.read<LightBloc>().add(PlayCustomEffect(effect.id));
  }

  void _stopCustom() => context.read<LightBloc>().add(const StopCustomEffect());

  void _commitSpeed(EffectDefinition effect, int value) {
    setState(() => _speedOverride = value);
    if (effect.kind == EffectKind.custom) {
      context.read<LightBloc>().add(ConfigureCustomEffect(speed: value));
    } else {
      context.read<LightBloc>().add(ChangeSpeed(value));
    }
  }

  void _commitIntensity(int value) {
    setState(() => _intensityOverride = value);
    context.read<LightBloc>().add(ConfigureCustomEffect(intensity: value));
  }

  void _selectPalette(EffectPalette palette) {
    setState(() => _paletteOverride = palette.id);
    context.read<LightBloc>().add(ConfigureCustomEffect(paletteId: palette.id));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Effects Studio'),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: tokens.onSurface,
        ),
        surfaceTintColor: Colors.transparent,
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: _DeviceChip()),
        ],
      ),
      body: BlocConsumer<LightBloc, LightState>(
        listenWhen: (previous, next) => _pendingId != null && previous != next,
        listener: (context, state) {
          if (_pendingId == null) return;
          setState(() => _pendingId = null);
          if (state is LightError) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
        },
        builder: (context, state) {
          final effect = _resolveSelection(state);
          final speed = _speedFor(state, effect);
          final intensity = _intensityFor(effect);
          final palette = effectPaletteOrDefault(_paletteIdFor(effect));
          final capabilities = state.lightCapabilities;
          final connected = state.lightIsConnected;

          _syncPreviewAnimation(effect);

          final visible = _visibleEffects();

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _StatusHeader(
                      connected: connected,
                      capabilities: capabilities,
                      effect: effect,
                    ),
                    const SizedBox(height: 16),
                    _HeroStage(
                      effect: effect,
                      animation: _preview,
                      effectSpeed: speed,
                      intensity: intensity,
                      palette: palette,
                      status: _statusFor(state, effect),
                    ),
                    const SizedBox(height: 20),
                    _ControlsPanel(
                      effect: effect,
                      speed: speed,
                      intensity: intensity,
                      selectedPaletteId: palette.id,
                      speedEnabled:
                          connected &&
                          (effect.kind == EffectKind.custom
                              ? capabilities.contains(DeviceCapability.color)
                              : capabilities.contains(DeviceCapability.speed)),
                      tuningEnabled:
                          connected &&
                          capabilities.contains(DeviceCapability.color),
                      onSpeedCommit: (v) => _commitSpeed(effect, v),
                      onIntensityCommit: _commitIntensity,
                      onPaletteSelected: _selectPalette,
                    ),
                    const SizedBox(height: 14),
                    _ActionBar(
                      effect: effect,
                      state: state,
                      pending: _pendingId == effect.id,
                      onSend: () => _sendDevicePattern(effect),
                      onPlay: () => _playCustom(effect),
                      onStop: _stopCustom,
                    ),
                    const SizedBox(height: 24),
                    _FilterBar(
                      kind: _kindFilter,
                      category: _categoryFilter,
                      onKind: (k) => setState(() => _kindFilter = k),
                      onCategory: (c) => setState(() => _categoryFilter = c),
                    ),
                    const SizedBox(height: 14),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 150,
                    mainAxisExtent: 125,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final tile = visible[index];
                    return _EffectTile(
                      effect: tile,
                      selected: tile.id == effect.id,
                      active: _isActive(state, tile),
                      pending: _pendingId == tile.id,
                      speed: speed,
                      intensity: intensity,
                      palette: effectPaletteOrDefault(_paletteIdFor(tile)),
                      onTap: () => _select(tile),
                    );
                  }, childCount: visible.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _syncPreviewAnimation(EffectDefinition effect) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (effect.kind == EffectKind.custom && !_preview.isAnimating) {
        _preview.repeat();
      } else if (effect.kind != EffectKind.custom && _preview.isAnimating) {
        _preview.stop();
      }
    });
  }

  List<EffectDefinition> _visibleEffects() {
    return kEffectCatalogue
        .where((e) {
          if (_kindFilter != null && e.kind != _kindFilter) return false;
          if (_categoryFilter != null && e.category != _categoryFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  bool _isActive(LightState state, EffectDefinition effect) {
    if (effect.kind == EffectKind.custom) {
      return state.lightCustomEffectId == effect.id && state.lightCustomPlaying;
    }
    return state.lightEffect == effect.commandName;
  }

  _StageStatus _statusFor(LightState state, EffectDefinition effect) {
    if (effect.playback == EffectPlayback.previewOnly) {
      return _StageStatus.previewOnly;
    }
    if (_pendingId == effect.id) return _StageStatus.sending;
    if (effect.kind == EffectKind.custom) {
      return state.lightCustomEffectId == effect.id && state.lightCustomPlaying
          ? _StageStatus.playing
          : _StageStatus.preview;
    }
    return state.lightEffect == effect.commandName
        ? _StageStatus.applied
        : _StageStatus.preview;
  }
}

enum _StageStatus { preview, sending, applied, playing, previewOnly }

/// Compact device + connection status that stays in the app bar.
class _DeviceChip extends StatelessWidget {
  const _DeviceChip();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<BleBloc, BleState>(
      builder: (context, state) {
        final (String name, Color color, IconData icon) = switch (state) {
          BleConnected(:final device) => (
            device.name,
            tokens.success,
            Icons.bluetooth_connected,
          ),
          BleConnecting() => (
            'Connecting…',
            tokens.warning,
            Icons.bluetooth_searching,
          ),
          _ => ('No device', tokens.onSurfaceVariant, Icons.bluetooth_disabled),
        };
        return Container(
          constraints: const BoxConstraints(maxWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Status header showing device capabilities and execution readiness.
class _StatusHeader extends StatelessWidget {
  final bool connected;
  final Set<DeviceCapability> capabilities;
  final EffectDefinition effect;

  const _StatusHeader({
    required this.connected,
    required this.capabilities,
    required this.effect,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final bool canRunNative = capabilities.contains(DeviceCapability.effect);
    final bool canRunCustom = capabilities.contains(DeviceCapability.color);
    final bool canRun =
        (effect.kind == EffectKind.hardwareNative && canRunNative) ||
        (effect.kind == EffectKind.custom && canRunCustom);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                size: 18,
                color: connected ? tokens.success : tokens.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                connected ? 'Device connected' : 'No device connected',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: connected ? tokens.onSurface : tokens.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (effect.kind == EffectKind.hardwareNative) ...[
                _CapabilityChip(
                  label: 'Device patterns',
                  enabled: canRunNative,
                  icon: Icons.memory,
                ),
              ],
              if (effect.kind == EffectKind.custom) ...[
                _CapabilityChip(
                  label: 'Custom effects',
                  enabled: canRunCustom,
                  icon: Icons.auto_awesome,
                ),
              ],
              if (effect.requiresAddressable)
                _CapabilityChip(
                  label: 'Needs addressable LEDs',
                  enabled: false,
                  icon: Icons.light_mode,
                ),
            ],
          ),
          if (!connected || !canRun) ...[
            const SizedBox(height: 10),
            Text(
              _statusMessage(canRun),
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusMessage(bool canRun) {
    if (!connected) return 'Connect a device to send effects to hardware.';
    if (effect.playback == EffectPlayback.previewOnly) {
      return 'This effect needs per-pixel control the transport cannot provide. '
          'Preview only — cannot be sent to device.';
    }
    if (effect.kind == EffectKind.custom && !canRun) {
      return 'This device cannot stream colours, so custom effects cannot play.';
    }
    // For device patterns, the action bar shows the capability message.
    return '';
  }
}

class _CapabilityChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final IconData icon;

  const _CapabilityChip({
    required this.label,
    required this.enabled,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: enabled
            ? tokens.primary.withValues(alpha: 0.12)
            : tokens.onSurfaceVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: enabled
              ? tokens.primary
              : tokens.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: enabled ? tokens.primary : tokens.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: enabled ? tokens.primary : tokens.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The large stage: the real custom algorithm, or a labelled decorative motif.
class _HeroStage extends StatelessWidget {
  final EffectDefinition effect;
  final Animation<double> animation;
  final int effectSpeed;
  final int intensity;
  final EffectPalette palette;
  final _StageStatus status;

  const _HeroStage({
    required this.effect,
    required this.animation,
    required this.effectSpeed,
    required this.intensity,
    required this.palette,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tokens.border),
        ),
        child: AspectRatio(
          aspectRatio: 1.34,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _StagePainter(
                  animation: animation,
                  effect: effect,
                  speed: effectSpeed,
                  intensity: intensity,
                  palette: palette,
                  tokens: tokens,
                  seed: _stableSeed(effect.id),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.background.withValues(alpha: 0),
                        tokens.background.withValues(alpha: 0.9),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: _Badge(
                                  label: effect.kind == EffectKind.custom
                                      ? 'CUSTOM'
                                      : 'DEVICE',
                                  color: effect.kind == EffectKind.custom
                                      ? tokens.primary
                                      : tokens.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: _Badge(
                                  label: effect.category.label.toUpperCase(),
                                  color: _categoryColor(
                                    effect.category,
                                    tokens,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: status),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      effect.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      effect.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: tokens.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    if (effect.kind == EffectKind.hardwareNative) ...[
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
                              'Pattern rendered by controller. Not verified on hardware.',
                              style: TextStyle(
                                color: tokens.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (effect.hardwareVerified == false &&
                        effect.kind == EffectKind.hardwareNative) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 13,
                            color: tokens.warning,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Mode ID from APK — visual pattern not confirmed on hardware.',
                              style: TextStyle(
                                color: tokens.warning,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _StageStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (Color color, IconData icon, String label) = switch (status) {
      _StageStatus.preview => (
        tokens.onSurfaceVariant,
        Icons.remove_red_eye_outlined,
        'Preview',
      ),
      _StageStatus.sending => (tokens.warning, Icons.sync, 'Sending…'),
      _StageStatus.applied => (tokens.success, Icons.check, 'Sent'),
      _StageStatus.playing => (tokens.success, Icons.graphic_eq, 'Playing'),
      _StageStatus.previewOnly => (
        tokens.warning,
        Icons.info_outline,
        'Preview only',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  final Animation<double> animation;
  final EffectDefinition effect;
  final int speed;
  final int intensity;
  final EffectPalette palette;
  final AppTokens tokens;
  final int seed;

  _StagePainter({
    required this.animation,
    required this.effect,
    required this.speed,
    required this.intensity,
    required this.palette,
    required this.tokens,
    required this.seed,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tokens.background);

    if (effect.kind == EffectKind.custom) {
      final sample = renderCustomEffect(
        effect.id,
        CustomEffectInput(
          time: animation.value * _kPreviewLoopSeconds,
          pixels: (size.width / 9).floor().clamp(18, 72),
          speed: speed / 100,
          intensity: intensity / 100,
          palette: palette,
          seed: seed,
        ),
      );
      if (sample != null) {
        if (effect.playback == EffectPlayback.colorSequence) {
          // Global-RGB effect: show what the single-zone device actually displays
          _paintSingleZonePreview(canvas, size, sample);
        } else {
          // Addressable-only effect: show spatial preview with clear label
          _paintSpatialPreview(canvas, size, sample);
        }
      }
    } else {
      _paintMotif(canvas, size);
    }
  }

  /// Paints the temporal colour sequence that a single-zone RGB device displays.
  /// This is what the hardware actually sees — one colour at a time, changing over time.
  void _paintSingleZonePreview(
    Canvas canvas,
    Size size,
    CustomEffectSample sample,
  ) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.35;
    final innerRadius = radius * 0.6;

    // Large central disc showing the current global colour
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Color.fromARGB(
          255,
          sample.global.red,
          sample.global.green,
          sample.global.blue,
        ),
    );

    // Inner ring showing the colour with a subtle pulse for intensity
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = tokens.background.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Labels explaining the single-zone reality
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // "Single-zone output" label
    textPainter.text = TextSpan(
      text: 'Single-zone output',
      style: TextStyle(
        color: tokens.onSurfaceVariant.withValues(alpha: 0.7),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - radius - 28),
    );

    // Hex colour value
    final hex =
        '#${sample.global.red.toRadixString(16).padLeft(2, '0')}'
        '${sample.global.green.toRadixString(16).padLeft(2, '0')}'
        '${sample.global.blue.toRadixString(16).padLeft(2, '0')}';
    textPainter.text = TextSpan(
      text: hex.toUpperCase(),
      style: TextStyle(
        color: tokens.onSurface.withValues(alpha: 0.9),
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + radius + 16),
    );
  }

  /// Paints the spatial preview for addressable-only effects (Meteor, Starlight).
  /// Clearly labelled as preview-only since the transport cannot reproduce it.
  void _paintSpatialPreview(
    Canvas canvas,
    Size size,
    CustomEffectSample sample,
  ) {
    final n = sample.pixels.length;
    if (n == 0) return;
    final slot = size.width / n;
    final gap = slot * 0.18;
    final barWidth = slot - gap;
    final radius = Radius.circular(barWidth * 0.4);
    final top = size.height * 0.12;
    final height = size.height * 0.55;

    // Overlapping low-alpha rects read as a soft glow
    final wash = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < n; i++) {
      final c = sample.pixels[i];
      wash.color = Color.fromARGB(38, c.red, c.green, c.blue);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * slot + gap / 2, top, barWidth, height),
          radius,
        ),
        wash,
      );
    }
    for (var i = 0; i < n; i++) {
      final c = sample.pixels[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * slot + gap / 2, top, barWidth, height),
          radius,
        ),
        Paint()..color = Color.fromARGB(255, c.red, c.green, c.blue),
      );
    }

    // "Preview only" badge overlay
    final badgeTop = top + height + 12;
    final center = size.center(Offset.zero);
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.text = TextSpan(
      text: 'Preview only — needs addressable LEDs',
      style: TextStyle(
        color: tokens.warning,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, badgeTop),
    );
  }

  /// Restrained, static stand-in for a controller-rendered pattern. Decorative
  /// and labelled — never a claim about the device's real output.
  void _paintMotif(Canvas canvas, Size size) {
    final accent = tokens.primary.withValues(alpha: 0.5);
    final muted = tokens.onSurfaceVariant.withValues(alpha: 0.22);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (effect.category) {
      case EffectCategory.static:
        paint
          ..color = accent
          ..strokeWidth = 3;
        canvas.drawCircle(
          size.center(Offset.zero),
          size.shortestSide * 0.13,
          paint,
        );
        paint
          ..color = muted
          ..strokeWidth = 2;
        canvas.drawCircle(
          size.center(Offset.zero),
          size.shortestSide * 0.24,
          paint,
        );
      case EffectCategory.motion:
        paint
          ..color = muted
          ..strokeWidth = 2;
        for (var i = -3; i <= 3; i++) {
          final dx = size.width * (0.5 + i * 0.11);
          canvas.drawLine(
            Offset(dx, size.height * 0.18),
            Offset(dx - size.width * 0.06, size.height * 0.82),
            paint,
          );
        }
        paint.color = accent;
        canvas.drawLine(
          Offset(size.width * 0.34, size.height * 0.18),
          Offset(size.width * 0.28, size.height * 0.82),
          paint,
        );
      case EffectCategory.rhythm:
        for (var i = 1; i <= 4; i++) {
          paint
            ..color = i.isEven ? muted : accent.withValues(alpha: 0.32)
            ..strokeWidth = 2;
          canvas.drawCircle(
            size.center(Offset.zero),
            size.shortestSide * 0.06 * i,
            paint,
          );
        }
      case EffectCategory.ambient:
        paint
          ..color = muted
          ..strokeWidth = 2;
        for (var row = 0; row < 3; row++) {
          final path = Path();
          final y = size.height * (0.36 + row * 0.14);
          path.moveTo(0, y);
          for (var x = 0.0; x <= size.width; x += 6) {
            path.lineTo(x, y + (row.isEven ? 8 : 6) * _sin(x / 34 + row));
          }
          canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) =>
      old.effect != effect ||
      old.speed != speed ||
      old.intensity != intensity ||
      old.palette != palette ||
      old.tokens != tokens ||
      old.seed != seed ||
      old.animation != animation;
}

class _ControlsPanel extends StatelessWidget {
  final EffectDefinition effect;
  final int speed;
  final int intensity;
  final String selectedPaletteId;
  final bool speedEnabled;
  final bool tuningEnabled;
  final ValueChanged<int> onSpeedCommit;
  final ValueChanged<int> onIntensityCommit;
  final ValueChanged<EffectPalette> onPaletteSelected;

  const _ControlsPanel({
    required this.effect,
    required this.speed,
    required this.intensity,
    required this.selectedPaletteId,
    required this.speedEnabled,
    required this.tuningEnabled,
    required this.onSpeedCommit,
    required this.onIntensityCommit,
    required this.onPaletteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final showSpeed = effect.speedRange != null;
    final showIntensity = effect.intensityRange != null;
    final showPalette =
        effect.supportsPalette && effect.kind == EffectKind.custom;

    if (!showSpeed && !showIntensity && !showPalette) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          if (showSpeed)
            _ParameterSlider(
              icon: Icons.speed,
              label: 'Speed',
              value: speed,
              range: effect.speedRange!,
              enabled: speedEnabled,
              onCommit: onSpeedCommit,
            ),
          if (showSpeed && (showIntensity || showPalette))
            Divider(height: 1, color: tokens.border),
          if (showIntensity)
            _ParameterSlider(
              icon: Icons.brightness_6_outlined,
              label: 'Intensity',
              value: intensity,
              range: effect.intensityRange!,
              enabled: tuningEnabled,
              onCommit: onIntensityCommit,
            ),
          if (showIntensity && showPalette)
            Divider(height: 1, color: tokens.border),
          if (showPalette)
            _PaletteRack(
              selectedId: selectedPaletteId,
              enabled: tuningEnabled,
              onSelected: onPaletteSelected,
            ),
        ],
      ),
    );
  }
}

class _ParameterSlider extends StatefulWidget {
  final IconData icon;
  final String label;
  final int value;
  final IntRange range;
  final bool enabled;
  final ValueChanged<int> onCommit;

  const _ParameterSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.range,
    required this.enabled,
    required this.onCommit,
  });

  @override
  State<_ParameterSlider> createState() => _ParameterSliderState();
}

class _ParameterSliderState extends State<_ParameterSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final value = (_drag ?? widget.value.toDouble())
        .clamp(widget.range.min.toDouble(), widget.range.max.toDouble())
        .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 17, color: tokens.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              '${value.round()}',
              style: TextStyle(
                color: widget.enabled ? tokens.onSurface : tokens.disabled,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: widget.range.min.toDouble(),
          max: widget.range.max.toDouble(),
          divisions: widget.range.max - widget.range.min,
          onChangeStart: widget.enabled
              ? (v) => setState(() => _drag = v)
              : null,
          onChanged: widget.enabled ? (v) => setState(() => _drag = v) : null,
          onChangeEnd: widget.enabled
              ? (v) {
                  setState(() => _drag = null);
                  widget.onCommit(v.round());
                }
              : null,
        ),
      ],
    );
  }
}

class _PaletteRack extends StatelessWidget {
  final String selectedId;
  final bool enabled;
  final ValueChanged<EffectPalette> onSelected;

  const _PaletteRack({
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                size: 17,
                color: tokens.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Palette',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kEffectPalettes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final palette = kEffectPalettes[index];
                return _PaletteSwatch(
                  palette: palette,
                  selected: palette.id == selectedId,
                  enabled: enabled,
                  onTap: () => onSelected(palette),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  final EffectPalette palette;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final checkColor = tokens.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      label: 'Palette ${palette.name}',
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 64,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? tokens.primary : tokens.border,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    for (final c in palette.colors)
                      Color.fromARGB(255, c.red, c.green, c.blue),
                  ],
                ),
              ),
              child: selected
                  ? Center(
                      child: Icon(Icons.check, size: 16, color: checkColor),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary action for the selected effect, with honest availability text.
class _ActionBar extends StatelessWidget {
  final EffectDefinition effect;
  final LightState state;
  final bool pending;
  final VoidCallback onSend;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  const _ActionBar({
    required this.effect,
    required this.state,
    required this.pending,
    required this.onSend,
    required this.onPlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final connected = state.lightIsConnected;
    final capabilities = state.lightCapabilities;

    final Widget button;
    String? hint;

    if (effect.playback == EffectPlayback.previewOnly) {
      button = const _DisabledButton(
        icon: Icons.remove_red_eye_outlined,
        label: 'Preview only',
      );
      hint =
          'Needs addressable LEDs. StarLight can preview this effect but '
          'cannot drive it on this device.';
    } else if (effect.kind == EffectKind.hardwareNative) {
      final supported = capabilities.contains(DeviceCapability.effect);
      final enabled = connected && supported && !pending;
      button = FilledButton.icon(
        onPressed: enabled ? onSend : null,
        icon: pending ? const _Spinner() : const Icon(Icons.send),
        label: Text(pending ? 'Sending…' : 'Send to device'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
      if (!connected) {
        hint = 'Connect a device to send this pattern.';
      } else if (!supported) {
        hint =
            'This device/profile does not accept controller effect commands.';
      }
    } else {
      final supported = capabilities.contains(DeviceCapability.color);
      final playing =
          state.lightCustomEffectId == effect.id && state.lightCustomPlaying;
      if (playing) {
        button = OutlinedButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      } else {
        final enabled = connected && supported && !pending;
        button = FilledButton.icon(
          onPressed: enabled ? onPlay : null,
          icon: pending ? const _Spinner() : const Icon(Icons.play_arrow),
          label: Text(pending ? 'Starting…' : 'Play on device'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
        if (!connected) {
          hint = 'Connect a device to play this effect.';
        } else if (!supported) {
          hint = 'This device cannot stream colours, so custom effects cannot play.';
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: button,
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: tokens.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hint,
                  style: TextStyle(
                    color: tokens.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DisabledButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DisabledButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FilledButton.icon(
      onPressed: null,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        disabledBackgroundColor: tokens.surfaceHigh,
        disabledForegroundColor: tokens.onSurfaceVariant,
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.tokens.onPrimary,
      ),
    );
  }
}

/// Source (device/custom) segmented control + category chips.
class _FilterBar extends StatelessWidget {
  final EffectKind? kind;
  final EffectCategory? category;
  final ValueChanged<EffectKind?> onKind;
  final ValueChanged<EffectCategory?> onCategory;

  const _FilterBar({
    required this.kind,
    required this.category,
    required this.onKind,
    required this.onCategory,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                _Segment(
                  label: 'All',
                  selected: kind == null,
                  onTap: () => onKind(null),
                ),
                _Segment(
                  label: 'Device',
                  selected: kind == EffectKind.hardwareNative,
                  onTap: () => onKind(EffectKind.hardwareNative),
                ),
                _Segment(
                  label: 'Custom',
                  selected: kind == EffectKind.custom,
                  onTap: () => onKind(EffectKind.custom),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryChip(
                label: 'All',
                selected: category == null,
                onTap: () => onCategory(null),
              ),
              for (final c in EffectCategory.values)
                _CategoryChip(
                  label: c.label,
                  selected: category == c,
                  onTap: () => onCategory(c),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? tokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? tokens.onPrimary : tokens.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? tokens.primary : tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? tokens.primary : tokens.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? tokens.onPrimary : tokens.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One selectable effect tile with a cheap static mini preview.
class _EffectTile extends StatelessWidget {
  final EffectDefinition effect;
  final bool selected;
  final bool active;
  final bool pending;
  final int speed;
  final int intensity;
  final EffectPalette palette;
  final VoidCallback onTap;

  const _EffectTile({
    required this.effect,
    required this.selected,
    required this.active,
    required this.pending,
    required this.speed,
    required this.intensity,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Effect ${effect.name}',
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tokens.primary : tokens.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: CustomPaint(
                      painter: _TilePainter(
                        effect: effect,
                        speed: speed,
                        intensity: intensity,
                        palette: palette,
                        tokens: tokens,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              effect.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              effect.kind == EffectKind.custom
                                  ? 'Custom'
                                  : effect.category.label,
                              style: TextStyle(
                                color: tokens.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (pending)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: tokens.primary,
                          ),
                        )
                      else if (active)
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: tokens.success,
                        )
                      else if (selected)
                        Icon(Icons.circle, size: 10, color: tokens.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  final EffectDefinition effect;
  final int speed;
  final int intensity;
  final EffectPalette palette;
  final AppTokens tokens;

  _TilePainter({
    required this.effect,
    required this.speed,
    required this.intensity,
    required this.palette,
    required this.tokens,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tokens.background);
    if (effect.kind != EffectKind.custom) {
      _paintMotif(canvas, size);
      return;
    }
    final sample = renderCustomEffect(
      effect.id,
      CustomEffectInput(
        time: 3.5,
        pixels: (size.width / 6).floor().clamp(10, 40),
        speed: speed / 100,
        intensity: intensity / 100,
        palette: palette,
        seed: _stableSeed(effect.id),
      ),
    );
    if (sample == null) return;

    if (effect.playback == EffectPlayback.colorSequence) {
      // Global-RGB: show single color disc matching what device sees
      final center = size.center(Offset.zero);
      final radius = size.shortestSide * 0.3;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Color.fromARGB(
            255,
            sample.global.red,
            sample.global.green,
            sample.global.blue,
          ),
      );
    } else {
      // Addressable-only: show spatial mini strip
      final n = sample.pixels.length;
      if (n == 0) return;
      final slot = size.width / n;
      final gap = slot * 0.2;
      final barWidth = slot - gap;
      final radius = Radius.circular(barWidth * 0.4);
      for (var i = 0; i < n; i++) {
        final c = sample.pixels[i];
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              i * slot + gap / 2,
              size.height * 0.16,
              barWidth,
              size.height * 0.68,
            ),
            radius,
          ),
          Paint()..color = Color.fromARGB(255, c.red, c.green, c.blue),
        );
      }
    }
  }

  void _paintMotif(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = tokens.onSurfaceVariant.withValues(alpha: 0.28)
      ..strokeWidth = 2;
    switch (effect.category) {
      case EffectCategory.static:
        paint.color = tokens.primary.withValues(alpha: 0.6);
        canvas.drawCircle(
          size.center(Offset.zero),
          size.shortestSide * 0.18,
          paint,
        );
      case EffectCategory.motion:
        for (var i = -2; i <= 2; i++) {
          final dx = size.width / 2 + i * size.width * 0.16;
          canvas.drawLine(
            Offset(dx, size.height * 0.2),
            Offset(dx - size.width * 0.1, size.height * 0.8),
            paint,
          );
        }
      case EffectCategory.rhythm:
        for (var i = 1; i <= 3; i++) {
          canvas.drawCircle(
            size.center(Offset.zero),
            size.shortestSide * 0.1 * i,
            paint,
          );
        }
      case EffectCategory.ambient:
        final path = Path();
        path.moveTo(0, size.height * 0.5);
        for (var x = 0.0; x <= size.width; x += 6) {
          path.lineTo(x, size.height * 0.5 + 6 * _sin(x / 20));
        }
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TilePainter old) =>
      old.effect != effect ||
      old.speed != speed ||
      old.intensity != intensity ||
      old.palette != palette ||
      old.tokens != tokens;
}

Color _categoryColor(EffectCategory category, AppTokens tokens) {
  // Decorative only: helps browsing, never communicates device state.
  return switch (category) {
    EffectCategory.static => tokens.onSurface,
    EffectCategory.motion => tokens.primary,
    EffectCategory.rhythm => tokens.warning,
    EffectCategory.ambient => tokens.success,
  };
}

/// Deterministic, platform-independent seed for a renderer.
int _stableSeed(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

double _sin(double v) {
  // Small local sine (Taylor around the wrapped angle) so painters do not need
  // to import dart:math for one call.
  final x = v % 6.283185307179586;
  final x2 = x * x;
  return x * (1 - x2 / 6 + x2 * x2 / 120);
}
