// ignore_for_file: unused_element, unused_element_parameter

part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM DOCK — Apple HIG Minimalist Redesign
// ═══════════════════════════════════════════════════════════════════════════════

class _MapFirstBottomDock extends StatefulWidget {
  const _MapFirstBottomDock({
    required this.tickN,
    required this.trackingN,
    required this.elapsedN,
    required this.maxSpeedN,
    required this.autoPausedN,
    required this.autoPauseStoppedN,
    required this.actionBusyN,
    required this.followModeN,
    required this.settings,
    required this.gps,
    required this.onAction,
    required this.onMapTap,
    required this.onAiTap,
    required this.onArTap,
    required this.onWeatherTap,
    required this.onMapboxTap,
    required this.onFollowModeTap,
    required this.performanceModeN,
    required this.onPerformanceTap,
  });

  final ValueNotifier<int> tickN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> elapsedN;
  final ValueNotifier<double> maxSpeedN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<int> autoPauseStoppedN;
  final ValueNotifier<bool> actionBusyN;
  final ValueNotifier<_MapFollowMode> followModeN;
  final SettingsService settings;
  final GpsService gps;
  final VoidCallback onAction;
  final VoidCallback onMapTap;
  final VoidCallback onAiTap;
  final VoidCallback onArTap;
  final VoidCallback onWeatherTap;
  final VoidCallback onMapboxTap;
  final VoidCallback onFollowModeTap;
  final ValueNotifier<_TrackingPerformanceMode> performanceModeN;
  final VoidCallback onPerformanceTap;

  static String _formatSeconds(int seconds) {
    final int safeSeconds = math.max(0, seconds);
    final int hours = safeSeconds ~/ 3600;
    final String minutes =
        ((safeSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String secs = (safeSeconds % 60).toString().padLeft(2, '0');

    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$secs'
        : '$minutes:$secs';
  }

  @override
  State<_MapFirstBottomDock> createState() => _MapFirstBottomDockState();
}

class _MapFirstBottomDockState extends State<_MapFirstBottomDock> {
  static const double _kMaxDockWidth = 440.0;
  static const double _kMinDockWidth = 300.0;
  static const double _kDismissDragDistance = 30.0;
  static const double _kDismissVelocity = 320.0;

  bool _collapsed = false;
  double _dragOffset = 0.0;

  void _setCollapsed(bool value) {
    if (_collapsed == value) return;
    HapticFeedback.selectionClick();
    setState(() {
      _collapsed = value;
      _dragOffset = 0.0;
    });
  }

  void _toggleCollapsed() => _setCollapsed(!_collapsed);

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final double next = (_dragOffset + (details.primaryDelta ?? 0.0))
        .clamp(-60.0, 60.0)
        .toDouble();
    if (next == _dragOffset) return;
    setState(() => _dragOffset = next);
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0.0;
    final bool shouldCollapse =
        velocity > _kDismissVelocity || _dragOffset > _kDismissDragDistance;
    final bool shouldExpand =
        velocity < -_kDismissVelocity || _dragOffset < -_kDismissDragDistance;

    if (shouldCollapse) {
      _setCollapsed(true);
    } else if (shouldExpand) {
      _setCollapsed(false);
    } else {
      setState(() => _dragOffset = 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Size screen = MediaQuery.sizeOf(context);
    final bool compact = screen.width < 360.0;
    final double sideInset = compact ? 10.0 : 14.0;
    final double bottom = math.max(safe.bottom + 8.0, 12.0);
    final double dragShift = _collapsed
        ? _dragOffset.clamp(-30.0, 16.0).toDouble()
        : _dragOffset.clamp(-16.0, 40.0).toDouble();

    return Positioned(
      left: sideInset,
      right: sideInset,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: math.min(_kMinDockWidth, screen.width - sideInset * 2),
            maxWidth: _kMaxDockWidth,
          ),
          child: RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: _handleVerticalDragEnd,
              child: AnimatedSlide(
                offset: Offset(0, dragShift / 180.0),
                duration: _dragOffset == 0.0
                    ? const Duration(milliseconds: 240)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: _collapsed
                      ? _buildCollapsedDock(context, compact: compact)
                      : _buildExpandedDock(context, compact: compact),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDock(BuildContext context, {required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 14,
            6,
            compact ? 12 : 14,
            compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Subtle drag handle
              _DockDragHandle(
                collapsed: false,
                onTap: _toggleCollapsed,
              ),
              const SizedBox(height: 6),

              // Auto-Pause alert banner if active
              ValueListenableBuilder<bool>(
                valueListenable: widget.autoPausedN,
                builder: (_, bool autoPaused, __) {
                  if (!autoPaused) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AutoPauseBanner(
                      stoppedN: widget.autoPauseStoppedN,
                    ),
                  );
                },
              ),

              // Metrics strip (Distance | Time | Avg Speed)
              _buildMetricsStrip(context, compact: compact),
              const SizedBox(height: 10),

              // Primary Action Row
              _buildActionRow(context, compact: compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedDock(BuildContext context, {required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              // Expand button
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 32,
                onPressed: () => _setCollapsed(false),
                child: const Icon(
                  CupertinoIcons.chevron_up,
                  size: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 4),

              // Collapsed Trip stats chip
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setCollapsed(false),
                  child: ValueListenableBuilder<int>(
                    valueListenable: widget.tickN,
                    builder: (_, __, ___) {
                      return _CollapsedTripChip(
                        distance: widget.settings.toDisplayDistance(
                          widget.gps.currentDistanceMiles,
                        ),
                        distanceUnit: widget.settings.distanceUnit,
                        elapsed: widget.gps.currentTripTime.inSeconds,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Quick action button
              ValueListenableBuilder<bool>(
                valueListenable: widget.trackingN,
                builder: (_, bool tracking, __) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: widget.actionBusyN,
                    builder: (_, bool busy, __) {
                      if (busy) {
                        return const SizedBox(
                          width: 38,
                          height: 38,
                          child: Center(
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 9,
                            ),
                          ),
                        );
                      }
                      return _PressableScale(
                        onTap: widget.onAction,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: tracking
                                ? const LinearGradient(
                                    colors: <Color>[
                                      Color(0xFFFF3B30),
                                      Color(0xFFD70015),
                                    ],
                                  )
                                : const LinearGradient(
                                    colors: <Color>[
                                      Color(0xFF34C759),
                                      Color(0xFF28CD41),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: (tracking
                                        ? const Color(0xFFFF3B30)
                                        : const Color(0xFF34C759))
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            tracking
                                ? CupertinoIcons.stop_fill
                                : CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsStrip(BuildContext context, {required bool compact}) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.tickN,
      builder: (BuildContext context, _, __) {
        final double dist = widget.settings
            .toDisplayDistance(widget.gps.currentDistanceMiles);
        final String distStr = dist.toStringAsFixed(1);
        final String distUnit = widget.settings.distanceUnit;

        final bool isAutoPaused = widget.autoPausedN.value;
        final int elapsedSecs = isAutoPaused
            ? widget.autoPauseStoppedN.value
            : widget.gps.currentTripTime.inSeconds;
        final String timeStr = _MapFirstBottomDock._formatSeconds(elapsedSecs);

        final double avgSpeed =
            widget.settings.toDisplaySpeed(widget.gps.currentAvgSpeedMph);
        final String avgSpeedStr = avgSpeed >= 10.0
            ? avgSpeed.round().toString()
            : avgSpeed.toStringAsFixed(1);
        final String speedUnit = widget.settings.speedUnit;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: <Widget>[
              // Column 1: DISTANCE
              Expanded(
                child: _MetricColumn(
                  label: 'DISTANCE',
                  value: distStr,
                  unit: distUnit,
                  valueColor: Colors.white,
                ),
              ),
              Container(
                width: 0.5,
                height: 30,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              // Column 2: TIME
              Expanded(
                child: _MetricColumn(
                  label: isAutoPaused ? 'PAUSED' : 'TIME',
                  value: timeStr,
                  unit: null,
                  valueColor: isAutoPaused ? _kBlueSoft : Colors.white,
                ),
              ),
              Container(
                width: 0.5,
                height: 30,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              // Column 3: AVG SPEED
              Expanded(
                child: _MetricColumn(
                  label: 'AVG SPEED',
                  value: avgSpeedStr,
                  unit: speedUnit,
                  valueColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionRow(BuildContext context, {required bool compact}) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.trackingN,
      builder: (_, bool tracking, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.actionBusyN,
          builder: (_, bool busy, __) {
            if (busy) {
              return const _BusyTrackingButton();
            }

            if (!tracking) {
              // Idle state: Clean, prominent Apple START TRIP button
              return _DockPrimaryButton(
                label: 'START TRIP',
                icon: CupertinoIcons.play_fill,
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF34C759), Color(0xFF28CD41)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shadowColor: const Color(0xFF34C759).withValues(alpha: 0.35),
                height: 48,
                onTap: widget.onAction,
              );
            }

            // Tracking state: Follow/Recenter button + STOP TRIP button
            return Row(
              children: <Widget>[
                // Map Recenter / Follow Mode toggle
                ValueListenableBuilder<_MapFollowMode>(
                  valueListenable: widget.followModeN,
                  builder: (_, _MapFollowMode mode, __) {
                    final bool isCentered = mode != _MapFollowMode.freeView;
                    return _PressableScale(
                      onTap: widget.onFollowModeTap,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isCentered
                              ? _kBlue.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCentered
                                ? _kBlue.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Icon(
                          mode.icon,
                          size: 20,
                          color: isCentered ? Colors.white : Colors.white70,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),

                // Expanded STOP TRIP button
                Expanded(
                  child: _DockPrimaryButton(
                    label: 'STOP TRIP',
                    icon: CupertinoIcons.stop_fill,
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFFF3B30), Color(0xFFD70015)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shadowColor: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                    height: 48,
                    onTap: widget.onAction,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// METRIC COLUMN (Apple Fitness HIG — No truncation)
// ═══════════════════════════════════════════════════════════════════════════════

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    this.unit,
    this.valueColor = Colors.white,
  });

  final String label;
  final String value;
  final String? unit;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (unit != null && unit!.isNotEmpty) ...<Widget>[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOCK PRIMARY BUTTON
// ═══════════════════════════════════════════════════════════════════════════════

class _DockPrimaryButton extends StatelessWidget {
  const _DockPrimaryButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.shadowColor,
    required this.height,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Gradient gradient;
  final Color shadowColor;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: shadowColor,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAG HANDLE
// ═══════════════════════════════════════════════════════════════════════════════

class _DockDragHandle extends StatelessWidget {
  const _DockDragHandle({
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: collapsed
          ? 'Expand tracking controls'
          : 'Minimize tracking controls',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 3),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTO-PAUSE BANNER
// ═══════════════════════════════════════════════════════════════════════════════

class _AutoPauseBanner extends StatelessWidget {
  const _AutoPauseBanner({
    required this.stoppedN,
  });

  final ValueNotifier<int> stoppedN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: stoppedN,
      builder: (_, int seconds, __) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kBlueSoft.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kBlueSoft.withValues(alpha: 0.22),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.pause_circle_fill,
                      color: _kBlueSoft,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AUTO PAUSED · ${_MapFirstBottomDock._formatSeconds(seconds)} · MOVE TO RESUME',
                      maxLines: 1,
                      style: const TextStyle(
                        color: _kBlueSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// COLLAPSED TRIP CHIP
// ═══════════════════════════════════════════════════════════════════════════════

class _CollapsedTripChip extends StatelessWidget {
  const _CollapsedTripChip({
    required this.distance,
    required this.distanceUnit,
    required this.elapsed,
  });

  final double distance;
  final String distanceUnit;
  final int elapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.location_fill, color: _kBlueSoft, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${distance.toStringAsFixed(1)} $distanceUnit',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _MapFirstBottomDock._formatSeconds(elapsed),
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFeatures: const <ui.FontFeature>[
                ui.FontFeature.tabularFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUSY INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════

class _BusyTrackingButton extends StatelessWidget {
  const _BusyTrackingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const CupertinoActivityIndicator(
        color: Colors.white,
        radius: 10,
      ),
    );
  }
}
