import '../models/tracking_accuracy_mode.dart';
import 'settings_service.dart';

extension SettingsServiceTrackingAccuracyX on SettingsService {
  TrackingAccuracyMode get trackingAccuracyMode {
    final int mode = gpsAccuracyMode;

    if (mode <= 0) return TrackingAccuracyMode.highAccuracy;
    if (mode == 1) return TrackingAccuracyMode.balanced;
    return TrackingAccuracyMode.batterySaver;
  }

  Future<void> setTrackingAccuracyMode(
    TrackingAccuracyMode mode,
  ) async {
    final int value = switch (mode) {
      TrackingAccuracyMode.highAccuracy => 0,
      TrackingAccuracyMode.balanced => 1,
      TrackingAccuracyMode.batterySaver => 2,
    };

    await setGpsAccuracyMode(value);
  }
}
