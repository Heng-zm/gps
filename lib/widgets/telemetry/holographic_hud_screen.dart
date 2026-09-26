import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/gforce_telemetry_service.dart';
import '../../services/glosa_speed_service.dart';
import '../../services/gps_service.dart';
import '../../services/holographic_hud_service.dart';
import '../../services/settings_service.dart';

/// Full-Screen Collimated Holographic Windshield HUD (Heads-Up Display)
class HolographicHudScreen extends StatefulWidget {
  const HolographicHudScreen({super.key});

  static Future<void> open(BuildContext context) {
    HapticFeedback.heavyImpact();
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const HolographicHudScreen(),
      ),
    );
  }

  @override
  State<HolographicHudScreen> createState() => _HolographicHudScreenState();
}

class _HolographicHudScreenState extends State<HolographicHudScreen> {
  final HolographicHudService _hud = HolographicHudService.instance;
  final GpsService _gps = GpsService.instance;
  final SettingsService _settings = SettingsService.instance;
  final GForceTelemetryService _gforce = GForceTelemetryService.instance;
  final GlosaSpeedService _glosa = GlosaSpeedService.instance;

  @override
  void initState() {
    super.initState();
    // Hide system status bar for true OLED black
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _gforce.start();
    _glosa.startV2iSync();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: _hud.isMirroredN,
        builder: (BuildContext context, bool isMirrored, _) {
          return ValueListenableBuilder<HudColorTheme>(
            valueListenable: _hud.themeN,
            builder: (BuildContext context, HudColorTheme theme, _) {
              final Widget content = _buildHudContent(context, theme.color, isMirrored);

              if (isMirrored) {
                // Mirror horizontally for windshield glass reflection
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: content,
                );
              }
              return content;
            },
          );
        },
      ),
    );
  }

  Widget _buildHudContent(BuildContext context, Color color, bool isMirrored) {
    final double displaySpeed = _settings.toDisplaySpeed(_gps.currentSpeedMph);
    final String unit = _settings.speedUnit.toUpperCase();
    final double heading = _gps.currentHeadingDegrees;

    return Stack(
      children: <Widget>[
        // Main Holographic Elements
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Compass & Heading
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(CupertinoIcons.compass, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    '${_cardinal(heading)} ${heading.round()}°',
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Massive Speedometer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    displaySpeed.round().toString(),
                    style: TextStyle(
                      color: color,
                      fontSize: 110,
                      fontWeight: FontWeight.w900,
                      height: 0.9,
                      shadows: <Shadow>[
                        Shadow(color: color.withValues(alpha: 0.6), blurRadius: 24),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    unit,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.75),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // GLOSA Green Wave Advisory Pill
              ValueListenableBuilder<GlosaIntersectionSnapshot>(
                valueListenable: _glosa.snapshotN,
                builder: (_, GlosaIntersectionSnapshot snap, __) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(CupertinoIcons.flame_fill, size: 14, color: color),
                        const SizedBox(width: 6),
                        Text(
                          'GREEN WAVE: CRUISE ${snap.recommendedSpeedKmh.round()} KM/H',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // G-Force Telemetry Mini-Vector
              ValueListenableBuilder<GForceReading>(
                valueListenable: _gforce.readingN,
                builder: (_, GForceReading g, __) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        'LAT ${g.lateralG >= 0 ? "+" : ""}${g.lateralG.toStringAsFixed(2)}G',
                        style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 18),
                      Text(
                        'LEAN ${g.leanAngleDeg.round()}°',
                        style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // Bottom Controls Bar (Exit, Mirror Toggle, Theme Cycle)
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // Close HUD button
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                onPressed: () => Navigator.pop(context),
                child: const Row(
                  children: <Widget>[
                    Icon(CupertinoIcons.xmark, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text('EXIT HUD', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),

              Row(
                children: <Widget>[
                  // Color Theme Cycle
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _hud.cycleTheme();
                    },
                    child: Row(
                      children: <Widget>[
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('COLOR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Mirror Flip Toggle
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: isMirrored ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _hud.toggleMirror();
                    },
                    child: Row(
                      children: <Widget>[
                        const Icon(CupertinoIcons.arrow_right_arrow_left, size: 13, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          isMirrored ? 'MIRRORED' : 'STANDARD',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _cardinal(double deg) {
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
