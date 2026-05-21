import 'package:geolocator/geolocator.dart';

enum TrackingAccuracyMode {
  highAccuracy,
  balanced,
  batterySaver,
}

extension TrackingAccuracyModeX on TrackingAccuracyMode {
  String get label {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 'High accuracy';
      case TrackingAccuracyMode.balanced:
        return 'Balanced';
      case TrackingAccuracyMode.batterySaver:
        return 'Battery saver';
    }
  }

  String get description {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 'Best GPS accuracy. Uses more battery.';
      case TrackingAccuracyMode.balanced:
        return 'Good route quality with moderate battery usage.';
      case TrackingAccuracyMode.batterySaver:
        return 'Lower GPS frequency for long trips.';
    }
  }

  int get intervalSeconds {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 1;
      case TrackingAccuracyMode.balanced:
        return 3;
      case TrackingAccuracyMode.batterySaver:
        return 8;
    }
  }

  Duration get intervalDuration => Duration(seconds: intervalSeconds);

  int get distanceFilterMeters {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 1;
      case TrackingAccuracyMode.balanced:
        return 5;
      case TrackingAccuracyMode.batterySaver:
        return 15;
    }
  }

  LocationAccuracy get geolocatorAccuracy {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return LocationAccuracy.bestForNavigation;
      case TrackingAccuracyMode.balanced:
        return LocationAccuracy.high;
      case TrackingAccuracyMode.batterySaver:
        return LocationAccuracy.medium;
    }
  }

  LocationSettings get locationSettings {
    return LocationSettings(
      accuracy: geolocatorAccuracy,
      distanceFilter: distanceFilterMeters,
    );
  }

  int get settingsIndex {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 0;
      case TrackingAccuracyMode.balanced:
        return 1;
      case TrackingAccuracyMode.batterySaver:
        return 2;
    }
  }

  String get storageKey => name;

  static TrackingAccuracyMode fromSettingsIndex(int value) {
    switch (value) {
      case 1:
        return TrackingAccuracyMode.balanced;
      case 2:
        return TrackingAccuracyMode.batterySaver;
      case 0:
      default:
        return TrackingAccuracyMode.highAccuracy;
    }
  }

  static TrackingAccuracyMode fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return TrackingAccuracyMode.highAccuracy;

    for (final TrackingAccuracyMode mode in TrackingAccuracyMode.values) {
      if (mode.storageKey.toLowerCase() == normalized ||
          mode.label.toLowerCase() == normalized) {
        return mode;
      }
    }

    switch (normalized) {
      case 'high':
      case 'best':
      case 'navigation':
        return TrackingAccuracyMode.highAccuracy;
      case 'medium':
      case 'balanced':
        return TrackingAccuracyMode.balanced;
      case 'low':
      case 'battery':
      case 'battery_saver':
      case 'powersave':
        return TrackingAccuracyMode.batterySaver;
    }

    return TrackingAccuracyMode.highAccuracy;
  }
}

extension TrackingAccuracyModeUxX on TrackingAccuracyMode {
  TrackingAccuracyMode get next {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return TrackingAccuracyMode.balanced;
      case TrackingAccuracyMode.balanced:
        return TrackingAccuracyMode.batterySaver;
      case TrackingAccuracyMode.batterySaver:
        return TrackingAccuracyMode.highAccuracy;
    }
  }

  int get batteryCostScore {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 3;
      case TrackingAccuracyMode.balanced:
        return 2;
      case TrackingAccuracyMode.batterySaver:
        return 1;
    }
  }

  int get routeQualityScore {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 3;
      case TrackingAccuracyMode.balanced:
        return 2;
      case TrackingAccuracyMode.batterySaver:
        return 1;
    }
  }

  bool recommendedForTrip(Duration expectedTripDuration) {
    final Duration safeDuration =
        expectedTripDuration.isNegative ? Duration.zero : expectedTripDuration;

    if (safeDuration.inHours >= 3) {
      return this == TrackingAccuracyMode.batterySaver;
    }

    if (safeDuration.inMinutes >= 45) {
      return this == TrackingAccuracyMode.balanced;
    }

    return this == TrackingAccuracyMode.highAccuracy;
  }

  String get uxBadge {
    switch (this) {
      case TrackingAccuracyMode.highAccuracy:
        return 'Best route';
      case TrackingAccuracyMode.balanced:
        return 'Recommended';
      case TrackingAccuracyMode.batterySaver:
        return 'Long trip';
    }
  }
}
