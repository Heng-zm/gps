import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppSpeedChart extends StatelessWidget {
  const AppSpeedChart({
    super.key,
    required this.values,
    this.height = 110,
    this.color = AppColors.blueSoft,
  });

  final List<double> values;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SpeedChartPainter(values: values, color: color),
        ),
      ),
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  const _SpeedChartPainter({
    required this.values,
    required this.color,
  });

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    canvas.drawRRect(
      bg,
      Paint()..color = AppColors.white.withValues(alpha: 0.055),
    );

    if (values.length < 2) return;

    double maxValue = 1;
    for (final double value in values) {
      if (value.isFinite && value > maxValue) maxValue = value;
    }

    const double pad = 12;
    final Path path = Path();

    for (int i = 0; i < values.length; i++) {
      final double x = pad + (i / (values.length - 1)) * (size.width - pad * 2);
      final double normalized = (values[i].isFinite ? values[i] : 0) / maxValue;
      final double y = size.height - pad - normalized.clamp(0, 1) * (size.height - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
