// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/bloc/profile/profile_state.dart';
import 'package:starlight/presentation/pages/settings/profile_editor_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Lists the built-in and custom device profiles.
///
/// The built-in MR Star profile is shown for context but cannot be edited or
/// deleted. Custom profiles can be searched, verified, edited, duplicated and
/// deleted.
class ProfilesSettingsPage extends StatefulWidget {
  const ProfilesSettingsPage({super.key});

  /// Opens the profile editor, optionally for an existing [profile].
  static Future<void> openEditor(
    BuildContext context, {
    DeviceProfile? profile,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ProfileEditorPage(profile: profile)),
    );
  }

  @override
  State<ProfilesSettingsPage> createState() => _ProfilesSettingsPageState();
}

class _ProfilesSettingsPageState extends State<ProfilesSettingsPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(title: const Text('Device profiles'), elevation: 0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ProfilesSettingsPage.openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New profile'),
      ),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final query = _query.trim().toLowerCase();
          final profiles = query.isEmpty
              ? state.profiles
              : state.profiles
                    .where(
                      (p) =>
                          p.name.toLowerCase().contains(query) ||
                          p.serviceUuid.toLowerCase().contains(query),
                    )
                    .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            children: [
              Text(
                'A profile describes how to talk to one BLE controller: which '
                'GATT service and characteristics to use, and how each command '
                'is encoded. Assign a profile to a device from its detail page.',
                style: TextStyle(
                  color: tokens.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Search profiles',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),
              for (final profile in profiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProfileCard(profile: profile, state: state),
                ),
              if (profiles.isEmpty && query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No profiles match “$_query”.',
                      style: TextStyle(color: tokens.onSurfaceVariant),
                    ),
                  ),
                ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: TextStyle(color: tokens.error, fontSize: 13),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final DeviceProfile profile;
  final ProfileState state;

  const _ProfileCard({required this.profile, required this.state});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cubit = context.read<ProfileCubit>();
    final verification = state.verificationFor(profile.id);

    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Text(
                  profile.name,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              _Badge(
                label: profile.isBuiltIn ? 'Built-in' : 'Custom',
                color: profile.isBuiltIn
                    ? tokens.onSurfaceVariant
                    : tokens.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            profile.isBuiltIn
                ? 'Always available — the app speaks this protocol natively.'
                : profile.capabilities.map((c) => c.label).join(' · '),
            style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 13),
          ),
          if (!profile.isBuiltIn) ...[
            const SizedBox(height: 10),
            _KeyValue(label: 'Service', value: profile.serviceUuid),
            _KeyValue(label: 'Write', value: profile.writeCharacteristicUuid),
            if (profile.notifyCharacteristicUuid != null)
              _KeyValue(
                label: 'Notify',
                value: profile.notifyCharacteristicUuid!,
              ),
            const SizedBox(height: 8),
            _VerificationLine(verification: verification),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => cubit.verifyProfile(profile.id),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Verify'),
                ),
                TextButton.icon(
                  onPressed: () => ProfilesSettingsPage.openEditor(
                    context,
                    profile: profile,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                IconButton(
                  tooltip: 'Duplicate',
                  onPressed: () => cubit.duplicateProfile(profile.id),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, cubit),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: tokens.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ProfileCubit cubit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text(
          '“${profile.name}” will be removed and detached from any device '
          'using it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cubit.deleteProfile(profile.id);
    }
  }
}

class _VerificationLine extends StatelessWidget {
  final ProfileVerification verification;

  const _VerificationLine({required this.verification});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final message = verification.message;
    final text = (message != null && message.isNotEmpty)
        ? '${verification.label} — $message'
        : verification.label;
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
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 12)),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
