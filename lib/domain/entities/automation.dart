import 'package:equatable/equatable.dart';
import 'scene.dart';

/// Trigger type for an automation.
enum AutomationTriggerType {
  time('time', 'At specific time'),
  sunrise('sunrise', 'At sunrise'),
  sunset('sunset', 'At sunset'),
  deviceState('deviceState', 'When device state changes'),
  manual('manual', 'Manual trigger');

  const AutomationTriggerType(this.id, this.label);
  final String id;
  final String label;
}

/// Action type for an automation.
enum AutomationActionType {
  deviceControl('deviceControl', 'Control device'),
  activateScene('activateScene', 'Activate scene'),
  delay('delay', 'Wait');

  const AutomationActionType(this.id, this.label);
  final String id;
  final String label;
}

/// Trigger for an automation.
class AutomationTrigger extends Equatable {
  final AutomationTriggerType type;
  final Map<String, dynamic> config; // e.g., {'time': '07:00', 'days': [1,2,3,4,5]} for time trigger

  const AutomationTrigger({
    required this.type,
    required this.config,
  });

  @override
  List<Object?> get props => [type, config];
}

/// Action for an automation.
class AutomationAction extends Equatable {
  final AutomationActionType type;
  final Map<String, dynamic> config; // e.g., {'deviceId': 'xxx', 'action': 'power', 'value': true}

  const AutomationAction({
    required this.type,
    required this.config,
  });

  @override
  List<Object?> get props => [type, config];
}

/// Represents an automation - a trigger and a set of actions.
class Automation extends Equatable {
  final String id;
  final String name;
  final bool enabled;
  final AutomationTrigger trigger;
  final List<AutomationAction> actions;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? lastRun;

  const Automation({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.trigger,
    required this.actions,
    required this.createdAt,
    this.updatedAt,
    this.lastRun,
  });

  Automation copyWith({
    String? id,
    String? name,
    bool? enabled,
    AutomationTrigger? trigger,
    List<AutomationAction>? actions,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastRun,
  }) {
    return Automation(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      trigger: trigger ?? this.trigger,
      actions: actions ?? this.actions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRun: lastRun ?? this.lastRun,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    enabled,
    trigger,
    actions,
    createdAt,
    updatedAt,
    lastRun,
  ];
}