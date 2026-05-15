// ignore_for_file: unused_element

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
    final double bottom = MediaQuery.of(context).padding.bottom + 168.0;

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
    required this.accuracyN,
    required this.autoPausedN,
    required this.settings,
  });

  final ValueNotifier<double> compassN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> tickN;
  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
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
                accuracyN: accuracyN,
                autoPausedN: autoPausedN,
                trackingN: trackingN,
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
    required this.accuracyN,
    required this.autoPausedN,
    required this.trackingN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<bool> trackingN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: trackingN,
      builder: (_, bool tracking, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: autoPausedN,
          builder: (_, bool autoPaused, __) {
            return ValueListenableBuilder<int>(
              valueListenable: signalN,
              builder: (_, int signal, __) {
                return ValueListenableBuilder<double>(
                  valueListenable: accuracyN,
                  builder: (_, double accuracy, __) {
                    return ValueListenableBuilder<int?>(
                      valueListenable: batteryN,
                      builder: (_, int? battery, __) {
                        final int safeSignal = signal.clamp(0, 4);
                        final bool hasGoodGps = safeSignal >= 2 &&
                            accuracy.isFinite &&
                            accuracy < 30.0;

                        final Color gpsColor = hasGoodGps
                            ? _kGreen
                            : tracking
                                ? _kBlueSoft
                                : _kBlueSoft;

                        final Color batteryColor = battery == null
                            ? _kTextMuted
                            : battery > 40
                                ? _kGreen
                                : battery > 20
                                    ? _kBlueSoft
                                    : _kRed;

                        final String gpsText =
                            accuracy.isFinite && accuracy < 40.0
                                ? 'GPS ±${accuracy.round()}m'
                                : tracking
                                    ? 'GPS searching'
                                    : 'GPS ready';

                        final String routeText = autoPaused
                            ? 'Auto paused'
                            : hasGoodGps || !tracking
                                ? 'Route ready'
                                : 'Route weak';

                        final Color routeColor =
                            autoPaused ? _kBlueSoft : gpsColor;

                        final String batteryText = battery == null
                            ? 'Battery --%'
                            : 'Battery $battery%';

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 345),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.48),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      CupertinoIcons.location_fill,
                                      size: 12,
                                      color: gpsColor,
                                    ),
                                    const SizedBox(width: 5),
                                    _SafeText(
                                      gpsText,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    _StatusDot(color: routeColor),
                                    Icon(
                                      autoPaused
                                          ? CupertinoIcons.pause_circle_fill
                                          : CupertinoIcons
                                              .checkmark_circle_fill,
                                      size: 12,
                                      color: routeColor,
                                    ),
                                    const SizedBox(width: 5),
                                    _SafeText(
                                      routeText,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: routeColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    _StatusDot(color: batteryColor),
                                    Icon(
                                      CupertinoIcons.battery_100,
                                      size: 12,
                                      color: batteryColor,
                                    ),
                                    const SizedBox(width: 5),
                                    _SafeText(
                                      batteryText,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
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
                  },
                );
              },
            );
          },
        );
      },
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
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.80),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _MiniHudChip extends StatelessWidget {
  const _MiniHudChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          _SafeText(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          _SafeText(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
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
    final double bottomSafe = MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 14,
      bottom: bottomSafe + 214,
      child: RepaintBoundary(
        child: ValueListenableBuilder<bool>(
          valueListenable: trackingN,
          builder: (_, bool tracking, __) {
            return ValueListenableBuilder<double>(
              valueListenable: speedN,
              builder: (_, double speed, __) {
                final bool isOver = tracking && speed > settings.speedAlertMph;

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
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPausedN,
                          builder: (_, bool autoPaused, __) {
                            return AppStatusPill(
                              label: autoPaused
                                  ? 'AUTO PAUSE'
                                  : tracking
                                      ? 'LIVE'
                                      : 'READY',
                              color: isOver
                                  ? _kRed
                                  : autoPaused
                                      ? _kBlueSoft
                                      : tracking
                                          ? _kGreen
                                          : Colors.white54,
                              icon: autoPaused
                                  ? CupertinoIcons.pause_fill
                                  : tracking
                                      ? CupertinoIcons.location_fill
                                      : CupertinoIcons.checkmark_alt,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReadyTrackingLabel extends StatelessWidget {
  const _ReadyTrackingLabel({
    required this.tracking,
    required this.autoPaused,
    required this.isOverLimit,
  });

  final bool tracking;
  final bool autoPaused;
  final bool isOverLimit;

  @override
  Widget build(BuildContext context) {
    final Color color = isOverLimit
        ? _kRed
        : autoPaused
            ? _kBlueSoft
            : tracking
                ? _kGreen
                : _kBlueSoft;

    final String label = isOverLimit
        ? 'SPEED ALERT'
        : autoPaused
            ? 'AUTO PAUSED'
            : tracking
                ? 'LIVE · Tracking'
                : 'READY · Tap Start';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.65,
          ),
        ),
      ),
    );
  }
}

class _CompactRouteQualityLine extends StatelessWidget {
  const _CompactRouteQualityLine({
    required this.signalN,
    required this.accuracyN,
    required this.speedN,
    required this.trackingN,
    required this.posN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<LatLng?> posN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: trackingN,
      builder: (_, bool tracking, __) {
        return ValueListenableBuilder<int>(
          valueListenable: signalN,
          builder: (_, int signal, __) {
            return ValueListenableBuilder<double>(
              valueListenable: accuracyN,
              builder: (_, double accuracy, __) {
                return ValueListenableBuilder<double>(
                  valueListenable: speedN,
                  builder: (_, double speed, __) {
                    return ValueListenableBuilder<LatLng?>(
                      valueListenable: posN,
                      builder: (_, LatLng? position, __) {
                        final _RouteQuality quality = _RouteQuality.resolve(
                          tracking: tracking,
                          signal: signal,
                          accuracy: accuracy,
                          speedMph: speed,
                          hasPosition: position != null,
                        );

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(quality.icon, color: quality.color, size: 15),
                            const SizedBox(width: 7),
                            Flexible(
                              child: _SafeText(
                                quality.title,
                                maxLines: 1,
                                style: TextStyle(
                                  color: quality.color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _RouteAccuracyPill(
                              accuracy: accuracy,
                              color: quality.color,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
