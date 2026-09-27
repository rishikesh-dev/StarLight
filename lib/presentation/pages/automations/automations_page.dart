import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/automation.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Automations screen: simple list of configured automations.
///
/// The full scheduler is out of scope for this milestone. This screen only
/// renders the existing [Automation] models and prepares the architecture
/// for future triggers (time, sunset, device state, timer).
class AutomationsPage extends StatelessWidget {
  const AutomationsPage({super.key});

  static const List<Automation> _defaultAutomations = [
    Automation(
      id: 'sunset-lighting',
      name: 'Sunset Lighting',
      enabled: true,
      trigger: AutomationTrigger(
        type: AutomationTriggerType.sunset,
        config: const {},
      ),
      actions: const [],
      createdAt: DateTime.now(),
    ),
    Automation(
      id: 'sleep',
      name: 'Sleep',
      enabled: true,
      trigger: AutomationTrigger(
        type: AutomationTriggerType.time,
        config: const {'time': '22:30'},
      ),
      actions: const [],
      createdAt: DateTime.now(),
    ),
    Automation(
      id: 'morning',
      name: 'Morning',
      enabled: true,
      trigger: AutomationTrigger(
        type: AutomationTriggerType.time,
        config: const {'time': '07:00'},
      ),
      actions: const [],
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).pushNamed('/automation-create'),
            tooltip: 'Create automation',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _defaultAutomations.length,
        itemBuilder: (context, index) {
          final automation = _defaultAutomations[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                leading: Icon(
                  automation.enabled ? Icons.schedule : Icons.schedule_outlined,
                  color: automation.enabled ? AppColors.primary : AppColors.onSurfaceVariant,
                ),
                title: Text(automation.name),
                subtitle: Text(_triggerLabel(automation.trigger)),
                trailing: Switch(
                  value: automation.enabled,
                  onChanged: (_) {},
                  activeColor: AppColors.primary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _triggerLabel(AutomationTrigger trigger) {
    return switch (trigger.type) {
      AutomationTriggerType.time => 'At specific time',
      AutomationTriggerType.sunrise => 'At sunrise',
      AutomationTriggerType.sunset => 'At sunset',
      AutomationTriggerType.deviceState => 'When device state changes',
      AutomationTriggerType.manual => 'Manual trigger',
    };
  }
}