import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/glosa_speed_service.dart';
import '../../theme/app_theme.dart';
import '../common/app_glass_card.dart';

class GlosaSpeedSheet extends StatefulWidget {
  const GlosaSpeedSheet({super.key});

  @override
  State<GlosaSpeedSheet> createState() => _GlosaSpeedSheetState();
}

class _GlosaSpeedSheetState extends State<GlosaSpeedSheet> {
  final GlosaSpeedService _service = GlosaSpeedService.instance;

  @override
  void initState() {
    super.initState();
    _service.startV2iSync();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlosaIntersectionSnapshot>(
      valueListenable: _service.snapshotN,
      builder: (BuildContext context, GlosaIntersectionSnapshot snap, _) {
        final Color phaseColor = snap.phase == SignalPhase.green
            ? AppColors.green
            : snap.phase == SignalPhase.yellow
                ? Colors.amber
                : AppColors.red;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Main Traffic Light Countdown Hero
              AppGlassCard(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                borderRadius: 24,
                child: Column(
                  children: <Widget>[
                    // Traffic Signal Tri-Light Capsule
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _SignalLamp(color: AppColors.red, active: snap.phase == SignalPhase.red),
                          const SizedBox(width: 12),
                          _SignalLamp(color: Colors.amber, active: snap.phase == SignalPhase.yellow),
                          const SizedBox(width: 12),
                          _SignalLamp(color: AppColors.green, active: snap.phase == SignalPhase.green),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Countdown Seconds
                    Text(
                      '${snap.secondsRemaining}s',
                      style: TextStyle(
                        color: phaseColor,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snap.phase == SignalPhase.red
                          ? 'REMAINING UNTIL GREEN WAVE'
                          : snap.phase == SignalPhase.yellow
                              ? 'TURNING RED SOON'
                              : 'REMAINING GREEN WINDOW',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // GLOSA Recommended Speed Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: phaseColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: phaseColor.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: <Widget>[
                          Text(
                            'RECOMMENDED CRUISING SPEED',
                            style: TextStyle(
                              color: phaseColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              Text(
                                snap.recommendedSpeedKmh.round().toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'KM/H',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Cruise at this speed to pass without stopping at red.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Intersection & Distance Info
              AppGlassCard(
                padding: const EdgeInsets.all(16),
                borderRadius: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(CupertinoIcons.location_north_line_fill, size: 16, color: AppColors.blueSoft),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            snap.intersectionName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        _StatItem(label: 'DISTANCE AHEAD', value: '${snap.distanceMeters.round()}m'),
                        _StatItem(label: 'EST. FUEL SAVED', value: '~${snap.fuelSavingsEstimatePercent}%'),
                        _StatItem(label: 'V2I LINK', value: '4.8ms (Low Latency)'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

class _SignalLamp extends StatelessWidget {
  const _SignalLamp({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withValues(alpha: 0.15),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 12),
              ]
            : null,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
