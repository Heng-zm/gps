import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/location_puck_style.dart';

/// Enum for type-safe map style preferences.
enum AppMapStyle {
  dark,
  light,
  satellite,
}

/// Single source of truth for all user-configurable settings.
/// Fully reactive via [ChangeNotifier].
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const double _milesToKm = 1.609344;
  static const double _feetToMeters = 0.3048;

  static const double _defaultSpeedAlertMph = 75.0;
  static const double _minSpeedAlertMph = 1.0;
  static const double _maxSpeedAlertMph = 180.0;

  // ───────────────────────────────────────────────────────────────────────────
  // Persistence Keys
  // ───────────────────────────────────────────────────────────────────────────

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
  static const String _prefLocationPuckStyle = 'location_puck_style';

  static const List<String> _settingsKeys = <String>[
    _prefUseKmh,
    _prefKeepScreenOn,
    _prefAutoSave,
    _prefWeather,
    _prefAlertEnabled,
    _prefAlertMph,
    _prefAltitude,
    _prefHeading,
    _prefGpsMode,
    _prefMapStyle,
    _prefLocationPuckStyle,
  ];

  SharedPreferences? _prefs;

  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  // ───────────────────────────────────────────────────────────────────────────
  // Persisted Settings Defaults
  // ───────────────────────────────────────────────────────────────────────────

  bool _useKmh = false;
  bool _keepScreenOn = true;
  bool _autoSaveTrips = true;
  bool _showWeather = true;
  bool _speedAlertEnabled = false;
  double _speedAlertMph = _defaultSpeedAlertMph;
  bool _showAltitude = true;
  bool _showHeading = true;
  int _gpsAccuracyMode = 0;
  AppMapStyle _mapStyle = AppMapStyle.dark;
  LocationPuckStyle _locationPuckStyle = LocationPuckStyle.classicBlue;

  // ───────────────────────────────────────────────────────────────────────────
  // Public Getters
  // ───────────────────────────────────────────────────────────────────────────

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
  LocationPuckStyle get locationPuckStyle => _locationPuckStyle;

  // ───────────────────────────────────────────────────────────────────────────
  // Derived Getters
  // ───────────────────────────────────────────────────────────────────────────

  bool get isMetric => _useKmh;
  bool get isImperial => !_useKmh;

  double get speedAlertDisplayValue {
    final double value = _useKmh ? _speedAlertMph * _milesToKm : _speedAlertMph;
    return value.roundToDouble();
  }

  double get speedAlertMin => _useKmh ? 1.0 : _minSpeedAlertMph;
  double get speedAlertMax => _useKmh ? 300.0 : _maxSpeedAlertMph;

  String get speedUnit => _useKmh ? 'km/h' : 'mph';
  String get distanceUnit => _useKmh ? 'km' : 'mi';
  String get altitudeUnit => _useKmh ? 'm' : 'ft';

  String get gpsAccuracyLabel {
    return switch (_gpsAccuracyMode) {
      1 => 'Balanced',
      2 => 'Low Power',
      _ => 'High Precision',
    };
  }

  String get mapStyleLabel {
    return switch (_mapStyle) {
      AppMapStyle.dark => 'Dark',
      AppMapStyle.light => 'Light',
      AppMapStyle.satellite => 'Satellite',
    };
  }

  String get locationPuckStyleLabel => _locationPuckStyle.label;

  // ───────────────────────────────────────────────────────────────────────────
  // Unit Converters
  // ───────────────────────────────────────────────────────────────────────────

  double toDisplaySpeed(double mph) {
    final double safeValue = _safeFinite(mph);
    return _useKmh ? safeValue * _milesToKm : safeValue;
  }

  double fromDisplaySpeed(double displayValue) {
    final double safeValue = _safeFinite(displayValue);
    return _useKmh ? safeValue / _milesToKm : safeValue;
  }

  double toDisplayDistance(double miles) {
    final double safeValue = _safeFinite(miles);
    return _useKmh ? safeValue * _milesToKm : safeValue;
  }

  double fromDisplayDistance(double displayValue) {
    final double safeValue = _safeFinite(displayValue);
    return _useKmh ? safeValue / _milesToKm : safeValue;
  }

  double toDisplayAltitude(double feet) {
    final double safeValue = _safeFinite(feet);
    return _useKmh ? safeValue * _feetToMeters : safeValue;
  }

  double fromDisplayAltitude(double displayValue) {
    final double safeValue = _safeFinite(displayValue);
    return _useKmh ? safeValue / _feetToMeters : safeValue;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Initialization
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> load({bool forceReload = false}) async {
    if (_isLoading) {
      return;
    }

    if (_isLoaded && !forceReload) {
      return;
    }

    _isLoading = true;

    try {
      final SharedPreferences prefs = await _getPrefs();

      _useKmh = _readBool(prefs, _prefUseKmh, fallback: false);
      _keepScreenOn = _readBool(prefs, _prefKeepScreenOn, fallback: true);
      _autoSaveTrips = _readBool(prefs, _prefAutoSave, fallback: true);
      _showWeather = _readBool(prefs, _prefWeather, fallback: true);
      _speedAlertEnabled = _readBool(
        prefs,
        _prefAlertEnabled,
        fallback: false,
      );
      _speedAlertMph = _sanitizeSpeedAlertMph(
        _readDouble(
          prefs,
          _prefAlertMph,
          fallback: _defaultSpeedAlertMph,
        ),
      );
      _showAltitude = _readBool(prefs, _prefAltitude, fallback: true);
      _showHeading = _readBool(prefs, _prefHeading, fallback: true);
      _gpsAccuracyMode = _sanitizeGpsAccuracyMode(
        _readInt(prefs, _prefGpsMode, fallback: 0),
      );
      _mapStyle = _parseMapStyleIndex(
        _readInt(prefs, _prefMapStyle, fallback: AppMapStyle.dark.index),
      );
      _locationPuckStyle = _parseLocationPuckStyle(
        _readString(prefs, _prefLocationPuckStyle),
      );

      _isLoaded = true;

      await _applyScreenWake();
    } catch (e, st) {
      debugPrint('SettingsService load error: $e\n$st');

      _resetInMemoryDefaults();
      _isLoaded = true;

      await _applyScreenWake();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    await load(forceReload: true);
  }

  Future<void> ensureLoaded() async {
    if (!_isLoaded) {
      await load();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Public Setters
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> setUseKmh(bool value) async {
    await _updateBool(
      key: _prefUseKmh,
      currentValue: _useKmh,
      newValue: value,
      assign: () => _useKmh = value,
    );
  }

  Future<void> setKeepScreenOn(bool value) async {
    final bool changed = await _updateBool(
      key: _prefKeepScreenOn,
      currentValue: _keepScreenOn,
      newValue: value,
      assign: () => _keepScreenOn = value,
    );

    if (changed) {
      await _applyScreenWake();
    }
  }

  Future<void> setAutoSaveTrips(bool value) async {
    await _updateBool(
      key: _prefAutoSave,
      currentValue: _autoSaveTrips,
      newValue: value,
      assign: () => _autoSaveTrips = value,
    );
  }

  Future<void> setShowWeather(bool value) async {
    await _updateBool(
      key: _prefWeather,
      currentValue: _showWeather,
      newValue: value,
      assign: () => _showWeather = value,
    );
  }

  Future<void> setSpeedAlertEnabled(bool value) async {
    await _updateBool(
      key: _prefAlertEnabled,
      currentValue: _speedAlertEnabled,
      newValue: value,
      assign: () => _speedAlertEnabled = value,
    );
  }

  Future<void> setSpeedAlertMph(double value) async {
    final double sanitized = _sanitizeSpeedAlertMph(value);

    await _updateDouble(
      key: _prefAlertMph,
      currentValue: _speedAlertMph,
      newValue: sanitized,
      assign: () => _speedAlertMph = sanitized,
    );
  }

  Future<void> setSpeedAlertDisplayValue(double displayValue) async {
    final double mph = _sanitizeSpeedAlertMph(fromDisplaySpeed(displayValue));

    await _updateDouble(
      key: _prefAlertMph,
      currentValue: _speedAlertMph,
      newValue: mph,
      assign: () => _speedAlertMph = mph,
    );
  }

  Future<void> setShowAltitude(bool value) async {
    await _updateBool(
      key: _prefAltitude,
      currentValue: _showAltitude,
      newValue: value,
      assign: () => _showAltitude = value,
    );
  }

  Future<void> setShowHeading(bool value) async {
    await _updateBool(
      key: _prefHeading,
      currentValue: _showHeading,
      newValue: value,
      assign: () => _showHeading = value,
    );
  }

  Future<void> setGpsAccuracyMode(int value) async {
    final int sanitized = _sanitizeGpsAccuracyMode(value);

    await _updateInt(
      key: _prefGpsMode,
      currentValue: _gpsAccuracyMode,
      newValue: sanitized,
      assign: () => _gpsAccuracyMode = sanitized,
    );
  }

  Future<void> setMapStyle(AppMapStyle value) async {
    if (_mapStyle == value) {
      return;
    }

    _mapStyle = value;
    notifyListeners();
    await _hapticSelection();

    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.setInt(_prefMapStyle, value.index);
    } catch (e, st) {
      debugPrint('SettingsService setMapStyle error: $e\n$st');
    }
  }

  Future<void> setLocationPuckStyle(LocationPuckStyle value) async {
    if (_locationPuckStyle == value) {
      return;
    }

    _locationPuckStyle = value;
    notifyListeners();
    await _hapticSelection();

    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.setString(_prefLocationPuckStyle, value.storageKey);
    } catch (e, st) {
      debugPrint('SettingsService setLocationPuckStyle error: $e\n$st');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Reset / Clear
  // ───────────────────────────────────────────────────────────────────────────

  /// Resets only settings keys to factory defaults.
  ///
  /// This is safer than clearing every SharedPreferences key because trip data,
  /// cached app data, or other services may also use SharedPreferences.
  Future<void> resetSettings() async {
    try {
      final SharedPreferences prefs = await _getPrefs();

      for (final String key in _settingsKeys) {
        await prefs.remove(key);
      }

      _resetInMemoryDefaults();
      _isLoaded = true;

      await _applyScreenWake();
      await HapticFeedback.vibrate();

      notifyListeners();
    } catch (e, st) {
      debugPrint('SettingsService resetSettings error: $e\n$st');
    }
  }

  /// Backward-compatible method name.
  ///
  /// Previously this cleared every SharedPreferences key. Now it safely resets
  /// settings only, to avoid deleting unrelated app data by accident.
  Future<void> clearAllData() async {
    await resetSettings();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Internal Update Helpers
  // ───────────────────────────────────────────────────────────────────────────

  Future<bool> _updateBool({
    required String key,
    required bool currentValue,
    required bool newValue,
    required VoidCallback assign,
  }) async {
    if (currentValue == newValue) {
      return false;
    }

    assign();
    notifyListeners();
    await _hapticSelection();

    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.setBool(key, newValue);
    } catch (e, st) {
      debugPrint('SettingsService bool update error for $key: $e\n$st');
    }

    return true;
  }

  Future<bool> _updateInt({
    required String key,
    required int currentValue,
    required int newValue,
    required VoidCallback assign,
  }) async {
    if (currentValue == newValue) {
      return false;
    }

    assign();
    notifyListeners();
    await _hapticSelection();

    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.setInt(key, newValue);
    } catch (e, st) {
      debugPrint('SettingsService int update error for $key: $e\n$st');
    }

    return true;
  }

  Future<bool> _updateDouble({
    required String key,
    required double currentValue,
    required double newValue,
    required VoidCallback assign,
  }) async {
    if ((currentValue - newValue).abs() < 0.000001) {
      return false;
    }

    assign();
    notifyListeners();
    await _hapticSelection();

    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.setDouble(key, newValue);
    } catch (e, st) {
      debugPrint('SettingsService double update error for $key: $e\n$st');
    }

    return true;
  }

  Future<SharedPreferences> _getPrefs() async {
    final SharedPreferences? cached = _prefs;

    if (cached != null) {
      return cached;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs;
  }

  Future<void> _hapticSelection() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Haptics can fail on web, desktop, simulators, or unsupported devices.
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // WakeLock Management
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _applyScreenWake() async {
    try {
      if (_keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e, st) {
      debugPrint('WakeLock exception: $e\n$st');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Safe SharedPreferences Readers
  // ───────────────────────────────────────────────────────────────────────────

  static bool _readBool(
    SharedPreferences prefs,
    String key, {
    required bool fallback,
  }) {
    try {
      final Object? value = prefs.get(key);
      if (value is bool) return value;
      if (value is String) {
        final String normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
    } catch (e, st) {
      debugPrint('SettingsService bool read error for $key: $e\n$st');
    }

    return fallback;
  }

  static int _readInt(
    SharedPreferences prefs,
    String key, {
    required int fallback,
  }) {
    try {
      final Object? value = prefs.get(key);
      if (value is int) return value;
      if (value is double && value.isFinite) return value.round();
      if (value is String) return int.tryParse(value.trim()) ?? fallback;
    } catch (e, st) {
      debugPrint('SettingsService int read error for $key: $e\n$st');
    }

    return fallback;
  }

  static double _readDouble(
    SharedPreferences prefs,
    String key, {
    required double fallback,
  }) {
    try {
      final Object? value = prefs.get(key);
      if (value is double && value.isFinite) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        final double? parsed = double.tryParse(value.trim());
        if (parsed != null && parsed.isFinite) return parsed;
      }
    } catch (e, st) {
      debugPrint('SettingsService double read error for $key: $e\n$st');
    }

    return fallback;
  }

  static String? _readString(SharedPreferences prefs, String key) {
    try {
      final Object? value = prefs.get(key);
      if (value == null) return null;
      if (value is String) return value;
      return value.toString();
    } catch (e, st) {
      debugPrint('SettingsService string read error for $key: $e\n$st');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Sanitizers / Parsers
  // ───────────────────────────────────────────────────────────────────────────

  static double _safeFinite(double value) {
    if (!value.isFinite) {
      return 0.0;
    }

    return value;
  }

  static double _sanitizeSpeedAlertMph(double value) {
    if (!value.isFinite) {
      return _defaultSpeedAlertMph;
    }

    return value.clamp(_minSpeedAlertMph, _maxSpeedAlertMph).toDouble();
  }

  static int _sanitizeGpsAccuracyMode(int value) {
    return value.clamp(0, 2).toInt();
  }

  static AppMapStyle _parseMapStyleIndex(int index) {
    final int safeIndex = index.clamp(0, AppMapStyle.values.length - 1).toInt();
    return AppMapStyle.values[safeIndex];
  }

  static LocationPuckStyle _parseLocationPuckStyle(String? value) {
    return LocationPuckStyle.fromStorageKey(value);
  }

  void _resetInMemoryDefaults() {
    _useKmh = false;
    _keepScreenOn = true;
    _autoSaveTrips = true;
    _showWeather = true;
    _speedAlertEnabled = false;
    _speedAlertMph = _defaultSpeedAlertMph;
    _showAltitude = true;
    _showHeading = true;
    _gpsAccuracyMode = 0;
    _mapStyle = AppMapStyle.dark;
    _locationPuckStyle = LocationPuckStyle.classicBlue;
  }
}
