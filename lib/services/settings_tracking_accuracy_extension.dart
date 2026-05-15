import '../models/tracking_accuracy_mode.dart';
import 'settings_service.dart';

extension SettingsServiceTrackingAccuracyX on SettingsService {
  TrackingAccuracyMode get trackingAccuracyMode {
    final int mode = gpsAccuracyMode;

    if (mode <= 0) return TrackingAccuracyMode.batterySaver;
    if (mode == 1) return TrackingAccuracyMode.balanced;
    return TrackingAccuracyMode.highAccuracy;
  }

  Future<void> setTrackingAccuracyMode(
    TrackingAccuracyMode mode,
  ) async {
    final int value = switch (mode) {
      TrackingAccuracyMode.batterySaver => 0,
      TrackingAccuracyMode.balanced => 1,
      TrackingAccuracyMode.highAccuracy => 2,
    };

    await setGpsAccuracyMode(value);
  }
}
