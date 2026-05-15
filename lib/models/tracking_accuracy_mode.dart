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
}
