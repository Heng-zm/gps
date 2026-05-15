import 'package:flutter/cupertino.dart';

import '../../theme/app_theme.dart';

class AppTimelineSlider extends StatelessWidget {
  const AppTimelineSlider({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.label,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final double safeMax = max <= 0 ? 1 : max;
    final double safeValue = value.clamp(0.0, safeMax);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!,
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
        ),
      ],
    );
  }
}
