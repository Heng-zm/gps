part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TOP HUD / SPEED HUD
// ═══════════════════════════════════════════════════════════════════════════════

class _MapFirstGradientScrim extends StatelessWidget {
  const _MapFirstGradientScrim();

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
              Colors.black.withValues(alpha: 0.22),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.40),
              Colors.black.withValues(alpha: 0.90),
            ],
            stops: const <double>[0.0, 0.18, 0.46, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _MapFirstFloatingModeBadge extends StatelessWidget {
  const _MapFirstFloatingModeBadge({
    required this.followModeN,
  });

  final ValueNotifier<_MapFollowMode> followModeN;

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.paddingOf(context).bottom + 168.0;

    return Positioned(
      left: 16,
      bottom: bottom,
      child: ValueListenableBuilder<_MapFollowMode>(
        valueListenable: followModeN,
        builder: (_, _MapFollowMode mode, __) {
          return _MapModeBadge(mode: mode);
        },
      ),
    );
  }
}

class _MapFirstTopHud extends StatelessWidget {
  const _MapFirstTopHud({
    required this.compassN,
    required this.weatherN,
    required this.trackingN,
    required this.tickN,
    required this.signalN,
    required this.batteryN,
    required this.batteryStateN,
    required this.accuracyN,
    required this.autoPausedN,
    required this.performanceModeN,
    required this.coachTipN,
    required this.onPerformanceTap,
    required this.settings,
  });

  final ValueNotifier<double> compassN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> tickN;
  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<BatteryState?> batteryStateN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<_TrackingPerformanceMode> performanceModeN;
  final ValueNotifier<String> coachTipN;
  final VoidCallback onPerformanceTap;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            children: <Widget>[
              _GlassPanel(
                radius: 26,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: <Widget>[
                    _CompassWidget(headingN: compassN),
                    const SizedBox(width: 8),
                    _TempDisplay(weatherN: weatherN, settings: settings),
                    const Spacer(),
                    _DigitalClock(tickN: tickN),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SlimStatusPill(
                signalN: signalN,
                batteryN: batteryN,
                batteryStateN: batteryStateN,
                accuracyN: accuracyN,
                autoPausedN: autoPausedN,
                trackingN: trackingN,
              ),
              const SizedBox(height: 7),
              _SmartTrackingIsland(
                performanceModeN: performanceModeN,
                coachTipN: coachTipN,
                onPerformanceTap: onPerformanceTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlimStatusPill extends StatelessWidget {
  const _SlimStatusPill({
    required this.signalN,
    required this.batteryN,
    required this.batteryStateN,
    required this.accuracyN,
    required this.autoPausedN,
    required this.trackingN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<BatteryState?> batteryStateN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<bool> trackingN;

  @override
  Widget build(BuildContext context) {
    final double maxWidth = MediaQuery.sizeOf(context).width * 0.9;
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        signalN,
        batteryN,
        batteryStateN,
        accuracyN,
        autoPausedN,
        trackingN,
      ]),
      builder: (BuildContext context, Widget? child) {
        final bool tracking = trackingN.value;
        final bool autoPaused = autoPausedN.value;
        final int safeSignal = signalN.value.clamp(0, 4).toInt();
        final double accuracy = accuracyN.value;
        final int? battery = batteryN.value;
        final BatteryState? batteryState = batteryStateN.value;

        final bool hasGoodGps =
            safeSignal >= 2 && accuracy.isFinite && accuracy < 30.0;

        final Color gpsColor = hasGoodGps
            ? _kGreen
            : tracking
                ? _kBlueSoft
                : _kTextMuted;

        final bool batteryCharging = batteryState == BatteryState.charging ||
            batteryState == BatteryState.full;
        final Color batteryColor = battery == null
            ? _kTextMuted
            : batteryCharging
                ? _kBlueSoft
                : battery > 40
                    ? _kGreen
                    : battery > 20
                        ? _kBlueSoft
                        : _kRed;

        final String gpsText = accuracy.isFinite && accuracy < 40.0
            ? 'GPS ±${accuracy.round()}m'
            : tracking
                ? 'GPS searching'
                : 'GPS ready';

        final String routeText = autoPaused
            ? 'Auto paused'
            : hasGoodGps || !tracking
                ? 'Route ready'
                : 'Route weak';

        final Color routeColor = autoPaused ? _kBlueSoft : gpsColor;

        final String batteryText = battery == null
            ? 'Battery --%'
            : batteryCharging
                ? 'Charging $battery%'
                : '$battery%';

        return Align(
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.labelSmall?.copyWith(
                            color: _kTextPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ) ??
                          const TextStyle(
                            color: _kTextPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            flex: 4,
                            child: _StatusSegment(
                              icon: CupertinoIcons.location_fill,
                              label: gpsText,
                              color: gpsColor,
                              textColor: _kTextPrimary,
                            ),
                          ),
                          _StatusDot(color: routeColor),
                          Flexible(
                            flex: 4,
                            child: _StatusSegment(
                              icon: autoPaused
                                  ? CupertinoIcons.pause_circle_fill
                                  : CupertinoIcons.checkmark_circle_fill,
                              label: routeText,
                              color: routeColor,
                              textColor: routeColor,
                            ),
                          ),
                          _StatusDot(color: batteryColor),
                          Flexible(
                            flex: 3,
                            child: _StatusSegment(
                              icon: batteryCharging
                                  ? CupertinoIcons.bolt_fill
                                  : CupertinoIcons.battery_100,
                              label: batteryText,
                              color: batteryColor,
                              textColor: _kTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _SmartTrackingIsland extends StatelessWidget {
  const _SmartTrackingIsland({
    required this.performanceModeN,
    required this.coachTipN,
    required this.onPerformanceTap,
  });

  final ValueNotifier<_TrackingPerformanceMode> performanceModeN;
  final ValueNotifier<String> coachTipN;
  final VoidCallback onPerformanceTap;

  @override
  Widget build(BuildContext context) {
    final double maxWidth = MediaQuery.sizeOf(context).width * 0.92;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.sparkles,
                      color: _kBlueSoft,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: coachTipN,
                        builder: (_, String tip, __) {
                          return _SafeText(
                            tip,
                            maxLines: 1,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.1,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 7),
                    ValueListenableBuilder<_TrackingPerformanceMode>(
                      valueListenable: performanceModeN,
                      builder: (_, _TrackingPerformanceMode mode, __) {
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 28,
                          pressedOpacity: 0.78,
                          onPressed: onPerformanceTap,
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: _kBlue.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _kBlueSoft.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(mode.icon, color: _kBlueSoft, size: 12),
                                const SizedBox(width: 4),
                                _SafeText(
                                  mode.label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: _kBlueSoft,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: _SafeText(
            label,
            maxLines: 1,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.80),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _MapFirstSpeedHud extends StatelessWidget {
  const _MapFirstSpeedHud({
    required this.speedN,
    required this.trackingN,
    required this.signalN,
    required this.accuracyN,
    required this.autoPausedN,
    required this.posN,
    required this.settings,
  });

  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> signalN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<LatLng?> posN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final double bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      right: 14,
      bottom: bottomSafe + 214,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          speedN,
          trackingN,
          autoPausedN,
          signalN,
          accuracyN,
          posN,
        ]),
        builder: (BuildContext context, Widget? child) {
          final double speed = speedN.value;
          final bool tracking = trackingN.value;
          final bool autoPaused = autoPausedN.value;
          final int signal = signalN.value.clamp(0, 4);
          final double accuracy = accuracyN.value;
          final bool hasPosition = posN.value != null;
          final bool hasUsableGps =
              hasPosition && signal >= 1 && accuracy.isFinite && accuracy < 40;

          final bool isOver = tracking && speed > settings.speedAlertMph;

          final String statusLabel = autoPaused
              ? 'AUTO PAUSE'
              : tracking
                  ? 'LIVE'
                  : hasUsableGps
                      ? 'READY'
                      : 'GPS';

          final Color statusColor = isOver
              ? _kRed
              : autoPaused
                  ? _kBlueSoft
                  : tracking
                      ? _kGreen
                      : hasUsableGps
                          ? Colors.white54
                          : _kBlueSoft;

          final IconData statusIcon = autoPaused
              ? CupertinoIcons.pause_fill
              : tracking
                  ? CupertinoIcons.location_fill
                  : hasUsableGps
                      ? CupertinoIcons.checkmark_alt
                      : CupertinoIcons.location_slash;

          return AnimatedScale(
            duration: _kAnimMed,
            curve: Curves.easeOutCubic,
            scale: isOver ? 1.04 : 1.0,
            child: AppGlassCard(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              borderRadius: 26,
              color: Colors.black.withValues(alpha: isOver ? 0.66 : 0.48),
              borderColor: isOver
                  ? _kRed.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SpeedometerWidget(
                    speedMph: speed,
                    isOverLimit: isOver,
                    compact: true,
                    showUnit: true,
                    showOverLimitBadge: false,
                  ),
                  const SizedBox(height: 7),
                  AppStatusPill(
                    label: statusLabel,
                    color: statusColor,
                    icon: statusIcon,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
