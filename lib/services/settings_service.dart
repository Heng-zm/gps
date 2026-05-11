import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Enum for type-safe map style preferences.
enum AppMapStyle { dark, light, satellite }

/// Single source of truth for all user-configurable settings.
/// Fully reactive via [ChangeNotifier].
class SettingsService extends ChangeNotifier {
  // Singleton pattern
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const double _milesToKm = 1.609344;
  static const double _feetToMeters = 0.3048;

  // Persistence Keys
  static const String _prefUseKmh = 'use_kmh';
  static const String _prefKeepScreenOn = 'keep_screen_on';
  static const String _prefAutoSave = 'auto_save_trips';
  static const String _prefWeather = 'show_weather';
  static const String _prefAlertEnabled = 'speed_alert_enabled';
  static const String _prefAlertMph = 'speed_alert_mph';
  static const String _prefAltitude = 'show_altitude';
  static const String _prefHeading = 'show_heading';
  static const String _prefGpsMode = 'gps_accuracy_mode';
  static const String _prefMapStyle = 'map_style_preference';

  SharedPreferences? _prefs;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool get isLoaded => _isLoaded;

  // ── Persisted Settings (Initialized with safe defaults) ───────────────
  bool _useKmh = false;
  bool _keepScreenOn = true;
  bool _autoSaveTrips = true;
  bool _showWeather = true;
  bool _speedAlertEnabled = false;
  double _speedAlertMph = 75.0;
  bool _showAltitude = true;
  bool _showHeading = true;
  int _gpsAccuracyMode = 0;
  AppMapStyle _mapStyle = AppMapStyle.dark;

  // ── Public Getters ────────────────────────────────────────────────────
  bool get useKmh => _useKmh;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoSaveTrips => _autoSaveTrips;
  bool get showWeather => _showWeather;
  bool get speedAlertEnabled => _speedAlertEnabled;
  double get speedAlertMph => _speedAlertMph;
  bool get showAltitude => _showAltitude;
  bool get showHeading => _showHeading;
  int get gpsAccuracyMode => _gpsAccuracyMode;
  AppMapStyle get mapStyle => _mapStyle;

  // ── Derived Getters ───────────────────────────────────────────────────
  double get speedAlertDisplayValue =>
      _useKmh ? (_speedAlertMph * _milesToKm).roundToDouble() : _speedAlertMph;

  double get speedAlertMax => _useKmh ? 300.0 : 180.0;
  String get speedUnit => _useKmh ? 'km/h' : 'mph';
  String get distanceUnit => _useKmh ? 'km' : 'mi';
  String get altitudeUnit => _useKmh ? 'm' : 'ft';

  String get gpsAccuracyLabel => switch (_gpsAccuracyMode) {
        1 => 'Balanced',
        2 => 'Low Power',
        _ => 'High Precision',
      };

  // ── Converters ────────────────────────────────────────────────────────
  double toDisplaySpeed(double mph) => _useKmh ? mph * _milesToKm : mph;
  double fromDisplaySpeed(double displayValue) =>
      _useKmh ? displayValue / _milesToKm : displayValue;
  double toDisplayDistance(double miles) =>
      _useKmh ? miles * _milesToKm : miles;
  double toDisplayAltitude(double feet) =>
      _useKmh ? feet * _feetToMeters : feet;

  // ── Initialization ────────────────────────────────────────────────────
  Future<void> load() async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      _prefs = await SharedPreferences.getInstance();

      // Load values with sensible defaults
      _useKmh = _prefs?.getBool(_prefUseKmh) ?? false;
      _keepScreenOn = _prefs?.getBool(_prefKeepScreenOn) ?? true;
      _autoSaveTrips = _prefs?.getBool(_prefAutoSave) ?? true;
      _showWeather = _prefs?.getBool(_prefWeather) ?? true;
      _speedAlertEnabled = _prefs?.getBool(_prefAlertEnabled) ?? false;
      _speedAlertMph = _prefs?.getDouble(_prefAlertMph) ?? 75.0;
      _showAltitude = _prefs?.getBool(_prefAltitude) ?? true;
      _showHeading = _prefs?.getBool(_prefHeading) ?? true;
      _gpsAccuracyMode = _prefs?.getInt(_prefGpsMode) ?? 0;
      final mapStyleIndex = _prefs?.getInt(_prefMapStyle) ?? 0;
      _mapStyle = AppMapStyle
          .values[mapStyleIndex.clamp(0, AppMapStyle.values.length - 1)];

      _isLoaded = true;
      await _applyScreenWake();
    } catch (e) {
      debugPrint('Settings Load Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Universal Persistence Helper ──────────────────────────────────────
  Future<void> _update<T>(
      String key, T value, void Function(T) assignState) async {
    assignState(value);
    notifyListeners();
    HapticFeedback.selectionClick();

    if (_prefs == null) return;
    if (value is bool) await _prefs!.setBool(key, value);
    if (value is double) await _prefs!.setDouble(key, value);
    if (value is int) await _prefs!.setInt(key, value);
  }

  // ── Public Setters ────────────────────────────────────────────────────
  Future<void> setUseKmh(bool v) =>
      _update(_prefUseKmh, v, (val) => _useKmh = val);
  Future<void> setAutoSaveTrips(bool v) =>
      _update(_prefAutoSave, v, (val) => _autoSaveTrips = val);
  Future<void> setShowWeather(bool v) =>
      _update(_prefWeather, v, (val) => _showWeather = val);
  Future<void> setSpeedAlertEnabled(bool v) =>
      _update(_prefAlertEnabled, v, (val) => _speedAlertEnabled = val);
  Future<void> setShowAltitude(bool v) =>
      _update(_prefAltitude, v, (val) => _showAltitude = val);
  Future<void> setShowHeading(bool v) =>
      _update(_prefHeading, v, (val) => _showHeading = val);
  Future<void> setGpsAccuracyMode(int v) =>
      _update(_prefGpsMode, v, (val) => _gpsAccuracyMode = val);
  Future<void> setMapStyle(AppMapStyle v) =>
      _update(_prefMapStyle, v.index, (val) => _mapStyle = v);

  Future<void> setKeepScreenOn(bool v) async {
    await _update(_prefKeepScreenOn, v, (val) => _keepScreenOn = val);
    await _applyScreenWake();
  }

  Future<void> setSpeedAlertDisplayValue(double displayValue) async {
    _speedAlertMph = fromDisplaySpeed(displayValue);
    await _prefs?.setDouble(_prefAlertMph, _speedAlertMph);
    notifyListeners();
  }

  /// Resets all user settings to factory defaults
  Future<void> clearAllData() async {
    if (_prefs == null) return;
    await _prefs!.clear();
    HapticFeedback.vibrate();

    // Re-initialize state by loading from now-empty preferences
    _isLoaded = false;
    await load();
  }

  // ── WakeLock Management ────────────────────────────────────────────────
  Future<void> _applyScreenWake() async {
    try {
      if (_keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('WakeLock Exception: $e');
    }
  }
}
