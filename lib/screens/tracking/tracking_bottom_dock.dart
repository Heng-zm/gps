// ignore_for_file: unused_element, unused_element_parameter

part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM DOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _MapFirstBottomDock extends StatelessWidget {
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
    required this.onWeatherTap,
    required this.onMapboxTap,
    required this.onFollowModeTap,
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
  final VoidCallback onWeatherTap;
  final VoidCallback onMapboxTap;
  final VoidCallback onFollowModeTap;

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomPad > 0 ? bottomPad + 8 : 12,
      child: RepaintBoundary(
        child: AppGlassCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          borderRadius: 28,
          color: _kSurface.withValues(alpha: 0.88),
          borderColor: Colors.white.withValues(alpha: 0.09),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<int>(
                valueListenable: tickN,
                builder: (_, __, ___) {
                  return Row(
                    children: <Widget>[
                      Expanded(
                        child: _DockMetricCard(
                          label: 'Distance',
                          value:
                              '${settings.toDisplayDistance(gps.currentDistanceMiles).toStringAsFixed(1)} ${settings.distanceUnit}',
                          icon: CupertinoIcons.map_fill,
                          color: _kBlueSoft,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: autoPausedN,
                          builder: (_, bool autoPaused, __) {
                            return _DockMetricCard(
                              label: autoPaused ? 'Paused' : 'Time',
                              value: _formatSeconds(
                                autoPaused
                                    ? autoPauseStoppedN.value
                                    : gps.currentTripTime.inSeconds,
                              ),
                              icon: autoPaused
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.timer,
                              color: autoPaused ? _kBlueSoft : _kGreen,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DockMetricCard(
                          label: 'Avg',
                          value:
                              '${settings.toDisplaySpeed(gps.currentAvgSpeedMph).round()} ${settings.speedUnit}',
                          icon: CupertinoIcons.speedometer,
                          color: _kBlue,
                        ),
                      ),
                    ],
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: autoPausedN,
                builder: (_, bool autoPaused, __) {
                  if (!autoPaused) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: _AutoPauseBanner(
                      stoppedN: autoPauseStoppedN,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: ValueListenableBuilder<_MapFollowMode>(
                      valueListenable: followModeN,
                      builder: (_, _MapFollowMode mode, __) {
                        return AppActionButton(
                          label: mode.label,
                          icon: mode.icon,
                          height: 46,
                          onTap: onFollowModeTap,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: trackingN,
                      builder: (_, bool tracking, __) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: actionBusyN,
                          builder: (_, bool busy, __) {
                            if (busy) {
                              return const _BusyTrackingButton();
                            }

                            return AppActionButton(
                              label: tracking ? 'Stop' : 'Start',
                              icon: tracking
                                  ? CupertinoIcons.stop_fill
                                  : CupertinoIcons.play_fill,
                              primary: true,
                              height: 48,
                              onTap: onAction,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppActionButton(
                      label: 'AI',
                      icon: Icons.auto_awesome_rounded,
                      height: 46,
                      onTap: onAiTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppActionButton(
                      label: 'Map',
                      icon: CupertinoIcons.map_fill,
                      height: 40,
                      onTap: onMapTap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppActionButton(
                      label: 'Route',
                      icon: CupertinoIcons.location_north_line_fill,
                      height: 40,
                      onTap: onMapboxTap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppActionButton(
                      label: 'Weather',
                      icon: CupertinoIcons.cloud_sun_fill,
                      height: 40,
                      onTap: onWeatherTap,
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
