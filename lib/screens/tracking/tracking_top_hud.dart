part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TOP HUD / SPEED HUD / FLOATING ACTIONS — Apple HIG Minimalist Redesign
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
              Colors.black.withValues(alpha: 0.32),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.38),
            ],
            stops: const <double>[0.0, 0.12, 0.82, 1.0],
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
    // Replaced by floating action island for a cleaner, unified Apple UI.
    return const SizedBox.shrink();
  }
}

/// Unified, ultra-clean Apple Dynamic Island-style Top HUD
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
    required this.onWeatherTap,
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
  final VoidCallback onWeatherTap;

  @override
  Widget build(BuildContext context) {
    final double topSafe = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topSafe + 6,
      left: 14,
      right: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Main Apple Glass Pill
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.7,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    // Left: GPS / Live indicator
                    ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        trackingN,
                        signalN,
                        accuracyN,
                        autoPausedN,
                      ]),
                      builder: (BuildContext context, _) {
                        final bool tracking = trackingN.value;
                        final bool autoPaused = autoPausedN.value;
                        final double accuracy = accuracyN.value;
                        final bool hasGoodGps = accuracy.isFinite && accuracy < 30.0;

                        final Color dotColor = autoPaused
                            ? _kBlueSoft
                            : tracking
                                ? _kGreen
                                : hasGoodGps
                                    ? _kBlueSoft
                                    : Colors.orange;

                        final String label = autoPaused
                            ? 'PAUSED'
                            : tracking
                                ? 'LIVE'
                                : hasGoodGps
                                    ? 'READY'
                                    : 'SEARCH';

                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 28,
                          onPressed: onPerformanceTap,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: dotColor.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  color: dotColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const Spacer(),

                    // Center: Compass Heading or Tracking Time
                    ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        trackingN,
                        compassN,
                        tickN,
                      ]),
                      builder: (BuildContext context, _) {
                        final bool tracking = trackingN.value;
                        final double heading = compassN.value;
                        final String cardinal = _cardinalDirection(heading);

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              CupertinoIcons.compass,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$cardinal ${heading.round()}°',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                fontFeatures: <ui.FontFeature>[
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const Spacer(),

                    // Right: Weather Pill & Battery
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 32,
                          onPressed: onWeatherTap,
                          child: ValueListenableBuilder<WeatherData?>(
                            valueListenable: weatherN,
                            builder: (BuildContext context, WeatherData? weather, _) {
                              final String tempStr = weather != null
                                  ? '${weather.temperature.round()}°${settings.useKmh ? "C" : "F"}'
                                  : '--°';
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    CupertinoIcons.cloud_sun_fill,
                                    size: 14,
                                    color: Colors.amber.shade300,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tempStr,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Battery indicator
                        ValueListenableBuilder<int?>(
                          valueListenable: batteryN,
                          builder: (BuildContext context, int? battery, _) {
                            final int level = battery ?? 100;
                            return Icon(
                              level > 75
                                  ? CupertinoIcons.battery_100
                                  : level > 25
                                      ? CupertinoIcons.battery_25
                                      : CupertinoIcons.battery_0,
                              size: 16,
                              color: level > 20
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : Colors.redAccent,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Optional subtle Coach Tip banner (only appears when tip is active)
          ValueListenableBuilder<String>(
            valueListenable: coachTipN,
            builder: (BuildContext context, String tip, _) {
              if (tip.isEmpty || tip == 'Standing by · GPS stable') {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(CupertinoIcons.sparkles, size: 11, color: _kBlueSoft),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              tip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
          ),
        ],
      ),
    );
  }

  static String _cardinalDirection(double deg) {
    if (!deg.isFinite) return 'N';
    final double d = (deg % 360 + 360) % 360;
    if (d >= 337.5 || d < 22.5) return 'N';
    if (d < 67.5) return 'NE';
    if (d < 112.5) return 'E';
    if (d < 157.5) return 'SE';
    if (d < 202.5) return 'S';
    if (d < 247.5) return 'SW';
    if (d < 292.5) return 'W';
    return 'NW';
  }
}

/// Sleek floating action column on the right edge (Apple Maps / Google Maps style)
class _MapFirstFloatingActions extends StatelessWidget {
  const _MapFirstFloatingActions({
    required this.followModeN,
    required this.onFollowModeTap,
    required this.onMapTap,
    required this.onMapboxTap,
    required this.onArTap,
    required this.onAiTap,
  });

  final ValueNotifier<_MapFollowMode> followModeN;
  final VoidCallback onFollowModeTap;
  final VoidCallback onMapTap;
  final VoidCallback onMapboxTap;
  final VoidCallback onArTap;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    final double topSafe = MediaQuery.paddingOf(context).top;

    return Positioned(
      right: 14,
      top: topSafe + 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 1. Follow / Compass Mode
          ValueListenableBuilder<_MapFollowMode>(
            valueListenable: followModeN,
            builder: (BuildContext context, _MapFollowMode mode, _) {
              final bool isCentered = mode != _MapFollowMode.freeView;
              return _FloatingCircleButton(
                icon: mode.icon,
                active: isCentered,
                activeColor: _kBlue,
                semanticLabel: mode.label,
                onTap: onFollowModeTap,
              );
            },
          ),
          const SizedBox(height: 10),

          // 2. Map Layers / 3D
          _FloatingCircleButton(
            icon: CupertinoIcons.map_fill,
            semanticLabel: 'Map Layers',
            onTap: onMapTap,
          ),
          const SizedBox(height: 10),

          // 3. Route Planner
          _FloatingCircleButton(
            icon: CupertinoIcons.arrow_turn_up_right,
            semanticLabel: 'Plan Route',
            onTap: onMapboxTap,
          ),
          const SizedBox(height: 10),

          // 4. AR Route Guidance
          _FloatingCircleButton(
            icon: CupertinoIcons.camera_viewfinder,
            semanticLabel: 'AR Camera',
            onTap: onArTap,
          ),
          const SizedBox(height: 10),

          // 5. AI Assistant
          _FloatingCircleButton(
            icon: CupertinoIcons.sparkles,
            activeColor: _kBlueSoft,
            semanticLabel: 'AI Coach',
            onTap: onAiTap,
          ),
        ],
      ),
    );
  }
}

/// Circular frosted glass button (Apple Maps standard 44x44pt)
class _FloatingCircleButton extends StatelessWidget {
  const _FloatingCircleButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.active = false,
    this.activeColor = _kBlue,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? activeColor.withValues(alpha: 0.28)
                    : Colors.black.withValues(alpha: 0.48),
                border: Border.all(
                  color: active
                      ? activeColor.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.12),
                  width: active ? 1.2 : 0.8,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.90),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact, elegant Speedometer HUD floating on the bottom-left above the dock
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
      left: 14,
      bottom: bottomSafe + 130,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          speedN,
          trackingN,
          autoPausedN,
        ]),
        builder: (BuildContext context, _) {
          final double speed = speedN.value;
          final bool tracking = trackingN.value;
          if (!tracking && speed <= 0.5) {
            return const SizedBox.shrink();
          }

          final bool isOver = tracking && speed > settings.speedAlertMph;

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isOver
                      ? Colors.red.shade900.withValues(alpha: 0.65)
                      : Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOver
                        ? _kRed.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SpeedometerWidget(
                      speedMph: speed,
                      isOverLimit: isOver,
                      compact: true,
                      showUnit: true,
                      showOverLimitBadge: false,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
