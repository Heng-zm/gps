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
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

const Color _kArBlue = AppColors.blue;
const Color _kArBlueSoft = AppColors.blueSoft;
const Color _kArGreen = AppColors.green;
const Color _kArRed = AppColors.red;
const Color _kArGold = Color(0xFFFFD54F);
const Color _kArSurface = Color(0xDD05070A);
const Distance _kArDistance = Distance();

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

extension _ArHudModeX on _ArHudMode {
_ArHudMode get next {
    switch (this) {
      case _ArHudMode.full:
        return _ArHudMode.minimal;
      case _ArHudMode.minimal:
        return _ArHudMode.full;
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
  bool _torchOn = false;
  _ArHudMode _hudMode = _ArHudMode.full;
  final ValueNotifier<_ArMotionStability> _motionStabilityN =
      ValueNotifier<_ArMotionStability>(_ArMotionStability.steady);
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  DateTime? _lastMotionSampleAt;
  double _motionEma = 0.0;
  String? _error;
  int _selectedCameraIndex = 0;

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
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initMotionSensor();
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
      if (mounted) setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_accelerometerSub?.cancel());
    _motionStabilityN.dispose();
    unawaited(_cameraController?.dispose());
    super.dispose();
  }


  void _initMotionSensor() {
    unawaited(_accelerometerSub?.cancel());

    try {
      _accelerometerSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 220),
      ).listen(
        _handleAccelerometerEvent,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('AR motion sensor error: $error\n$stackTrace');
        },
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      debugPrint('AR motion sensor init failed: $error\n$stackTrace');
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

    if (_motionStabilityN.value != next) {
      _motionStabilityN.value = next;
    }
  }

  Future<void> _initCamera() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _cameraReady = false;
    });

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No camera available on this device.';
        });
        return;
      }

      int index = _selectedCameraIndex.clamp(0, _cameras.length - 1).toInt();
      final int backIndex = _cameras.indexWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
      );
      if (_cameraController == null && backIndex >= 0) index = backIndex;

      _selectedCameraIndex = index;

      final CameraController controller = CameraController(
        _cameras[index],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController?.dispose();
      _cameraController = controller;

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _loading = false;
        _cameraReady = true;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.description ?? error.code;
      });
    } catch (error, stackTrace) {
      debugPrint('AR camera init failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Camera failed to start.';
      });
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
      debugPrint('Torch toggle failed: $error');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    HapticFeedback.selectionClick();
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
                    motionStability: _motionStabilityN.value,
                    loading: _loading,
                    error: _error,
                  );
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

    if (!_cameraReady || controller == null || !controller.value.isInitialized) {
      return _ArCameraError(
        message: 'Camera is not ready.',
        onRetry: _initCamera,
      );
    }

    final Size screen = MediaQuery.sizeOf(context);
    final Size preview = controller.value.previewSize ?? screen;
    final double previewAspect = preview.height / preview.width;
    final double screenAspect = screen.width / screen.height;

    return Transform.scale(
      scale: previewAspect / screenAspect,
      child: Center(
        child: CameraPreview(controller),
      ),
    );
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

    final bool charging =
        batteryState == BatteryState.charging || batteryState == BatteryState.full;
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
      targetLabel: hasTarget
          ? _distanceLabel(meters, settings)
          : 'Plan route first',
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

    for (int i = 0; i < points.length; i++) {
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
    required this.motionStability,
    required this.loading,
    required this.error,
  });

  final _ArRouteSnapshot snapshot;
  final VoidCallback onClose;
  final VoidCallback onTorch;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHudMode;
  final _ArMotionStability motionStability;
  final bool torchOn;
  final bool canSwitchCamera;
  final _ArHudMode hudMode;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Size size = MediaQuery.sizeOf(context);
    final bool compact = size.width < 390.0 || size.height < 720.0;
    final bool minimal = hudMode == _ArHudMode.minimal;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 14,
          8,
          compact ? 10 : 14,
          12 + safe.bottom * 0.12,
        ),
        child: Column(
          children: <Widget>[
            _ArTopBar(
              onClose: onClose,
              onTorch: onTorch,
              onSwitchCamera: onSwitchCamera,
              onHudMode: onHudMode,
              torchOn: torchOn,
              canSwitchCamera: canSwitchCamera,
              hudMode: hudMode,
            ),
            SizedBox(height: compact ? 8 : 10),
            if (!minimal) _ArStatusStrip(snapshot: snapshot),
            if (!minimal) SizedBox(height: compact ? 8 : 10),
            _ArMotionStabilityBanner(
              stability: motionStability,
              compact: compact || minimal,
            ),
            SizedBox(height: compact ? 6 : 8),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? 360 : 430,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _ArDirectionArrow(
                        snapshot: snapshot,
                        compact: compact || minimal,
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      _ArSensorRadar(
                        snapshot: snapshot,
                        compact: compact || minimal,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _ArBottomHud(
              snapshot: snapshot,
              compact: compact || minimal,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArTopBar extends StatelessWidget {
  const _ArTopBar({
    required this.onClose,
    required this.onTorch,
    required this.onSwitchCamera,
    required this.onHudMode,
    required this.torchOn,
    required this.canSwitchCamera,
    required this.hudMode,
  });

  final VoidCallback onClose;
  final VoidCallback onTorch;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHudMode;
  final bool torchOn;
  final bool canSwitchCamera;
  final _ArHudMode hudMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ArRoundButton(
          icon: CupertinoIcons.xmark,
          label: 'Close AR camera',
          onTap: onClose,
        ),
        const Spacer(),
        const _ArPill(
          icon: CupertinoIcons.camera_viewfinder,
          label: 'AR ROUTE',
          color: _kArBlueSoft,
        ),
        const Spacer(),
        _ArRoundButton(
          icon: torchOn ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
          label: 'Toggle torch',
          active: torchOn,
          onTap: onTorch,
        ),
        const SizedBox(width: 8),
        _ArRoundButton(
          icon: CupertinoIcons.camera_rotate,
          label: 'Switch camera',
          enabled: canSwitchCamera,
          onTap: onSwitchCamera,
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
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
            label: snapshot.hasRoute ? '${snapshot.routePointCount} pts' : 'No route',
            color: snapshot.hasRoute ? _kArGreen : _kArGold,
          ),
        ],
      ),
    );
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
    final double arrowSize = compact ? 82.0 : 112.0;

    return _ArGlass(
      radius: compact ? 28 : 34,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        compact ? 12 : 14,
        compact ? 14 : 18,
        compact ? 13 : 16,
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
          SizedBox(height: compact ? 9 : 12),
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: arrowSize + 34,
                height: arrowSize + 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: arrowColor.withValues(alpha: 0.14),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: arrowColor.withValues(alpha: 0.14),
                      blurRadius: 22,
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
                      color: arrowColor.withValues(alpha: 0.44),
                      blurRadius: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 9),
          Text(
            snapshot.hasRoute
                ? 'follow arrow and radar dot'
                : 'open Route first, then use AR',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                  decoration: TextDecoration.none,
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Icon(
            hasRoute ? Icons.navigation_rounded : Icons.route_rounded,
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                direction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  decoration: TextDecoration.none,
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                distance,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    decoration: TextDecoration.none,
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  fontFeatures: <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

    return _ArGlass(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CustomPaint(
            size: Size.square(compact ? 96 : 118),
            painter: _ArRadarPainter(
              heading: snapshot.heading,
              targetBearing: snapshot.targetBearing,
              relativeBearing: snapshot.relativeBearing,
              hasRoute: snapshot.hasRoute,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 150 : 168),
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
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  snapshot.hasRoute
                      ? _radarInstruction(snapshot.relativeBearing)
                      : 'Plan a route to show target dot.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Bearing ${snapshot.targetBearing.round()}° · ${snapshot.relativeBearing.round()}°',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                  decoration: TextDecoration.none,
                    color: Colors.white.withValues(alpha: 0.56),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _radarInstruction(double relativeBearing) {
    final double abs = relativeBearing.abs();
    if (abs <= 10.0) return 'Target is straight ahead.';
    if (abs <= 45.0) {
      return relativeBearing > 0
          ? 'Target slightly to your right.'
          : 'Target slightly to your left.';
    }
    if (abs <= 120.0) {
      return relativeBearing > 0
          ? 'Turn phone right toward target.'
          : 'Turn phone left toward target.';
    }
    return 'Target is behind you.';
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
    final double radius = math.min(size.width, size.height) / 2.0 - 8.0;

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.18);

    final Paint innerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.08);

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: hasRoute ? 0.22 : 0.10);

    final Paint activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: hasRoute ? 0.92 : 0.36);

    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawCircle(center, radius * 0.62, innerRingPaint);
    canvas.drawCircle(center, radius * 0.30, innerRingPaint);

    _drawCardinalLabels(canvas, center, radius);
    _drawHeadingNeedle(canvas, center, radius);
    _drawTargetArc(canvas, center, radius, glowPaint, activePaint);

    final Paint userPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 4.2, userPaint);

    final Paint userGlow = Paint()
      ..color = color.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, 8.0, userGlow);

    if (hasRoute) {
      final Offset dot = _targetDot(center, radius * 0.72);
      final Paint dotGlow = Paint()
        ..color = color.withValues(alpha: 0.48)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(dot, 12.0, dotGlow);
      canvas.drawCircle(dot, 7.0, Paint()..color = color);
      canvas.drawCircle(dot, 3.0, Paint()..color = Colors.white);
    } else {
      final Paint idlePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = _kArGold.withValues(alpha: 0.5);
      canvas.drawLine(
        center.translate(-14, 0),
        center.translate(14, 0),
        idlePaint,
      );
      canvas.drawLine(
        center.translate(0, -14),
        center.translate(0, 14),
        idlePaint,
      );
    }
  }

  Offset _targetDot(Offset center, double radius) {
    final double radians = relativeBearing * math.pi / 180.0;
    return Offset(
      center.dx + math.sin(radians) * radius,
      center.dy - math.cos(radians) * radius,
    );
  }

  void _drawTargetArc(
    Canvas canvas,
    Offset center,
    double radius,
    Paint glowPaint,
    Paint activePaint,
  ) {
    final double startRad = -math.pi / 2;
    final double sweepRad =
        (relativeBearing.clamp(-180.0, 180.0).toDouble()) * math.pi / 180.0;
    final Rect rect = Rect.fromCircle(center: center, radius: radius - 3);

    canvas.drawArc(rect, startRad, sweepRad, false, glowPaint);
    canvas.drawArc(rect, startRad, sweepRad, false, activePaint);
  }

  void _drawHeadingNeedle(Canvas canvas, Offset center, double radius) {
    final double rad = 0.0; // top of radar = current phone heading
    final Offset end = Offset(
      center.dx + math.sin(rad) * (radius * 0.52),
      center.dy - math.cos(rad) * (radius * 0.52),
    );

    final Paint needlePaint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.82);

    canvas.drawLine(center, end, needlePaint);
    canvas.drawCircle(end, 3.0, Paint()..color = Colors.white);
  }

  void _drawCardinalLabels(Canvas canvas, Offset center, double radius) {
    const List<_RadarLabel> labels = <_RadarLabel>[
      _RadarLabel('N', 0),
      _RadarLabel('E', 90),
      _RadarLabel('S', 180),
      _RadarLabel('W', 270),
    ];

    for (final _RadarLabel label in labels) {
      final double relative = _signedHeadingDelta(heading, label.degrees);
      final double radians = relative * math.pi / 180.0;
      final Offset position = Offset(
        center.dx + math.sin(radians) * (radius + 1),
        center.dy - math.cos(radians) * (radius + 1),
      );

      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: label.text,
          style: TextStyle(
                  decoration: TextDecoration.none,
            color: label.text == 'N'
                ? _kArBlueSoft
                : Colors.white.withValues(alpha: 0.55),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArRadarPainter oldDelegate) {
    return oldDelegate.heading != heading ||
        oldDelegate.targetBearing != targetBearing ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.hasRoute != hasRoute ||
        oldDelegate.color != color;
  }
}

class _RadarLabel {
  const _RadarLabel(this.text, this.degrees);

  final String text;
  final double degrees;
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
      radius: compact ? 26 : 30,
      padding: EdgeInsets.all(compact ? 11 : 14),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: compact ? 76 : 92,
            child: Column(
              children: <Widget>[
                Text(
                  snapshot.speedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                  decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: compact ? 36 : 44,
                    height: 0.92,
                    fontWeight: FontWeight.w900,
                    letterSpacing: compact ? -1.6 : -2.2,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  snapshot.speedUnit,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: _kArBlueSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: compact ? 42 : 48,
            margin: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Icon(
                  snapshot.hasRoute
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.exclamationmark_triangle_fill,
                  color: snapshot.hasRoute ? _kArGreen : _kArGold,
                  size: compact ? 18 : 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    snapshot.coachTip,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                  decoration: TextDecoration.none,
                      color: Colors.white,
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
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
        child: _ArGlass(
          radius: 28,
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  CupertinoIcons.camera_fill,
                  color: _kArGold,
                  size: 38,
                ),
                const SizedBox(height: 12),
                const Text(
                  'AR Camera unavailable',
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
                  style: TextStyle(
                  decoration: TextDecoration.none,
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  color: _kArBlue,
                  borderRadius: BorderRadius.circular(16),
                  onPressed: onRetry,
                  child: const Text(
                    'Retry camera',
                    style: TextStyle(fontWeight: FontWeight.w900),
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
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.28),
              Colors.black.withValues(alpha: 0.72),
            ],
            stops: const <double>[0.0, 0.30, 0.62, 1.0],
          ),
        ),
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
    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 44,
        pressedOpacity: 0.78,
        onPressed: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.42,
          child: _ArGlass(
            radius: 999,
            padding: EdgeInsets.zero,
            color: active
                ? _kArBlue.withValues(alpha: 0.34)
                : Colors.black.withValues(alpha: 0.42),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                color: active ? _kArBlueSoft : Colors.white,
                size: 19,
              ),
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
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _ArGlass(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
                  decoration: TextDecoration.none,
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
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
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? _kArSurface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 18,
                offset: const Offset(0, 8),
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
