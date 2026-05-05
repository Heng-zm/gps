import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Single source of truth for all user-configurable settings.
/// Reactive via [ChangeNotifier].
class SettingsService extends ChangeNotifier {
  // Singleton pattern
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const double _milesToKm = 1.609344;
  static const String _prefUseKmh = 'use_kmh';
  static const String _prefKeepScreenOn = 'keep_screen_on';
  static const String _prefAutoSave = 'auto_save_trips';
  static const String _prefWeather = 'show_weather';
  static const String _prefAlertEnabled = 'speed_alert_enabled';
  static const String _prefAlertMph = 'speed_alert_mph';
  static const String _prefAltitude = 'show_altitude';
  static const String _prefHeading = 'show_heading';
  static const String _prefGpsMode = 'gps_accuracy_mode';

  SharedPreferences? _prefs;
  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;

  // ── Persisted Settings ────────────────────────────────────────────────────
  late bool _useKmh;
  late bool _keepScreenOn;
  late bool _autoSaveTrips;
  late bool _showWeather;
  late bool _speedAlertEnabled;
  late double _speedAlertMph;
  late bool _showAltitude;
  late bool _showHeading;
  late int _gpsAccuracyMode;

  // ── Public Getters ────────────────────────────────────────────────────────
  bool get useKmh => _useKmh;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoSaveTrips => _autoSaveTrips;
  bool get showWeather => _showWeather;
  bool get speedAlertEnabled => _speedAlertEnabled;
  double get speedAlertMph => _speedAlertMph;
  bool get showAltitude => _showAltitude;
  bool get showHeading => _showHeading;
  int get gpsAccuracyMode => _gpsAccuracyMode;

  // ── Derived Helpers (Dart 3.0 Switch Expressions) ─────────────────────────
  double get speedAlertDisplayValue =>
      _useKmh ? _speedAlertMph * _milesToKm : _speedAlertMph;
  double get speedAlertMax => _useKmh ? 320.0 : 200.0;
  String get speedUnit => _useKmh ? 'km/h' : 'mph';
  String get distanceUnit => _useKmh ? 'km' : 'mi';

  double toDisplaySpeed(double mph) => _useKmh ? mph * _milesToKm : mph;
  double fromDisplaySpeed(double display) =>
      _useKmh ? display / _milesToKm : display;
  double toDisplayDistance(double miles) =>
      _useKmh ? miles * _milesToKm : miles;

  String get gpsAccuracyLabel => switch (_gpsAccuracyMode) {
        1 => 'Balanced',
        2 => 'Low Power',
        _ => 'Best',
      };

  // ── Initialization ────────────────────────────────────────────────────────
  Future<void> load() async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      _prefs = await SharedPreferences.getInstance();
      _useKmh = _prefs?.getBool(_prefUseKmh) ?? false;
      _keepScreenOn = _prefs?.getBool(_prefKeepScreenOn) ?? true;
      _autoSaveTrips = _prefs?.getBool(_prefAutoSave) ?? true;
      _showWeather = _prefs?.getBool(_prefWeather) ?? true;
      _speedAlertEnabled = _prefs?.getBool(_prefAlertEnabled) ?? false;
      _speedAlertMph = _prefs?.getDouble(_prefAlertMph) ?? 80.0;
      _showAltitude = _prefs?.getBool(_prefAltitude) ?? true;
      _showHeading = _prefs?.getBool(_prefHeading) ?? true;
      _gpsAccuracyMode = _prefs?.getInt(_prefGpsMode) ?? 0;

      _isLoaded = true;
      await _applyScreenWake();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Universal Persistence Helper ──────────────────────────────────────────
  /// Saves the value to disk and triggers UI rebuilds.
  Future<void> _set<T>(
      String key, T value, void Function(T) updateState) async {
    updateState(value);
    if (value is bool) await _prefs?.setBool(key, value);
    if (value is double) await _prefs?.setDouble(key, value);
    if (value is int) await _prefs?.setInt(key, value);
    notifyListeners();
  }

  // ── Public Setters ────────────────────────────────────────────────────────
  Future<void> setUseKmh(bool v) =>
      _set(_prefUseKmh, v, (val) => _useKmh = val);

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    await _prefs?.setBool(_prefKeepScreenOn, v);
    await _applyScreenWake();
    notifyListeners();
  }

  Future<void> setAutoSaveTrips(bool v) =>
      _set(_prefAutoSave, v, (val) => _autoSaveTrips = val);
  Future<void> setShowWeather(bool v) =>
      _set(_prefWeather, v, (val) => _showWeather = val);
  Future<void> setSpeedAlertEnabled(bool v) =>
      _set(_prefAlertEnabled, v, (val) => _speedAlertEnabled = val);

  Future<void> setSpeedAlertDisplayValue(double displayValue) async {
    _speedAlertMph = fromDisplaySpeed(displayValue);
    await _prefs?.setDouble(_prefAlertMph, _speedAlertMph);
    notifyListeners();
  }

  Future<void> setShowAltitude(bool v) =>
      _set(_prefAltitude, v, (val) => _showAltitude = val);
  Future<void> setShowHeading(bool v) =>
      _set(_prefHeading, v, (val) => _showHeading = val);
  Future<void> setGpsAccuracyMode(int v) =>
      _set(_prefGpsMode, v, (val) => _gpsAccuracyMode = val);

  Future<void> clearAllData() async {
    await _prefs?.clear();
    // Re-initialize local state to defaults
    _useKmh = false;
    _keepScreenOn = true;
    _autoSaveTrips = true;
    _showWeather = true;
    _speedAlertEnabled = false;
    _speedAlertMph = 80.0;
    _showAltitude = true;
    _showHeading = true;
    _gpsAccuracyMode = 0;

    await _applyScreenWake();
    notifyListeners();
  }

  // ── WakeLock Management (Upgraded for Web safety) ─────────────────────────
  Future<void> _applyScreenWake() async {
    try {
      if (_keepScreenOn) {
        // Only trigger on mobile or if browser permissions are likely granted
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      // Browsers often block WakeLock without a user gesture or HTTPS.
      // We swallow this to prevent app crashes, but log in debug mode.
      debugPrint('Wakelock Exception: $e');
    }
  }
}
