import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppTimelineSlider extends StatelessWidget {
  const AppTimelineSlider({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.label,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final String? label;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final double safeMax = max.isFinite && max > 0 ? max : 1.0;
    final double safeValue = (value.isFinite ? value : 0.0).clamp(0.0, safeMax).toDouble();

    return Semantics(
      slider: true,
      label: label,
      value: safeValue.toStringAsFixed(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
          ],
          CupertinoSlider(
            value: safeValue,
            min: 0,
            max: safeMax,
            activeColor: AppColors.blue,
            thumbColor: AppColors.white,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
