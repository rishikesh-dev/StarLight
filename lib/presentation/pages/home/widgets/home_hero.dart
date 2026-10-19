// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/theme/rgb_color_x.dart';

/// The main lighting panel at the top of Home.
///
/// A compact, premium panel over the charcoal surface: the real device name,
/// the honest connection/power state, and the capability-gated controls. Power
/// and brightness are only rendered when the connected device actually
/// supports them, and the power state is only *stated* once the device
/// confirmed it (state notification or completed command) — before that the
/// panel says "Connected" without pretending the light is on or off. The
/// atmospheric wash uses the *confirmed* device colour and only breathes while
/// the light is really on; there is no decorative gradient pretending to be
/// device state.
class HomeHero extends StatelessWidget {
  /// Fallback action used when no device is paired yet.
  final VoidCallback onAddDevice;

  const HomeHero({super.key, required this.onAddDevice});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      builder: (context, bleState) {
        return BlocBuilder<LightBloc, LightState>(
          builder: (context, lightState) {
            final confirmed = context.read<LightBloc>().hasConfirmedState;
            final content = _resolve(context, bleState, lightState, confirmed);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _HeroCard(content: content),
            );
          },
        );
      },
    );
  }

  _HeroContent _resolve(
    BuildContext context,
    BleState ble,
    LightState light,
    bool confirmed,
  ) {
    final tokens = context.tokens;
    switch (ble) {
      case BleConnected(:final device):
        final capabilities = light.lightCapabilities;
        final showPower = capabilities.contains(DeviceCapability.power);
        final showBrightness = capabilities.contains(
          DeviceCapability.brightness,
        );
        final on = confirmed && light.isLightOn;
        return _HeroContent(
          overline: 'Main Light',
          title: device.name,
          // Only state ON/OFF once the device has confirmed it; otherwise
          // describe what is actually known: the connection.
          subtitle: confirmed ? (on ? 'On' : 'Off') : 'Connected',
          color: on ? light.lightColor.toColor() : tokens.onSurfaceVariant,
          lit: on,
          connected: true,
          showPower: showPower,
          showBrightness: showBrightness,
          brightnessPercent: light.brightnessPercent,
          powerOn: on,
          // Connected but nothing controllable: offer the detail screen
          // instead of pretending there are controls.
          actionLabel: (showPower || showBrightness) ? null : 'View controls',
          actionIcon: Icons.tune,
          action: (showPower || showBrightness)
              ? null
              : () => Navigator.of(context).pushNamed('/controller'),
        );
      case BleConnecting(:final deviceName):
        return _HeroContent(
          overline: 'Main Light',
          title: 'Connecting…',
          subtitle: deviceName,
          color: tokens.warning,
          actionIcon: Icons.bluetooth_searching,
        );
      case BleDisconnected(:final device) when device != null:
        return _HeroContent(
          overline: 'Main Light',
          title: device.name,
          subtitle: 'Not connected',
          color: tokens.onSurfaceVariant,
          actionLabel: 'Reconnect',
          actionIcon: Icons.link,
          action: () => context.read<BleBloc>().add(const ReconnectRequested()),
        );
      case BleBluetoothOff():
        return _HeroContent(
          overline: 'Bluetooth',
          title: 'Bluetooth is off',
          subtitle: 'Turn it on to find and control your lights.',
          color: tokens.warning,
          actionLabel: 'Turn on Bluetooth',
          actionIcon: Icons.bluetooth,
          action: () => context.read<BleBloc>().add(const RetryBluetooth()),
        );
      case BlePermissionDenied(:final permanentlyDenied):
        return _HeroContent(
          overline: 'Bluetooth',
          title: 'Permission needed',
          subtitle: 'StarLight needs Bluetooth access to reach your devices.',
          color: tokens.warning,
          actionLabel: permanentlyDenied ? 'Open settings' : 'Grant permission',
          actionIcon: Icons.lock_outline,
          action: () => context.read<BleBloc>().add(
            permanentlyDenied
                ? const OpenAppSettingsRequested()
                : const RetryBluetooth(),
          ),
        );
      case BleBluetoothUnavailable():
        return _HeroContent(
          overline: 'Bluetooth',
          title: 'Bluetooth unavailable',
          subtitle: 'This device cannot use Bluetooth right now.',
          color: tokens.warning,
          actionLabel: 'Try again',
          actionIcon: Icons.refresh,
          action: () =>
              context.read<BleBloc>().add(const EnsureBluetoothReady()),
        );
      case BleError():
        return _HeroContent(
          overline: 'Bluetooth',
          title: 'Bluetooth error',
          subtitle: 'Something went wrong while preparing Bluetooth.',
          color: tokens.error,
          actionLabel: 'Try again',
          actionIcon: Icons.refresh,
          action: () =>
              context.read<BleBloc>().add(const EnsureBluetoothReady()),
        );
      case BleScanning():
        return _HeroContent(
          overline: 'Looking for devices',
          title: 'Scanning…',
          subtitle: 'Searching for nearby StarLight controllers.',
          color: tokens.primary,
          actionIcon: Icons.bluetooth_searching,
        );
      case BleBluetoothEnabling():
      case BleCheckingPermissions():
        return _HeroContent(
          overline: 'Getting ready',
          title: 'Preparing Bluetooth…',
          subtitle: 'Checking the adapter and permissions.',
          color: tokens.primary,
          actionIcon: Icons.bluetooth,
        );
      default:
        return _HeroContent(
          overline: 'Main Light',
          title: 'No lights yet',
          subtitle: 'Add your first StarLight device to get started.',
          color: tokens.primary,
          actionLabel: 'Add Device',
          actionIcon: Icons.add,
          action: onAddDevice,
        );
    }
  }
}

/// Resolved, display-ready content for the hero.
class _HeroContent {
  final String overline;
  final String title;
  final String subtitle;

  /// Colour of the *confirmed* device state (used for the wash and dot).
  final Color color;

  /// Whether the confirmed device colour should breathe in the background.
  final bool lit;

  /// Connected to a controllable device (renders the control row).
  final bool connected;
  final bool showPower;
  final bool showBrightness;
  final int brightnessPercent;
  final bool powerOn;

  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? action;

  const _HeroContent({
    required this.overline,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.actionIcon,
    this.lit = false,
    this.connected = false,
    this.showPower = false,
    this.showBrightness = false,
    this.brightnessPercent = 0,
    this.powerOn = false,
    this.actionLabel,
    this.action,
  });
}

class _HeroCard extends StatelessWidget {
  final _HeroContent content;

  const _HeroCard({required this.content});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final showAmbience = content.connected && content.lit;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.surfaceHigh, tokens.surface],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // The wash communicates the confirmed colour only while the
            // light is really on; otherwise the panel stays plain charcoal.
            if (showAmbience)
              Positioned(
                right: -70,
                top: -90,
                child: IgnorePointer(child: _Wash(color: content.color)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceHigh.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          content.overline.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: tokens.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _StatusDot(color: content.color, lit: content.lit),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    content.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  if (content.connected &&
                      (content.showPower || content.showBrightness)) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (content.showPower) ...[
                          _PowerButton(
                            on: content.powerOn,
                            onTap: () => context.read<LightBloc>().add(
                              TogglePower(!content.powerOn),
                            ),
                          ),
                          if (content.showBrightness) const SizedBox(width: 14),
                        ],
                        if (content.showBrightness)
                          Expanded(
                            child: _HeroBrightness(
                              percent: content.brightnessPercent,
                              onCommit: (v) => context.read<LightBloc>().add(
                                ChangeBrightness(v * 10),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ] else if (content.actionLabel != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _HeroAction(content: content, tokens: tokens),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact action button used by the hero's non-control states.
class _HeroAction extends StatelessWidget {
  final _HeroContent content;
  final AppTokens tokens;

  const _HeroAction({required this.content, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );
    return FilledButton.icon(
      onPressed: content.action,
      icon: Icon(content.actionIcon, size: 18),
      label: Text(content.actionLabel!),
      style: content.lit
          ? style
          : style.copyWith(
              backgroundColor: WidgetStatePropertyAll(tokens.surfaceHigh),
              foregroundColor: WidgetStatePropertyAll(tokens.onSurface),
            ),
    );
  }
}

/// Power toggle for the connected device (capability-gated).
class _PowerButton extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _PowerButton({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = on ? tokens.success : tokens.onSurfaceVariant;
    return Semantics(
      label: on ? 'Turn off' : 'Turn on',
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on
                ? tokens.success.withValues(alpha: 0.14)
                : tokens.surfaceHigh,
            border: Border.all(
              color: on ? tokens.success : tokens.border,
              width: 1.5,
            ),
          ),
          child: Icon(Icons.power_settings_new, color: color, size: 24),
        ),
      ),
    );
  }
}

/// Brightness slider that previews during the drag and commits on release, so
/// the UI never shows a value the device has not been asked for.
class _HeroBrightness extends StatefulWidget {
  final int percent;
  final ValueChanged<int> onCommit;

  const _HeroBrightness({required this.percent, required this.onCommit});

  @override
  State<_HeroBrightness> createState() => _HeroBrightnessState();
}

class _HeroBrightnessState extends State<_HeroBrightness> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final value = (_drag ?? widget.percent.toDouble()).clamp(0, 100).toDouble();

    return Row(
      children: [
        Icon(
          widget.percent == 0 ? Icons.brightness_low : Icons.brightness_6,
          size: 20,
          color: tokens.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: tokens.primary,
              inactiveTrackColor: tokens.border,
              thumbColor: tokens.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                setState(() => _drag = null);
                widget.onCommit(v.round().clamp(0, 100));
              },
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 36,
          child: Text(
            '${value.round()}%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small status light; glows while the light is actually on.
class _StatusDot extends StatelessWidget {
  final Color color;
  final bool lit;

  const _StatusDot({required this.color, required this.lit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: lit
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Soft radial light source matching the light's confirmed colour.
class _Wash extends StatelessWidget {
  final Color color;

  const _Wash({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
