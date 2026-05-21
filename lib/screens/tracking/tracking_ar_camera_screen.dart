// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/mapbox_route_models.dart';
import '../../models/ar_guidance_models.dart';
import '../../models/ai_detection_models.dart';
import '../../services/settings_service.dart';
import '../../services/ai_object_tracking_service.dart';
import '../../services/ai_road_condition_service.dart';
import '../../services/ai_tracking_brain_service.dart';
import '../../services/ai_scene_understanding_service.dart';
import '../../services/ai_tflite_object_detection_service.dart';
import '../../theme/app_theme.dart';

const Color _kArBlue = AppColors.blue;
const Color _kArBlueSoft = AppColors.blueSoft;
const Color _kArGreen = AppColors.green;
const Color _kArRed = AppColors.red;
const Color _kArGold = Color(0xFFFFD54F);
const Color _kArSurface = Color(0xDD05070A);
const Distance _kArDistance = Distance();

const double _kArSideInset = 12.0;
const double _kArMaxContentWidth = 420.0;
const Duration _kArPanelAnim = Duration(milliseconds: 260);
const Duration _kArFastAnim = Duration(milliseconds: 160);
const Duration _kArSlowAnim = Duration(milliseconds: 420);
const Curve _kArEase = Curves.easeOutCubic;
const double _kArMinTopPadding = 8.0;
const double _kArMinBottomPadding = 14.0;
const double _kArBottomHudGap = 10.0;
const Duration _kArSceneUpdateInterval = Duration(milliseconds: 420);
const Duration _kArObjectUpdateInterval = Duration(milliseconds: 520);
const double _kArSceneMotionDelta = 0.45;
const double _kArSceneBearingDelta = 4.0;

enum _ArMotionStability {
  steady,
  moving,
  shaking,
}

extension _ArMotionStabilityX on _ArMotionStability {
  String get label {
    switch (this) {
      case _ArMotionStability.steady:
        return 'Stable';
      case _ArMotionStability.moving:
        return 'Moving';
      case _ArMotionStability.shaking:
        return 'Hold steady';
    }
  }

  Color get color {
    switch (this) {
      case _ArMotionStability.steady:
        return _kArGreen;
      case _ArMotionStability.moving:
        return _kArGold;
      case _ArMotionStability.shaking:
        return _kArRed;
    }
  }

  IconData get icon {
    switch (this) {
      case _ArMotionStability.steady:
        return CupertinoIcons.checkmark_shield_fill;
      case _ArMotionStability.moving:
        return CupertinoIcons.hand_raised_fill;
      case _ArMotionStability.shaking:
        return CupertinoIcons.exclamationmark_triangle_fill;
    }
  }
}

enum _ArHudMode {
  full,
  minimal,
}

enum _ArModelStatus {
  loading,
  ready,
  webFallback,
  failed,
}

extension _ArModelStatusX on _ArModelStatus {
  String get label {
    switch (this) {
      case _ArModelStatus.loading:
        return 'MODEL LOAD';
      case _ArModelStatus.ready:
        return 'MODEL OK';
      case _ArModelStatus.webFallback:
        return 'WEB AUTO';
      case _ArModelStatus.failed:
        return 'MODEL FAIL';
    }
  }

  Color get color {
    switch (this) {
      case _ArModelStatus.loading:
        return _kArGold;
      case _ArModelStatus.ready:
        return _kArGreen;
      case _ArModelStatus.webFallback:
        return _kArBlueSoft;
      case _ArModelStatus.failed:
        return _kArRed;
    }
  }

  IconData get icon {
    switch (this) {
      case _ArModelStatus.loading:
        return CupertinoIcons.hourglass;
      case _ArModelStatus.ready:
        return CupertinoIcons.checkmark_shield_fill;
      case _ArModelStatus.webFallback:
        return CupertinoIcons.globe;
      case _ArModelStatus.failed:
        return CupertinoIcons.exclamationmark_triangle_fill;
    }
  }
}

extension _ArHudModeX on _ArHudMode {
  _ArHudMode get next {
    switch (this) {
      case _ArHudMode.full:
        return _ArHudMode.minimal;
      case _ArHudMode.minimal:
        return _ArHudMode.full;
    }
  }

  IconData get icon {
    switch (this) {
      case _ArHudMode.full:
        return CupertinoIcons.eye_fill;
      case _ArHudMode.minimal:
        return CupertinoIcons.eye_slash_fill;
    }
  }

  String get semanticsLabel {
    switch (this) {
      case _ArHudMode.full:
        return 'Switch to minimal AR HUD';
      case _ArHudMode.minimal:
        return 'Switch to full AR HUD';
    }
  }
}

enum _ArVisualMode {
  street,
  markerless,
}

extension _ArVisualModeX on _ArVisualMode {
  _ArVisualMode get next {
    switch (this) {
      case _ArVisualMode.street:
        return _ArVisualMode.markerless;
      case _ArVisualMode.markerless:
        return _ArVisualMode.street;
    }
  }

  String get label {
    switch (this) {
      case _ArVisualMode.street:
        return 'Street AR';
      case _ArVisualMode.markerless:
        return 'Markerless';
    }
  }

  IconData get icon {
    switch (this) {
      case _ArVisualMode.street:
        return CupertinoIcons.location_north_fill;
      case _ArVisualMode.markerless:
        return CupertinoIcons.cube_box_fill;
    }
  }
}

class TrackingArCameraScreen extends StatefulWidget {
  const TrackingArCameraScreen({
    super.key,
    required this.speedN,
    required this.compassN,
    required this.headingN,
    required this.accuracyN,
    required this.batteryN,
    required this.batteryStateN,
    required this.coachTipN,
    required this.posN,
    required this.plannedRouteN,
    required this.settings,
  });

  final ValueNotifier<double> speedN;
  final ValueNotifier<double> compassN;
  final ValueNotifier<double> headingN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<BatteryState?> batteryStateN;
  final ValueNotifier<String> coachTipN;
  final ValueNotifier<LatLng?> posN;
  final ValueNotifier<PlannedRoute?> plannedRouteN;
  final SettingsService settings;

  @override
  State<TrackingArCameraScreen> createState() => _TrackingArCameraScreenState();
}

class _TrackingArCameraScreenState extends State<TrackingArCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  bool _loading = true;
  bool _cameraReady = false;
  bool _cameraInitInProgress = false;
  bool _torchOn = false;
  bool _autoObjectTracking = true;
  bool _overlayCollapsed = false;
  final ValueNotifier<_ArModelStatus> _modelStatusN =
      ValueNotifier<_ArModelStatus>(_ArModelStatus.webFallback);
  _ArHudMode _hudMode = _ArHudMode.full;
  _ArVisualMode _visualMode = _ArVisualMode.street;
  final ValueNotifier<_ArMotionStability> _motionStabilityN =
      ValueNotifier<_ArMotionStability>(_ArMotionStability.steady);
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  DateTime? _lastMotionSampleAt;
  double _motionEma = 0.0;
  String? _error;
  int _selectedCameraIndex = 0;

  late final AiObjectTrackingService _objectTrackingService =
      AiObjectTrackingService();
  late final ValueNotifier<AiTrackedObject?> _trackedObjectN =
      _objectTrackingService.trackedObjectN;
  late final AiRoadConditionService _roadConditionService =
      AiRoadConditionService();
  late final ValueNotifier<AiRoadConditionSnapshot> _roadConditionN =
      _roadConditionService.roadConditionN;
  late final AiTrackingBrainService _trackingBrainService =
      const AiTrackingBrainService();
  final ValueNotifier<AiTrackingBrainResult> _aiGuardN =
      ValueNotifier<AiTrackingBrainResult>(AiTrackingBrainResult.idle());
  late final AiSceneUnderstandingService _sceneService =
      AiSceneUnderstandingService();
  late final ValueNotifier<ArSceneSnapshot> _sceneN = _sceneService.sceneN;

  late final AiTfliteObjectDetectionService _tfliteDetector =
      AiTfliteObjectDetectionService();
  late final ValueNotifier<AiDetectionResult> _detectionN =
      _tfliteDetector.resultN;

  DateTime? _lastTfliteFrameAt;
  Timer? _objectTrackingTimer;
  DateTime? _lastAiBrainAt;
  DateTime? _lastAiGuardHapticAt;
  DateTime? _lastObjectUpdateAt;
  DateTime? _lastSceneTickAt;
  double? _lastSceneMotionScore;
  double? _lastSceneBearing;
  double? _lastSceneDistance;
  bool? _lastSceneHasRoute;

  late final Listenable _overlayListenable = Listenable.merge(<Listenable>[
    widget.speedN,
    widget.compassN,
    widget.headingN,
    widget.accuracyN,
    widget.batteryN,
    widget.batteryStateN,
    widget.coachTipN,
    widget.posN,
    widget.plannedRouteN,
    _motionStabilityN,
    _trackedObjectN,
    _roadConditionN,
    _aiGuardN,
    _sceneN,
    _detectionN,
    _modelStatusN,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initMotionSensor();
    _startObjectTrackingTicker();
    _sceneService.start(mode: ArEnvironmentMode.street);
    unawaited(_initTfliteDetector());
    unawaited(_initCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _cameraController;
    if (controller == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(controller.dispose());
      _cameraController = null;
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _torchOn = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_accelerometerSub?.cancel());
    _motionStabilityN.dispose();
    _objectTrackingTimer?.cancel();
    _objectTrackingService.dispose();
    _roadConditionService.dispose();
    _tfliteDetector.dispose();
    _sceneService.dispose();
    _aiGuardN.dispose();
    _modelStatusN.dispose();

    final CameraController? controller = _cameraController;
    if (controller != null) {
      unawaited(() async {
        try {
          if (controller.value.isInitialized) {
            if (controller.value.isStreamingImages) {
              await controller.stopImageStream();
            }
            await controller.setFlashMode(FlashMode.off);
          }
        } catch (_) {
          // Camera may already be disposed by the platform lifecycle.
        }
        await controller.dispose();
      }());
    }

    super.dispose();
  }

  Future<void> _initTfliteDetector() async {
    await _tfliteDetector.load();
  }

  void _startObjectTrackingTicker() {
    _objectTrackingTimer?.cancel();
    _objectTrackingTimer = Timer.periodic(
      const Duration(milliseconds: 260),
      (_) => _updateObjectTrackingEstimate(),
    );
  }

  bool _shouldUpdateScene({
    required DateTime now,
    required bool hasRoute,
    required double distanceMeters,
    required double relativeBearing,
    required double motionScore,
  }) {
    final DateTime? lastAt = _lastSceneTickAt;
    if (lastAt == null) return true;

    if (now.difference(lastAt) >= _kArSceneUpdateInterval) return true;
    if (_lastSceneHasRoute != hasRoute) return true;

    final double lastMotion = _lastSceneMotionScore ?? motionScore;
    final double lastBearing = _lastSceneBearing ?? relativeBearing;
    final double lastDistance = _lastSceneDistance ?? distanceMeters;

    if ((motionScore - lastMotion).abs() >= _kArSceneMotionDelta) return true;
    if ((relativeBearing - lastBearing).abs() >= _kArSceneBearingDelta) {
      return true;
    }
    if ((distanceMeters - lastDistance).abs() >= 3.0) return true;

    return false;
  }

  Future<void> _handleTfliteCameraImage(CameraImage image) async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastTfliteFrameAt;

    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 650)) {
      return;
    }

    _lastTfliteFrameAt = now;
    await _tfliteDetector.detect(image);
  }

  void _updateObjectTrackingEstimate() {
    if (!mounted) return;

    final DateTime now = DateTime.now();
    final DateTime? lastObjectAt = _lastObjectUpdateAt;
    if (lastObjectAt != null &&
        now.difference(lastObjectAt) < _kArObjectUpdateInterval) {
      return;
    }
    _lastObjectUpdateAt = now;

    final Size screen = MediaQuery.sizeOf(context);
    final double speedKmh = widget.settings.toDisplaySpeed(widget.speedN.value);
    final double accuracy = widget.accuracyN.value;
    final double motionScore = _motionEma;

    _objectTrackingService.updateAutoTracking(
      screen: screen,
      userSpeedKmh: speedKmh,
      gpsAccuracyMeters: accuracy,
      motionScore: motionScore,
      timestamp: now,
      enabled: _autoObjectTracking,
    );

    _objectTrackingService.updateTelemetry(
      userSpeedKmh: speedKmh,
      gpsAccuracyMeters: accuracy,
      motionScore: motionScore,
      timestamp: now,
    );

    final bool hasRoute = (widget.plannedRouteN.value?.points.length ?? 0) >= 2;
    final double distanceMeters = _estimateNextTargetMeters();
    final double relativeBearing = _estimateRelativeBearing();

    if (_shouldUpdateScene(
      now: now,
      hasRoute: hasRoute,
      distanceMeters: distanceMeters,
      relativeBearing: relativeBearing,
      motionScore: motionScore,
    )) {
      _lastSceneTickAt = now;
      _lastSceneHasRoute = hasRoute;
      _lastSceneDistance = distanceMeters;
      _lastSceneBearing = relativeBearing;
      _lastSceneMotionScore = motionScore;

      final List<AiSceneObject> detectedObjects = _detectionN.value.detections
          .map((AiDetection detection) => detection.toSceneObject())
          .toList(growable: false);

      _sceneService.tick(
        hasRoute: hasRoute,
        distanceMeters: distanceMeters,
        relativeBearing: relativeBearing,
        instruction: widget.coachTipN.value,
        motionScore: motionScore,
        gpsAccuracyMeters: accuracy,
        detectedObjects: detectedObjects,
      );
    }

    _refreshAiGuard();
  }

  double _estimateRelativeBearing() {
    final LatLng? position = widget.posN.value;
    final PlannedRoute? route = widget.plannedRouteN.value;
    final List<LatLng> points = route?.points ?? const <LatLng>[];

    if (position == null || points.length < 2) return 0.0;

    double bestDistance = double.infinity;
    int bestIndex = 0;
    final int step = points.length > 180
        ? 3
        : points.length > 80
            ? 2
            : 1;

    for (int i = 0; i < points.length; i += step) {
      final LatLng point = points[i];
      final double distance = _kArDistance.as(
        LengthUnit.Meter,
        position,
        point,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    final int targetIndex = (bestIndex + 5).clamp(0, points.length - 1).toInt();
    final LatLng target = points[targetIndex];
    final double targetBearing = _normDeg(
      _kArDistance.bearing(position, target),
    );

    return _signedHeadingDelta(_normDeg(widget.headingN.value), targetBearing);
  }

  double _estimateNextTargetMeters() {
    final LatLng? position = widget.posN.value;
    final PlannedRoute? route = widget.plannedRouteN.value;
    final List<LatLng> points = route?.points ?? const <LatLng>[];

    if (position == null || points.length < 2) return 0.0;

    double bestDistance = double.infinity;
    int bestIndex = 0;
    final int step = points.length > 180
        ? 3
        : points.length > 80
            ? 2
            : 1;

    for (int i = 0; i < points.length; i += step) {
      final LatLng point = points[i];
      final double distance = _kArDistance.as(
        LengthUnit.Meter,
        position,
        point,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    final int targetIndex = (bestIndex + 5).clamp(0, points.length - 1).toInt();
    final LatLng target = points[targetIndex];

    return _kArDistance.as(LengthUnit.Meter, position, target);
  }

  void _handleObjectTrackingTap(TapDownDetails details) {
    final Size screen = MediaQuery.sizeOf(context);
    if (screen.width <= 0 || screen.height <= 0) return;

    HapticFeedback.selectionClick();
    _objectTrackingService.lockAtScreenPoint(
      details.localPosition,
      screen,
      userSpeedKmh: widget.settings.toDisplaySpeed(widget.speedN.value),
      timestamp: DateTime.now(),
    );
    _refreshAiGuard(force: true);
  }

  void _clearObjectTracking() {
    HapticFeedback.lightImpact();
    _objectTrackingService.clearLock();
    _refreshAiGuard(force: true);
  }

  void _toggleAutoObjectTracking() {
    HapticFeedback.selectionClick();
    setState(() => _autoObjectTracking = !_autoObjectTracking);
    if (!_autoObjectTracking) {
      _objectTrackingService.clearLock();
    }
    _refreshAiGuard(force: true);
  }

  void _toggleVisualMode() {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _visualMode = _visualMode.next);
  }

  void _toggleOverlayCollapsed() {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _overlayCollapsed = !_overlayCollapsed);
  }

  void _toggleArEnvironmentMode() {
    final ArEnvironmentMode next = _sceneN.value.environmentMode.next;
    HapticFeedback.selectionClick();
    _sceneService.setMode(next);
  }

  void _resetArScan() {
    HapticFeedback.lightImpact();
    _sceneService.resetScan();
  }

  void _initMotionSensor() {
    unawaited(_accelerometerSub?.cancel());

    try {
      _accelerometerSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 220),
      ).listen(
        _handleAccelerometerEvent,
        onError: (Object error, StackTrace stackTrace) {},
        cancelOnError: false,
      );
    } catch (error) {
      // Ignored in production.
    }
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    if (!mounted) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastMotionSampleAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 170)) {
      return;
    }
    _lastMotionSampleAt = now;

    final double magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    final double motion = (magnitude - 9.80665).abs();
    _motionEma =
        _motionEma == 0.0 ? motion : (_motionEma * 0.72 + motion * 0.28);

    final _ArMotionStability next;
    if (_motionEma >= 4.8) {
      next = _ArMotionStability.shaking;
    } else if (_motionEma >= 2.0) {
      next = _ArMotionStability.moving;
    } else {
      next = _ArMotionStability.steady;
    }

    _roadConditionService.updateAccelerometer(
      x: event.x,
      y: event.y,
      z: event.z,
      userSpeedKmh: widget.settings.toDisplaySpeed(widget.speedN.value),
      timestamp: now,
    );

    if (_motionStabilityN.value != next) {
      _motionStabilityN.value = next;
    }
    _refreshAiGuard();
  }

  void _refreshAiGuard({bool force = false}) {
    if (!mounted) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastAiBrainAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 360)) {
      return;
    }
    _lastAiBrainAt = now;

    final BatteryState? batteryState = widget.batteryStateN.value;
    final bool isCharging = batteryState == BatteryState.charging ||
        batteryState == BatteryState.full;

    final AiTrackingBrainResult next = _trackingBrainService.evaluate(
      speedKmh: widget.settings.toDisplaySpeed(widget.speedN.value),
      gpsAccuracyMeters: widget.accuracyN.value,
      batteryPercent: widget.batteryN.value,
      isCharging: isCharging,
      motionScore: _motionEma,
      hasRoute: (widget.plannedRouteN.value?.points.length ?? 0) >= 2,
      object: _trackedObjectN.value,
      road: _roadConditionN.value,
    );

    final AiTrackingBrainResult old = _aiGuardN.value;
    if (next.materiallyDiffers(old)) {
      _aiGuardN.value = next;
      if (next.shouldVibrate) {
        final DateTime? lastHaptic = _lastAiGuardHapticAt;
        if (lastHaptic == null ||
            now.difference(lastHaptic) > const Duration(seconds: 4)) {
          _lastAiGuardHapticAt = now;
          HapticFeedback.mediumImpact();
        }
      }
    }
  }

  Future<void> _initCamera() async {
    if (!mounted || _cameraInitInProgress) return;

    _cameraInitInProgress = true;

    setState(() {
      _loading = true;
      _error = null;
      _cameraReady = false;
    });

    CameraController? nextController;

    try {
      final List<CameraDescription> cameras = await availableCameras();

      if (!mounted) return;

      _cameras = cameras;

      if (_cameras.isEmpty) {
        setState(() {
          _loading = false;
          _cameraReady = false;
          _error = 'No camera available on this device.';
        });
        return;
      }

      int index = _selectedCameraIndex.clamp(0, _cameras.length - 1).toInt();
      final int backIndex = _cameras.indexWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
      );

      if (_cameraController == null && backIndex >= 0) {
        index = backIndex;
      }

      _selectedCameraIndex = index;

      nextController = CameraController(
        _cameras[index],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      final CameraController? previousController = _cameraController;
      _cameraController = nextController;

      try {
        await previousController?.dispose();
      } catch (error) {
        // Ignored in production.
      }

      await nextController.initialize();

      if (nextController.value.isInitialized &&
          !nextController.value.isStreamingImages) {
        try {
          await nextController.startImageStream(_handleTfliteCameraImage);
        } catch (_) {
          // Some platforms do not support camera image streaming.
        }
      }

      if (!mounted) {
        await nextController.dispose();
        return;
      }

      setState(() {
        _loading = false;
        _cameraReady = true;
        _torchOn = false;
      });
    } on CameraException catch (error) {
      if (nextController != null &&
          identical(_cameraController, nextController)) {
        _cameraController = null;
      }

      try {
        await nextController?.dispose();
      } catch (_) {
        // Ignored in production.
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
        _cameraReady = false;
        _torchOn = false;
        _error = error.description ?? error.code;
      });
    } catch (error) {
      if (nextController != null &&
          identical(_cameraController, nextController)) {
        _cameraController = null;
      }

      try {
        await nextController?.dispose();
      } catch (_) {
        // Ignored in production.
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
        _cameraReady = false;
        _torchOn = false;
        _error = 'Camera failed to start.';
      });
    } finally {
      _cameraInitInProgress = false;
    }
  }

  Future<void> _toggleTorch() async {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      HapticFeedback.selectionClick();
      final bool next = !_torchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _torchOn = next);
    } catch (error) {
      // Ignored in production.
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _loading || _cameraInitInProgress) return;
    HapticFeedback.selectionClick();
    _torchOn = false;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initCamera();
  }

  void _toggleHudMode() {
    HapticFeedback.selectionClick();
    setState(() => _hudMode = _hudMode.next);
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _cameraController;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: Colors.black,
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: _buildCameraPreview(controller),
              ),
              const Positioned.fill(child: _ArScrim()),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: _handleObjectTrackingTap,
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<AiTrackedObject?>(
                  valueListenable: _trackedObjectN,
                  builder: (_, AiTrackedObject? tracked, __) {
                    return _ArObjectTrackingOverlay(
                      tracked: tracked,
                      onClear: _clearObjectTracking,
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _overlayListenable,
                  builder: (_, __) {
                    final _ArRouteSnapshot snapshot = _ArRouteSnapshot.from(
                      position: widget.posN.value,
                      route: widget.plannedRouteN.value,
                      compassHeading: widget.compassN.value,
                      hybridHeading: widget.headingN.value,
                      speedMph: widget.speedN.value,
                      accuracyMeters: widget.accuracyN.value,
                      battery: widget.batteryN.value,
                      batteryState: widget.batteryStateN.value,
                      coachTip: widget.coachTipN.value,
                      settings: widget.settings,
                    );

                    return _ArRouteOverlay(
                      snapshot: snapshot,
                      onClose: () => Navigator.of(context).maybePop(),
                      onTorch: _toggleTorch,
                      onSwitchCamera: _switchCamera,
                      torchOn: _torchOn,
                      canSwitchCamera: _cameras.length > 1,
                      hudMode: _hudMode,
                      onHudMode: _toggleHudMode,
                      autoObjectTracking: _autoObjectTracking,
                      onAutoObjectTracking: _toggleAutoObjectTracking,
                      motionStability: _motionStabilityN.value,
                      loading: _loading,
                      error: _error,
                      scene: _sceneN.value,
                      onEnvironmentMode: _toggleArEnvironmentMode,
                      onResetScan: _resetArScan,
                    );
                  },
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.viewPaddingOf(context).top + 122,
                child: ValueListenableBuilder<AiTrackingBrainResult>(
                  valueListenable: _aiGuardN,
                  builder: (_, AiTrackingBrainResult result, __) {
                    return _ArAiGuardBanner(result: result);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview(CameraController? controller) {
    if (_loading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return _ArCameraError(
        message: _error!,
        onRetry: _initCamera,
      );
    }

    if (!_cameraReady ||
        controller == null ||
        !controller.value.isInitialized) {
      return _ArCameraError(
        message: 'Camera is not ready.',
        onRetry: _initCamera,
      );
    }

    final Size screen = MediaQuery.sizeOf(context);
    final Size preview = controller.value.previewSize ?? screen;
    final double previewAspect = preview.height / preview.width;

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: screen.width,
            height: screen.width / previewAspect,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _ArAiGuardBanner extends StatelessWidget {
  const _ArAiGuardBanner({required this.result});

  final AiTrackingBrainResult result;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: ClipRRect(
          key: ValueKey<String>('ai-guard-${result.title}-${result.score}'),
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: result.color.withValues(alpha: 0.28)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: result.color.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: result.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: result.color.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(result.icon, color: result.color, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          result.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${result.score}%',
                    style: TextStyle(
                      color: result.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArObjectTrackingOverlay extends StatelessWidget {
  const _ArObjectTrackingOverlay({
    required this.tracked,
    required this.onClear,
  });

  final AiTrackedObject? tracked;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.viewPaddingOf(context);
    final AiTrackedObject? object = tracked;

    if (object == null) {
      return IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: math.max(safe.bottom, _kArMinBottomPadding) + 104,
                  left: 18,
                  right: 18),
              child: _ArObjectHintCard(),
            ),
          ),
        ),
      );
    }

    final Rect box = object.screenBoxFor(size);
    final Color riskColor = object.risk.color;
    const double labelWidth = 174.0;
    final double labelLeft =
        (box.left + 4).clamp(12.0, size.width - labelWidth - 12.0).toDouble();
    final double labelTop =
        (box.top - 18).clamp(safe.top + 92.0, size.height - 220.0).toDouble();

    return Stack(
      children: <Widget>[
        Positioned.fromRect(
          rect: box,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: riskColor, width: 2.2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: riskColor.withValues(alpha: 0.20),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _ArObjectCornerPainter(color: riskColor),
              ),
            ),
          ),
        ),
        Positioned(
          left: labelLeft,
          top: labelTop,
          width: labelWidth,
          child: _ArObjectSpeedLabel(object: object),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: math.max(safe.bottom, _kArMinBottomPadding) + 104,
          child: _ArObjectRiskBanner(
            object: object,
            onClear: onClear,
          ),
        ),
      ],
    );
  }
}

class _ArObjectCornerPainter extends CustomPainter {
  const _ArObjectCornerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const double length = 18;
    // Draw corner brackets with lines instead of ui.Path to avoid conflicts with
    // `Path<LatLng>` from routing/map packages.
    canvas
      ..drawLine(const Offset(0, 0), Offset(length, 0), paint)
      ..drawLine(const Offset(0, 0), Offset(0, length), paint)
      ..drawLine(
        Offset(size.width - length, 0),
        Offset(size.width, 0),
        paint,
      )
      ..drawLine(
        Offset(size.width, 0),
        Offset(size.width, length),
        paint,
      )
      ..drawLine(
        Offset(size.width, size.height - length),
        Offset(size.width, size.height),
        paint,
      )
      ..drawLine(
        Offset(size.width - length, size.height),
        Offset(size.width, size.height),
        paint,
      )
      ..drawLine(
        Offset(0, size.height),
        Offset(length, size.height),
        paint,
      )
      ..drawLine(
        Offset(0, size.height - length),
        Offset(0, size.height),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant _ArObjectCornerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ArRouteSnapshot {
  const _ArRouteSnapshot({
    required this.hasRoute,
    required this.routePointCount,
    required this.distanceToTargetMeters,
    required this.heading,
    required this.targetBearing,
    required this.relativeBearing,
    required this.arrowTurns,
    required this.directionLabel,
    required this.targetLabel,
    required this.speedLabel,
    required this.speedUnit,
    required this.gpsLabel,
    required this.gpsColor,
    required this.batteryLabel,
    required this.batteryColor,
    required this.coachTip,
  });

  final bool hasRoute;
  final int routePointCount;
  final double distanceToTargetMeters;
  final double heading;
  final double targetBearing;
  final double relativeBearing;
  final double arrowTurns;
  final String directionLabel;
  final String targetLabel;
  final String speedLabel;
  final String speedUnit;
  final String gpsLabel;
  final Color gpsColor;
  final String batteryLabel;
  final Color batteryColor;
  final String coachTip;

  static _ArRouteSnapshot from({
    required LatLng? position,
    required PlannedRoute? route,
    required double compassHeading,
    required double hybridHeading,
    required double speedMph,
    required double accuracyMeters,
    required int? battery,
    required BatteryState? batteryState,
    required String coachTip,
    required SettingsService settings,
  }) {
    final List<LatLng> points = route?.points ?? const <LatLng>[];
    final LatLng? target = _nextUsefulTarget(position, points);
    final bool hasTarget = position != null && target != null;

    final double targetBearing = hasTarget
        ? _normDeg(_kArDistance.bearing(position, target))
        : _normDeg(compassHeading);
    final double heading = _normDeg(hybridHeading);
    final double relative = _signedHeadingDelta(heading, targetBearing);
    final double meters =
        hasTarget ? _kArDistance.as(LengthUnit.Meter, position, target) : 0.0;

    final bool gpsGood = accuracyMeters.isFinite && accuracyMeters <= 18.0;
    final bool gpsWeak = !accuracyMeters.isFinite || accuracyMeters >= 35.0;

    final Color gpsColor = gpsGood
        ? _kArGreen
        : gpsWeak
            ? _kArRed
            : _kArGold;
    final String gpsLabel = accuracyMeters.isFinite && accuracyMeters < 80
        ? 'GPS ±${accuracyMeters.round()}m'
        : 'GPS searching';

    final bool charging = batteryState == BatteryState.charging ||
        batteryState == BatteryState.full;
    final Color batteryColor = battery == null
        ? Colors.white54
        : charging
            ? _kArBlueSoft
            : battery <= 20
                ? _kArRed
                : battery <= 40
                    ? _kArGold
                    : _kArGreen;

    final double displaySpeed = settings.toDisplaySpeed(speedMph);
    final String speedLabel = displaySpeed.isFinite
        ? displaySpeed.clamp(0.0, 999.0).round().toString()
        : '0';

    return _ArRouteSnapshot(
      hasRoute: hasTarget,
      routePointCount: points.length,
      distanceToTargetMeters: meters,
      heading: heading,
      targetBearing: targetBearing,
      relativeBearing: relative,
      arrowTurns: relative / 360.0,
      directionLabel: _directionLabel(relative),
      targetLabel:
          hasTarget ? _distanceLabel(meters, settings) : 'Plan route first',
      speedLabel: speedLabel,
      speedUnit: settings.speedUnit.toUpperCase(),
      gpsLabel: gpsLabel,
      gpsColor: gpsColor,
      batteryLabel: battery == null
          ? 'BAT --%'
          : charging
              ? 'CHG $battery%'
              : 'BAT $battery%',
      batteryColor: batteryColor,
      coachTip: coachTip.trim().isEmpty ? 'AR route ready' : coachTip.trim(),
    );
  }

  static LatLng? _nextUsefulTarget(LatLng? current, List<LatLng> points) {
    if (current == null || points.length < 2) return null;

    double bestDistance = double.infinity;
    int bestIndex = 0;

    final int step = points.length > 180
        ? 3
        : points.length > 80
            ? 2
            : 1;
    for (int i = 0; i < points.length; i += step) {
      final LatLng point = points[i];
      final double distance = _kArDistance.as(LengthUnit.Meter, current, point);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    final int lookAhead = bestDistance < 25.0 ? 7 : 4;
    final int targetIndex =
        (bestIndex + lookAhead).clamp(0, points.length - 1).toInt();

    return points[targetIndex];
  }

  static String _directionLabel(double relative) {
    final double abs = relative.abs();

    if (abs <= 12.0) return 'Straight ahead';
    if (abs <= 42.0) return relative > 0 ? 'Slight right' : 'Slight left';
    if (abs <= 115.0) return relative > 0 ? 'Turn right' : 'Turn left';
    return relative > 0 ? 'Sharp right' : 'Sharp left';
  }

  static String _distanceLabel(double meters, SettingsService settings) {
    if (!meters.isFinite || meters <= 0.0) return '0 m';

    final double miles = meters / 1609.344;
    final double display = settings.toDisplayDistance(miles);

    if (settings.useKmh) {
      if (meters < 950.0) return '${meters.round()} m';
      return '${(meters / 1000.0).toStringAsFixed(1)} km';
    }

    if (display < 0.2) {
      return '${(display * 5280.0).round()} ft';
    }
    return '${display.toStringAsFixed(1)} mi';
  }
}

class _ArRouteOverlay extends StatelessWidget {
  const _ArRouteOverlay({
    required this.snapshot,
    required this.onClose,
    required this.onTorch,
    required this.onSwitchCamera,
    required this.torchOn,
    required this.canSwitchCamera,
    required this.hudMode,
    required this.onHudMode,
    required this.autoObjectTracking,
    required this.onAutoObjectTracking,
    required this.motionStability,
    required this.loading,
    required this.error,
    required this.scene,
    required this.onEnvironmentMode,
    required this.onResetScan,
  });

  final _ArRouteSnapshot snapshot;
  final VoidCallback onClose;
  final VoidCallback onTorch;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHudMode;
  final bool autoObjectTracking;
  final VoidCallback onAutoObjectTracking;
  final _ArMotionStability motionStability;
  final bool torchOn;
  final bool canSwitchCamera;
  final _ArHudMode hudMode;
  final bool loading;
  final String? error;
  final ArSceneSnapshot scene;
  final VoidCallback onEnvironmentMode;
  final VoidCallback onResetScan;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.viewPaddingOf(context);
    final Size size = MediaQuery.sizeOf(context);
    final bool compact = size.width < 390.0 || size.height < 760.0;
    final bool minimal = hudMode == _ArHudMode.minimal;
    final double side = compact ? 8.0 : _kArSideInset;
    final double safeTop = math.max(safe.top, _kArMinTopPadding);
    final double safeBottom = math.max(safe.bottom, _kArMinBottomPadding);

    return AnimatedPadding(
      duration: _kArPanelAnim,
      curve: _kArEase,
      padding: EdgeInsets.fromLTRB(
          side, safeTop + 4, side, safeBottom + _kArBottomHudGap),
      child: Column(
        children: <Widget>[
          _ArPremiumTopBar(
            onClose: onClose,
            onTorch: onTorch,
            onSwitchCamera: onSwitchCamera,
            onHudMode: onHudMode,
            onEnvironmentMode: onEnvironmentMode,
            onResetScan: onResetScan,
            autoObjectTracking: autoObjectTracking,
            onAutoObjectTracking: onAutoObjectTracking,
            torchOn: torchOn,
            canSwitchCamera: canSwitchCamera,
            hudMode: hudMode,
            scene: scene,
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: _kArPanelAnim,
            curve: _kArEase,
            alignment: Alignment.topCenter,
            child: Column(
              children: <Widget>[
                if (!minimal) _ArStatusStrip(snapshot: snapshot),
                if (!minimal) const SizedBox(height: 8),
                if (!minimal)
                  _ArSceneStatusBanner(
                    scene: scene,
                    motionStability: motionStability,
                    loading: loading,
                    error: error,
                    compact: compact,
                  )
                else
                  AnimatedSize(
                    duration: _kArPanelAnim,
                    curve: _kArEase,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _ArSystemBanner(
                            loading: loading, error: error, compact: true),
                        const SizedBox(height: 6),
                        _ArMotionStabilityBanner(
                            stability: motionStability, compact: true),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AnimatedSwitcher(
                  duration: _kArSlowAnim,
                  switchInCurve: _kArEase,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    final Animation<Offset> slide = Tween<Offset>(
                      begin: const Offset(0.0, 0.035),
                      end: Offset.zero,
                    ).animate(
                        CurvedAnimation(parent: animation, curve: _kArEase));

                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: scene.environmentMode == ArEnvironmentMode.street
                      ? _ArStreetModeView(
                          key: const ValueKey<String>('street-ar'),
                          snapshot: snapshot,
                          scene: scene,
                          compact: compact || minimal,
                        )
                      : _ArMarkerlessModeView(
                          key: const ValueKey<String>('markerless-ar'),
                          snapshot: snapshot,
                          scene: scene,
                          compact: compact || minimal,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ArPremiumBottomHud(
              snapshot: snapshot, scene: scene, compact: compact || minimal),
        ],
      ),
    );
  }
}

class _ArPremiumTopBar extends StatelessWidget {
  const _ArPremiumTopBar({
    required this.onClose,
    required this.onTorch,
    required this.onSwitchCamera,
    required this.onHudMode,
    required this.onEnvironmentMode,
    required this.onResetScan,
    required this.autoObjectTracking,
    required this.onAutoObjectTracking,
    required this.torchOn,
    required this.canSwitchCamera,
    required this.hudMode,
    required this.scene,
  });

  final VoidCallback onClose;
  final VoidCallback onTorch;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHudMode;
  final VoidCallback onEnvironmentMode;
  final VoidCallback onResetScan;
  final bool autoObjectTracking;
  final VoidCallback onAutoObjectTracking;
  final bool torchOn;
  final bool canSwitchCamera;
  final _ArHudMode hudMode;
  final ArSceneSnapshot scene;

  @override
  Widget build(BuildContext context) {
    final bool tight = MediaQuery.sizeOf(context).width < 390.0;
    return Row(
      children: <Widget>[
        _ArRoundButton(
            icon: CupertinoIcons.xmark, label: 'Close AR', onTap: onClose),
        SizedBox(width: tight ? 5 : 7),
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ArPill(
              icon: scene.environmentMode == ArEnvironmentMode.street
                  ? CupertinoIcons.location_north_fill
                  : CupertinoIcons.cube_box_fill,
              label: tight
                  ? scene.environmentMode.label.replaceAll(' AR', '')
                  : scene.environmentMode.label,
              color: _kArBlueSoft,
            ),
          ),
        ),
        SizedBox(width: tight ? 5 : 7),
        _ArRoundButton(
          icon: CupertinoIcons.arrow_2_circlepath,
          label: 'Switch AR mode',
          active: scene.environmentMode == ArEnvironmentMode.markerless,
          onTap: onEnvironmentMode,
        ),
        SizedBox(width: tight ? 5 : 7),
        _ArRoundButton(
          icon: scene.anchorLocked
              ? CupertinoIcons.checkmark_shield_fill
              : CupertinoIcons.viewfinder,
          label: 'Reset AR scan',
          active: scene.anchorLocked,
          onTap: onResetScan,
        ),
        SizedBox(width: tight ? 5 : 7),
        _ArRoundButton(
            icon: CupertinoIcons.scope,
            label: 'Auto object tracking',
            active: autoObjectTracking,
            onTap: onAutoObjectTracking),
        SizedBox(width: tight ? 5 : 7),
        _ArRoundButton(
            icon: hudMode.icon,
            label: hudMode.semanticsLabel,
            active: hudMode == _ArHudMode.minimal,
            onTap: onHudMode),
        SizedBox(width: tight ? 5 : 7),
        _ArRoundButton(
            icon: torchOn ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
            label: 'Toggle torch',
            active: torchOn,
            onTap: onTorch),
      ],
    );
  }
}

class _ArSceneStatusBanner extends StatelessWidget {
  const _ArSceneStatusBanner({
    super.key,
    required this.scene,
    required this.motionStability,
    required this.loading,
    required this.error,
    required this.compact,
  });

  final ArSceneSnapshot scene;
  final _ArMotionStability motionStability;
  final bool loading;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color = scene.trackingLost
        ? _kArRed
        : scene.anchorLocked
            ? _kArGreen
            : scene.scanState == ArScanState.surfaceDetected
                ? _kArBlueSoft
                : _kArGold;

    final String label = error != null
        ? 'Camera issue · $error'
        : loading
            ? 'Starting AR camera…'
            : scene.shouldShowWarning
                ? scene.warningLabel
                : scene.statusLabel;

    return AnimatedSwitcher(
      duration: _kArPanelAnim,
      switchInCurve: _kArEase,
      switchOutCurve: Curves.easeInCubic,
      child: _ArGlass(
        key: ValueKey<String>(
            '${scene.scanState.name}-${scene.warningLabel}-$loading-$error'),
        radius: 999,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12, vertical: compact ? 7 : 8),
        color: Colors.black.withValues(alpha: 0.58),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading)
              const CupertinoActivityIndicator(color: Colors.white)
            else
              Icon(
                scene.anchorLocked
                    ? CupertinoIcons.checkmark_shield_fill
                    : scene.trackingLost
                        ? CupertinoIcons.exclamationmark_triangle_fill
                        : CupertinoIcons.viewfinder,
                color: color,
                size: compact ? 13 : 15,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    decoration: TextDecoration.none,
                    color: color,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 8),
            _ArTinyProgress(value: scene.anchorConfidence, color: color),
          ],
        ),
      ),
    );
  }
}

class _ArTinyProgress extends StatelessWidget {
  const _ArTinyProgress({
    super.key,
    required this.value,
    required this.color,
  });

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          color: color,
        ),
      ),
    );
  }
}

class _ArStreetModeView extends StatelessWidget {
  const _ArStreetModeView({
    super.key,
    required this.snapshot,
    required this.scene,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final ArSceneSnapshot scene;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ArRouteAnchor? anchor = scene.anchor;
    final bool locked = scene.anchorLocked;
    final Color color = snapshot.hasRoute ? _kArBlueSoft : _kArGold;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ArPerspectiveLabelCard(
          label: snapshot.hasRoute ? snapshot.targetLabel : 'Plan route',
          color: snapshot.hasRoute ? _kArBlueSoft : _kArGold,
          compact: compact,
        ),
        SizedBox(height: compact ? 8 : 10),
        _ArRouteRibbon(
          color: color,
          relativeBearing: snapshot.relativeBearing,
          hasRoute: snapshot.hasRoute,
          pathShift: scene.pathShift,
          compact: compact,
        ),
        SizedBox(height: compact ? 10 : 12),
        _Ar3DChevrons(
          color: color,
          relativeBearing: anchor?.relativeBearing ?? snapshot.relativeBearing,
          locked: locked,
          compact: compact,
        ),
        SizedBox(height: compact ? 12 : 14),
        _ArInstructionCard(
          title: snapshot.directionLabel,
          subtitle: scene.hasObstacle
              ? 'Object-aware path guidance active'
              : snapshot.hasRoute
                  ? 'Follow the glowing route ribbon'
                  : 'Create a route before using AR guidance',
          color: color,
          compact: compact,
        ),
      ],
    );
  }
}

class _ArMarkerlessModeView extends StatelessWidget {
  const _ArMarkerlessModeView({
    super.key,
    required this.snapshot,
    required this.scene,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final ArSceneSnapshot scene;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color = scene.anchorLocked
        ? _kArGreen
        : scene.scanState == ArScanState.trackingLost
            ? _kArRed
            : _kArBlueSoft;

    return _ArGlass(
      radius: compact ? 24 : 30,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        compact ? 13 : 16,
        compact ? 14 : 18,
        compact ? 14 : 17,
      ),
      color: Colors.black.withValues(alpha: 0.62),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ArDirectionHeader(
            color: color,
            direction: scene.scanState.label,
            distance: scene.anchorLocked ? 'Anchor locked' : 'Scan surface',
            hasRoute: scene.anchorLocked,
          ),
          SizedBox(height: compact ? 12 : 16),
          SizedBox(
            width: compact ? 220 : 265,
            height: compact ? 154 : 184,
            child: CustomPaint(
              painter: _ArMarkerlessScanPainter(
                scene: scene,
                color: color,
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          _Ar3DFloorArrow(
            color: color,
            relativeBearing: snapshot.relativeBearing,
            locked: scene.anchorLocked,
            compact: compact,
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            scene.anchorLocked
                ? '3D arrow anchored to detected surface'
                : 'Move phone slowly to scan floor and surroundings',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: TextDecoration.none,
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArPerspectiveLabelCard extends StatelessWidget {
  const _ArPerspectiveLabelCard({
    required this.label,
    required this.color,
    required this.compact,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(-0.12),
      child: Container(
        constraints: BoxConstraints(maxWidth: compact ? 210 : 260),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 20 : 24,
          vertical: compact ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            decoration: TextDecoration.none,
            color: Colors.white,
            fontSize: compact ? 18 : 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
      ),
    );
  }
}

class _ArInstructionCard extends StatelessWidget {
  const _ArInstructionCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: 18,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      color: Colors.black.withValues(alpha: 0.58),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(CupertinoIcons.location_north_fill, color: color, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArPremiumBottomHud extends StatelessWidget {
  const _ArPremiumBottomHud({
    required this.snapshot,
    required this.scene,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final ArSceneSnapshot scene;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = scene.anchorLocked
        ? _kArGreen
        : scene.trackingLost
            ? _kArRed
            : _kArGold;

    return _ArGlass(
      radius: compact ? 22 : 26,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 9 : 11,
      ),
      color: Colors.black.withValues(alpha: 0.74),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: compact ? 58 : 72,
            child: Column(
              children: <Widget>[
                Text(
                  snapshot.speedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: compact ? 27 : 34,
                    height: 0.94,
                    fontWeight: FontWeight.w900,
                    letterSpacing: compact ? -1.2 : -1.7,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snapshot.speedUnit,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: _kArBlueSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.15,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: compact ? 34 : 40,
            margin: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.13),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(
                    scene.anchorLocked
                        ? CupertinoIcons.checkmark_shield_fill
                        : scene.trackingLost
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.viewfinder,
                    color: statusColor,
                    size: compact ? 16 : 18,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    scene.statusLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: TextDecoration.none,
                      color: Colors.white,
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1.16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArRoundButton extends StatelessWidget {
  const _ArRoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool tight = MediaQuery.sizeOf(context).width < 390.0;
    final double size = tight ? 32.0 : 36.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: enabled ? onTap : null,
        child: AnimatedScale(
          duration: _kArFastAnim,
          curve: _kArEase,
          scale: active ? 1.05 : 1.0,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.42,
            duration: _kArFastAnim,
            curve: _kArEase,
            child: AnimatedContainer(
              duration: _kArFastAnim,
              curve: _kArEase,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? _kArBlueSoft.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.54),
                border: Border.all(
                    color: active
                        ? _kArBlueSoft.withValues(alpha: 0.42)
                        : Colors.white.withValues(alpha: 0.13)),
                boxShadow: <BoxShadow>[
                  if (active)
                    BoxShadow(
                        color: _kArBlueSoft.withValues(alpha: 0.18),
                        blurRadius: 14),
                ],
              ),
              child: Icon(icon,
                  color: active ? _kArBlueSoft : Colors.white,
                  size: tight ? 15 : 17),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArPill extends StatelessWidget {
  const _ArPill({
    required this.icon,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: 999,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 11,
        vertical: compact ? 7 : 8,
      ),
      color: Colors.black.withValues(alpha: 0.58),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 84 : 118),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: compact ? 12 : 13),
            SizedBox(width: compact ? 5 : 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  decoration: TextDecoration.none,
                  color: color,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArMiniStatus extends StatelessWidget {
  const _ArMiniStatus({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 118),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                decoration: TextDecoration.none,
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArDot extends StatelessWidget {
  const _ArDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 7),
        ],
      ),
    );
  }
}

class _ArGlass extends StatelessWidget {
  const _ArGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 22,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? _kArSurface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESTORED AR UI HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class _ArScrim extends StatelessWidget {
  const _ArScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.78),
              Colors.black.withValues(alpha: 0.16),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.16),
              Colors.black.withValues(alpha: 0.82),
            ],
            stops: const <double>[0.0, 0.18, 0.45, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _ArCameraError extends StatelessWidget {
  const _ArCameraError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: _ArGlass(
            radius: 24,
            padding: const EdgeInsets.all(18),
            color: Colors.black.withValues(alpha: 0.78),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kArGold.withValues(alpha: 0.14),
                    border: Border.all(
                      color: _kArGold.withValues(alpha: 0.26),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: _kArGold,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Camera unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: onRetry,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kArBlueSoft.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _kArBlueSoft.withValues(alpha: 0.28),
                      ),
                    ),
                    child: const Text(
                      'Retry camera',
                      style: TextStyle(
                        decoration: TextDecoration.none,
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArObjectHintCard extends StatelessWidget {
  const _ArObjectHintCard();

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      color: Colors.black.withValues(alpha: 0.58),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kArBlueSoft.withValues(alpha: 0.13),
              border: Border.all(color: _kArBlueSoft.withValues(alpha: 0.24)),
            ),
            child: const Icon(
              CupertinoIcons.scope,
              color: _kArBlueSoft,
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'Auto object tracking is ready · tap to lock manually',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration: TextDecoration.none,
                color: Colors.white,
                fontSize: 11,
                height: 1.18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArObjectRiskBanner extends StatelessWidget {
  const _ArObjectRiskBanner({
    required this.object,
    required this.onClear,
  });

  final AiTrackedObject object;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bool isAuto = object.id.startsWith('auto-');

    return _ArGlass(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      color: Colors.black.withValues(alpha: 0.72),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: object.risk.color.withValues(alpha: 0.14),
              border: Border.all(
                color: object.risk.color.withValues(alpha: 0.26),
              ),
            ),
            child: Icon(
              object.risk.icon,
              color: object.risk.color,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(decoration: TextDecoration.none),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isAuto ? 'Auto object active' : 'Object locked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${object.speedLabel} · Risk ${object.riskScore}% · ${(object.confidence * 100).round()}% confidence',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: object.risk.color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: onClear,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
              child: const Icon(
                CupertinoIcons.xmark,
                color: Colors.white70,
                size: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArStatusStrip extends StatelessWidget {
  const _ArStatusStrip({required this.snapshot});

  final _ArRouteSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: Colors.black.withValues(alpha: 0.62),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 4,
        children: <Widget>[
          _ArMiniStatus(
            icon: CupertinoIcons.location_fill,
            label: snapshot.gpsLabel,
            color: snapshot.gpsColor,
          ),
          const _ArDot(color: _kArBlueSoft),
          _ArMiniStatus(
            icon: CupertinoIcons.battery_100,
            label: snapshot.batteryLabel,
            color: snapshot.batteryColor,
          ),
          _ArDot(color: snapshot.hasRoute ? _kArGreen : _kArGold),
          _ArMiniStatus(
            icon: Icons.route_rounded,
            label: snapshot.hasRoute
                ? '${snapshot.routePointCount} pts'
                : 'No route yet',
            color: snapshot.hasRoute ? _kArGreen : _kArGold,
          ),
        ],
      ),
    );
  }
}

class _ArSystemBanner extends StatelessWidget {
  const _ArSystemBanner({
    required this.loading,
    required this.error,
    required this.compact,
  });

  final bool loading;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String? message = error == null
        ? loading
            ? 'Starting AR camera…'
            : null
        : 'Camera issue · ${error!}';

    if (message == null) return const SizedBox.shrink();

    final bool hasError = error != null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _ArGlass(
        radius: 999,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 8,
        ),
        color: Colors.black.withValues(alpha: hasError ? 0.62 : 0.42),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading && !hasError) ...<Widget>[
              const CupertinoActivityIndicator(color: Colors.white),
              const SizedBox(width: 8),
            ] else ...<Widget>[
              const Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: _kArGold,
                size: 15,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  decoration: TextDecoration.none,
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArMotionStabilityBanner extends StatelessWidget {
  const _ArMotionStabilityBanner({
    required this.stability,
    required this.compact,
  });

  final _ArMotionStability stability;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool quiet = stability == _ArMotionStability.steady;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: quiet && compact
          ? const SizedBox.shrink()
          : _ArGlass(
              radius: 999,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 7 : 8,
              ),
              color: Colors.black.withValues(alpha: quiet ? 0.34 : 0.58),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    stability.icon,
                    color: stability.color,
                    size: compact ? 13 : 15,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    stability == _ArMotionStability.shaking
                        ? 'Phone shaking · hold steady'
                        : stability == _ArMotionStability.moving
                            ? 'Motion detected · move slowly'
                            : 'AR stable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: TextDecoration.none,
                      color: quiet
                          ? Colors.white.withValues(alpha: 0.72)
                          : stability.color,
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ArStreetGuidanceStack extends StatelessWidget {
  const _ArStreetGuidanceStack({
    super.key,
    required this.snapshot,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ArStreetNamePlate(
          label: snapshot.hasRoute ? snapshot.targetLabel : 'Plan route',
          compact: compact,
        ),
        SizedBox(height: compact ? 8 : 10),
        _ArChevronGuidance(
          snapshot: snapshot,
          compact: compact,
        ),
        SizedBox(height: compact ? 12 : 14),
        _ArSensorRadar(
          snapshot: snapshot,
          compact: compact,
        ),
      ],
    );
  }
}

class _ArMarkerlessGuidanceStack extends StatelessWidget {
  const _ArMarkerlessGuidanceStack({
    super.key,
    required this.snapshot,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: compact ? 24 : 30,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        compact ? 13 : 16,
        compact ? 14 : 18,
        compact ? 14 : 17,
      ),
      color: Colors.black.withValues(alpha: 0.64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ArDirectionHeader(
            color: snapshot.hasRoute ? _kArBlueSoft : _kArGold,
            direction: 'Markerless scan',
            distance: snapshot.hasRoute ? snapshot.targetLabel : 'Find surface',
            hasRoute: snapshot.hasRoute,
          ),
          SizedBox(height: compact ? 12 : 16),
          SizedBox(
            width: compact ? 210 : 250,
            height: compact ? 136 : 162,
            child: CustomPaint(
              painter: _ArMarkerlessSurfacePainter(
                hasRoute: snapshot.hasRoute,
                relativeBearing: snapshot.relativeBearing,
                color: snapshot.hasRoute ? _kArBlueSoft : _kArGold,
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            snapshot.hasRoute
                ? 'Object and flat surface locked for AR guidance'
                : 'Move phone slowly to scan surroundings',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: TextDecoration.none,
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArStreetNamePlate extends StatelessWidget {
  const _ArStreetNamePlate({
    required this.label,
    required this.compact,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String safeLabel = label.trim().isEmpty ? 'Next route' : label.trim();

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(-0.10),
      child: Container(
        constraints: BoxConstraints(maxWidth: compact ? 178 : 230),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 22,
          vertical: compact ? 9 : 11,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[
              Color(0xFF1389FF),
              Color(0xFF0066E6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kArBlueSoft.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Text(
          safeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            decoration: TextDecoration.none,
            color: Colors.white,
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _ArChevronGuidance extends StatelessWidget {
  const _ArChevronGuidance({
    required this.snapshot,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color = snapshot.hasRoute ? _kArBlueSoft : _kArGold;
    final double size = compact ? 165 : 205;

    return _ArGlass(
      radius: compact ? 24 : 30,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        compact ? 12 : 15,
        compact ? 14 : 18,
        compact ? 12 : 15,
      ),
      color: Colors.black.withValues(alpha: 0.58),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ArDirectionHeader(
            color: color,
            direction: snapshot.directionLabel,
            distance: snapshot.targetLabel,
            hasRoute: snapshot.hasRoute,
          ),
          SizedBox(height: compact ? 10 : 12),
          SizedBox(
            width: size,
            height: compact ? 94 : 112,
            child: CustomPaint(
              painter: _ArChevronPainter(
                color: color,
                relativeBearing: snapshot.relativeBearing,
                hasRoute: snapshot.hasRoute,
              ),
            ),
          ),
          SizedBox(height: compact ? 7 : 9),
          Text(
            snapshot.hasRoute
                ? 'Follow the floating street arrows'
                : 'Create a route before using AR guidance',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: TextDecoration.none,
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArChevronPainter extends CustomPainter {
  const _ArChevronPainter({
    required this.color,
    required this.relativeBearing,
    required this.hasRoute,
  });

  final Color color;
  final double relativeBearing;
  final bool hasRoute;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint shadow = Paint()
      ..color = color.withValues(alpha: 0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    final Paint fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final double angle = (relativeBearing / 90.0).clamp(-1.0, 1.0) * 0.24;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    for (int i = 0; i < 3; i++) {
      final double x = (i - 1) * size.width * 0.22;
      final ui.Path path = ui.Path()
        ..moveTo(x + size.width * 0.10, -size.height * 0.30)
        ..lineTo(x - size.width * 0.07, 0)
        ..lineTo(x + size.width * 0.10, size.height * 0.30);

      canvas.drawPath(path, shadow);
      canvas.drawPath(path, stroke);
      canvas.drawPath(path, fill);
    }

    if (!hasRoute) {
      final Paint idle = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _kArGold.withValues(alpha: 0.35);
      canvas.drawCircle(Offset.zero, size.height * 0.42, idle);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArChevronPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.hasRoute != hasRoute;
  }
}

class _ArMarkerlessSurfacePainter extends CustomPainter {
  const _ArMarkerlessSurfacePainter({
    required this.hasRoute,
    required this.relativeBearing,
    required this.color,
  });

  final bool hasRoute;
  final double relativeBearing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint surfacePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.10);

    final Paint surfaceStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.18);

    final ui.Path plane = ui.Path()
      ..moveTo(size.width * 0.22, size.height * 0.18)
      ..lineTo(size.width * 0.78, size.height * 0.18)
      ..lineTo(size.width * 0.96, size.height * 0.88)
      ..lineTo(size.width * 0.04, size.height * 0.88)
      ..close();

    canvas.drawPath(plane, surfacePaint);
    canvas.drawPath(plane, surfaceStroke);

    final Paint dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final List<Offset> dots = <Offset>[
      Offset(size.width * 0.36, size.height * 0.42),
      Offset(size.width * 0.64, size.height * 0.42),
      Offset(size.width * 0.36, size.height * 0.66),
      Offset(size.width * 0.64, size.height * 0.66),
    ];

    for (final Offset dot in dots) {
      canvas.drawCircle(dot, 4.2, dotPaint);
      canvas.drawCircle(
        dot,
        8.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = color.withValues(alpha: 0.34),
      );
    }

    final Paint cubeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..color = hasRoute ? color : _kArGold;

    final Rect front = Rect.fromCenter(
      center: Offset(size.width * 0.50, size.height * 0.55),
      width: size.width * 0.22,
      height: size.height * 0.22,
    );

    canvas.drawRect(front, cubeStroke);
    canvas.drawLine(
        front.topLeft, front.topLeft.translate(18, -14), cubeStroke);
    canvas.drawLine(
        front.topRight, front.topRight.translate(18, -14), cubeStroke);
    canvas.drawLine(
        front.bottomRight, front.bottomRight.translate(18, -14), cubeStroke);
    canvas.drawLine(front.topLeft.translate(18, -14),
        front.topRight.translate(18, -14), cubeStroke);
    canvas.drawLine(front.topRight.translate(18, -14),
        front.bottomRight.translate(18, -14), cubeStroke);

    if (hasRoute) {
      final double angle = (relativeBearing / 90.0).clamp(-1.0, 1.0) * 0.18;
      canvas.save();
      canvas.translate(size.width * 0.50, size.height * 0.30);
      canvas.rotate(angle);
      final Paint arrowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;
      final ui.Path arrow = ui.Path()
        ..moveTo(0, 24)
        ..lineTo(0, -20)
        ..moveTo(0, -20)
        ..lineTo(-14, -4)
        ..moveTo(0, -20)
        ..lineTo(14, -4);
      canvas.drawPath(arrow, arrowPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ArMarkerlessSurfacePainter oldDelegate) {
    return oldDelegate.hasRoute != hasRoute ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.color != color;
  }
}

class _ArDirectionArrow extends StatelessWidget {
  const _ArDirectionArrow({
    required this.snapshot,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color arrowColor = snapshot.hasRoute ? _kArBlueSoft : _kArGold;
    final double arrowSize = compact ? 62.0 : 84.0;
    final String hint = snapshot.hasRoute
        ? 'Follow the arrow and radar dot'
        : 'Create a route before using AR guidance';

    return _ArGlass(
      radius: compact ? 22 : 26,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 14,
        compact ? 10 : 12,
        compact ? 12 : 14,
        compact ? 12 : 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ArDirectionHeader(
            color: arrowColor,
            direction: snapshot.directionLabel,
            distance: snapshot.targetLabel,
            hasRoute: snapshot.hasRoute,
          ),
          SizedBox(height: compact ? 8 : 10),
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: arrowSize + 24,
                height: arrowSize + 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: arrowColor.withValues(alpha: 0.08),
                  border: Border.all(color: arrowColor.withValues(alpha: 0.18)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: arrowColor.withValues(alpha: 0.16),
                      blurRadius: compact ? 18 : 24,
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: snapshot.arrowTurns,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  CupertinoIcons.arrow_up_circle_fill,
                  color: arrowColor,
                  size: arrowSize,
                  shadows: <Shadow>[
                    Shadow(
                      color: arrowColor.withValues(alpha: 0.40),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 9),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: TextDecoration.none,
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArDirectionHeader extends StatelessWidget {
  const _ArDirectionHeader({
    required this.color,
    required this.direction,
    required this.distance,
    required this.hasRoute,
  });

  final Color color;
  final String direction;
  final String distance;
  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(
            hasRoute
                ? CupertinoIcons.location_north_fill
                : CupertinoIcons.exclamationmark_triangle_fill,
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DefaultTextStyle.merge(
            style: const TextStyle(decoration: TextDecoration.none),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  direction.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  distance,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ArRouteRibbon extends StatelessWidget {
  const _ArRouteRibbon({
    required this.color,
    required this.relativeBearing,
    required this.hasRoute,
    required this.pathShift,
    required this.compact,
  });

  final Color color;
  final double relativeBearing;
  final bool hasRoute;
  final double pathShift;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: compact ? 205 : 260,
        height: compact ? 78 : 96,
        child: CustomPaint(
          painter: _ArRouteRibbonPainter(
            color: color,
            relativeBearing: relativeBearing,
            hasRoute: hasRoute,
            pathShift: pathShift,
            time: DateTime.now(),
          ),
        ),
      ),
    );
  }
}

class _ArRouteRibbonPainter extends CustomPainter {
  const _ArRouteRibbonPainter({
    required this.color,
    required this.relativeBearing,
    required this.hasRoute,
    required this.pathShift,
    required this.time,
  });

  final Color color;
  final double relativeBearing;
  final bool hasRoute;
  final double pathShift;
  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final double pulse = CurvesEase.pulse(time, speed: 1400);
    final double shift =
        (relativeBearing / 90.0).clamp(-1.0, 1.0) * 24.0 + pathShift * 20.0;

    final ui.Path path = ui.Path()
      ..moveTo(size.width * 0.50, size.height)
      ..quadraticBezierTo(
        size.width * 0.50 + shift * 0.6,
        size.height * 0.55,
        size.width * 0.50 + shift,
        size.height * 0.08,
      );

    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasRoute ? 34 : 20
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: hasRoute ? 0.20 + pulse * 0.08 : 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    final Paint ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasRoute ? 18 : 10
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: hasRoute ? 0.64 : 0.28);

    final Paint center = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasRoute ? 4 : 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: hasRoute ? 0.55 : 0.20);

    canvas.drawPath(path, glow);
    canvas.drawPath(path, ribbon);
    canvas.drawPath(path, center);
  }

  @override
  bool shouldRepaint(covariant _ArRouteRibbonPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.hasRoute != hasRoute ||
        oldDelegate.pathShift != pathShift ||
        oldDelegate.time.millisecondsSinceEpoch ~/ 250 !=
            time.millisecondsSinceEpoch ~/ 250;
  }
}

class _Ar3DChevrons extends StatelessWidget {
  const _Ar3DChevrons({
    required this.color,
    required this.relativeBearing,
    required this.locked,
    required this.compact,
  });

  final Color color;
  final double relativeBearing;
  final bool locked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 190 : 235,
      height: compact ? 86 : 108,
      child: CustomPaint(
        painter: _Ar3DChevronPainter(
          color: color,
          relativeBearing: relativeBearing,
          locked: locked,
          time: DateTime.now(),
        ),
      ),
    );
  }
}

class _Ar3DChevronPainter extends CustomPainter {
  const _Ar3DChevronPainter({
    required this.color,
    required this.relativeBearing,
    required this.locked,
    required this.time,
  });

  final Color color;
  final double relativeBearing;
  final bool locked;
  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final double pulse = CurvesEase.pulse(time, speed: 900);
    final double angle = (relativeBearing / 90.0).clamp(-1.0, 1.0) * 0.22;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    for (int i = 0; i < 3; i++) {
      final double x = (i - 1) * size.width * 0.22;
      final double alpha = i == 0
          ? 1.0
          : i == 1
              ? 0.72
              : 0.48;

      final ui.Path face = ui.Path()
        ..moveTo(x + size.width * 0.10, -size.height * 0.30)
        ..lineTo(x - size.width * 0.08, 0)
        ..lineTo(x + size.width * 0.10, size.height * 0.30);

      final Paint shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final Paint edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: alpha);

      final Paint fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: alpha);

      canvas.drawPath(face, shadow);
      canvas.drawPath(face, edge);
      canvas.drawPath(face, fill);
    }

    if (locked) {
      canvas.drawCircle(
        Offset.zero,
        46 + pulse * 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.25),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Ar3DChevronPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.locked != locked ||
        oldDelegate.time.millisecondsSinceEpoch ~/ 250 !=
            time.millisecondsSinceEpoch ~/ 250;
  }
}

class _Ar3DFloorArrow extends StatelessWidget {
  const _Ar3DFloorArrow({
    required this.color,
    required this.relativeBearing,
    required this.locked,
    required this.compact,
  });

  final Color color;
  final double relativeBearing;
  final bool locked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 150 : 190,
      height: compact ? 86 : 110,
      child: CustomPaint(
        painter: _Ar3DFloorArrowPainter(
          color: color,
          relativeBearing: relativeBearing,
          locked: locked,
          time: DateTime.now(),
        ),
      ),
    );
  }
}

class _Ar3DFloorArrowPainter extends CustomPainter {
  const _Ar3DFloorArrowPainter({
    required this.color,
    required this.relativeBearing,
    required this.locked,
    required this.time,
  });

  final Color color;
  final double relativeBearing;
  final bool locked;
  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final double pulse = CurvesEase.pulse(time, speed: 1100);
    final double angle = (relativeBearing / 90.0).clamp(-1.0, 1.0) * 0.28;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    final Paint groundShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, size.height * 0.28),
        width: size.width * 0.78,
        height: size.height * 0.22,
      ),
      groundShadow,
    );

    final ui.Path arrow = ui.Path()
      ..moveTo(0, -size.height * 0.40)
      ..lineTo(size.width * 0.34, -size.height * 0.02)
      ..lineTo(size.width * 0.14, -size.height * 0.02)
      ..lineTo(size.width * 0.14, size.height * 0.36)
      ..lineTo(-size.width * 0.14, size.height * 0.36)
      ..lineTo(-size.width * 0.14, -size.height * 0.02)
      ..lineTo(-size.width * 0.34, -size.height * 0.02)
      ..close();

    final Paint side = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.62);
    final Paint face = Paint()
      ..style = PaintingStyle.fill
      ..color = Color.lerp(Colors.white, color, 0.32)!;
    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: 0.82);

    canvas.save();
    canvas.translate(8, 10);
    canvas.drawPath(arrow, side);
    canvas.restore();

    canvas.drawPath(arrow, face);
    canvas.drawPath(arrow, outline);

    if (locked) {
      canvas.drawCircle(
        Offset.zero,
        size.height * (0.52 + pulse * 0.05),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.30),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Ar3DFloorArrowPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.locked != locked ||
        oldDelegate.time.millisecondsSinceEpoch ~/ 250 !=
            time.millisecondsSinceEpoch ~/ 250;
  }
}

class _ArMarkerlessScanPainter extends CustomPainter {
  const _ArMarkerlessScanPainter({
    required this.scene,
    required this.color,
  });

  final ArSceneSnapshot scene;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double pulse = CurvesEase.pulse(scene.updatedAt, speed: 1200);

    final Paint planePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.08);
    final Paint planeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.38);

    final ui.Path plane = ui.Path()
      ..moveTo(size.width * 0.22, size.height * 0.18)
      ..lineTo(size.width * 0.78, size.height * 0.18)
      ..lineTo(size.width * 0.96, size.height * 0.88)
      ..lineTo(size.width * 0.04, size.height * 0.88)
      ..close();

    canvas.drawPath(plane, planePaint);
    canvas.drawPath(plane, planeStroke);

    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.12);

    for (int i = 1; i <= 3; i++) {
      final double t = i / 4;
      canvas.drawLine(
        Offset(size.width * (0.22 - t * 0.18), size.height * (0.18 + t * 0.70)),
        Offset(size.width * (0.78 + t * 0.18), size.height * (0.18 + t * 0.70)),
        grid,
      );
    }

    final Paint dot = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final List<Offset> anchors = <Offset>[
      Offset(size.width * 0.34, size.height * 0.42),
      Offset(size.width * 0.64, size.height * 0.42),
      Offset(size.width * 0.40, size.height * 0.67),
      Offset(size.width * 0.70, size.height * 0.70),
    ];

    for (final Offset point in anchors) {
      canvas.drawCircle(point, 4 + pulse * 1.5, dot);
      canvas.drawCircle(
        point,
        10 + pulse * 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.28),
      );
    }

    final Paint cube = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = scene.anchorLocked ? _kArGreen : color;

    final Rect front = Rect.fromCenter(
      center: Offset(size.width * 0.52, size.height * 0.56),
      width: size.width * 0.22,
      height: size.height * 0.22,
    );

    canvas.drawRect(front, cube);
    canvas.drawLine(front.topLeft, front.topLeft.translate(18, -14), cube);
    canvas.drawLine(front.topRight, front.topRight.translate(18, -14), cube);
    canvas.drawLine(
        front.bottomRight, front.bottomRight.translate(18, -14), cube);
    canvas.drawLine(front.topLeft.translate(18, -14),
        front.topRight.translate(18, -14), cube);
    canvas.drawLine(front.topRight.translate(18, -14),
        front.bottomRight.translate(18, -14), cube);

    if (scene.hasObstacle) {
      final Paint warning = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _kArGold;
      canvas.drawCircle(
        Offset(size.width * 0.74, size.height * 0.46),
        16,
        warning,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArMarkerlessScanPainter oldDelegate) {
    return oldDelegate.scene.scanState != scene.scanState ||
        oldDelegate.scene.anchorConfidence != scene.anchorConfidence ||
        oldDelegate.scene.scanConfidence != scene.scanConfidence ||
        oldDelegate.scene.hasObstacle != scene.hasObstacle ||
        oldDelegate.color != color ||
        oldDelegate.scene.updatedAt.millisecondsSinceEpoch ~/ 250 !=
            scene.updatedAt.millisecondsSinceEpoch ~/ 250;
  }
}

class _ArRadarPainter extends CustomPainter {
  const _ArRadarPainter({
    required this.heading,
    required this.targetBearing,
    required this.relativeBearing,
    required this.hasRoute,
    required this.color,
  });

  final double heading;
  final double targetBearing;
  final double relativeBearing;
  final bool hasRoute;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2.0;
    final double outerRadius = radius - 4.0;

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.18);

    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.10);

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = color.withValues(alpha: 0.42);

    canvas.drawCircle(center, outerRadius, ringPaint);
    canvas.drawCircle(center, outerRadius * 0.58, gridPaint);

    canvas.drawLine(
      Offset(center.dx, center.dy - outerRadius),
      Offset(center.dx, center.dy + outerRadius),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx - outerRadius, center.dy),
      Offset(center.dx + outerRadius, center.dy),
      gridPaint,
    );

    final TextPainter north = _label('N', color);
    final TextPainter east = _label('E', Colors.white.withValues(alpha: 0.55));
    final TextPainter south = _label('S', Colors.white.withValues(alpha: 0.55));
    final TextPainter west = _label('W', Colors.white.withValues(alpha: 0.55));

    north.paint(canvas,
        Offset(center.dx - north.width / 2, center.dy - outerRadius - 1));
    east.paint(
        canvas,
        Offset(center.dx + outerRadius - east.width + 1,
            center.dy - east.height / 2));
    south.paint(
        canvas,
        Offset(center.dx - south.width / 2,
            center.dy + outerRadius - south.height + 1));
    west.paint(canvas,
        Offset(center.dx - outerRadius - 1, center.dy - west.height / 2));

    final double headingRad = _degToRad(heading - 90.0);
    final Offset headingEnd = Offset(
      center.dx + math.cos(headingRad) * outerRadius * 0.74,
      center.dy + math.sin(headingRad) * outerRadius * 0.74,
    );

    final Paint headingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.82);

    canvas.drawLine(center, headingEnd, headingPaint);
    canvas.drawCircle(headingEnd, 3.2, Paint()..color = Colors.white);

    if (hasRoute) {
      final double targetRad = _degToRad(relativeBearing - 90.0);
      final Offset target = Offset(
        center.dx + math.cos(targetRad) * outerRadius * 0.62,
        center.dy + math.sin(targetRad) * outerRadius * 0.62,
      );

      canvas.drawCircle(center, outerRadius * 0.72, glowPaint);

      final Paint targetPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;

      canvas.drawCircle(target, 5.2, targetPaint);
      canvas.drawCircle(
        target,
        9.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.38),
      );
    } else {
      final Paint idlePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.36);

      canvas.drawCircle(center, outerRadius * 0.28, idlePaint);
      canvas.drawCircle(center, 3.6, Paint()..color = color);
    }
  }

  TextPainter _label(String text, Color color) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  double _degToRad(double degrees) => degrees * math.pi / 180.0;

  @override
  bool shouldRepaint(covariant _ArRadarPainter oldDelegate) {
    return oldDelegate.heading != heading ||
        oldDelegate.targetBearing != targetBearing ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.hasRoute != hasRoute ||
        oldDelegate.color != color;
  }
}

class _ArSensorRadar extends StatelessWidget {
  const _ArSensorRadar({
    required this.snapshot,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color = snapshot.hasRoute ? _kArBlueSoft : _kArGold;
    final double radarSize = compact ? 72.0 : 94.0;

    return _ArGlass(
      radius: compact ? 22 : 26,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        compact ? 8 : 10,
        compact ? 10 : 12,
        compact ? 8 : 10,
      ),
      color: Colors.black.withValues(alpha: 0.58),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CustomPaint(
            size: Size.square(radarSize),
            painter: _ArRadarPainter(
              heading: snapshot.heading,
              targetBearing: snapshot.targetBearing,
              relativeBearing: snapshot.relativeBearing,
              hasRoute: snapshot.hasRoute,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 150 : 176),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  snapshot.hasRoute ? 'TARGET RADAR' : 'RADAR READY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot.hasRoute
                      ? _radarInstruction(snapshot.relativeBearing)
                      : 'Plan route to show the target dot.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Bearing ${snapshot.targetBearing.round()}° · ${snapshot.relativeBearing.round()}°',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white.withValues(alpha: 0.52),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArSlideHintCard extends StatelessWidget {
  const _ArSlideHintCard({
    required this.label,
    required this.compact,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: 16,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 8 : 9,
      ),
      color: Colors.black.withValues(alpha: 0.52),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            CupertinoIcons.chevron_down_circle,
            color: _kArBlueSoft,
            size: compact ? 14 : 16,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: TextDecoration.none,
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArBottomHud extends StatelessWidget {
  const _ArBottomHud({
    required this.snapshot,
    required this.compact,
  });

  final _ArRouteSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: compact ? 22 : 26,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 9 : 11,
      ),
      color: Colors.black.withValues(alpha: 0.70),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: compact ? 58 : 72,
            child: Column(
              children: <Widget>[
                Text(
                  snapshot.speedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: compact ? 27 : 34,
                    height: 0.94,
                    fontWeight: FontWeight.w900,
                    letterSpacing: compact ? -1.2 : -1.7,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snapshot.speedUnit,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: _kArBlueSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.15,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: compact ? 34 : 40,
            margin: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (snapshot.hasRoute ? _kArGreen : _kArGold)
                        .withValues(alpha: 0.13),
                    border: Border.all(
                      color: (snapshot.hasRoute ? _kArGreen : _kArGold)
                          .withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(
                    snapshot.hasRoute
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.exclamationmark_triangle_fill,
                    color: snapshot.hasRoute ? _kArGreen : _kArGold,
                    size: compact ? 16 : 18,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    snapshot.coachTip,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: TextDecoration.none,
                      color: Colors.white,
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1.16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _radarInstruction(double relativeBearing) {
  final double bearing = relativeBearing.isFinite ? relativeBearing : 0.0;
  final double absBearing = bearing.abs();

  if (absBearing <= 10.0) return 'Target straight ahead.';
  if (absBearing <= 35.0) {
    return bearing > 0.0 ? 'Target slightly right.' : 'Target slightly left.';
  }
  if (absBearing <= 80.0) {
    return bearing > 0.0
        ? 'Turn right toward target.'
        : 'Turn left toward target.';
  }
  if (absBearing <= 135.0) {
    return bearing > 0.0
        ? 'Sharp right toward route.'
        : 'Sharp left toward route.';
  }
  return 'Turn around toward route.';
}

double _normDeg(double value) {
  if (!value.isFinite) return 0.0;
  final double normalized = value % 360.0;
  return normalized < 0.0 ? normalized + 360.0 : normalized;
}

double _signedHeadingDelta(double from, double to) {
  double delta = _normDeg(to) - _normDeg(from);
  if (delta > 180.0) delta -= 360.0;
  if (delta < -180.0) delta += 360.0;
  return delta;
}

class _ArObjectSpeedLabel extends StatelessWidget {
  const _ArObjectSpeedLabel({required this.object});

  final AiTrackedObject object;

  @override
  Widget build(BuildContext context) {
    final bool isAuto = object.id.startsWith('auto-');

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: object.risk.color.withValues(alpha: 0.90),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: object.risk.color.withValues(alpha: 0.18),
              blurRadius: 12,
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: object.risk.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAuto ? 'Auto tracked object' : 'Locked object',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: object.risk.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '~${object.speedLabel} · Risk ${object.riskScore}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
