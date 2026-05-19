// ignore_for_file: unused_element, unused_element_parameter

part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM DOCK
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
  static const double _kMaxDockWidth = 430.0;
  static const double _kMinDockWidth = 300.0;
  static const double _kDismissDragDistance = 34.0;
  static const double _kDismissVelocity = 360.0;

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
        .clamp(-72.0, 72.0)
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
    final double sideInset = compact ? 10.0 : 12.0;
    final double bottom = math.max(safe.bottom + 8.0, 12.0);
    final double dragShift = _collapsed
        ? _dragOffset.clamp(-40.0, 22.0).toDouble()
        : _dragOffset.clamp(-18.0, 54.0).toDouble();

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
                offset: Offset(0, dragShift / 220.0),
                duration: _dragOffset == 0.0
                    ? const Duration(milliseconds: 260)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 280),
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
    return AppGlassCard(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        7,
        compact ? 10 : 12,
        compact ? 10 : 12,
      ),
      borderRadius: 28,
      color: _kSurface.withValues(alpha: 0.90),
      borderColor: Colors.white.withValues(alpha: 0.10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _DockDragHandle(
            collapsed: false,
            onTap: _toggleCollapsed,
          ),
          const SizedBox(height: 7),
          _buildMetricRow(compact: compact),
          ValueListenableBuilder<bool>(
            valueListenable: widget.autoPausedN,
            builder: (_, bool autoPaused, __) {
              if (!autoPaused) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(top: 9),
                child: _AutoPauseBanner(
                  stoppedN: widget.autoPauseStoppedN,
                ),
              );
            },
          ),
          SizedBox(height: compact ? 8 : 10),
          _buildPrimaryActionRow(compact: compact),
          SizedBox(height: compact ? 7 : 8),
          _buildSecondaryActionRow(compact: compact),
        ],
      ),
    );
  }

  Widget _buildCollapsedDock(BuildContext context, {required bool compact}) {
    return AppGlassCard(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        7,
        compact ? 10 : 12,
        compact ? 9 : 10,
      ),
      borderRadius: 26,
      color: _kSurface.withValues(alpha: 0.92),
      borderColor: Colors.white.withValues(alpha: 0.11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _DockDragHandle(
            collapsed: true,
            onTap: _toggleCollapsed,
          ),
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Expanded(
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
              const SizedBox(width: 8),
              SizedBox(
                width: compact ? 116 : 132,
                child: ValueListenableBuilder<bool>(
                  valueListenable: widget.trackingN,
                  builder: (_, bool tracking, __) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: widget.actionBusyN,
                      builder: (_, bool busy, __) {
                        if (busy) return const _BusyTrackingButton();

                        return AppActionButton(
                          label: tracking ? 'Stop' : 'Start',
                          icon: tracking
                              ? CupertinoIcons.stop_fill
                              : CupertinoIcons.play_fill,
                          primary: true,
                          height: 44,
                          onTap: widget.onAction,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              _DockRoundIconButton(
                icon: CupertinoIcons.chevron_up,
                semanticLabel: 'Open controls',
                onTap: () => _setCollapsed(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow({required bool compact}) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.tickN,
      builder: (_, __, ___) {
        return Row(
          children: <Widget>[
            Expanded(
              child: _DockMetricCard(
                label: 'Distance',
                value:
                    '${widget.settings.toDisplayDistance(widget.gps.currentDistanceMiles).toStringAsFixed(1)} ${widget.settings.distanceUnit}',
                icon: CupertinoIcons.map_fill,
                color: _kBlueSoft,
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.autoPausedN,
                builder: (_, bool autoPaused, __) {
                  return _DockMetricCard(
                    label: autoPaused ? 'Paused' : 'Time',
                    value: _MapFirstBottomDock._formatSeconds(
                      autoPaused
                          ? widget.autoPauseStoppedN.value
                          : widget.gps.currentTripTime.inSeconds,
                    ),
                    icon: autoPaused
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.timer,
                    color: autoPaused ? _kBlueSoft : _kGreen,
                  );
                },
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            Expanded(
              child: _DockMetricCard(
                label: 'Avg',
                value:
                    '${widget.settings.toDisplaySpeed(widget.gps.currentAvgSpeedMph).round()} ${widget.settings.speedUnit}',
                icon: CupertinoIcons.speedometer,
                color: _kBlue,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPrimaryActionRow({required bool compact}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: ValueListenableBuilder<_MapFollowMode>(
            valueListenable: widget.followModeN,
            builder: (_, _MapFollowMode mode, __) {
              return _DockActionButton(
                label: mode.label,
                icon: mode.icon,
                height: compact ? 43 : 46,
                onTap: widget.onFollowModeTap,
              );
            },
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          flex: 2,
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.trackingN,
            builder: (_, bool tracking, __) {
              return ValueListenableBuilder<bool>(
                valueListenable: widget.actionBusyN,
                builder: (_, bool busy, __) {
                  if (busy) return const _BusyTrackingButton();

                  return AppActionButton(
                    label: tracking ? 'Stop' : 'Start',
                    icon: tracking
                        ? CupertinoIcons.stop_fill
                        : CupertinoIcons.play_fill,
                    primary: true,
                    height: compact ? 45 : 48,
                    onTap: widget.onAction,
                  );
                },
              );
            },
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _DockActionButton(
            label: 'AI',
            icon: Icons.auto_awesome_rounded,
            height: compact ? 43 : 46,
            onTap: widget.onAiTap,
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryActionRow({required bool compact}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _DockActionButton(
            label: 'Map',
            icon: CupertinoIcons.map_fill,
            height: compact ? 37 : 40,
            small: true,
            onTap: widget.onMapTap,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _DockActionButton(
            label: 'Route',
            icon: CupertinoIcons.location_north_line_fill,
            height: compact ? 37 : 40,
            small: true,
            onTap: widget.onMapboxTap,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _DockActionButton(
            label: 'AR',
            icon: CupertinoIcons.camera_viewfinder,
            height: compact ? 37 : 40,
            small: true,
            onTap: widget.onArTap,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _DockActionButton(
            label: 'Weather',
            icon: CupertinoIcons.cloud_sun_fill,
            height: compact ? 37 : 40,
            small: true,
            onTap: widget.onWeatherTap,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: ValueListenableBuilder<_TrackingPerformanceMode>(
            valueListenable: widget.performanceModeN,
            builder: (_, _TrackingPerformanceMode mode, __) {
              return _DockActionButton(
                label: mode == _TrackingPerformanceMode.performance
                    ? 'Perf'
                    : mode == _TrackingPerformanceMode.battery
                        ? 'Save'
                        : 'Bal',
                icon: mode.icon,
                height: compact ? 37 : 40,
                small: true,
                onTap: widget.onPerformanceTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

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
      label: collapsed ? 'Open tracking controls' : 'Close tracking controls',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: collapsed ? 46 : 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: collapsed ? 0.30 : 0.22),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    collapsed
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 10,
                    color: Colors.white.withValues(alpha: 0.36),
                  ),
                  const SizedBox(width: 5),
                  _SafeText(
                    collapsed ? 'SLIDE UP FOR CONTROLS' : 'SLIDE DOWN TO HIDE',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.36),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.label,
    required this.icon,
    required this.height,
    required this.onTap,
    this.small = false,
  });

  final String label;
  final IconData icon;
  final double height;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: small ? 0.065 : 0.075),
          borderRadius: BorderRadius.circular(small ? 15 : 17),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.09),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: _kTextPrimary, size: small ? 13 : 15),
            SizedBox(width: small ? 5 : 6),
            Flexible(
              child: _SafeText(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: small ? 10 : 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: small ? 0.0 : 0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockRoundIconButton extends StatelessWidget {
  const _DockRoundIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: _PressableScale(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.075),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: _kTextPrimary, size: 17),
        ),
      ),
    );
  }
}

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
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.map_fill, color: _kBlueSoft, size: 14),
          const SizedBox(width: 7),
          Expanded(
            child: _SafeText(
              '${distance.toStringAsFixed(1)} $distanceUnit',
              maxLines: 1,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SafeText(
            _MapFirstBottomDock._formatSeconds(elapsed),
            maxLines: 1,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DockMetricCard extends StatelessWidget {
  const _DockMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppMetricCard(
      label: label,
      value: value,
      icon: icon,
      color: color,
      compact: true,
    );
  }
}

class _BusyTrackingButton extends StatelessWidget {
  const _BusyTrackingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.blueButtonGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const CupertinoActivityIndicator(
        color: Colors.white,
        radius: 10,
      ),
    );
  }
}

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
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kBlueSoft.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _kBlueSoft.withValues(alpha: 0.18),
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
                    _SafeText(
                      'AUTO PAUSED · ${_MapFirstBottomDock._formatSeconds(seconds)} · MOVE TO RESUME',
                      maxLines: 1,
                      style: const TextStyle(
                        color: _kBlueSoft,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
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

class _DockStat extends StatelessWidget {
  const _DockStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SafeText(
          value,
          maxLines: 1,
          style: const TextStyle(
            color: _kTextPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(height: 3),
        _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: compact ? 36 : 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.09),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.045),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: compact ? 12 : 14),
            SizedBox(height: compact ? 2 : 3),
            _SafeText(
              label,
              maxLines: 1,
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: compact ? 7.5 : 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFE TEXT — avoids Flutter Web EllipsisFragment hit-test assertion
// ═══════════════════════════════════════════════════════════════════════════════
