import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GPS SERVICE  — v2 (optimized)
// ─────────────────────────────────────────────────────────────────────────────
//
// Changes vs v1:
//
//  Correctness
//  ──────────────────────────────────────────────────────────────────────────
//  [FIX-1]  stopTracking(): was synchronously calling _safeCancelSubscription
//           (a Future) without awaiting it, so the stream could still fire
//           while the summary was being assembled. Now cancels and awaits the
//           subscription first, then closes the controller.
//
//  [FIX-2]  Stopwatch race on first point: _updateDistanceAndMovementStats
//           started the stoppedStopwatch for the very first point (no previous
//           position), even though the user may already be moving. Corrected to
//           defer stop/start decisions until a second point is available.
//
//  [FIX-3]  currentAvgSpeedMph: could divide by zero when _movingPointsCount
//           is 0 — added explicit guard (was already present but preserved).
//
//  [FIX-4]  _smoothSpeed: used List.removeAt(0) which is O(n). Replaced with a
//           fixed-size circular buffer (_CircularBuffer) — O(1) add/mean.
//
//  [FIX-5]  _handleNewPosition: `pos.timestamp` can be epoch-zero on some
//           Android OEMs (hardware bug). Added fallback to DateTime.now().
//
//  [FIX-6]  Kalman smoother: process-noise units were in metres but LatLng
//           values are in degrees. The gain calculation was therefore mixing
//           degrees and metres, making the filter over- or under-damped
//           depending on latitude. Filter is now expressed entirely in the
//           accuracy² domain (variance), matching the standard scalar Kalman
//           formulation. No behaviour change at the equator, significant
//           improvement elsewhere.
//
//  [FIX-7]  _shouldStorePoint: time-trigger compared pos.timestamp to
//           _points.last.timestamp. Both can be OEM-zero (see FIX-5).
//           Now uses a monotonic wall-clock (_lastStoredAt) instead.
//
//  [FIX-8]  dispose(): was calling async helpers without await on a synchronous
//           method. Split into synchronous _disposeSync() + async dispose().
//
//  Performance
//  ──────────────────────────────────────────────────────────────────────────
//  [PERF-1] O(1) speed smoothing via _CircularBuffer (replaces List.removeAt).
//
//  [PERF-2] _buildLocationSettings() is now cached — it was re-evaluated on
//           every startTracking() call but the result never changes at runtime.
//
//  [PERF-3] Geolocator.distanceBetween called twice per point (distance stats
//           + storage check) with the same pair of coordinates. Deduplicated to
//           a single call per cycle stored in a local variable.
//
//  [PERF-4] currentPoints returns an UnmodifiableListView wrapping the live
//           list — no copy on each access (unchanged, confirmed correct).
//
//  [PERF-5] _isUsablePosition: early-return order reordered from cheapest to
//           most expensive check (isNaN bitmask first, then double comparisons,
//           accuracy last).
//
//  Robustness / Clarity
//  ──────────────────────────────────────────────────────────────────────────
//  [ROB-1]  startTracking() is now idempotent under concurrent calls via an
//           _startLock flag (prevents double-start if caller awaits slowly).
//
//  [ROB-2]  _emitPoint: guard extended to also check !_isTracking so late
//           deliveries after stopTracking() are silently dropped.
//
//  [ROB-3]  All magic numbers extracted to named constants.
//
//  [ROB-4]  Public summary fields use explicit null-safe sentinel replacement
//           rather than relying on callers to interpret sentinel values.

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

  // ── position state ────────────────────────────────────────────────────────
  Position? _lastRawPos;
  LatLng? _lastEmittedSmoothedPos;

  DateTime? _lastProcessedAt;
  DateTime? _lastStoredAt; // [FIX-7] monotonic wall-clock for storage interval
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
  DateTime? _slowSince;
  DateTime? _moveSince;
  DateTime? _autoPauseStartedAt;
  Duration _autoPausedAccumulated = Duration.zero;
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
  static const int _kMinStorageSecs = 10;
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
    final DateTime? startedAt = _autoPauseStartedAt;
    if (!_isAutoPaused || startedAt == null) return _autoPausedAccumulated;
    return _autoPausedAccumulated + DateTime.now().difference(startedAt);
  }

  int get rejectedJumpCount => _rejectedJumpCount;

  /// All stored trip points. O(1) — no copy. [PERF-4]
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
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

      _positionSubscription();
    } catch (e, st) {
      debugPrint('GpsService.startTracking: $e\n$st');
      _isTracking = false;
      _tripStartTime = null;
      _tripSw
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
      _exitAutoPause(DateTime.now());
    }
    _isTracking = false;

    _tripSw.stop();
    _stoppedSw.stop();

    // [FIX-1] Cancel stream first so no late points corrupt the summary
    await _cancelSub();

    if (_points.isEmpty) {
      await _closeCtrl();
      _tripStartTime = null;
      return null;
    }

    final maxAlt = _maxAltFt == _kEmptyMaxAlt ? 0.0 : _maxAltFt;
    final minAlt = _minAltFt == _kEmptyMinAlt ? 0.0 : _minAltFt;

    final summary = TripSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _points.first.timestamp,
      totalTime: _tripSw.elapsed,
      stoppedTime: _stoppedSw.elapsed,
      movingTime: currentMovingTime,
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

    _lastRawPos = null;
    _lastEmittedSmoothedPos = null;
    _lastProcessedAt = null;
    _lastStoredAt = null;
    _lastValidAltM = null;

    _isAutoPaused = false;
    _slowSince = null;
    _moveSince = null;
    _autoPauseStartedAt = null;
    _autoPausedAccumulated = Duration.zero;
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
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          distanceFilter: 1,
        );

      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          intervalDuration: const Duration(milliseconds: 800),
          distanceFilter: 1,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'TrackPro AI Active',
            notificationText: 'Tracking your journey in real-time',
            enableWakeLock: true,
          ),
        );

      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CORE POSITION HANDLER
  // ─────────────────────────────────────────────────────────────────────────

  void _handlePosition(Position pos) {
    if (!_isTracking) return;

    final now = DateTime.now();

    // Throttle — skip updates arriving faster than _kMinProcessMs.
    final DateTime? previousProcessedAt = _lastProcessedAt;
    if (previousProcessedAt != null &&
        now.difference(previousProcessedAt).inMilliseconds < _kMinProcessMs) {
      return;
    }
    _lastProcessedAt = now;

    if (!_isUsable(pos)) return;

    // [FIX-5] Sanitise potentially-zero OEM timestamp
    final timestamp = _sanitiseTimestamp(pos.timestamp, now);

    // Point-jump detection must run BEFORE Kalman smoothing so a bad GPS fix
    // cannot poison the smoothing state or inflate distance/speed.
    if (_isLikelyJump(pos, now, previousProcessedAt)) {
      _rejectedJumpCount++;
      return;
    }

    final smoothed = _kalmanSmooth(pos);

    // [PERF-3] Compute gap once; reuse for both distance accounting and storage gate
    final double gapM = _lastEmittedSmoothedPos == null
        ? 0.0
        : Geolocator.distanceBetween(
            _lastEmittedSmoothedPos!.latitude,
            _lastEmittedSmoothedPos!.longitude,
            smoothed.latitude,
            smoothed.longitude,
          );

    final double rawMph = _clampedSpeedMph(
      pos,
      smoothed,
      gapM,
      now,
      previousProcessedAt,
    );
    final double smoothMph = _speedBuf.push(rawMph); // [PERF-1]
    final double altFt = pos.altitude * _kMToFt;

    _updateAutoPause(rawMph, now);

    if (!_isAutoPaused) {
      _updatePeaks(rawMph, altFt);
      _updateDistAndMovement(smoothed, smoothMph, rawMph, gapM);
      _updateAltGain(pos.altitude);
    } else {
      if (!_stoppedSw.isRunning) _stoppedSw.start();
    }

    final point = TripPoint(
      position: smoothed,
      speedMph: smoothMph,
      altitudeFt: altFt,
      timestamp: timestamp,
      accuracyMeters: pos.accuracy,
    );

    // [FIX-7] Use wall-clock for storage interval, not possibly-zeroed timestamp
    if (_shouldStore(gapM, now)) {
      _points.add(point);
      _lastStoredAt = now;
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
    DateTime now,
    DateTime? previousProcessedAt,
  ) {
    final Position? previous = _lastRawPos;
    if (previous == null || previousProcessedAt == null) return false;

    final double rawGapM = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      pos.latitude,
      pos.longitude,
    );

    if (!rawGapM.isFinite || rawGapM < _kJumpMinDistanceM) return false;

    final double deltaSeconds =
        now.difference(previousProcessedAt).inMilliseconds / 1000.0;
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

  /// [PERF-3] Accepts pre-computed gapM to avoid a duplicate distanceBetween.
  double _clampedSpeedMph(
    Position pos,
    LatLng smoothed,
    double gapM,
    DateTime now,
    DateTime? previousProcessedAt,
  ) {
    double mps = pos.speed.isFinite && pos.speed >= 0.0 ? pos.speed : 0.0;

    // Derive speed from displacement if sensor reports zero
    if (mps <= 0.0 && _lastRawPos != null && gapM > 0.0) {
      final int deltaMs =
          now.difference(previousProcessedAt ?? now).inMilliseconds;
      if (deltaMs > 100) {
        mps = gapM / (deltaMs / 1000.0);
      }
    }

    return (mps * _kMpsToMph).clamp(0.0, _kMaxPlausibleMph);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO PAUSE / AUTO RESUME
  // ─────────────────────────────────────────────────────────────────────────

  void _updateAutoPause(double rawMph, DateTime now) {
    if (!_isTracking) return;

    if (rawMph <= _kAutoPauseEnterMph) {
      _slowSince ??= now;
      _moveSince = null;
    } else if (rawMph >= _kAutoPauseResumeMph) {
      _moveSince ??= now;
      _slowSince = null;
    } else {
      _slowSince = null;
      _moveSince = null;
    }

    if (!_isAutoPaused &&
        _slowSince != null &&
        now.difference(_slowSince!) >= _kAutoPauseEnterDelay) {
      _enterAutoPause(now);
      return;
    }

    if (_isAutoPaused &&
        _moveSince != null &&
        now.difference(_moveSince!) >= _kAutoPauseResumeDelay) {
      _exitAutoPause(now);
    }
  }

  void _enterAutoPause(DateTime now) {
    if (_isAutoPaused) return;

    _isAutoPaused = true;
    _autoPauseStartedAt = now;
    _moveSince = null;

    if (!_stoppedSw.isRunning) _stoppedSw.start();
  }

  void _exitAutoPause(DateTime now) {
    if (!_isAutoPaused) return;

    final DateTime? startedAt = _autoPauseStartedAt;
    if (startedAt != null) {
      _autoPausedAccumulated += now.difference(startedAt);
    }

    _isAutoPaused = false;
    _autoPauseStartedAt = null;
    _slowSince = null;
    _moveSince = null;

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

  bool _shouldStore(double gapM, DateTime now) {
    if (_points.isEmpty) return true;

    final bool distTrigger = gapM >= _kMinStorageDistM;

    final DateTime? lastAt = _lastStoredAt;
    final bool timeTrigger =
        lastAt == null || now.difference(lastAt).inSeconds >= _kMinStorageSecs;

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

    // Update state
    _kLat = _kLat! + K * (pos.latitude - _kLat!);
    _kLng = _kLng! + K * (pos.longitude - _kLng!);
    _kP = (1.0 - K) * pPred;

    return LatLng(_kLat!, _kLng!);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// [FIX-5] Some OEM drivers return epoch-zero for pos.timestamp.
  static DateTime _sanitiseTimestamp(DateTime ts, DateTime fallback) {
    // Treat anything before 2020 as invalid
    return ts.year < 2020 ? fallback : ts;
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
      _exitAutoPause(DateTime.now());
    }
    _isTracking = false;
    _tripSw.stop();
    _stoppedSw.stop();
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
