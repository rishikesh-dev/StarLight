import 'package:equatable/equatable.dart';

/// Home settings and metadata.
class Home extends Equatable {
  final String id;
  final String name;
  final String? location; // city, country for sunrise/sunset
  final double? latitude;
  final double? longitude;
  final String timezone;
  final Map<String, dynamic> preferences;

  const Home({
    required this.id,
    required this.name,
    this.location,
    this.latitude,
    this.longitude,
    this.timezone = 'UTC',
    this.preferences = const {},
  });

  Home copyWith({
    String? id,
    String? name,
    String? location,
    double? latitude,
    double? longitude,
    String? timezone,
    Map<String, dynamic>? preferences,
  }) {
    return Home(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timezone: timezone ?? this.timezone,
      preferences: preferences ?? this.preferences,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    location,
    latitude,
    longitude,
    timezone,
    preferences,
  ];
}

/// Default home for first launch.
class DefaultHome {
  static const Home home = Home(
    id: 'default',
    name: 'My Home',
    timezone: 'UTC',
  );
}