// ignore_for_file: unused_element

part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED TRACKING WIDGETS / PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: style,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════════

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground({required this.child});

  final Widget child;

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (_, Widget? child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.lerp(
                const Alignment(-0.38, -0.70),
                const Alignment(0.42, -0.95),
                _animation.value,
              )!,
              radius: 1.04 + _animation.value * 0.22,
              colors: const <Color>[
                Color(0xFF1B1200),
                Color(0xFF0C0800),
                AppColors.black,
              ],
              stops: const <double>[0.0, 0.48, 1.0],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -90 + _animation.value * 22,
                top: 96,
                child: _AmbientOrb(
                  size: 210,
                  color: _kBlue.withValues(alpha: 0.07),
                ),
              ),
              Positioned(
                left: -120,
                bottom: 180 - _animation.value * 18,
                child: _AmbientOrb(
                  size: 250,
                  color: _kBlue.withValues(alpha: 0.045),
                ),
              ),
              child!,
            ],
          ),
        );
      },
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: size * 0.45,
              spreadRadius: size * 0.16,
            ),
          ],
        ),
        child: SizedBox.square(dimension: size),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.compassN,
    required this.weatherN,
    required this.trackingN,
    required this.tickN,
    required this.settings,
  });

  final ValueNotifier<double> compassN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> tickN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: _GlassPanel(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: <Widget>[
              _CompassWidget(headingN: compassN),
              const SizedBox(width: 12),
              _TempDisplay(weatherN: weatherN, settings: settings),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: trackingN,
                builder: (_, bool tracking, __) {
                  return AnimatedSwitcher(
                    duration: _kAnimMed,
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (Widget child, Animation<double> anim) {
                      return FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      );
                    },
                    child: tracking
                        ? const _LivePill(key: ValueKey<String>('live'))
                        : const _IdlePill(key: ValueKey<String>('idle')),
                  );
                },
              ),
              const SizedBox(width: 10),
              _DigitalClock(tickN: tickN),
            ],
          ),
        ),
      ),
    );
  }
}

class _TempDisplay extends StatelessWidget {
  const _TempDisplay({
    required this.weatherN,
    required this.settings,
  });

  final ValueNotifier<WeatherData?> weatherN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: weatherN,
      builder: (_, WeatherData? weather, __) {
        final bool metric = settings.useKmh;
        final String unit = metric ? '°C' : '°F';

        String value = '--';
        if (weather != null) {
          final double temp =
              metric ? weather.temperature : (weather.temperature * 9 / 5) + 32;
          value = temp.isFinite ? temp.round().toString() : '--';
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SafeText(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -0.4,
                fontFeatures: <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1, left: 2),
              child: _SafeText(
                unit,
                maxLines: 1,
                style: const TextStyle(
                  color: _kBlueSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DigitalClock extends StatelessWidget {
  const _DigitalClock({required this.tickN});

  final ValueNotifier<int> tickN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tickN,
      builder: (_, __, ___) {
        final DateTime now = DateTime.now();
        final String h = now.hour.toString().padLeft(2, '0');
        final String m = now.minute.toString().padLeft(2, '0');
        final String s = now.second.toString().padLeft(2, '0');

        return IgnorePointer(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFeatures: <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
                letterSpacing: -0.5,
                height: 1.0,
              ),
              children: <InlineSpan>[
                TextSpan(
                  text: '$h:$m',
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ':$s',
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPEEDOMETER
// ═══════════════════════════════════════════════════════════════════════════════

class _SpeedometerSection extends StatelessWidget {
  const _SpeedometerSection({
    required this.speedN,
    required this.trackingN,
    required this.settings,
  });

  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: trackingN,
        builder: (_, bool tracking, __) {
          return ValueListenableBuilder<double>(
            valueListenable: speedN,
            builder: (_, double speed, __) {
              final bool isOver = tracking && speed > settings.speedAlertMph;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedContainer(
                  duration: _kAnimMed,
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        isOver
                            ? _kRedGlow.withValues(alpha: 0.38)
                            : Colors.white.withValues(alpha: 0.085),
                        isOver
                            ? _kRedGlow.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.025),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: isOver
                          ? _kRed.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.08),
                      width: isOver ? 1.5 : 1.0,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: isOver
                            ? _kRed.withValues(alpha: 0.24)
                            : Colors.black.withValues(alpha: 0.34),
                        blurRadius: isOver ? 34 : 24,
                        spreadRadius: isOver ? 1 : 0,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: SpeedometerWidget(
                    speedMph: speed,
                    isOverLimit: isOver,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATUS ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.signalN,
    required this.batteryN,
    this.batteryStateN,
    required this.accuracyN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<BatteryState?>? batteryStateN;
  final ValueNotifier<double> accuracyN;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: signalN,
              builder: (_, int strength, __) {
                final int signal = strength.clamp(0, 4).toInt();

                return ValueListenableBuilder<double>(
                  valueListenable: accuracyN,
                  builder: (_, double accuracy, __) {
                    final String value =
                        accuracy < 40 ? '±${accuracy.round()}m' : '--';

                    return _StatusChip(
                      label: 'GPS SIGNAL',
                      leading: _SignalBars(strength: signal),
                      value: value,
                      valueColor: _signalColor(signal),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<int?>(
              valueListenable: batteryN,
              builder: (_, int? percent, __) {
                final ValueNotifier<BatteryState?>? stateNotifier =
                    batteryStateN;

                if (stateNotifier == null) {
                  return _StatusChip(
                    label: 'BATTERY',
                    leading: _BatteryIcon(percent: percent),
                    value: percent == null ? '--%' : '$percent%',
                    valueColor: _batteryColor(percent, null),
                  );
                }

                return ValueListenableBuilder<BatteryState?>(
                  valueListenable: stateNotifier,
                  builder: (_, BatteryState? state, __) {
                    final bool charging = state == BatteryState.charging ||
                        state == BatteryState.full;

                    return _StatusChip(
                      label: charging ? 'CHARGING' : 'BATTERY',
                      leading: _BatteryIcon(percent: percent, state: state),
                      value: percent == null ? '--%' : '$percent%',
                      valueColor: _batteryColor(percent, state),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Color _signalColor(int signal) {
    if (signal >= 3) return _kGreen;
    if (signal >= 2) return _kBlue;
    return _kRed;
  }

  static Color _batteryColor(int? percent, BatteryState? state) {
    if (state == BatteryState.charging || state == BatteryState.full) {
      return _kBlueSoft;
    }
    if (percent == null) return _kTextMuted;
    if (percent > 40) return _kGreen;
    if (percent > 20) return const Color(0xFFFFCC00);
    return _kRed;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.leading,
    required this.value,
    this.valueColor = _kTextPrimary,
  });

  final String label;
  final Widget leading;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: 9),
          Expanded(
            child: _SafeText(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SafeText(
            value,
            maxLines: 1,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE ROUTE QUALITY INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════

class _RouteQualityCard extends StatelessWidget {
  const _RouteQualityCard({
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ValueListenableBuilder<bool>(
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

                          return _GlassPanel(
                            radius: 20,
                            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                            child: Row(
                              children: <Widget>[
                                _RouteQualityBadge(quality: quality),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          _SafeText(
                                            quality.title,
                                            maxLines: 1,
                                            style: TextStyle(
                                              color: quality.color,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (tracking)
                                            _SafeText(
                                              speed < 1.0
                                                  ? 'STATIONARY'
                                                  : 'MOVING',
                                              maxLines: 1,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.35),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      _SafeText(
                                        quality.message,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: _kTextMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _RouteAccuracyPill(
                                  accuracy: accuracy,
                                  color: quality.color,
                                ),
                              ],
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
      ),
    );
  }
}

class _RouteQuality {
  const _RouteQuality({
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
    required this.score,
  });

  final String title;
  final String message;
  final Color color;
  final IconData icon;
  final double score;

  static _RouteQuality resolve({
    required bool tracking,
    required int signal,
    required double accuracy,
    required double speedMph,
    required bool hasPosition,
  }) {
    final int safeSignal = signal.clamp(0, 4).toInt();
    final double safeAccuracy =
        accuracy.isFinite ? accuracy.clamp(5.0, 40.0).toDouble() : 40.0;

    if (!tracking) {
      return const _RouteQuality(
        title: 'ROUTE QUALITY READY',
        message: 'Start tracking to measure live GPS route quality.',
        color: _kBlueSoft,
        icon: CupertinoIcons.location,
        score: 0.42,
      );
    }

    if (!hasPosition || safeSignal <= 0) {
      return const _RouteQuality(
        title: 'SEARCHING GPS',
        message: 'Waiting for accurate location before drawing the route.',
        color: _kRed,
        icon: CupertinoIcons.location_slash,
        score: 0.14,
      );
    }

    if (safeAccuracy <= 8.0 && safeSignal >= 3) {
      return const _RouteQuality(
        title: 'EXCELLENT ROUTE',
        message: 'Strong GPS lock. Route line should be very accurate.',
        color: _kGreen,
        icon: CupertinoIcons.check_mark_circled_solid,
        score: 1.0,
      );
    }

    if (safeAccuracy <= 18.0 && safeSignal >= 2) {
      return const _RouteQuality(
        title: 'GOOD ROUTE',
        message: 'GPS is stable. Route quality is good for live tracking.',
        color: _kBlueSoft,
        icon: CupertinoIcons.location_fill,
        score: 0.72,
      );
    }

    if (speedMph < 1.0 && safeAccuracy <= 28.0) {
      return const _RouteQuality(
        title: 'IDLE GPS DRIFT',
        message: 'You are still. Small GPS drift may appear on the map.',
        color: _kBlue,
        icon: CupertinoIcons.scope,
        score: 0.55,
      );
    }

    return const _RouteQuality(
      title: 'WEAK ROUTE QUALITY',
      message: 'Move outdoors or wait for better GPS accuracy.',
      color: _kRed,
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      score: 0.32,
    );
  }
}

class _RouteQualityBadge extends StatelessWidget {
  const _RouteQualityBadge({required this.quality});

  final _RouteQuality quality;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CircularProgressIndicator(
            value: quality.score,
            strokeWidth: 3.2,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(quality.color),
          ),
          Icon(
            quality.icon,
            color: quality.color,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _RouteAccuracyPill extends StatelessWidget {
  const _RouteAccuracyPill({
    required this.accuracy,
    required this.color,
  });

  final double accuracy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String label =
        accuracy.isFinite && accuracy < 40.0 ? '±${accuracy.round()}m' : '--';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: _SafeText(
          label,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

class _GridDashboard extends StatelessWidget {
  const _GridDashboard({
    required this.tickN,
    required this.posN,
    required this.weatherN,
    required this.loadingN,
    required this.maxSpeedN,
    required this.followModeN,
    required this.settings,
    required this.gps,
    required this.mapController,
    required this.polylineCount,
    required this.onMapReady,
    required this.onMapTap,
    required this.onWeatherTap,
    required this.onFollowModeTap,
  });

  final ValueNotifier<int> tickN;
  final ValueNotifier<LatLng?> posN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> loadingN;
  final ValueNotifier<double> maxSpeedN;
  final ValueNotifier<_MapFollowMode> followModeN;
  final SettingsService settings;
  final GpsService gps;
  final fm.MapController mapController;
  final int Function() polylineCount;
  final VoidCallback onMapReady;
  final VoidCallback onMapTap;
  final VoidCallback onWeatherTap;
  final VoidCallback onFollowModeTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: tickN,
            builder: (_, __, ___) {
              final double distance =
                  settings.toDisplayDistance(gps.currentDistanceMiles);
              final double average =
                  settings.toDisplaySpeed(gps.currentAvgSpeedMph);

              return Row(
                children: <Widget>[
                  Expanded(
                    child: _StatCard(
                      label: 'DISTANCE',
                      value: _safeNum(distance),
                      unit: settings.distanceUnit,
                      isDecimal: true,
                      icon: CupertinoIcons.location_fill,
                      accent: _kBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'AVG SPEED',
                      value: _safeNum(average),
                      unit: settings.speedUnit,
                      isDecimal: false,
                      icon: CupertinoIcons.speedometer,
                      accent: _kGreen,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: maxSpeedN,
                  builder: (_, double maxMph, __) {
                    return _StatCard(
                      label: 'MAX SPEED',
                      value: _safeNum(settings.toDisplaySpeed(maxMph)),
                      unit: settings.speedUnit,
                      isDecimal: false,
                      icon: CupertinoIcons.bolt_fill,
                      accent: _kBlueSoft,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    final Duration moving = _safeMoving(
                      gps.currentTripTime,
                      gps.currentStoppedTime,
                    );

                    return _StatCard(
                      label: 'MOVING TIME',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.timer_fill,
                      accent: _kGreen,
                      overrideText: _fmtDuration(moving),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    return _StatCard(
                      label: 'STOPPED',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.pause_fill,
                      accent: _kRed,
                      overrideText: _fmtDuration(gps.currentStoppedTime),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    return _StatCard(
                      label: 'TOTAL TIME',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.clock_fill,
                      accent: _kBlue,
                      overrideText: _fmtDuration(gps.currentTripTime),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MapFollowModeStrip(
            followModeN: followModeN,
            onTap: onFollowModeTap,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 194,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _MapThumbnail(
                    posN: posN,
                    mapController: mapController,
                    gps: gps,
                    polylineCount: polylineCount,
                    onMapReady: onMapReady,
                    onTap: onMapTap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: settings.showWeather
                      ? _WeatherThumbnail(
                          weatherN: weatherN,
                          loadingN: loadingN,
                          onTap: onWeatherTap,
                        )
                      : const _EmptyCard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _safeNum(double value) {
    return value.isFinite && value >= 0.0 ? value : 0.0;
  }

  static Duration _safeMoving(Duration total, Duration stopped) {
    final Duration moving = total - stopped;
    return moving.isNegative ? Duration.zero : moving;
  }

  static String _fmtDuration(Duration duration) {
    final int seconds = math.max(0, duration.inSeconds);
    final int hours = seconds ~/ 3600;
    final String minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String secs = (seconds % 60).toString().padLeft(2, '0');

    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$secs'
        : '$minutes:$secs';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAT CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.isDecimal,
    required this.icon,
    this.accent,
    this.overrideText,
  });

  final String label;
  final double value;
  final String unit;
  final bool isDecimal;
  final IconData icon;
  final Color? accent;
  final String? overrideText;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  late double _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant _StatCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.overrideText != null &&
        oldWidget.overrideText != widget.overrideText) {
      _previousValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? _kBlue;
    final double begin = _previousValue;

    return _GlassPanel(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.20),
                  ),
                ),
                child: Icon(widget.icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SafeText(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: widget.overrideText != null
                ? _SafeText(
                    widget.overrideText!,
                    maxLines: 1,
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      fontFeatures: const <ui.FontFeature>[
                        ui.FontFeature.tabularFigures(),
                      ],
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: 0.28),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: begin,
                          end: widget.value,
                        ),
                        duration: _kAnimMed,
                        curve: Curves.easeOutCubic,
                        onEnd: () {
                          _previousValue = widget.value;
                        },
                        builder: (_, double value, __) {
                          return _SafeText(
                            widget.isDecimal
                                ? value.toStringAsFixed(1)
                                : value.round().toString(),
                            maxLines: 1,
                            style: TextStyle(
                              color: _kTextPrimary,
                              fontSize: 31,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              fontFeatures: const <ui.FontFeature>[
                                ui.FontFeature.tabularFigures(),
                              ],
                              shadows: <Shadow>[
                                Shadow(
                                  color: accent.withValues(alpha: 0.28),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (widget.unit.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 5),
                        _SafeText(
                          widget.unit,
                          maxLines: 1,
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART MAP FOLLOW MODE
// ═══════════════════════════════════════════════════════════════════════════════

class _MapFollowModeStrip extends StatelessWidget {
  const _MapFollowModeStrip({
    required this.followModeN,
    required this.onTap,
  });

  final ValueNotifier<_MapFollowMode> followModeN;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_MapFollowMode>(
      valueListenable: followModeN,
      builder: (_, _MapFollowMode mode, __) {
        return _PressableScale(
          onTap: onTap,
          child: _GlassPanel(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _kBlue.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Icon(
                    mode.icon,
                    color: _kBlue,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _SafeText(
                        'SMART MAP FOLLOW',
                        maxLines: 1,
                        style: TextStyle(
                          color: _kTextMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          _SafeText(
                            mode.label,
                            maxLines: 1,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _SafeText(
                              mode.subtitle,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _SafeText(
                        'CHANGE',
                        maxLines: 1,
                        style: TextStyle(
                          color: _kBlueSoft,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: _kBlueSoft,
                        size: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapModeBadge extends StatelessWidget {
  const _MapModeBadge({
    required this.mode,
  });

  final _MapFollowMode mode;

  @override
  Widget build(BuildContext context) {
    final Color color = mode == _MapFollowMode.freeView ? _kBlueSoft : _kBlue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: 0.26),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(mode.icon, color: color, size: 12),
                const SizedBox(width: 5),
                _SafeText(
                  mode.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
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

// ═══════════════════════════════════════════════════════════════════════════════
// MAP THUMBNAIL
// ═══════════════════════════════════════════════════════════════════════════════

class _MapThumbnail extends StatefulWidget {
  const _MapThumbnail({
    required this.posN,
    required this.mapController,
    required this.gps,
    required this.polylineCount,
    required this.onMapReady,
    required this.onTap,
  });

  final ValueNotifier<LatLng?> posN;
  final fm.MapController mapController;
  final GpsService gps;
  final int Function() polylineCount;
  final VoidCallback onMapReady;
  final VoidCallback onTap;

  @override
  State<_MapThumbnail> createState() => _MapThumbnailState();
}

class _MapThumbnailState extends State<_MapThumbnail> {
  List<LatLng> _cachedSmooth = const <LatLng>[];
  int _cachedCount = -1;
  LatLng? _cachedLast;

  List<LatLng> _smoothedPolyline() {
    final int count = widget.polylineCount();
    final LatLng? last = widget.posN.value;

    if (count == _cachedCount && last == _cachedLast) {
      return _cachedSmooth;
    }

    final List<LatLng> raw = widget.gps.currentPoints
        .map((TripPoint p) => p.position)
        .where(_isValid)
        .toList(growable: false);

    _cachedCount = count;
    _cachedLast = last;

    if (raw.length < 2) {
      _cachedSmooth = const <LatLng>[];
      return _cachedSmooth;
    }

    final List<LatLng> simplified = simplifyPolyline(raw, epsilon: 0.00004);
    final List<LatLng> smoothed = smoothPolyline(
      simplified,
      tension: 0.5,
      subdivisions: 8,
    );

    final List<LatLng> valid = <LatLng>[];
    for (final LatLng point in smoothed) {
      if (!_isValid(point)) continue;
      if (valid.isEmpty || valid.last != point) valid.add(point);
    }

    _cachedSmooth = List<LatLng>.unmodifiable(valid);
    return _cachedSmooth;
  }

  static bool _isValid(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: _GlassPanel(
          radius: 24,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: <Widget>[
                AbsorbPointer(
                  child: fm.FlutterMap(
                    mapController: widget.mapController,
                    options: fm.MapOptions(
                      initialCenter: widget.posN.value ?? _kDefaultCenter,
                      initialZoom: _kDefaultZoom,
                      interactionOptions: const fm.InteractionOptions(
                        flags: fm.InteractiveFlag.none,
                      ),
                      onMapReady: widget.onMapReady,
                    ),
                    children: <Widget>[
                      fm.TileLayer(
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/'
                            'World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.trackpro.ai',
                        tileBuilder: _legacySatelliteDarkTileBuilder,
                      ),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: widget.posN,
                        builder: (_, __, ___) {
                          final List<LatLng> polyline = _smoothedPolyline();

                          if (polyline.length < 2) {
                            return const SizedBox.shrink();
                          }

                          return fm.PolylineLayer(
                            polylines: <fm.Polyline>[
                              fm.Polyline(
                                points: polyline,
                                color: _kBlue.withValues(alpha: 0.30),
                                strokeWidth: 8.0,
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                              fm.Polyline(
                                points: polyline,
                                color: _kBlueSoft,
                                strokeWidth: 3.5,
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                            ],
                          );
                        },
                      ),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: widget.posN,
                        builder: (_, LatLng? position, __) {
                          if (position == null || !_isValid(position)) {
                            return const SizedBox.shrink();
                          }

                          return fm.MarkerLayer(
                            markers: <fm.Marker>[
                              fm.Marker(
                                point: position,
                                width: 60,
                                height: 60,
                                alignment: Alignment.center,
                                child: const _LiveMarker(),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 12,
                  top: 12,
                  child: _OverlayLabel(
                    icon: CupertinoIcons.map_fill,
                    label: 'LIVE MAP',
                  ),
                ),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _ExpandIcon(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _darkTileBuilder(
    BuildContext context,
    Widget tile,
    fm.TileImage tileImage,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.58,
        0,
        0,
        0,
        -8,
        0,
        0.58,
        0,
        0,
        -8,
        0,
        0,
        0.58,
        0,
        -8,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: tile,
    );
  }
}

Widget _legacySatelliteDarkTileBuilder(
  BuildContext context,
  Widget tile,
  fm.TileImage tileImage,
) {
  // Legacy helper kept for compatibility, but satellite tiles should remain
  // unfiltered so the map is no longer overly black/high-contrast.
  return tile;
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEATHER THUMBNAIL + SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _WeatherThumbnail extends StatelessWidget {
  const _WeatherThumbnail({
    required this.weatherN,
    required this.loadingN,
    required this.onTap,
  });

  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> loadingN;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: RepaintBoundary(
        child: _GlassPanel(
          radius: 24,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ValueListenableBuilder<WeatherData?>(
                    valueListenable: weatherN,
                    builder: (_, WeatherData? weather, __) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: loadingN,
                        builder: (_, bool loading, __) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 300,
                              height: 220,
                              child: WeatherWidget(
                                weather: weather,
                                isLoading: loading && weather == null,
                                onRetry: () {},
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Positioned(
                  left: 12,
                  top: 12,
                  child: _OverlayLabel(
                    icon: CupertinoIcons.cloud_sun_fill,
                    label: 'WEATHER',
                  ),
                ),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _ExpandIcon(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherSheet extends StatelessWidget {
  const _WeatherSheet({
    required this.weatherN,
    required this.loadingN,
    required this.onRetry,
  });

  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> loadingN;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 70),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 14),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    CupertinoIcons.cloud_sun_fill,
                    color: _kBlueSoft,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  _SafeText(
                    'LIVE WEATHER',
                    maxLines: 1,
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: _kBorder, thickness: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 38),
              child: ValueListenableBuilder<WeatherData?>(
                valueListenable: weatherN,
                builder: (_, WeatherData? weather, __) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: loadingN,
                    builder: (_, bool loading, __) {
                      return WeatherWidget(
                        weather: weather,
                        isLoading: loading && weather == null,
                        onRetry: onRetry,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM DOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.trackingN,
    required this.elapsedN,
    required this.onAction,
    required this.onMapTap,
    required this.onAiTap,
  });

  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> elapsedN;
  final VoidCallback onAction;
  final VoidCallback onMapTap;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: _kSurface.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            bottomPad > 0 ? bottomPad + 10 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SecondaryButton(
                      icon: CupertinoIcons.map_fill,
                      label: 'FULL MAP',
                      onTap: onMapTap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SecondaryButton(
                      icon: Icons.auto_awesome_rounded,
                      label: 'ASK AI',
                      onTap: onAiTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: trackingN,
                builder: (_, bool tracking, __) {
                  return _PrimaryActionButton(
                    isTracking: tracking,
                    isBusy: false,
                    onTap: onAction,
                    timerNotifier: elapsedN,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED UI
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.105),
            Colors.white.withValues(alpha: 0.043),
            Colors.white.withValues(alpha: 0.018),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: _kBlueDeep.withValues(alpha: 0.05),
            blurRadius: 30,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: _kAnimFast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: _kBlueSoft, size: 12),
                const SizedBox(width: 5),
                _SafeText(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
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

class _ExpandIcon extends StatelessWidget {
  const _ExpandIcon();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 31,
          height: 31,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: const Icon(
            CupertinoIcons.fullscreen,
            size: 14,
            color: _kTextPrimary,
          ),
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: _kRed.withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LiveDot(),
          SizedBox(width: 7),
          _SafeText(
            'LIVE',
            maxLines: 1,
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdlePill extends StatelessWidget {
  const _IdlePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: const Center(
        child: _SafeText(
          'READY',
          maxLines: 1,
          style: TextStyle(
            color: _kTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 24,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              color: Colors.white.withValues(alpha: 0.22),
              size: 28,
            ),
            const SizedBox(height: 6),
            _SafeText(
              'WEATHER OFF',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.22),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPASS
// ═══════════════════════════════════════════════════════════════════════════════

class _CompassWidget extends StatefulWidget {
  const _CompassWidget({required this.headingN});

  final ValueNotifier<double> headingN;

  @override
  State<_CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<_CompassWidget> {
  double _previousRad = 0.0;

  static const List<String> _cardinals = <String>[
    'N',
    'NE',
    'E',
    'SE',
    'S',
    'SW',
    'W',
    'NW',
  ];

  static String _cardinal(double degrees) {
    return _cardinals[((degrees + 22.5) / 45.0).floor() % 8];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.headingN,
      builder: (_, double unwrapped, __) {
        final double deg = unwrapped % 360.0;
        final double normal = deg < 0.0 ? deg + 360.0 : deg;
        final String label = _cardinal(normal);
        final double target = unwrapped * (math.pi / 180.0);
        final double begin = _previousRad;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: begin, end: target),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          onEnd: () => _previousRad = target,
          builder: (_, double radians, __) {
            return Row(
              children: <Widget>[
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.35),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const SizedBox.expand(),
                      ),
                      Transform.rotate(
                        angle: radians,
                        child: const CustomPaint(
                          size: Size(38, 38),
                          painter: _NeedlePainter(),
                        ),
                      ),
                      const CustomPaint(
                        size: Size(38, 38),
                        painter: _CompassRingPainter(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _SafeText(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
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

class _CompassRingPainter extends CustomPainter {
  const _CompassRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);
    final double radius = size.width / 2.0 - 3.0;

    final Paint paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final double radians = i * 45.0 * (math.pi / 180.0) - math.pi / 2.0;
      final double length = i.isEven ? 4.5 : 3.0;

      final Offset outer = center +
          Offset(
            math.cos(radians) * radius,
            math.sin(radians) * radius,
          );

      final Offset inner = center +
          Offset(
            math.cos(radians) * (radius - length),
            math.sin(radians) * (radius - length),
          );

      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassRingPainter oldDelegate) => false;
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);

    canvas.drawPath(
      ui.Path()
        ..moveTo(center.dx, center.dy - 12.0)
        ..lineTo(center.dx - 3.0, center.dy)
        ..lineTo(center.dx + 3.0, center.dy)
        ..close(),
      Paint()
        ..color = _kRed
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      ui.Path()
        ..moveTo(center.dx, center.dy + 12.0)
        ..lineTo(center.dx - 3.0, center.dy)
        ..lineTo(center.dx + 3.0, center.dy)
        ..close(),
      Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIGNAL / BATTERY / MARKERS
// ═══════════════════════════════════════════════════════════════════════════════

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.strength});

  final int strength;

  @override
  Widget build(BuildContext context) {
    final int safeStrength = strength.clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List<Widget>.generate(4, (int index) {
        final bool active = index < safeStrength;

        final Color color;
        if (!active) {
          color = Colors.white12;
        } else if (safeStrength >= 3) {
          color = _kGreen;
        } else if (safeStrength >= 2) {
          color = _kBlue;
        } else {
          color = _kRed;
        }

        return AnimatedContainer(
          duration: _kAnimMed,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: active ? 8.0 + index * 4.0 : 6.0 + index * 3.0,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
            boxShadow: active
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.50),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  const _BatteryIcon({
    required this.percent,
    this.state,
  });

  final int? percent;
  final BatteryState? state;

  Color get _color {
    final int? value = percent;
    if (value == null) return Colors.white38;
    if (value > 40) return _kGreen;
    if (value > 20) return const Color(0xFFFFCC00);
    return _kRed;
  }

  IconData get _icon {
    final int? value = percent;
    if (value == null) return CupertinoIcons.battery_0;
    if (value > 75) return CupertinoIcons.battery_100;
    if (value > 20) return CupertinoIcons.battery_25;
    return CupertinoIcons.battery_0;
  }

  @override
  Widget build(BuildContext context) {
    return Icon(_icon, size: 20, color: _color);
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();

    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kRed.withValues(alpha: 0.5 + _animation.value * 0.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _kRed.withValues(alpha: 0.4),
                blurRadius: 8 + _animation.value * 10,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LocationPuckMarker extends StatefulWidget {
  const _LocationPuckMarker({
    required this.heading,
  });

  final double heading;

  @override
  State<_LocationPuckMarker> createState() => _LocationPuckMarkerState();
}

class _LocationPuckMarkerState extends State<_LocationPuckMarker>
    with SingleTickerProviderStateMixin {
  static const Color _blue = Color(0xFF2F80FF);
  static const Color _blueDeep = Color(0xFF0B58D8);

  late final AnimationController _controller;
  double _displayHeading = 0.0;

  @override
  void initState() {
    super.initState();

    _displayHeading = _normalizeHeading(widget.heading);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _LocationPuckMarker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final double next = _normalizeHeading(widget.heading);
    double delta = next - _normalizeHeading(_displayHeading);

    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;

    // Ignore tiny GPS heading jitter so the puck stays stable when stopped.
    if (delta.abs() < 1.0) return;

    _displayHeading += delta;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _normalizeHeading(double value) {
    if (!value.isFinite) return 0.0;
    final double normalized = value % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final double t = _controller.value;
          final double pulse = Curves.easeOutCubic.transform(t);
          final double breathe = 0.5 + math.sin(t * math.pi * 2.0) * 0.5;

          return SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Subtle expanding GPS pulse.
                Opacity(
                  opacity: (1.0 - pulse).clamp(0.0, 1.0) * 0.22,
                  child: Container(
                    width: 30 + pulse * 32,
                    height: 30 + pulse * 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                  ),
                ),

                // Accuracy halo like modern map apps.
                Container(
                  width: 42 + breathe * 3,
                  height: 42 + breathe * 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _blue.withValues(alpha: 0.16),
                    border: Border.all(
                      color: _blue.withValues(alpha: 0.22),
                      width: 1.2,
                    ),
                  ),
                ),

                // Soft ground shadow.
                Transform.translate(
                  offset: const Offset(0, 5),
                  child: Container(
                    width: 34,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.20),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),

                // Small heading nub, matching the reference puck.
                AnimatedRotation(
                  turns: _displayHeading / 360.0,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: Transform.translate(
                    offset: const Offset(0, -18),
                    child: Container(
                      width: 8,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.26),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 4,
                        height: 8,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),

                // White outer puck ring.
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.white,
                        Color(0xFFE9F1FF),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.24),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),

                // Blue center.
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-0.25, -0.30),
                      radius: 0.9,
                      colors: <Color>[
                        Color(0xFF6FB2FF),
                        _blue,
                        _blueDeep,
                      ],
                      stops: <double>[0.0, 0.58, 1.0],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                      width: 1.4,
                    ),
                  ),
                ),

                // Gloss highlight.
                Transform.translate(
                  offset: const Offset(-4, -5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Kept for source compatibility with earlier painter-based puck versions.
class _LocationHeadingConePainter extends CustomPainter {
  const _LocationHeadingConePainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // No-op: the updated puck uses lightweight widgets instead of a cone painter.
  }

  @override
  bool shouldRepaint(covariant _LocationHeadingConePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Compatibility marker for older mini-map / thumbnail widgets that still
/// reference _LiveMarker.
class _LiveMarker extends StatelessWidget {
  const _LiveMarker();

  @override
  Widget build(BuildContext context) {
    return const _LocationPuckMarker(heading: 0.0);
  }
}

class _NavigationGeoMarker extends StatefulWidget {
  const _NavigationGeoMarker({
    required this.heading,
  });

  final double heading;

  @override
  State<_NavigationGeoMarker> createState() => _NavigationGeoMarkerState();
}

class _NavigationGeoMarkerState extends State<_NavigationGeoMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double rad = widget.heading * math.pi / 180.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Opacity(
                opacity: (1.0 - _pulse.value).clamp(0.0, 1.0) * 0.32,
                child: Container(
                  width: 30 + _pulse.value * 34,
                  height: 30 + _pulse.value * 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2A5BFF),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.90),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: rad,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    const Positioned(
                      top: 11,
                      child: CustomPaint(
                        size: Size(34, 44),
                        painter: _NavArrowPainter(
                          fill: Color(0xFF2A5BFF),
                          stroke: Colors.white,
                          shadow: Color(0x442A5BFF),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFDEE5FF),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavArrowPainter extends CustomPainter {
  const _NavArrowPainter({
    required this.fill,
    required this.stroke,
    required this.shadow,
  });

  final Color fill;
  final Color stroke;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Path path = ui.Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height * 0.70)
      ..lineTo(size.width * 0.57, size.height * 0.62)
      ..lineTo(size.width * 0.52, size.height)
      ..lineTo(size.width * 0.48, size.height)
      ..lineTo(size.width * 0.43, size.height * 0.62)
      ..lineTo(0, size.height * 0.70)
      ..close();

    canvas.drawShadow(path, shadow, 8, false);

    final Paint fillPaint = Paint()..color = fill;
    final Paint strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _NavArrowPainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.shadow != shadow;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUTTONS
// ═══════════════════════════════════════════════════════════════════════════════

class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: _kAnimFast,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _kAnimFast,
          height: 50,
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.115)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.075),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon, color: _kBlueSoft, size: 17),
              const SizedBox(width: 8),
              Flexible(
                child: _SafeText(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
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

class _PrimaryActionButton extends StatefulWidget {
  const _PrimaryActionButton({
    required this.isTracking,
    required this.isBusy,
    required this.onTap,
    required this.timerNotifier,
  });

  final bool isTracking;
  final bool isBusy;
  final VoidCallback onTap;
  final ValueNotifier<int> timerNotifier;

  @override
  State<_PrimaryActionButton> createState() => _PrimaryActionButtonState();
}

class _PrimaryActionButtonState extends State<_PrimaryActionButton> {
  bool _pressed = false;

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

  void _setPressed(bool value) {
    if (!mounted || widget.isBusy || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color main = widget.isTracking ? _kRed : _kGreen;
    final Color textColor = widget.isTracking ? Colors.white : Colors.black;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        if (!widget.isBusy) widget.onTap();
      },
      child: AnimatedOpacity(
        duration: _kAnimFast,
        opacity: widget.isBusy ? 0.78 : 1.0,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1.0,
          duration: _kAnimFast,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: _kAnimFast,
            curve: Curves.easeOut,
            height: 48,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _pressed
                    ? <Color>[
                        main.withValues(alpha: 0.72),
                        main.withValues(alpha: 0.55),
                      ]
                    : <Color>[
                        main,
                        main.withValues(alpha: 0.82),
                      ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.13),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: main.withValues(alpha: _pressed ? 0.18 : 0.34),
                  blurRadius: _pressed ? 14 : 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: _kAnimMed,
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.88, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  );
                },
                child: widget.isBusy
                    ? Row(
                        key: const ValueKey<String>('busy'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CupertinoActivityIndicator(
                            radius: 8,
                            color: textColor,
                          ),
                          const SizedBox(width: 8),
                          _SafeText(
                            widget.isTracking ? 'SAVING' : 'STARTING',
                            maxLines: 1,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      )
                    : widget.isTracking
                        ? ValueListenableBuilder<int>(
                            key: const ValueKey<String>('tracking'),
                            valueListenable: widget.timerNotifier,
                            builder: (_, int seconds, __) {
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    const Icon(
                                      CupertinoIcons.stop_fill,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    _SafeText(
                                      _formatSeconds(seconds),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                        letterSpacing: 1.0,
                                        fontFeatures: <ui.FontFeature>[
                                          ui.FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : FittedBox(
                            key: const ValueKey<String>('stopped'),
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  CupertinoIcons.play_fill,
                                  color: textColor,
                                  size: 15,
                                ),
                                const SizedBox(width: 7),
                                _SafeText(
                                  'START',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    fontSize: 13,
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
  }
}
