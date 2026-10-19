// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/bloc/profile/profile_state.dart';
import 'package:starlight/presentation/pages/settings/profiles_settings_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/light_controls.dart';

/// Full device details / controller screen (route `/controller`).
///
/// Shows the real connection status and identity of the paired device, the
/// controls it actually supports, and the actions to reconnect, rename or
/// forget it. While disconnected it shows the last-known state instead of
/// fabricating a live connection; when no state is known yet it says so.
class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key});

  static BleDevice? _deviceOf(BleState state) => switch (state) {
    BleConnected(:final device) => device,
    BleDisconnected(:final device) => device,
    BleConnecting() => BleDevice(
      id: state.deviceId,
      name: state.deviceName,
      rssi: 0,
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      builder: (context, state) {
        final device = _deviceOf(state);
        final connected = state is BleConnected;
        final connecting = state is BleConnecting;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              device?.name ?? 'Device',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (device != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename device',
                  onPressed: () => _rename(context, device),
                ),
            ],
          ),
          body: device == null
              ? const _NoDevice()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    _StatusCard(
                      device: device,
                      connected: connected,
                      connecting: connecting,
                    ),
                    const SizedBox(height: 20),
                    _ControlsSection(connected: connected),
                    const SizedBox(height: 20),
                    _EffectsSection(),
                    const SizedBox(height: 20),
                    const _SupportedControlsCard(),
                    const SizedBox(height: 16),
                    _DetailsCard(device: device),
                    const SizedBox(height: 16),
                    _ProfileSection(deviceId: device.id),
                    const SizedBox(height: 24),
                    _Actions(connected: connected),
                  ],
                ),
        );
      },
    );
  }

  static Future<void> _rename(BuildContext context, BleDevice device) async {
    final bloc = context.read<BleBloc>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: device.name),
    );
    if (name == null || name.trim().isEmpty) return;
    bloc.add(RenameDevice(name.trim()));
  }
}

class _NoDevice extends StatelessWidget {
  const _NoDevice();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 48, color: tokens.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'No device selected',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Add or connect a device to see its details here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final BleDevice device;
  final bool connected;
  final bool connecting;

  const _StatusCard({
    required this.device,
    required this.connected,
    required this.connecting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final (label, color) = connecting
        ? ('Connecting…', tokens.primary)
        : connected
        ? ('Connected', tokens.success)
        : ('Disconnected', tokens.onSurfaceVariant);

    return _Section(
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  connected
                      ? 'Bluetooth Low Energy'
                      : 'Not connected — showing last known details',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (connected) _RssiBadge(rssi: device.rssi),
        ],
      ),
    );
  }
}

class _RssiBadge extends StatelessWidget {
  final int rssi;

  const _RssiBadge({required this.rssi});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (icons, label) = rssi >= -60
        ? (Icons.signal_cellular_alt, 'Strong')
        : rssi >= -75
        ? (Icons.signal_cellular_alt_2_bar, 'Fair')
        : (Icons.signal_cellular_alt_1_bar, 'Weak');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icons, size: 16, color: tokens.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: tokens.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ControlsSection extends StatelessWidget {
  final bool connected;

  const _ControlsSection({required this.connected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return BlocBuilder<LightBloc, LightState>(
      builder: (context, state) {
        final hasState = state is! LightInitial;
        if (!connected && !hasState) {
          return _Section(
            child: Row(
              children: [
                Icon(Icons.link_off, color: tokens.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Connect to this device to view and control it.',
                    style: TextStyle(color: tokens.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Controls',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!connected)
                  Text(
                    'Last known',
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              child: LightControls(enabled: connected, showColorWheel: true),
            ),
          ],
        );
      },
    );
  }
}

/// Entry point to the Effects Studio.
///
/// The section is always actionable (the studio itself is usable while
/// disconnected and gates what can actually be sent). The subtitle and chip
/// reflect the confirmed active effect — including a streaming custom effect —
/// and explain the real reason when the device/profile supports nothing.
class _EffectsSection extends StatelessWidget {
  const _EffectsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return BlocBuilder<LightBloc, LightState>(
      builder: (context, state) {
        final capabilities = state.lightCapabilities;
        final supportsEffect = capabilities.contains(DeviceCapability.effect);
        final supportsColor = capabilities.contains(DeviceCapability.color);
        final supportsAnything = supportsEffect || supportsColor;
        final activeId = state.lightActiveEffectId;
        final activeEffect = effectById(activeId);
        final playingCustom =
            state.lightCustomPlaying && state.lightCustomEffectId != null;
        final subtitle = !supportsAnything
            ? (capabilities.isEmpty
                  ? 'Verify the assigned profile to enable effects'
                  : 'Not supported by this device')
            : activeEffect == null
            ? 'Browse device patterns and custom effects'
            : playingCustom
            ? 'Playing: ${activeEffect.name}'
            : 'Active: ${activeEffect.name}';

        return _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Effects',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (activeEffect != null && supportsAnything)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        activeEffect.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tokens.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // Always reachable: the studio can be previewed while
                  // disconnected and gates only the commands it cannot send.
                  onPressed: () => Navigator.of(context).pushNamed('/effects'),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Open Effects Studio'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SupportedControlsCard extends StatelessWidget {
  const _SupportedControlsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return BlocBuilder<LightBloc, LightState>(
      builder: (context, state) {
        final capabilities = state.lightCapabilities.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supported controls',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (capabilities.isEmpty)
                Text(
                  'None available — the assigned profile must be verified for '
                  'this device before controls appear.',
                  style: TextStyle(
                    color: tokens.onSurfaceVariant,
                    fontSize: 13,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final capability in capabilities)
                      Chip(
                        label: Text(capability.label),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final BleDevice device;

  const _DetailsCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DetailRow(label: 'Protocol', value: 'BLE (GATT)'),
          const SizedBox(height: 10),
          _DetailRow(label: 'Device ID', value: device.id),
        ],
      ),
    );
  }
}

/// Assigns a saved profile to this device and shows whether the device
/// actually matches it.
///
/// A profile is only used to drive controls once it has been verified against
/// the live GATT table; until then the controls fall back to the built-in
/// behaviour. Nothing here is fabricated — the verification line reflects a
/// real observation (or the absence of a connected device).
class _ProfileSection extends StatelessWidget {
  final String deviceId;

  const _ProfileSection({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final cubit = context.read<ProfileCubit>();

    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final assigned = state.assignedProfile(deviceId);
        final selectedId = assigned?.id ?? kMrStarProfileId;
        final optionIds = <String>{
          kMrStarProfileId,
          for (final profile in state.customProfiles) profile.id,
        };
        final value = optionIds.contains(selectedId)
            ? selectedId
            : kMrStarProfileId;

        return _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device profile',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How StarLight talks to this device.',
                style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: value,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Profile',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: kMrStarProfileId,
                    child: Text('Built-in (MR Star)'),
                  ),
                  for (final profile in state.customProfiles)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(profile.name),
                    ),
                ],
                onChanged: (newValue) {
                  if (newValue != null) cubit.assignProfile(deviceId, newValue);
                },
              ),
              if (assigned != null) ...[
                const SizedBox(height: 10),
                _VerificationSummary(
                  verification: state.verificationFor(assigned.id),
                ),
                const SizedBox(height: 4),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => cubit.verifyProfile(assigned.id),
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('Verify on this device'),
                    ),
                    TextButton(
                      onPressed: () => ProfilesSettingsPage.openEditor(context),
                      child: const Text('New profile'),
                    ),
                  ],
                ),
                Text(
                  'Profiles are only used once the device matches them. Until '
                  'then StarLight uses its built-in behaviour.',
                  style: TextStyle(
                    color: tokens.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VerificationSummary extends StatelessWidget {
  final ProfileVerification verification;

  const _VerificationSummary({required this.verification});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (IconData icon, Color color) = switch (verification.status) {
      ProfileVerificationStatus.verified => (
        Icons.check_circle,
        tokens.success,
      ),
      ProfileVerificationStatus.failed => (Icons.error_outline, tokens.error),
      ProfileVerificationStatus.notConnected => (
        Icons.bluetooth_disabled,
        tokens.onSurfaceVariant,
      ),
      ProfileVerificationStatus.unverified => (
        Icons.help_outline,
        tokens.onSurfaceVariant,
      ),
    };
    final message = verification.message;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            (message != null && message.isNotEmpty)
                ? '${verification.label} — $message'
                : verification.label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final bool connected;

  const _Actions({required this.connected});

  @override
  Widget build(BuildContext context) {
    final bleBloc = context.read<BleBloc>();
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: connected
              ? OutlinedButton.icon(
                  onPressed: () => bleBloc.add(const DisconnectRequested()),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                )
              : FilledButton.icon(
                  onPressed: () => bleBloc.add(const ReconnectRequested()),
                  icon: const Icon(Icons.link),
                  label: const Text('Reconnect'),
                ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => _confirmForget(context, bleBloc),
            style: TextButton.styleFrom(foregroundColor: context.tokens.error),
            child: const Text('Forget device'),
          ),
        ),
      ],
    );
  }

  static Future<void> _confirmForget(
    BuildContext context,
    BleBloc bleBloc,
  ) async {
    final navigator = Navigator.of(context);
    final tokens = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget device?'),
        content: const Text(
          'This removes the saved pairing. You can add the device again by '
          'scanning for it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: tokens.error),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    bleBloc.add(const ForgetDevice());
    navigator.pop();
  }
}

class _Section extends StatelessWidget {
  final Widget child;

  const _Section({required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: child,
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String initialName;

  const _RenameDialog({required this.initialName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename device'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 40,
        decoration: const InputDecoration(hintText: 'Device name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
