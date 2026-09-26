import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ferromagnetic_radar_service.dart';
import '../../theme/app_theme.dart';
import '../common/app_glass_card.dart';

class FerromagneticRadarSheet extends StatefulWidget {
  const FerromagneticRadarSheet({super.key});

  @override
  State<FerromagneticRadarSheet> createState() => _FerromagneticRadarSheetState();
}

class _FerromagneticRadarSheetState extends State<FerromagneticRadarSheet> {
  final FerromagneticRadarService _service = FerromagneticRadarService.instance;

  @override
  void initState() {
    super.initState();
    _service.start();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MagneticRadarReading>(
      valueListenable: _service.readingN,
      builder: (BuildContext context, MagneticRadarReading reading, _) {
        final bool isAnomaly = reading.anomalyDelta > 18.0;
        final Color themeColor = isAnomaly
            ? (reading.totalMicroTesla > 75 ? AppColors.red : Colors.amberAccent)
            : AppColors.blueSoft;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Main Flux Gauge Hero
              AppGlassCard(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                borderRadius: 24,
                child: Column(
                  children: <Widget>[
                    Text(
                      'TOTAL MAGNETIC FLUX DENSITY',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          reading.totalMicroTesla.toStringAsFixed(1),
                          style: TextStyle(
                            color: themeColor,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'μT',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Geomagnetic Baseline: ~42.5 μT · Delta: +${reading.anomalyDelta.toStringAsFixed(1)} μT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Anomaly Classification Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: themeColor.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            isAnomaly
                                ? CupertinoIcons.exclamationmark_shield_fill
                                : CupertinoIcons.checkmark_shield_fill,
                            size: 13,
                            color: themeColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _labelFromAnomaly(reading.anomalyType),
                            style: TextStyle(
                              color: themeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Live Waterfall Spectrogram Canvas
              _buildWaterfallCard(reading.historyWaterfall),
              const SizedBox(height: 14),

              // 3-Axis Vector Breakdown
              AppGlassCard(
                padding: const EdgeInsets.all(14),
                borderRadius: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _AxisPill(label: 'X-AXIS', value: '${reading.xMicroTesla.toStringAsFixed(1)} μT'),
                    _AxisPill(label: 'Y-AXIS', value: '${reading.yMicroTesla.toStringAsFixed(1)} μT'),
                    _AxisPill(label: 'Z-AXIS', value: '${reading.zMicroTesla.toStringAsFixed(1)} μT'),
                    _AxisPill(label: 'PEAK FLUX', value: '${reading.peakMicroTesla.toStringAsFixed(1)} μT'),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Reset Peak button
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 32,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _service.resetPeak();
                },
                child: Center(
                  child: Text(
                    'RESET PEAK FLUX',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaterfallCard(List<double> waterfall) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'SPATIAL WATERFALL SPECTROGRAM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '48 SAMPLES',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WaterfallPainter(waterfall: waterfall),
            ),
          ),
        ],
      ),
    );
  }

  static String _labelFromAnomaly(MagneticAnomalyType type) {
    switch (type) {
      case MagneticAnomalyType.structuralIronGirders:
        return 'Bridge Girder / Reinforced Steel Frame';
      case MagneticAnomalyType.undergroundPipeline:
        return 'Subsurface Ferrous Pipeline / Cable Detected';
      case MagneticAnomalyType.highVoltageCable:
        return 'High-Voltage Power Field Anomaly';
      case MagneticAnomalyType.voidDepletion:
        return 'Geological Magnetic Void / Cavity';
      case MagneticAnomalyType.ambientNormal:
        return 'Ambient Geomagnetic Field Normal';
    }
  }
}

class _AxisPill extends StatelessWidget {
  const _AxisPill({required this.label, required this.value});
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
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  const _WaterfallPainter({required this.waterfall});
  final List<double> waterfall;

  @override
  void paint(Canvas canvas, Size size) {
    if (waterfall.isEmpty) return;

    final double barWidth = size.width / 48.0;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < waterfall.length; i++) {
      final double val = waterfall[i];
      final double norm = ((val - 20.0) / 80.0).clamp(0.05, 1.0);
      final double barHeight = norm * size.height;

      paint.color = val > 80.0
          ? AppColors.red
          : val > 60.0
              ? Colors.amberAccent
              : AppColors.blueSoft;

      final Rect rect = Rect.fromLTWH(
        size.width - (i + 1) * barWidth,
        size.height - barHeight,
        barWidth - 1.0,
        barHeight,
      );

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter old) => true;
}
