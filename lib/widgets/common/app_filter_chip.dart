import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_haptics.dart';

class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.blueSoft : AppColors.white54;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 40,
        pressedOpacity: 0.82,
        onPressed: enabled
            ? () {
                AppHaptics.select();
                onTap();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1.0 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.blue.withValues(alpha: 0.18)
                  : AppColors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: selected
                    ? AppColors.blueSoft.withValues(alpha: 0.24)
                    : AppColors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, color: color, size: 14),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.55,
                    ),
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
