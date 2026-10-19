// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/theme/rgb_color_x.dart';
import 'package:starlight/presentation/widgets/color_picker_dialog.dart';
import 'package:starlight/presentation/widgets/color_wheel.dart';
import 'package:starlight/presentation/widgets/power_button.dart';
import 'package:starlight/presentation/widgets/quick_color_picker.dart';

/// Capabilities the built-in MR Star controller exposes over its GATT service
/// (FFF0 / write FFF3 / notify FFF4).
///
/// This is only the default: the live set is derived from the assigned,
/// verified device profile and carried on the [LightState]. An empty set (a
/// profile assigned but not verified) means no control is offered.
const Set<DeviceCapability> kMrStarCapabilities = kDefaultLightCapabilities;

/// Reusable, capability-gated light controls (power, brightness, colour).
///
/// Every control routes through the single [LightBloc]; state is only updated
/// after the corresponding command succeeds, so nothing is shown as applied
/// until it actually was. The widget keeps the last known-good values across a
/// [LightError] (which carries no payload) rather than resetting the controls
/// to defaults — a failed command must never look like a successful change.
///
/// [enabled] reflects the live transport connection. When false the controls
/// are rendered but disabled (e.g. showing last-known state while offline).
///
/// [headerBuilder] optionally renders a header (device name / status) that
/// needs the derived on/off value, so callers do not have to duplicate the
/// last-known-value logic.
class LightControls extends StatefulWidget {
  final bool enabled;

  /// Renders the HSV [ColorWheel] above the quick swatches for continuous
  /// colour selection. Defaults to false so existing callers (and their
  /// tests) keep the original compact layout.
  final bool showColorWheel;

  final Widget Function(BuildContext context, bool isOn)? headerBuilder;

  const LightControls({
    super.key,
    this.enabled = true,
    this.showColorWheel = false,
    this.headerBuilder,
  });

  @override
  State<LightControls> createState() => _LightControlsState();
}

class _LightControlsState extends State<LightControls> {
  bool _isOn = false;
  int _brightness = 0;
  RGBColor _color = const RGBColor(255, 255, 255);

  @override
  void initState() {
    super.initState();
    _absorb(context.read<LightBloc>().state);
  }

  void _absorb(LightState state) {
    if (state is LightError) return;
    _isOn = state.isLightOn;
    _brightness = state.lightBrightness;
    _color = state.lightColor;
  }

  Future<void> _pickColour(RGBColor current) async {
    final picked = await ColorPickerDialog.show(context, current);
    if (picked == null || !mounted) return;
    context.read<LightBloc>().add(ChangeColor(picked));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LightBloc, LightState>(
      listener: (context, state) {
        if (state is LightError) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('Command failed: ${state.message}')),
            );
        }
      },
      builder: (context, state) {
        _absorb(state);
        final enabled = widget.enabled;
        final capabilities = state.lightCapabilities;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.headerBuilder != null) ...[
              widget.headerBuilder!(context, _isOn),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (capabilities.contains(DeviceCapability.power)) ...[
                  PowerButton(
                    isOn: _isOn,
                    isConnected: enabled,
                    onTap: enabled
                        ? () =>
                              context.read<LightBloc>().add(TogglePower(!_isOn))
                        : null,
                  ),
                  const SizedBox(width: 16),
                ],
                if (capabilities.contains(DeviceCapability.brightness))
                  Expanded(
                    child: _BrightnessControl(
                      percent: (_brightness / 10).round().clamp(0, 100),
                      enabled: enabled,
                      onChangeEnd: (value) => context.read<LightBloc>().add(
                        ChangeBrightness((value * 10).round()),
                      ),
                    ),
                  ),
              ],
            ),
            if (capabilities.contains(DeviceCapability.color)) ...[
              const SizedBox(height: 16),
              _ColourHeader(
                color: _color,
                enabled: enabled,
                onCustom: () => _pickColour(_color),
              ),
              const SizedBox(height: 10),
              if (widget.showColorWheel) ...[
                Center(
                  child: Builder(
                    builder: (context) {
                      final hsv = _color.toHsvColor();
                      return ColorWheel(
                        initialHue: hsv.hue,
                        initialSaturation: hsv.saturation,
                        onChanged: enabled
                            ? (result) => context.read<LightBloc>().add(
                                ChangeColor(
                                  RGBColorX.fromHsv(
                                    result.hue,
                                    result.saturation,
                                    1,
                                  ),
                                ),
                              )
                            : (_) {},
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
              QuickColorPicker(
                currentColor: _color,
                isConnected: enabled,
                onColorSelected: (c) =>
                    context.read<LightBloc>().add(ChangeColor(c)),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ColourHeader extends StatelessWidget {
  final RGBColor color;
  final bool enabled;
  final VoidCallback onCustom;

  const _ColourHeader({
    required this.color,
    required this.enabled,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.toColor(),
            shape: BoxShape.circle,
            border: Border.all(color: tokens.border),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Colour',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.colorize),
          onPressed: enabled ? onCustom : null,
          tooltip: 'Custom colour',
        ),
      ],
    );
  }
}

/// Stateful slider that previews the dragged value locally and only issues a
/// single command on release (avoids flooding the BLE command queue).
class _BrightnessControl extends StatefulWidget {
  final int percent;
  final bool enabled;
  final ValueChanged<int> onChangeEnd;

  const _BrightnessControl({
    required this.percent,
    required this.enabled,
    required this.onChangeEnd,
  });

  @override
  State<_BrightnessControl> createState() => _BrightnessControlState();
}

class _BrightnessControlState extends State<_BrightnessControl> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (_drag ?? widget.percent.toDouble()).clamp(0, 100).toDouble();
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Brightness',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${value.round()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 100,
          divisions: 100,
          label: '${value.round()}%',
          onChangeStart: enabled ? (v) => setState(() => _drag = v) : null,
          onChanged: enabled ? (v) => setState(() => _drag = v) : null,
          onChangeEnd: enabled
              ? (v) {
                  setState(() => _drag = null);
                  widget.onChangeEnd(v.round());
                }
              : null,
        ),
      ],
    );
  }
}
