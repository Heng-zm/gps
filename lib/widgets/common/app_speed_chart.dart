import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppSpeedChart extends StatelessWidget {
  const AppSpeedChart({
    super.key,
    required this.values,
    this.height = 110,
    this.color = AppColors.blueSoft,
    this.maxSamples = 96,
  });

  final List<double> values;
  final double height;
  final Color color;
  final int maxSamples;

  @override
  Widget build(BuildContext context) {
    final List<double> safeValues = _downsample(values, maxSamples);

    return RepaintBoundary(
      child: SizedBox(
        height: height.clamp(48.0, 260.0).toDouble(),
        width: double.infinity,
        child: CustomPaint(
          isComplex: true,
          painter: _SpeedChartPainter(values: safeValues, color: color),
        ),
      ),
    );
  }

  static List<double> _downsample(List<double> source, int maxSamples) {
    final int safeMax = maxSamples.clamp(8, 300).toInt();
    if (source.length <= safeMax) {
      return source.map((double value) => value.isFinite ? value : 0.0).toList(growable: false);
    }

    return List<double>.generate(safeMax, (int index) {
      final int sourceIndex = ((index / (safeMax - 1)) * (source.length - 1)).round();
      final double value = source[sourceIndex];
      return value.isFinite ? value : 0.0;
    }, growable: false);
  }
}

class _SpeedChartPainter extends CustomPainter {
  const _SpeedChartPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    canvas.drawRRect(bg, Paint()..color = AppColors.white.withValues(alpha: 0.055));

    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    double maxValue = 1.0;
    for (final double value in values) {
      if (value.isFinite && value > maxValue) maxValue = value;
    }

    const double pad = 12.0;
    final Path path = Path();
    final Path fill = Path();

    for (int i = 0; i < values.length; i++) {
      final double x = pad + (i / (values.length - 1)) * (size.width - pad * 2);
      final double normalized = ((values[i].isFinite ? values[i] : 0.0) / maxValue).clamp(0.0, 1.0).toDouble();
      final double y = size.height - pad - normalized * (size.height - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height - pad);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width - pad, size.height - pad);
    fill.close();

    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.values.length != values.length || oldDelegate.values != values;
  }
}
