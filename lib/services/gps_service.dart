// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_data.dart';
import 'settings_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GPS SERVICE  — v2 (optimized)
// ─────────────────────────────────────────────────────────────────────────────
class GpsService {
  GpsService._internal();
  static final GpsService instance = GpsService._internal();

  // ── stream infrastructure ─────────────────────────────────────────────────
  StreamController<TripPoint>? _pointCtrl;
  StreamSubscription<Position>? _posSub;

  // ── trip data ─────────────────────────────────────────────────────────────
  final List<TripPoint> _points = <TripPoint>[];
  final Stopwatch _tripSw = Stopwatch();
  final Stopwatch _stoppedSw = Stopwatch();

  // Monotonic clock used for all inter-point timing math. Unlike DateTime.now(),
  // this cannot jump backwards/forwards when the OS syncs the system clock.
  final Stopwatch _tickSw = Stopwatch();

  // ── position state ────────────────────────────────────────────────────────
  Position? _lastRawPos;
  LatLng? _lastEmittedSmoothedPos;
  LatLng? _lastStoredSmoothedPos;

  int? _lastProcessedMs;
  int? _lastStoredMs;
  double? _lastValidAltM;

  // ── accumulators ──────────────────────────────────────────────────────────
  double _totalDistM = 0.0;
  double _altGainM = 0.0;
  double _maxSpeedMph = 0.0;
  double _movingSpeedSum = 0.0;
  int _movingCount = 0;

  double _maxAltFt = _kEmptyMaxAlt;
  double _minAltFt = _kEmptyMinAlt;

  // ── smoothing ─────────────────────────────────────────────────────────────
  // [PERF-1] O(1) circular buffer instead of List.removeAt(0)
  final _CircularBuffer _speedBuf = _CircularBuffer(_kSpeedWindow);

  double? _kLat; // Kalman state — latitude
  double? _kLng; // Kalman state — longitude
  double _kP = _kInitialVariance; // [FIX-6] variance in accuracy² domain

  // ── lifecycle flags ───────────────────────────────────────────────────────
  bool _isTracking = false;
  bool _startLock = false; // [ROB-1] prevents concurrent startTracking
  bool _isAutoPaused = false;
  DateTime? _tripStartTime;
  int? _slowSinceMs;
  int? _moveSinceMs;
  int _rejectedJumpCount = 0;

  // ── cached location settings [PERF-2] ────────────────────────────────────
  LocationSettings? _cachedLocationSettings;

  // ─────────────────────────────────────────────────────────────────────────
  // CONSTANTS
  // ─────────────────────────────────────────────────────────────────────────

  static const double _kStoppedMph = 1.1;
  static const double _kAutoPauseEnterMph = 1.2;
  static const double _kAutoPauseResumeMph = 2.8;
  static const Duration _kAutoPauseEnterDelay = Duration(seconds: 12);
  static const Duration _kAutoPauseResumeDelay = Duration(seconds: 3);
  static const double _kMpsToMph = 2.23694;
  static const double _kMToFt = 3.28084;
  static const double _kMToMiles = 1609.34;
  static const double _kAltJitterM = 1.5;
  static const double _kMaxPlausibleMph = 250.0;
  static const double _kJumpMinDistanceM = 45.0;
  static const double _kJumpMaxSpeedMph = 165.0;
  static const double _kJumpAccuracyBufferM = 25.0;
  static const double _kStoppedJumpDistanceM = 30.0;
  static const double _kMinStorageDistM = 3.0;
  static const double _kAutoPausedMinStorageDistM = 12.0;
  static const int _kMinStorageSecs = 10;
  static const int _kAutoPausedMinStorageSecs = 60;
  static const int _kMinProcessMs = 200;
  static const int _kSpeedWindow = 4;
  static const double _kEmptyMaxAlt = -100000.0;
  static const double _kEmptyMinAlt = 100000.0;
  static const double _kInitialVariance =
      225.0; // [FIX-6] 15m² initial uncertainty
  static const double _kProcessNoise = 9.0; // [FIX-6] 3m² per step (√9 = 3m)

  static double get _kAccuracyThreshM => kIsWeb ? 100.0 : 40.0;

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  bool get isTracking => _isTracking;
  bool get isAutoPaused => _isAutoPaused;
  DateTime? get tripStartTime => _tripStartTime;
  Stream<TripPoint>? get pointStream => _pointCtrl?.stream;

  Duration get currentAutoPausedTime {
    // Kept for UI compatibility. Stopped time is now the single source of truth
    // for idle / auto-pause accumulation.
    return _stoppedSw.elapsed;
  }

  int get rejectedJumpCount => _rejectedJumpCount;

  bool get hasPoints => _points.isNotEmpty;
  TripPoint? get latestPoint => _points.isEmpty ? null : _points.last;

  /// All stored trip points. Safe read-only view.
  List<TripPoint> get currentPoints => UnmodifiableListView<TripPoint>(_points);

  double get currentDistanceMiles => _totalDistM / _kMToMiles;
  double get currentMaxSpeedMph => _maxSpeedMph;

  double get currentAvgSpeedMph {
    if (_movingCount == 0) return 0.0;
    return _movingSpeedSum / _movingCount;
  }

  Duration get currentTripTime => _tripSw.elapsed;
  Duration get currentStoppedTime => _stoppedSw.elapsed;

  Duration get currentMovingTime {
    final m = _tripSw.elapsed - _stoppedSw.elapsed;
    return m.isNegative ? Duration.zero : m;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERMISSION
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (e, st) {
      debugPrint('GpsService.requestPermission: $e\n$st');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ONE-SHOT LOCATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<Position?> getCurrentLocation() async {
    try {
      if (!await requestPermission()) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 6));
    } catch (e, st) {
      debugPrint('GpsService.getCurrentLocation: $e\n$st');
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (e2, st2) {
        debugPrint('GpsService.getLastKnownPosition: $e2\n$st2');
        return null;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRACKING LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startTracking() async {
    if (_isTracking || _startLock) return; // [ROB-1]
    _startLock = true;

    try {
      if (!await requestPermission()) return;

      await _cancelSub();
      await _closeCtrl();
      _resetState();

      _pointCtrl = StreamController<TripPoint>.broadcast();
      _isTracking = true;
      _tripStartTime = DateTime.now();
      _tripSw.start();
      _tickSw.start();
      _cachedLocationSettings = null; // Pick up the latest GPS accuracy setting.

      _positionSubscription();
    } catch (e, st) {
      debugPrint('GpsService.startTracking: $e\n$st');
      _isTracking = false;
      _tripStartTime = null;
      _tripSw
        ..stop()
        ..reset();
      _stoppedSw
        ..stop()
        ..reset();
      _tickSw
        ..stop()
        ..reset();
      await _cancelSub();
      await _closeCtrl();
    } finally {
      _startLock = false;
    }
  }

  void _positionSubscription() {
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(),
      ).listen(
        _handlePosition,
        onError: (Object e, StackTrace st) {
          debugPrint('GpsService stream: $e\n$st');
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      debugPrint('GpsService._positionSubscription: $e\n$st');
      rethrow;
    }
  }

  /// Returns a [TripSummary] or null if no points were collected.
  /// [FIX-1] Awaits subscription cancellation before assembling summary.
  Future<TripSummary?> stopTracking() async {
    if (!_isTracking) return null;
    if (_isAutoPaused) {
      _exitAutoPause();
    }
    _isTracking = false;

    _tripSw.stop();
    _stoppedSw.stop();
    _tickSw.stop();

    // [FIX-1] Cancel stream first so no late points corrupt the summary
    await _cancelSub();

    if (_points.isEmpty) {
      await _closeCtrl();
      _tripStartTime = null;
      return null;
    }

    final maxAlt = _maxAltFt == _kEmptyMaxAlt ? 0.0 : _maxAltFt;
    final minAlt = _minAltFt == _kEmptyMinAlt ? 0.0 : _minAltFt;

    final Duration totalTime = _tripSw.elapsed;
    final Duration stoppedTime = _stoppedSw.elapsed;
    final Duration rawMovingTime = totalTime - stoppedTime;
    final Duration movingTime =
        rawMovingTime.isNegative ? Duration.zero : rawMovingTime;

    final summary = TripSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _points.first.timestamp,
      totalTime: totalTime,
      stoppedTime: stoppedTime,
      movingTime: movingTime,
      maxSpeedMph: _maxSpeedMph,
      avgSpeedMph: currentAvgSpeedMph,
      altitudeGainFt: _altGainM * _kMToFt,
      maxAltitudeFt: maxAlt,
      minAltitudeFt: minAlt,
      distanceMiles: _totalDistM / _kMToMiles,
      points: List<TripPoint>.unmodifiable(_points),
    );

    await _closeCtrl();
    _tripStartTime = null;
    return summary;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESET
  // ─────────────────────────────────────────────────────────────────────────

  void _resetState() {
    _points.clear();
    _speedBuf.clear();

    _tripSw
      ..stop()
      ..reset();
    _stoppedSw
      ..stop()
      ..reset();
    _tickSw
      ..stop()
      ..reset();

    _lastRawPos = null;
    _lastEmittedSmoothedPos = null;
    _lastStoredSmoothedPos = null;
    _lastProcessedMs = null;
    _lastStoredMs = null;
    _lastValidAltM = null;

    _isAutoPaused = false;
    _slowSinceMs = null;
    _moveSinceMs = null;
    _rejectedJumpCount = 0;

    _kLat = null;
    _kLng = null;
    _kP = _kInitialVariance;

    _totalDistM = 0.0;
    _altGainM = 0.0;
    _maxSpeedMph = 0.0;
    _movingSpeedSum = 0.0;
    _movingCount = 0;

    _maxAltFt = _kEmptyMaxAlt;
    _minAltFt = _kEmptyMinAlt;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCATION SETTINGS — cached [PERF-2]
  // ─────────────────────────────────────────────────────────────────────────

  LocationSettings _locationSettings() {
    return _cachedLocationSettings ??= _buildLocationSettings();
  }

  LocationSettings _buildLocationSettings() {
    final int mode = SettingsService.instance.gpsAccuracyMode;
    final LocationAccuracy accuracy = _accuracyForMode(mode);
    final int distanceFilter = _distanceFilterForMode(mode);
    final Duration androidInterval = _androidIntervalForMode(mode);

    if (kIsWeb) {
      return LocationSettings(
        accuracy: mode == 2 ? LocationAccuracy.medium : LocationAccuracy.high,
        distanceFilter: math.max(2, distanceFilter).toInt(),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: accuracy,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: mode == 2,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          distanceFilter: distanceFilter,
        );

      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          intervalDuration: androidInterval,
          distanceFilter: distanceFilter,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'TrackPro AI Active',
            notificationText: 'Tracking your journey in real-time',
            enableWakeLock: true,
          ),
        );

      default:
        return LocationSettings(
          accuracy: mode == 2 ? LocationAccuracy.medium : LocationAccuracy.high,
          distanceFilter: math.max(2, distanceFilter).toInt(),
        );
    }
  }

  static LocationAccuracy _accuracyForMode(int mode) {
    switch (mode) {
      case 2:
        return LocationAccuracy.medium;
      case 1:
        return LocationAccuracy.high;
      default:
        return LocationAccuracy.bestForNavigation;
    }
  }

  static int _distanceFilterForMode(int mode) {
    switch (mode) {
      case 2:
        return 10;
      case 1:
        return 4;
      default:
        return 1;
    }
  }

  static Duration _androidIntervalForMode(int mode) {
    switch (mode) {
      case 2:
        return const Duration(seconds: 4);
      case 1:
        return const Duration(milliseconds: 1500);
      default:
        return const Duration(milliseconds: 800);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CORE POSITION HANDLER
  // ─────────────────────────────────────────────────────────────────────────

  void _handlePosition(Position pos) {
    if (!_isTracking) return;

    final int nowMs = _tickSw.elapsedMilliseconds;
    final DateTime wallNow = DateTime.now();

    // Throttle noisy platforms before expensive work using monotonic time.
    final int? previousProcessedMs = _lastProcessedMs;
    if (previousProcessedMs != null &&
        nowMs - previousProcessedMs < _kMinProcessMs) {
      return;
    }

    if (!_isUsable(pos)) return;

    // Point-jump detection must run BEFORE Kalman smoothing so a bad GPS fix
    // cannot poison the smoothing state or inflate distance/speed.
    if (_isLikelyJump(pos, nowMs, previousProcessedMs)) {
      _rejectedJumpCount++;
      return;
    }

    // From here the fix is accepted as a processed GPS update.
    _lastProcessedMs = nowMs;

    // Sanitise potentially-zero/null OEM timestamp for persisted route data.
    // This is intentionally separate from monotonic timing math.
    final DateTime timestamp = _sanitiseTimestamp(pos.timestamp, wallNow);

    final LatLng smoothed = _kalmanSmooth(pos);

    // Distance since the last accepted/emitted point. This affects total trip
    // distance, so keep the more accurate geodesic calculation here.
    final double gapM = _lastEmittedSmoothedPos == null
        ? 0.0
        : Geolocator.distanceBetween(
            _lastEmittedSmoothedPos!.latitude,
            _lastEmittedSmoothedPos!.longitude,
            smoothed.latitude,
            smoothed.longitude,
          );

    // Distance since the last stored point. This only gates storage thresholds,
    // so the fast approximation avoids another geodesic calculation per tick.
    final double storageGapM = _lastStoredSmoothedPos == null
        ? double.infinity
        : _fastDistanceM(
            _lastStoredSmoothedPos!.latitude,
            _lastStoredSmoothedPos!.longitude,
            smoothed.latitude,
            smoothed.longitude,
          );

    final double rawMph = _clampedSpeedMph(
      pos,
      gapM,
      nowMs,
      previousProcessedMs,
    );
    final double smoothMph = _speedBuf.push(rawMph);
    final double altFt = pos.altitude * _kMToFt;

    _updateAutoPause(rawMph, nowMs);

    if (!_isAutoPaused) {
      _updatePeaks(rawMph, altFt);
      _updateDistAndMovement(smoothed, smoothMph, rawMph, gapM);
      _updateAltGain(pos.altitude);
    } else {
      if (!_stoppedSw.isRunning) _stoppedSw.start();
    }

    final TripPoint point = TripPoint(
      position: smoothed,
      speedMph: smoothMph,
      altitudeFt: altFt,
      timestamp: timestamp,
      accuracyMeters: pos.accuracy,
    );

    if (_shouldStore(storageGapM, nowMs)) {
      _points.add(point);
      _lastStoredMs = nowMs;
      _lastStoredSmoothedPos = smoothed;
    }

    _lastRawPos = pos;
    _lastEmittedSmoothedPos = smoothed;

    _emit(point);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VALIDATION  [PERF-5] cheapest checks first
  // ─────────────────────────────────────────────────────────────────────────

  bool _isUsable(Position pos) {
    // 1. NaN / infinite  (cheapest — single bitmask in FPU)
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) return false;

    // 2. Range check
    if (pos.latitude.abs() > 90.0) return false;
    if (pos.longitude.abs() > 180.0) return false;

    // 3. Accuracy validity
    if (!pos.accuracy.isFinite || pos.accuracy <= 0.0) return false;

    // 4. Accuracy threshold (most expensive comparison — last)
    if (pos.accuracy > _kAccuracyThreshM) return false;

    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POINT JUMP DETECTION
  // ─────────────────────────────────────────────────────────────────────────

  bool _isLikelyJump(
    Position pos,
    int nowMs,
    int? previousProcessedMs,
  ) {
    final Position? previous = _lastRawPos;
    if (previous == null || previousProcessedMs == null) return false;

    final double rawGapM = _fastDistanceM(
      previous.latitude,
      previous.longitude,
      pos.latitude,
      pos.longitude,
    );

    if (!rawGapM.isFinite || rawGapM < _kJumpMinDistanceM) return false;

    final int deltaMs = nowMs - previousProcessedMs;
    final double deltaSeconds = deltaMs / 1000.0;
    if (!deltaSeconds.isFinite || deltaSeconds <= 0.25) return false;

    final double previousAccuracy =
        previous.accuracy.isFinite && previous.accuracy > 0.0
            ? previous.accuracy
            : _kAccuracyThreshM;
    final double currentAccuracy = pos.accuracy.isFinite && pos.accuracy > 0.0
        ? pos.accuracy
        : _kAccuracyThreshM;

    // Accuracy can legitimately move the reported point by some amount.
    // Subtract that budget so normal GPS noise does not get rejected.
    final double accuracyBudgetM =
        previousAccuracy + currentAccuracy + _kJumpAccuracyBufferM;
    final double effectiveJumpM =
        math.max(0.0, rawGapM - accuracyBudgetM).toDouble();

    final double impliedMph = (effectiveJumpM / deltaSeconds) * _kMpsToMph;

    final double reportedMph =
        (pos.speed.isFinite && pos.speed > 0.0) ? pos.speed * _kMpsToMph : 0.0;

    // Dynamic threshold: allow high reported speed, but reject impossible jumps.
    final double dynamicThresholdMph =
        math.max(_kJumpMaxSpeedMph, reportedMph * 2.2 + 25.0).toDouble();

    if (impliedMph > dynamicThresholdMph) {
      debugPrint(
        'GpsService point jump rejected: '
        '${rawGapM.toStringAsFixed(1)}m in '
        '${deltaSeconds.toStringAsFixed(1)}s, implied '
        '${impliedMph.toStringAsFixed(1)} mph, reported '
        '${reportedMph.toStringAsFixed(1)} mph',
      );
      return true;
    }

    // Extra guard for stopped/idle drift: when the sensor says the user is
    // basically stopped but the location suddenly jumps far away, reject it.
    if (reportedMph <= _kStoppedMph &&
        rawGapM >= _kStoppedJumpDistanceM &&
        effectiveJumpM >= _kStoppedJumpDistanceM) {
      debugPrint(
        'GpsService stopped jump rejected: '
        '${rawGapM.toStringAsFixed(1)}m while reported speed is '
        '${reportedMph.toStringAsFixed(1)} mph',
      );
      return true;
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SPEED
  // ─────────────────────────────────────────────────────────────────────────

  /// Accepts pre-computed gapM to avoid duplicate distanceBetween calls.
  /// Uses monotonic elapsed milliseconds to avoid system clock / NTP drift.
  double _clampedSpeedMph(
    Position pos,
    double gapM,
    int nowMs,
    int? previousProcessedMs,
  ) {
    double mps = pos.speed.isFinite && pos.speed >= 0.0 ? pos.speed : 0.0;

    // Derive speed from displacement if sensor reports zero.
    if (mps <= 0.0 &&
        _lastRawPos != null &&
        gapM > 0.0 &&
        previousProcessedMs != null) {
      final int deltaMs = nowMs - previousProcessedMs;
      if (deltaMs > 100) {
        mps = gapM / (deltaMs / 1000.0);
      }
    }

    return (mps * _kMpsToMph).clamp(0.0, _kMaxPlausibleMph);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO PAUSE / AUTO RESUME
  // ─────────────────────────────────────────────────────────────────────────

  void _updateAutoPause(double rawMph, int nowMs) {
    if (!_isTracking) return;

    if (rawMph <= _kAutoPauseEnterMph) {
      _slowSinceMs ??= nowMs;
      _moveSinceMs = null;
    } else if (rawMph >= _kAutoPauseResumeMph) {
      _moveSinceMs ??= nowMs;
      _slowSinceMs = null;
    } else {
      _slowSinceMs = null;
      _moveSinceMs = null;
    }

    if (!_isAutoPaused &&
        _slowSinceMs != null &&
        nowMs - _slowSinceMs! >= _kAutoPauseEnterDelay.inMilliseconds) {
      _enterAutoPause(nowMs);
      return;
    }

    if (_isAutoPaused &&
        _moveSinceMs != null &&
        nowMs - _moveSinceMs! >= _kAutoPauseResumeDelay.inMilliseconds) {
      _exitAutoPause();
    }
  }

  void _enterAutoPause(int nowMs) {
    if (_isAutoPaused) return;

    _isAutoPaused = true;
    _moveSinceMs = null;

    if (!_stoppedSw.isRunning) _stoppedSw.start();
  }

  void _exitAutoPause() {
    if (!_isAutoPaused) return;

    _isAutoPaused = false;
    _slowSinceMs = null;
    _moveSinceMs = null;

    if (_stoppedSw.isRunning) _stoppedSw.stop();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATS
  // ─────────────────────────────────────────────────────────────────────────

  void _updatePeaks(double rawMph, double altFt) {
    if (rawMph > _maxSpeedMph) _maxSpeedMph = rawMph;
    if (altFt.isFinite) {
      if (altFt > _maxAltFt) _maxAltFt = altFt;
      if (altFt < _minAltFt) _minAltFt = altFt;
    }
  }

  /// [FIX-2] Stopwatch decision deferred until a previous point exists.
  void _updateDistAndMovement(
    LatLng smoothed,
    double smoothMph,
    double rawMph,
    double gapM,
  ) {
    if (_lastEmittedSmoothedPos == null) {
      // First point — no decision yet, but start stopped clock tentatively
      if (!_stoppedSw.isRunning) _stoppedSw.start();
      return;
    }

    final bool moving = rawMph >= _kStoppedMph && gapM > 1.0;

    if (moving) {
      _totalDistM += gapM;
      _movingSpeedSum += smoothMph;
      _movingCount++;
      if (_stoppedSw.isRunning) _stoppedSw.stop();
    } else {
      if (!_stoppedSw.isRunning) _stoppedSw.start();
    }
  }

  void _updateAltGain(double altM) {
    if (!altM.isFinite) return;
    final prev = _lastValidAltM;
    if (prev == null) {
      _lastValidAltM = altM;
      return;
    }
    final diff = altM - prev;
    if (diff.abs() > _kAltJitterM) {
      if (diff > 0.0) _altGainM += diff;
      _lastValidAltM = altM;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STORAGE GATE  [FIX-7]
  // ─────────────────────────────────────────────────────────────────────────

  bool _shouldStore(double gapM, int nowMs) {
    if (_points.isEmpty) return true;

    final double minDistance =
        _isAutoPaused ? _kAutoPausedMinStorageDistM : _kMinStorageDistM;
    final int minSeconds =
        _isAutoPaused ? _kAutoPausedMinStorageSecs : _kMinStorageSecs;

    final bool distTrigger = gapM.isFinite && gapM >= minDistance;

    final int? lastMs = _lastStoredMs;
    final bool timeTrigger =
        lastMs == null || nowMs - lastMs >= minSeconds * 1000;

    return distTrigger || timeTrigger;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KALMAN SMOOTHER  [FIX-6]
  //
  // Standard scalar Kalman (one filter per axis) with variance in m²:
  //   P_pred  = P + Q
  //   K       = P_pred / (P_pred + R)
  //   x_new   = x + K * (z - x)
  //   P_new   = (1 - K) * P_pred
  //
  // R = accuracy² (measurement noise variance in m²)
  // Q = _kProcessNoise (process noise variance in m²)
  //
  // The LatLng deltas are tiny (~10⁻⁵°) so applying the gain directly to
  // degrees works correctly — the ratio K is dimensionless.
  // ─────────────────────────────────────────────────────────────────────────

  LatLng _kalmanSmooth(Position pos) {
    if (_kLat == null || _kLng == null) {
      _kLat = pos.latitude;
      _kLng = pos.longitude;
      _kP = math.max(pos.accuracy * pos.accuracy, _kInitialVariance);
      return LatLng(pos.latitude, pos.longitude);
    }

    // Predict
    final double pPred = _kP + _kProcessNoise;

    // Measurement noise (variance = accuracy²)
    final double r = pos.accuracy.clamp(1.0, 100.0);
    final double R = r * r;

    // Kalman gain
    final double K = pPred / (pPred + R);

    // Update state. Longitude uses the shortest angular delta so crossing
    // the antimeridian (180 / -180) does not pull the filter across the globe.
    final double lngDelta = (pos.longitude - _kLng! + 180.0) % 360.0 - 180.0;
    _kLat = _kLat! + K * (pos.latitude - _kLat!);
    _kLng = _normaliseLongitude(_kLng! + K * lngDelta);
    _kP = (1.0 - K) * pPred;

    return LatLng(_kLat!, _kLng!);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static double _fastDistanceM(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    if (!lat1.isFinite || !lng1.isFinite || !lat2.isFinite || !lng2.isFinite) {
      return double.infinity;
    }

    // Fast equirectangular approximation. Accurate enough for small threshold
    // checks and much cheaper than full geodesic distance.
    const double earthRadiusM = 6371008.8;
    final double lat1Rad = lat1 * math.pi / 180.0;
    final double lat2Rad = lat2 * math.pi / 180.0;
    final double dLat = lat2Rad - lat1Rad;
    final double dLngDeg = (lng2 - lng1 + 180.0) % 360.0 - 180.0;
    final double dLng = dLngDeg * math.pi / 180.0;
    final double x = dLng * math.cos((lat1Rad + lat2Rad) * 0.5);
    return earthRadiusM * math.sqrt(x * x + dLat * dLat);
  }

  static double _normaliseLongitude(double longitude) {
    final double normalized = (longitude + 180.0) % 360.0 - 180.0;
    // Preserve +180 for inputs that land exactly on the antimeridian instead
    // of returning -180 for every positive wrap.
    if (normalized == -180.0 && longitude > 0.0) return 180.0;
    return normalized;
  }

  /// [FIX-5] Some OEM drivers return epoch-zero for pos.timestamp.
  static DateTime _sanitiseTimestamp(DateTime? ts, DateTime fallback) {
    // Treat missing or pre-2020 OEM timestamps as invalid.
    if (ts == null || ts.year < 2020) return fallback;
    return ts;
  }

  /// [ROB-2] Drop late events after stop.
  void _emit(TripPoint point) {
    final ctrl = _pointCtrl;
    if (ctrl == null || ctrl.isClosed || !_isTracking) return;
    try {
      ctrl.add(point);
    } catch (e, st) {
      debugPrint('GpsService._emit: $e\n$st');
    }
  }

  Future<void> _cancelSub() async {
    final sub = _posSub;
    _posSub = null;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (e, st) {
      debugPrint('GpsService._cancelSub: $e\n$st');
    }
  }

  Future<void> _closeCtrl() async {
    final ctrl = _pointCtrl;
    _pointCtrl = null;
    if (ctrl == null || ctrl.isClosed) return;
    try {
      await ctrl.close();
    } catch (e, st) {
      debugPrint('GpsService._closeCtrl: $e\n$st');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSE  [FIX-8] async to allow proper await
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    if (_isAutoPaused) {
      _exitAutoPause();
    }
    _isTracking = false;
    _tripSw.stop();
    _stoppedSw.stop();
    _tickSw.stop();
    await _cancelSub();
    await _closeCtrl();
    _tripStartTime = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CIRCULAR BUFFER — O(1) push + running mean  [PERF-1]
// ─────────────────────────────────────────────────────────────────────────────

class _CircularBuffer {
  _CircularBuffer(this._capacity)
      : _buf = List<double>.filled(_capacity, 0.0),
        _head = 0,
        _count = 0,
        _sum = 0.0;

  final int _capacity;
  final List<double> _buf;
  int _head;
  int _count;
  double _sum;

  /// Push a value; returns the new running mean.
  double push(double value) {
    if (_count == _capacity) {
      // Evict the oldest value
      _sum -= _buf[_head];
    } else {
      _count++;
    }
    _buf[_head] = value;
    _sum += value;
    _head = (_head + 1) % _capacity;
    return _count == 0 ? 0.0 : _sum / _count;
  }

  void clear() {
    _buf.fillRange(0, _capacity, 0.0);
    _head = 0;
    _count = 0;
    _sum = 0.0;
  }
}
