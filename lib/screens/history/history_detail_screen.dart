part of 'history_screen.dart';

const double _kReplayPanelSafeGap = 18.0;
const double _kReplayFloatingGap = 22.0;
const double _kReplayCollapsedPanelHeight = 92.0;
const double _kReplayExpandedPanelHeight = 216.0;

// TRIP DETAIL / REPLAY
// ═══════════════════════════════════════════════════════════════════════════════

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.trip,
    required this.settings,
    required this.onExport,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final ValueChanged<SavedTrip> onExport;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen>
    with TickerProviderStateMixin {
  // ── Map ──────────────────────────────────────────────────────────────────
  late final fm.MapController _mapController;
  late final List<SavedRoutePoint> _route;
  late final List<LatLng> _points;

  bool _mapReady = false;

  // ── Replay engine ─────────────────────────────────────────────────────────
  Timer? _replayTimer;
  DateTime _lastReplayTick = DateTime.now();

  bool _replayPlaying = false;
  int _replayIndex = 0;
  double _segmentProgress = 0.0;
  double _replaySpeedMph = 0.0;
  double _replayBearing = 0.0;
  double _replaySpeedMultiplier = 1.0;

  final ValueNotifier<LatLng?> _replayPositionNotifier =
      ValueNotifier<LatLng?>(null);
  final ValueNotifier<double> _replayBearingNotifier =
      ValueNotifier<double>(0.0);
  final ValueNotifier<double> _hudSpeed = ValueNotifier<double>(0.0);

  final ValueNotifier<int> _replayIndexNotifier = ValueNotifier<int>(0);

  // ── Camera ────────────────────────────────────────────────────────────────
  bool _followMode = true;
  double _currentZoom = _kDefaultReplayZoom;

  late final AnimationController _cameraAnimController;
  Animation<LatLng>? _moveAnim;
  VoidCallback? _cameraAnimListener;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _mapStylePickerOpen = false;
  bool _showSpeedGradient = false;

  bool _topCardExpanded = true;
  bool _replayPanelExpanded = true;
  Timer? _autoCollapseTimer;

  late MapboxVisualStyle _visualStyle;

  late final AnimationController _zoomInCtrl;
  late final AnimationController _zoomOutCtrl;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get _hasRoute => _points.length >= 2;

  Duration get _elapsedReplayTime {
    if (!_hasRoute || widget.trip.totalTime.inSeconds == 0) {
      return Duration.zero;
    }
    final double fraction =
        (_replayIndex + _segmentProgress) / math.max(1, _points.length - 1);
    return Duration(
      milliseconds: (fraction * widget.trip.totalTime.inMilliseconds).round(),
    );
  }

  String _estimatedRemaining(double multiplier) {
    final Duration total = widget.trip.totalTime;
    if (total.inSeconds == 0) return '';

    final double fraction =
        (_replayIndex + _segmentProgress) / math.max(1, _points.length - 1);
    final double remainingRealSeconds = total.inSeconds * (1.0 - fraction);
    final double replaySeconds = remainingRealSeconds / multiplier;

    if (replaySeconds < 60) return '~${replaySeconds.round()}s';
    final int mins = (replaySeconds / 60).round();
    return '~${mins}m';
  }

  Color _speedColor(double speedMph) {
    if (!speedMph.isFinite || speedMph <= 0.0) return _kBlue;
    if (speedMph < 10) return _kBlue.withValues(alpha: 0.8);
    if (speedMph < 25) return _kBlue;
    if (speedMph < 45) return Colors.white;
    if (speedMph < 62) return _kCyan;
    return _kRed;
  }

  @override
  void initState() {
    super.initState();

    _mapController = fm.MapController();

    _route = widget.trip.route
        .where((SavedRoutePoint p) => p.isValid)
        .toList(growable: false);
    _points =
        _route.map((SavedRoutePoint p) => p.latLng).toList(growable: false);

    _visualStyle = _initialVisualStyle();

    _zoomInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
      value: 1.0,
      lowerBound: 0.88,
      upperBound: 1.0,
    );
    _zoomOutCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
      value: 1.0,
      lowerBound: 0.88,
      upperBound: 1.0,
    );

    _cameraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    if (_hasRoute) {
      _replayPositionNotifier.value = _points.first;
      _replayBearingNotifier.value = _bearingBetween(_points.first, _points[1]);
      _replaySpeedMph = _route.first.speedMph;
      _replayBearing = _replayBearingNotifier.value;
      _hudSpeed.value = _replaySpeedMph;
    }

    _autoCollapseTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _topCardExpanded) {
        setState(() => _topCardExpanded = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hasRoute) {
        _fitRoute(haptic: false);
      } else if (_points.isNotEmpty) {
        _animatedMove(_points.first, _currentZoom);
      }
    });
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _stopReplayTimer();
    if (_moveAnim != null && _cameraAnimListener != null) {
      _moveAnim!.removeListener(_cameraAnimListener!);
    }
    _cameraAnimListener = null;
    _cameraAnimController.stop();
    _cameraAnimController.dispose();
    _moveAnim = null;
    _mapReady = false;
    _mapController.dispose();
    _replayPositionNotifier.dispose();
    _replayBearingNotifier.dispose();
    _replayIndexNotifier.dispose();
    _hudSpeed.dispose();
    _zoomInCtrl.dispose();
    _zoomOutCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDetailExportSheet(SavedTrip trip) async {
    HapticFeedback.mediumImpact();

    await showCupertinoModalPopup<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext sheetContext) {
        return _TripExportSheet(
          trip: trip,
          settings: widget.settings,
          onSelected: (TripExportFormat format) async {
            Navigator.of(sheetContext).pop();
            await _copyDetailTripExport(trip, format);
          },
        );
      },
    );
  }

  Future<void> _copyDetailTripExport(
    SavedTrip trip,
    TripExportFormat format,
  ) async {
    final bool routeFormat =
        format == TripExportFormat.gpx || format == TripExportFormat.kml;
    if (routeFormat && trip.route.length < 2) {
      _showDetailSnack(
        'This trip has no route points to export as ${format.label}.',
        _kRed,
      );
      return;
    }

    final String content = _TripExportBuilder.build(
      trip: trip,
      settings: widget.settings,
      format: format,
    );
    final String filename = _TripExportBuilder.fileName(trip, format);

    final bool shared = await _shareTripExportFile(
      context: context,
      filename: filename,
      content: content,
      format: format,
    );
    if (!mounted) return;

    if (shared) {
      _showDetailSnack('$filename ready to share.', _kGreen);
      return;
    }

    final bool copied = await _safeCopyToClipboard(content);
    if (!mounted) return;

    if (copied) {
      _showDetailSnack(
        'Share unavailable. $filename copied to clipboard.',
        _kGoldSoft,
      );
      return;
    }

    _showDetailSnack(
      'Share and clipboard are unavailable. Export text opened instead.',
      _kGoldSoft,
    );

    await _showTripExportPreviewPopup(
      context: context,
      filename: filename,
      extensionName: format.extensionName,
      content: content,
    );
  }

  Future<bool> _shareTripExportFile({
    required BuildContext context,
    required String filename,
    required String content,
    required TripExportFormat format,
  }) async {
    // Compile-safe fallback for Trip Replay detail export.
    //
    // The History list export can use the native share-sheet helper from
    // history_export_widgets.dart. This local method intentionally avoids
    // direct SharePlus/XFile references because this file is a `part` file
    // and cannot import packages by itself.
    final bool copied = await _safeCopyToClipboard(content);
    if (!copied && context.mounted) {
      await _showTripExportPreviewPopup(
        context: context,
        filename: filename,
        extensionName: format.extensionName,
        content: content,
      );
    }
    return copied;
  }

  void _showDetailSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewPaddingOf(context).bottom + 240),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  // ── Style helpers ─────────────────────────────────────────────────────────

  MapboxVisualStyle _initialVisualStyle() {
    final List<MapboxVisualStyle> styles = MapboxStyleCatalog.all;
    if (styles.isEmpty) {
      throw StateError('MapboxStyleCatalog.all must not be empty.');
    }

    final String mapName = widget.settings.mapStyle.name.toLowerCase();
    for (final MapboxVisualStyle style in styles) {
      if (style.storageKey.toLowerCase().contains(mapName) ||
          style.label.toLowerCase().contains(mapName)) {
        return style;
      }
    }

    return styles.first;
  }

  void _selectStyle(MapboxVisualStyle style) {
    HapticFeedback.selectionClick();
    setState(() {
      _visualStyle = style;
      _mapStylePickerOpen = false;
    });
  }

  void _toggleStylePicker() {
    HapticFeedback.selectionClick();
    setState(() => _mapStylePickerOpen = !_mapStylePickerOpen);
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _animatedMove(LatLng destination, double zoom, {bool force = false}) {
    if (!destination.latitude.isFinite || !destination.longitude.isFinite) {
      return;
    }

    final double safeZoom = zoom.clamp(_kMinZoom, _kMaxZoom).toDouble();

    if (!_mapReady || !mounted) {
      try {
        _mapController.move(destination, safeZoom);
      } catch (_) {}
      return;
    }

    LatLng start;
    try {
      start = _mapController.camera.center;
    } catch (_) {
      try {
        _mapController.move(destination, safeZoom);
      } catch (_) {}
      return;
    }

    if (_moveAnim != null && _cameraAnimListener != null) {
      _moveAnim!.removeListener(_cameraAnimListener!);
    }

    _cameraAnimController.stop();
    _cameraAnimController.reset();

    final Animation<LatLng> anim =
        _LatLngTween(begin: start, end: destination).animate(
      CurvedAnimation(
        parent: _cameraAnimController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _moveAnim = anim;

    void listener() {
      if (!mounted || !_mapReady || _moveAnim != anim) return;
      try {
        _mapController.move(anim.value, safeZoom);
      } catch (_) {}
    }

    _cameraAnimListener = listener;
    anim.addListener(listener);

    _cameraAnimController.forward().whenComplete(() {
      if (_moveAnim == anim && _cameraAnimListener == listener) {
        anim.removeListener(listener);
        _cameraAnimListener = null;
        _moveAnim = null;
      }
    });
  }

  void _fitRoute({bool haptic = true}) {
    if (_points.isEmpty) return;
    if (haptic) HapticFeedback.lightImpact();

    if (_points.length == 1) {
      _animatedMove(_points.first, _currentZoom, force: true);
      return;
    }

    final fm.LatLngBounds bounds = fm.LatLngBounds.fromPoints(_points);

    if (_mapReady && mounted) {
      try {
        _mapController.fitCamera(
          fm.CameraFit.bounds(
            bounds: bounds,
            padding: EdgeInsets.fromLTRB(46, 132, 46, MediaQuery.viewPaddingOf(context).bottom + 350),
          ),
        );
      } catch (_) {}
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      try {
        setState(() {
          _currentZoom = _mapController.camera.zoom;
        });
      } catch (_) {}
    });

    setState(() => _followMode = false);
  }

  void _toggleFollow() {
    HapticFeedback.lightImpact();
    final bool next = !_followMode;
    setState(() => _followMode = next);
    if (next && _replayPositionNotifier.value != null) {
      _animatedMove(_replayPositionNotifier.value!, _currentZoom, force: true);
    }
  }

  void _doZoom(int delta, AnimationController ctrl) {
    HapticFeedback.selectionClick();
    ctrl.reverse().then((_) => ctrl.forward());

    double base = _currentZoom;
    if (_mapReady && mounted) {
      try {
        base = _mapController.camera.zoom;
      } catch (_) {}
    }

    final double nextZoom =
        (base + delta).clamp(_kMinZoom, _kMaxZoom).toDouble();
    setState(() => _currentZoom = nextZoom);

    if (_mapReady && mounted) {
      try {
        _mapController.move(_mapController.camera.center, nextZoom);
      } catch (_) {}
    }
  }

  void _moveMapToReplayPosition() {
    final LatLng? position = _replayPositionNotifier.value;
    if (position == null || !_followMode || !_mapReady || !mounted) return;

    try {
      _mapController.move(
          position, math.max(_currentZoom, _kDefaultReplayZoom));
    } catch (_) {}
  }

  // ── Replay engine ─────────────────────────────────────────────────────────

  void _startReplay() {
    if (!_hasRoute) return;
    HapticFeedback.selectionClick();

    if (_replayIndex >= _points.length - 1 && _segmentProgress >= 1.0) {
      _resetReplayState();
    }

    _lastReplayTick = DateTime.now();
    setState(() => _replayPlaying = true);
    _replayTimer ??= Timer.periodic(_kReplayFrame, (_) => _onReplayTick());
  }

  void _pauseReplay() {
    _stopReplayTimer();
    if (mounted) setState(() => _replayPlaying = false);
  }

  void _resetReplay() {
    HapticFeedback.selectionClick();
    _stopReplayTimer();
    _resetReplayState();
    _moveMapToReplayPosition();
  }

  void _resetReplayState() {
    if (!mounted) return;
    _replayIndex = 0;
    _segmentProgress = 0.0;
    _replaySpeedMph = _route.isNotEmpty ? _route.first.speedMph : 0.0;
    _replayBearing =
        _hasRoute ? _bearingBetween(_points.first, _points[1]) : 0.0;

    final LatLng? startPos = _hasRoute ? _points.first : null;
    _replayPositionNotifier.value = startPos;
    _replayBearingNotifier.value = _replayBearing;
    _replayIndexNotifier.value = 0;
    _hudSpeed.value = _replaySpeedMph;

    setState(() => _replayPlaying = false);
  }

  void _stopReplayTimer() {
    _replayTimer?.cancel();
    _replayTimer = null;
  }

  void _skipReplay(int seconds) {
    if (!_hasRoute) return;
    HapticFeedback.selectionClick();

    final Duration totalDur = widget.trip.totalTime;
    if (totalDur.inSeconds <= 0) return; // Prevent division-by-zero

    final Duration current = _elapsedReplayTime;
    final int newSeconds =
        (current.inSeconds + seconds).clamp(0, totalDur.inSeconds).toInt();
    final double targetProgress = newSeconds / totalDur.inSeconds;

    _scrubReplay(targetProgress);
  }

  void _onReplayTick() {
    if (!_hasRoute || !mounted) return;

    final DateTime now = DateTime.now();
    final double dt = now.difference(_lastReplayTick).inMilliseconds / 1000.0;
    _lastReplayTick = now;

    final double step =
        (dt * _replaySpeedMultiplier * 1.8).clamp(0.0, 0.20).toDouble();

    int newIndex = _replayIndex;
    double newProgress = _segmentProgress + step;

    while (newProgress >= 1.0 && newIndex < _points.length - 2) {
      newProgress -= 1.0;
      newIndex++;
    }

    bool didEnd = false;
    if (newIndex >= _points.length - 2 && newProgress >= 1.0) {
      newIndex = _points.length - 2;
      newProgress = 1.0;
      didEnd = true;
    }

    _replayIndex = newIndex;
    _segmentProgress = newProgress;

    final LatLng a = _points[_replayIndex];
    final LatLng b =
        _points[(_replayIndex + 1).clamp(0, _points.length - 1).toInt()];
    final double t = newProgress.clamp(0.0, 1.0).toDouble();

    final LatLng newPosition = LatLng(
      ui.lerpDouble(a.latitude, b.latitude, t) ?? a.latitude,
      ui.lerpDouble(a.longitude, b.longitude, t) ?? a.longitude,
    );

    final double startSpd = _route[_replayIndex].speedMph;
    final double endSpd =
        _route[(_replayIndex + 1).clamp(0, _route.length - 1).toInt()].speedMph;
    final double newSpeed = ui.lerpDouble(startSpd, endSpd, t) ?? startSpd;
    final double newBearing = _bearingBetween(a, b);

    _replayPositionNotifier.value = newPosition;
    _replayBearingNotifier.value = newBearing;
    _hudSpeed.value = newSpeed;
    _replayIndexNotifier.value = _replayIndex;
    _replaySpeedMph = newSpeed;
    _replayBearing = newBearing;

    _moveMapToReplayPosition();

    if (didEnd) {
      _stopReplayTimer();
      if (mounted) {
        setState(() => _replayPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Replay complete'),
            backgroundColor: _kGoldSoft.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 200),
            duration: const Duration(seconds: 2),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );

        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted && !_replayPlaying && _segmentProgress >= 1.0) {
            _resetReplayState();
            _moveMapToReplayPosition();
          }
        });
      }
    }
  }

  void _scrubReplay(double value) {
    if (!_hasRoute) return;
    _pauseReplay();

    final double safe = value.clamp(0.0, 1.0).toDouble();
    final double scaled = safe * (_points.length - 1);
    final int index =
        scaled.floor().clamp(0, math.max(0, _points.length - 2)).toInt();
    final double progress = (scaled - index).clamp(0.0, 1.0).toDouble();

    _replayIndex = index;
    _segmentProgress = progress;

    final LatLng a = _points[_replayIndex];
    final LatLng b =
        _points[(_replayIndex + 1).clamp(0, _points.length - 1).toInt()];
    final LatLng newPos = LatLng(
      ui.lerpDouble(a.latitude, b.latitude, progress) ?? a.latitude,
      ui.lerpDouble(a.longitude, b.longitude, progress) ?? a.longitude,
    );
    final double newBearing = _bearingBetween(a, b);

    _replayPositionNotifier.value = newPos;
    _replayBearingNotifier.value = newBearing;
    _replayBearing = newBearing;
    _replaySpeedMph = _route[_replayIndex].speedMph;
    _replayIndexNotifier.value = _replayIndex;
    _hudSpeed.value = _replaySpeedMph;

    _moveMapToReplayPosition();
    setState(() {}); // Update slider progress bar only.
  }

  void _setReplayMultiplier(double value) {
    HapticFeedback.selectionClick();
    setState(() => _replaySpeedMultiplier = value);
    if (_replayPlaying) {
      _stopReplayTimer();
      _lastReplayTick = DateTime.now();
      _replayTimer = Timer.periodic(_kReplayFrame, (_) => _onReplayTick());
    }
  }

  // ── Map options ───────────────────────────────────────────────────────────

  fm.MapOptions _mapOptions(double safeBottom) {
    if (_hasRoute) {
      return fm.MapOptions(
        initialCameraFit: fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(_points),
          padding: EdgeInsets.fromLTRB(46, 132, 46, safeBottom + 330),
        ),
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
        ),
        onMapReady: () {
          if (mounted) _mapReady = true;
        },
        onMapEvent: (fm.MapEvent event) {
          if (event is fm.MapEventMove) {
            _currentZoom = event.camera.zoom;
          }
          if (event is fm.MapEventMoveStart &&
              event.source != fm.MapEventSource.mapController) {
            if (_followMode && mounted) setState(() => _followMode = false);
          }
        },
      );
    }

    return fm.MapOptions(
      initialCenter: _kFallbackCenter,
      initialZoom: _kFallbackZoom,
      interactionOptions: const fm.InteractionOptions(
        flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
      ),
      onMapReady: () {
        if (mounted) _mapReady = true;
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = widget.settings;
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);

    final double distance =
        settings.toDisplayDistance(widget.trip.distanceMiles);
    final double maxSpeed = settings.toDisplaySpeed(widget.trip.maxSpeedMph);
    final double avgSpeed = settings.toDisplaySpeed(widget.trip.avgSpeedMph);

    final LocationPuckStyle puckStyle = settings.locationPuckStyle;
    final double puckSize = puckStyle.markerSize.clamp(50.0, 92.0).toDouble();

    final double safeTop = padding.top + 10.0;
    final double safeBottom = math.max(padding.bottom, 16.0);
    final double playerBaseHeight = _replayPanelExpanded
        ? _kReplayExpandedPanelHeight
        : _kReplayCollapsedPanelHeight;
    final double playerHeight = playerBaseHeight + safeBottom;
    final double floatingBottom = playerHeight + _kReplayFloatingGap;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: _kBg,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: fm.FlutterMap(
                  mapController: _mapController,
                  options: _mapOptions(safeBottom),
                  children: <Widget>[
                    fm.TileLayer(
                      key: ValueKey<String>(_visualStyle.storageKey),
                      urlTemplate: _visualStyle.rasterTilesUrl(
                        MapboxConfig.accessToken,
                      ),
                      userAgentPackageName: 'com.trackpro.ai',
                      retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.0,
                    ),
                    if (_points.length >= 2) ...<Widget>[
                      if (_showSpeedGradient)
                        _buildSpeedGradientLayer()
                      else
                        fm.PolylineLayer(
                          polylines: <fm.Polyline>[
                            fm.Polyline(
                              points: _points,
                              color: Colors.black.withValues(alpha: 0.64),
                              strokeWidth: 15,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                            fm.Polyline(
                              points: _points,
                              color: Colors.white.withValues(alpha: 0.94),
                              strokeWidth: 11,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                            fm.Polyline(
                              points: _points,
                              color: _kGoldSoft.withValues(alpha: 0.95),
                              strokeWidth: 5,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                          ],
                        ),
                      fm.MarkerLayer(
                        markers: <fm.Marker>[
                          fm.Marker(
                            point: _points.first,
                            width: 32,
                            height: 32,
                            child: _buildMapPin(_kGreen),
                          ),
                          fm.Marker(
                            point: _points.last,
                            width: 32,
                            height: 32,
                            child: _buildMapPin(_kRed),
                          ),
                        ],
                      ),
                    ],
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _replayPositionNotifier,
                      builder: (_, LatLng? pos, __) {
                        if (pos == null) return const SizedBox.shrink();

                        return ValueListenableBuilder<double>(
                          valueListenable: _replayBearingNotifier,
                          builder: (_, double bearing, __) {
                            return ValueListenableBuilder<double>(
                              valueListenable: _hudSpeed,
                              builder: (_, double speedMph, __) {
                                return fm.MarkerLayer(
                                  markers: <fm.Marker>[
                                    fm.Marker(
                                      point: pos,
                                      width: puckSize,
                                      height: puckSize,
                                      alignment: Alignment.center,
                                      child: AppLocationPuck(
                                        style: puckStyle,
                                        bearing: bearing,
                                        speed: settings.toDisplaySpeed(
                                          speedMph,
                                        ),
                                        size: puckSize,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Positioned.fill(child: _MapGradientScrimClean()),
              Positioned(
                left: 14,
                right: 14,
                top: safeTop,
                child: _ReplayTopBar(
                  title: 'Trip Replay',
                  subtitle: widget.trip.formattedDate,
                  style: _visualStyle,
                  stylePickerOpen: _mapStylePickerOpen,
                  onBack: () => Navigator.of(context).maybePop(),
                  onExportTap: () => _openDetailExportSheet(widget.trip),
                  onStyleTap: _toggleStylePicker,
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                top: safeTop + 72,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _topCardExpanded
                      ? _CleanTripStatsBar(
                          key: const ValueKey<String>('expanded-stats'),
                          settings: settings,
                          distance: distance,
                          maxSpeed: maxSpeed,
                          avgSpeed: avgSpeed,
                          duration: widget.trip.formattedDuration,
                          onCollapse: () => setState(() {
                            _topCardExpanded = false;
                          }),
                        )
                      : Align(
                          key: const ValueKey<String>('collapsed-stats'),
                          alignment: Alignment.centerLeft,
                          child: _CompactTripPill(
                            distance:
                                '${distance.toStringAsFixed(distance >= 100 ? 0 : 1)} ${settings.distanceUnit}',
                            onTap: () => setState(() {
                              _topCardExpanded = true;
                            }),
                          ),
                        ),
                ),
              ),
              if (_hasRoute)
                Positioned(
                  left: 14,
                  bottom: floatingBottom,
                  child: _buildSpeedHud(settings),
                ),
              Positioned(
                right: 14,
                bottom: floatingBottom,
                child: _buildMapFloatingControls(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildReplayControls(),
              ),
              if (_mapStylePickerOpen) ...<Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _mapStylePickerOpen = false),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.40),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MapStyleSheet(
                    selected: _visualStyle,
                    onChanged: _selectStyle,
                    bottomPad: safeBottom,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPin(Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 10,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  // ── Speed gradient polyline layer ─────────────────────────────────────────
  Widget _buildSpeedGradientLayer() {
    final List<fm.Polyline> polylines = <fm.Polyline>[];

    for (int i = 1; i < _route.length; i++) {
      final double avgMph = (_route[i - 1].speedMph + _route[i].speedMph) / 2.0;
      final Color color = _speedColor(avgMph);
      final List<LatLng> seg = <LatLng>[_points[i - 1], _points[i]];

      polylines
        ..add(fm.Polyline(
          points: seg,
          color: color.withValues(alpha: 0.22),
          strokeWidth: 13,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ))
        ..add(fm.Polyline(
          points: seg,
          color: color,
          strokeWidth: 4.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ));
    }

    return fm.PolylineLayer(polylines: polylines);
  }

  // ── Speed HUD ─────────────────────────────────────────────────────────────
  Widget _buildSpeedHud(SettingsService settings) {
    return ValueListenableBuilder<double>(
      valueListenable: _hudSpeed,
      builder: (_, double speedMph, __) {
        final double displaySpeed = settings.toDisplaySpeed(speedMph);
        final Color accent = _speedColor(speedMph);

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.82),
                    _kSurface.withValues(alpha: 0.75),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accent.withValues(alpha: 0.22),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.15),
                    blurRadius: 16,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _replayPlaying
                              ? _kGoldSoft
                              : Colors.white.withValues(alpha: 0.3),
                          boxShadow: _replayPlaying
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: _kGoldSoft.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _replayPlaying ? 'REPLAYING' : 'PAUSED',
                        style: TextStyle(
                          decoration: TextDecoration.none,
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> anim) {
                          return FadeTransition(opacity: anim, child: child);
                        },
                        child: Text(
                          displaySpeed.round().toString(),
                          key: ValueKey<int>(displaySpeed.round()),
                          style: const TextStyle(
                            decoration: TextDecoration.none,
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -1.5,
                            fontFeatures: <ui.FontFeature>[
                              ui.FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            settings.speedUnit,
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'max ${settings.toDisplaySpeed(widget.trip.maxSpeedMph).round()}',
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const <ui.FontFeature>[
                                ui.FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 90,
                    child: Stack(
                      children: <Widget>[
                        Container(
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOut,
                          widthFactor:
                              (settings.toDisplaySpeed(_replaySpeedMph) / 100.0)
                                  .clamp(0.025, 1.0)
                                  .toDouble(),
                          child: Container(
                            height: 3.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  accent.withValues(alpha: 0.5),
                                  accent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.7),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Unified Floating Map Controls ──────────────────────────────────────────

  Widget _buildMapFloatingControls() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _CleanMapButton(
                icon: _followMode
                    ? CupertinoIcons.location_fill
                    : CupertinoIcons.location,
                active: _followMode,
                color: _kBlue,
                onTap: _toggleFollow,
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _zoomInCtrl,
                builder: (_, Widget? child) {
                  return Transform.scale(
                      scale: _zoomInCtrl.value, child: child);
                },
                child: _CleanMapButton(
                  icon: CupertinoIcons.plus,
                  onTap: () => _doZoom(1, _zoomInCtrl),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _zoomOutCtrl,
                builder: (_, Widget? child) {
                  return Transform.scale(
                      scale: _zoomOutCtrl.value, child: child);
                },
                child: _CleanMapButton(
                  icon: CupertinoIcons.minus,
                  onTap: () => _doZoom(-1, _zoomOutCtrl),
                ),
              ),
              const SizedBox(height: 6),
              _CleanMapButton(
                icon: CupertinoIcons.viewfinder,
                color: _kGoldSoft,
                onTap: () => _fitRoute(),
              ),
              const SizedBox(height: 6),
              _CleanMapButton(
                icon: _showSpeedGradient
                    ? CupertinoIcons.speedometer
                    : CupertinoIcons.waveform_path_ecg,
                active: _showSpeedGradient,
                color: _kCyan,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showSpeedGradient = !_showSpeedGradient);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplayControls() {
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    final double bottomPad = math.max(padding.bottom, 12.0);
    // Keep enough room for the replay controls on small phones and while
    // AnimatedSwitcher is transitioning between expanded/collapsed players.
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final double expandedHeight =
        math.min(244.0 + bottomPad, screenHeight * 0.34);
    final double collapsedHeight =
        math.min(118.0 + bottomPad, screenHeight * 0.20);
    final double panelHeight = _replayPanelExpanded
        ? math.max(218.0 + bottomPad, expandedHeight)
        : math.max(104.0 + bottomPad, collapsedHeight);

    return ValueListenableBuilder<int>(
      valueListenable: _replayIndexNotifier,
      builder: (_, __, ___) {
        final double progress = !_hasRoute
            ? 0.0
            : ((_replayIndex + _segmentProgress) /
                    math.max(1, _points.length - 1))
                .clamp(0.0, 1.0)
                .toDouble();

        final String elapsedStr = _formatDurationShort(_elapsedReplayTime);
        final String totalStr = _formatDurationShort(widget.trip.totalTime);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: (DragEndDetails details) {
            final double velocity = details.primaryVelocity ?? 0.0;
            if (velocity > 140) {
              HapticFeedback.selectionClick();
              setState(() => _replayPanelExpanded = false);
            } else if (velocity < -140) {
              HapticFeedback.selectionClick();
              setState(() => _replayPanelExpanded = true);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: panelHeight,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: Container(
                  padding: EdgeInsets.fromLTRB(18, 10, 18, bottomPad + 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        _kSurface.withValues(alpha: 0.91),
                        Colors.black.withValues(alpha: 0.98),
                      ],
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.46),
                        blurRadius: 30,
                        offset: const Offset(0, -12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: <Widget>[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _replayPanelExpanded = !_replayPanelExpanded;
                          });
                        },
                        child: SizedBox(
                          height: 18,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: _replayPanelExpanded ? 42 : 58,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRect(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (
                              Widget? currentChild,
                              List<Widget> previousChildren,
                            ) {
                              return Stack(
                                alignment: Alignment.topCenter,
                                clipBehavior: Clip.hardEdge,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              );
                            },
                            child: SingleChildScrollView(
                              key: ValueKey<String>(
                                _replayPanelExpanded
                                    ? 'expanded-player-scroll'
                                    : 'collapsed-player-scroll',
                              ),
                              physics: const NeverScrollableScrollPhysics(),
                              clipBehavior: Clip.hardEdge,
                              child: _replayPanelExpanded
                                  ? _ExpandedReplayPlayer(
                                      hasRoute: _hasRoute,
                                      replayPlaying: _replayPlaying,
                                      progress: progress,
                                      elapsedText: elapsedStr,
                                      totalText: totalStr,
                                      speedMultiplier: _replaySpeedMultiplier,
                                      onScrub: _scrubReplay,
                                      onReset: _resetReplay,
                                      onBackward: () => _skipReplay(-15),
                                      onForward: () => _skipReplay(15),
                                      onPlayPause: _replayPlaying
                                          ? _pauseReplay
                                          : _startReplay,
                                      onSpeedTap: () {
                                        final List<double> values = <double>[
                                          0.5,
                                          1.0,
                                          2.0,
                                          4.0,
                                        ];
                                        final int current = values
                                            .indexOf(_replaySpeedMultiplier);
                                        final double next = values[
                                            (current + 1) % values.length];
                                        _setReplayMultiplier(next);
                                      },
                                    )
                                  : _CollapsedReplayPlayer(
                                      hasRoute: _hasRoute,
                                      replayPlaying: _replayPlaying,
                                      progress: progress,
                                      elapsedText: elapsedStr,
                                      totalText: totalStr,
                                      speedMultiplier: _replaySpeedMultiplier,
                                      onOpen: () {
                                        HapticFeedback.selectionClick();
                                        setState(
                                          () => _replayPanelExpanded = true,
                                        );
                                      },
                                      onPlayPause: _replayPlaying
                                          ? _pauseReplay
                                          : _startReplay,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatDurationShort(Duration duration) {
    final int totalSeconds = math.max(0, duration.inSeconds);
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int secs = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  // ── Bearing helper ────────────────────────────────────────────────────────

  static double _bearingBetween(LatLng a, LatLng b) {
    final double lat1 = _degToRad(a.latitude);
    final double lat2 = _degToRad(b.latitude);
    final double dLng = _degToRad(b.longitude - a.longitude);

    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    return ((_radToDeg(math.atan2(y, x)) + 360.0) % 360.0);
  }

  static double _degToRad(double value) => value * math.pi / 180.0;
  static double _radToDeg(double value) => value * 180.0 / math.pi;
}

class _ExpandedReplayPlayer extends StatelessWidget {
  const _ExpandedReplayPlayer({
    super.key,
    required this.hasRoute,
    required this.replayPlaying,
    required this.progress,
    required this.elapsedText,
    required this.totalText,
    required this.speedMultiplier,
    required this.onScrub,
    required this.onReset,
    required this.onBackward,
    required this.onForward,
    required this.onPlayPause,
    required this.onSpeedTap,
  });

  final bool hasRoute;
  final bool replayPlaying;
  final double progress;
  final String elapsedText;
  final String totalText;
  final double speedMultiplier;
  final ValueChanged<double> onScrub;
  final VoidCallback onReset;
  final VoidCallback onBackward;
  final VoidCallback onForward;
  final VoidCallback onPlayPause;
  final VoidCallback onSpeedTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            _TimeText(elapsedText),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 26,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: <Color>[_kGoldSoft, _kCyan],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: _kGoldSoft.withValues(alpha: 0.28),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    CupertinoSlider(
                      value: progress,
                      min: 0,
                      max: 1,
                      activeColor: Colors.transparent,
                      thumbColor: hasRoute ? _kGoldSoft : Colors.white24,
                      onChanged: hasRoute ? onScrub : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TimeText(totalText, alignRight: true),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            _CleanCircleButton(
              icon: CupertinoIcons.arrow_counterclockwise,
              enabled: hasRoute,
              onTap: onReset,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _CleanCircleButton(
                  icon: CupertinoIcons.gobackward_15,
                  enabled: hasRoute,
                  onTap: onBackward,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasRoute ? onPlayPause : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: hasRoute
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[_kGoldSoft, _kGold],
                        )
                      : null,
                  color: hasRoute ? null : Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  boxShadow: hasRoute
                      ? <BoxShadow>[
                          BoxShadow(
                            color: _kGoldSoft.withValues(alpha: 0.30),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  replayPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  color: hasRoute ? const Color(0xFF15130D) : Colors.white24,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CleanCircleButton(
                  icon: CupertinoIcons.goforward_15,
                  enabled: hasRoute,
                  onTap: onForward,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: _SpeedTinyPill(
                  value: speedMultiplier,
                  onTap: onSpeedTap,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CollapsedReplayPlayer extends StatelessWidget {
  const _CollapsedReplayPlayer({
    super.key,
    required this.hasRoute,
    required this.replayPlaying,
    required this.progress,
    required this.elapsedText,
    required this.totalText,
    required this.speedMultiplier,
    required this.onOpen,
    required this.onPlayPause,
  });

  final bool hasRoute;
  final bool replayPlaying;
  final double progress;
  final String elapsedText;
  final String totalText;
  final double speedMultiplier;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;

  String get _speedLabel {
    if (speedMultiplier == speedMultiplier.roundToDouble()) {
      return '${speedMultiplier.toInt()}x';
    }
    return '${speedMultiplier.toStringAsFixed(1)}x';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hasRoute ? onPlayPause : null,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: hasRoute
                  ? const LinearGradient(colors: <Color>[_kGoldSoft, _kGold])
                  : null,
              color: hasRoute ? null : Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              boxShadow: hasRoute
                  ? <BoxShadow>[
                      BoxShadow(
                        color: _kGoldSoft.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              replayPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              color: hasRoute ? const Color(0xFF15130D) : Colors.white24,
              size: 21,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          elapsedText,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                            fontFeatures: const <ui.FontFeature>[
                              ui.FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            totalText,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.38),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.none,
                              fontFeatures: const <ui.FontFeature>[
                                ui.FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: <Widget>[
                      Container(
                        height: 5,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 5,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[_kGoldSoft, _kCyan],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kCyan.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(color: _kCyan.withValues(alpha: 0.22)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _speedLabel,
                maxLines: 1,
                style: const TextStyle(
                  color: _kCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLEAN TRIP REPLAY SAFE-AREA UI HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class _MapGradientScrimClean extends StatelessWidget {
  const _MapGradientScrimClean();

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
              Colors.black.withValues(alpha: 0.22),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.20),
              Colors.black.withValues(alpha: 0.86),
            ],
            stops: const <double>[0.0, 0.15, 0.43, 0.68, 1.0],
          ),
        ),
      ),
    );
  }
}

class _ReplayTopBar extends StatelessWidget {
  const _ReplayTopBar({
    required this.title,
    required this.subtitle,
    required this.style,
    required this.stylePickerOpen,
    required this.onBack,
    required this.onExportTap,
    required this.onStyleTap,
  });

  final String title;
  final String subtitle;
  final MapboxVisualStyle style;
  final bool stylePickerOpen;
  final VoidCallback onBack;
  final VoidCallback onExportTap;
  final VoidCallback onStyleTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 370;
        final double gap = compact ? 6 : 10;
        final double titleHeight = compact ? 52 : 56;
        final EdgeInsets titlePadding = EdgeInsets.symmetric(
          horizontal: compact ? 11 : 15,
        );

        return Row(
          children: <Widget>[
            _TopGlassButton(
              icon: CupertinoIcons.chevron_left,
              compact: compact,
              onTap: onBack,
            ),
            SizedBox(width: gap),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: titleHeight,
                    padding: titlePadding,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        if (!compact) ...<Widget>[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: _kGoldSoft,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _SafeText(
                                title,
                                maxLines: 1,
                                style: TextStyle(
                                  decoration: TextDecoration.none,
                                  color: Colors.white,
                                  fontSize: compact ? 14 : 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              _SafeText(
                                subtitle,
                                maxLines: 1,
                                style: TextStyle(
                                  decoration: TextDecoration.none,
                                  color: Colors.white54,
                                  fontSize: compact ? 10 : 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: gap),
            _TopGlassButton(
              icon: CupertinoIcons.square_arrow_up_fill,
              color: _kBlue,
              compact: compact,
              onTap: onExportTap,
            ),
            SizedBox(width: gap),
            _TopGlassButton(
              icon: style.icon,
              color: style.accentColor,
              active: stylePickerOpen,
              compact: compact,
              onTap: onStyleTap,
            ),
          ],
        );
      },
    );
  }
}

class _TopGlassButton extends StatelessWidget {
  const _TopGlassButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.active = false,
    this.compact = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: compact ? 48 : 56,
            height: compact ? 52 : 56,
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? color.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Icon(icon, color: active ? color : Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _CleanTripStatsBar extends StatelessWidget {
  const _CleanTripStatsBar({
    super.key,
    required this.settings,
    required this.distance,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.duration,
    required this.onCollapse,
  });

  final SettingsService settings;
  final double distance;
  final double maxSpeed;
  final double avgSpeed;
  final String duration;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _CleanStatTile(
                  label: 'Distance',
                  value: distance.toStringAsFixed(distance >= 100 ? 0 : 1),
                  unit: settings.distanceUnit,
                  color: _kGoldSoft,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CleanStatTile(
                  label: 'Max',
                  value: maxSpeed.round().toString(),
                  unit: settings.speedUnit,
                  color: _kCyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CleanStatTile(
                  label: 'Avg',
                  value: avgSpeed.round().toString(),
                  unit: settings.speedUnit,
                  color: _kGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CleanStatTile(
                  label: 'Time',
                  value: duration,
                  unit: '',
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCollapse,
                child: Container(
                  width: 34,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Icon(
                    CupertinoIcons.chevron_up,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CleanStatTile extends StatelessWidget {
  const _CleanStatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                if (unit.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      unit,
                      maxLines: 1,
                      style: const TextStyle(
                        decoration: TextDecoration.none,
                        color: Colors.white38,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          _SafeText(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              decoration: TextDecoration.none,
              color: Colors.white38,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTripPill extends StatelessWidget {
  const _CompactTripPill({
    super.key,
    required this.distance,
    required this.onTap,
  });

  final String distance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(CupertinoIcons.map_fill,
                    color: _kGoldSoft, size: 15),
                const SizedBox(width: 7),
                _SafeText(
                  distance,
                  maxLines: 1,
                  style: const TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 7),
                const Icon(
                  CupertinoIcons.chevron_down,
                  color: Colors.white54,
                  size: 13,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CleanMapButton extends StatelessWidget {
  const _CleanMapButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(icon, color: active ? color : Colors.white70, size: 19),
      ),
    );
  }
}

class _CleanCircleButton extends StatelessWidget {
  const _CleanCircleButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.075 : 0.035),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: enabled ? 0.10 : 0.04),
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white70 : Colors.white24,
          size: 20,
        ),
      ),
    );
  }
}

class _SpeedTinyPill extends StatelessWidget {
  const _SpeedTinyPill({
    required this.value,
    required this.onTap,
  });

  final double value;
  final VoidCallback onTap;

  String get label {
    if (value == value.roundToDouble()) return '${value.toInt()}x';
    return '${value.toStringAsFixed(1)}x';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _kCyan.withValues(alpha: 0.13),
          shape: BoxShape.circle,
          border: Border.all(color: _kCyan.withValues(alpha: 0.22)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            decoration: TextDecoration.none,
            color: _kCyan,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText(
    this.text, {
    this.alignRight = false,
  });

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none,
            fontFeatures: const <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAIL SCREEN SUPPORTING WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _MapGradientScrim extends StatelessWidget {
  const _MapGradientScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.10),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.36),
              Colors.black.withValues(alpha: 0.92),
            ],
            stops: const <double>[0.0, 0.18, 0.46, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _CollapsibleDetailCard extends StatelessWidget {
  const _CollapsibleDetailCard({
    required this.expanded,
    required this.onToggle,
    required this.trip,
    required this.settings,
    required this.distance,
    required this.maxSpeed,
    required this.avgSpeed,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final SavedTrip trip;
  final SettingsService settings;
  final double distance;
  final double maxSpeed;
  final double avgSpeed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: _GlassCard(
        radius: 28,
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: <Color>[_kGoldSoft, _kGold]),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    CupertinoIcons.location_north_fill,
                    color: Color(0xFF15130D),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _SafeText(
                        'Trip Replay',
                        maxLines: 1,
                        style: TextStyle(
                          decoration: TextDecoration.none,
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _SafeText(
                        trip.formattedDate,
                        maxLines: 1,
                        style: const TextStyle(
                          decoration: TextDecoration.none,
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    CupertinoIcons.chevron_up,
                    color: Colors.white38,
                    size: 16,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _InlineMetric(
                        label: 'Distance',
                        value:
                            distance.toStringAsFixed(distance >= 100 ? 0 : 1),
                        unit: settings.distanceUnit,
                        color: _kGoldSoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InlineMetric(
                        label: 'Max',
                        value: maxSpeed.round().toString(),
                        unit: settings.speedUnit,
                        color: _kCyan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InlineMetric(
                        label: 'Avg',
                        value: avgSpeed.round().toString(),
                        unit: settings.speedUnit,
                        color: _kGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InlineMetric(
                        label: 'Time',
                        value: trip.formattedDuration,
                        unit: '',
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 220),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SafeText(
            value,
            maxLines: 1,
            style: TextStyle(
                decoration: TextDecoration.none,
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          _SafeText(
            unit.isEmpty ? label : '$label · $unit',
            maxLines: 1,
            style: const TextStyle(
                decoration: TextDecoration.none,
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MapStyleButton extends StatelessWidget {
  const _MapStyleButton({
    required this.style,
    required this.open,
    required this.onTap,
  });

  final MapboxVisualStyle style;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: open ? 0.95 : 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: open
                    ? style.accentColor.withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Icon(style.icon, color: style.accentColor, size: 21),
          ),
        ),
      ),
    );
  }
}

class _MapStyleSheet extends StatelessWidget {
  const _MapStyleSheet({
    required this.selected,
    required this.onChanged,
    required this.bottomPad,
  });

  final MapboxVisualStyle selected;
  final ValueChanged<MapboxVisualStyle> onChanged;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _kSurface.withValues(alpha: 0.96),
                Colors.black.withValues(alpha: 0.98),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: _SafeText(
                  'Map Style',
                  maxLines: 1,
                  style: TextStyle(
                    decoration: TextDecoration.none,
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...MapboxStyleCatalog.all.map((MapboxVisualStyle style) {
                final bool active = selected == style;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(style),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: active
                          ? style.accentColor.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: active
                            ? style.accentColor.withValues(alpha: 0.40)
                            : Colors.white.withValues(alpha: 0.07),
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(style.icon, color: style.accentColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SafeText(
                            style.label,
                            maxLines: 1,
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              color: active ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (active)
                          Icon(CupertinoIcons.checkmark_circle_fill,
                              color: style.accentColor, size: 18),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedMultiplierSelector extends StatelessWidget {
  const _SpeedMultiplierSelector({
    required this.selected,
    required this.onChanged,
    required this.estimatedRemaining,
  });

  final double selected;
  final ValueChanged<double> onChanged;
  final String Function(double multiplier) estimatedRemaining;

  static const List<double> _values = <double>[0.5, 1.0, 2.0, 4.0];

  static String _label(double value) {
    if (value == value.roundToDouble()) return '${value.toInt()}x';
    return '${value.toStringAsFixed(1)}x';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _values.map((double value) {
        final bool active = selected == value;
        final String remaining = estimatedRemaining(value);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: active
                      ? const LinearGradient(colors: <Color>[_kBlue, _kCyan])
                      : null,
                  color: active ? null : Colors.white.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? _kCyan.withValues(alpha: 0.34)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _label(value),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        decoration: TextDecoration.none,
                        color: active ? Colors.white : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (remaining.isNotEmpty)
                      Text(
                        remaining,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          decoration: TextDecoration.none,
                          color: active
                              ? Colors.white.withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.25),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _ZoomBox extends StatelessWidget {
  const _ZoomBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _kBorder),
          ),
          child: Icon(icon, color: Colors.white70, size: 19),
        ),
      ),
    );
  }
}

class _ReplayRoundButton extends StatelessWidget {
  const _ReplayRoundButton({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withValues(alpha: 0.105),
                _kSurface.withValues(alpha: 0.82),
                Colors.black.withValues(alpha: 0.40),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

Future<bool> _safeCopyToClipboard(String content) async {
  try {
    await Clipboard.setData(ClipboardData(text: content));
    return true;
  } on PlatformException catch (error, stackTrace) {
    debugPrint('Clipboard export failed: $error\n$stackTrace');
    return false;
  } catch (error, stackTrace) {
    debugPrint('Clipboard export failed: $error\n$stackTrace');
    return false;
  }
}

Future<void> _showTripExportPreviewPopup({
  required BuildContext context,
  required String filename,
  required String extensionName,
  required String content,
}) async {
  await showCupertinoModalPopup<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    builder: (BuildContext popupContext) {
      final double maxHeight = MediaQuery.sizeOf(popupContext).height * 0.82;

      return Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              minWidth: double.infinity,
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                border: Border(
                  top: BorderSide(color: _kBorder),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: <Widget>[
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _kGoldSoft.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(
                                  color: _kGoldSoft.withValues(alpha: 0.20),
                                ),
                              ),
                              child: const Icon(
                                CupertinoIcons.doc_text_fill,
                                color: _kGoldSoft,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _SafeText(
                                    filename,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  _SafeText(
                                    'Clipboard blocked. Select text below and save as .$extensionName',
                                    maxLines: 2,
                                    softWrap: true,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minSize: 40,
                              onPressed: () => Navigator.of(popupContext).pop(),
                              child: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                                color: Colors.white54,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: SelectableText(
                            content,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.35,
                              fontFamily: 'monospace',
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        color: _kGoldSoft,
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () => Navigator.of(popupContext).pop(),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Color(0xFF15130D),
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
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
    },
  );
}
