import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_haptics.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = AppColors.blueSoft,
    this.backgroundColor,
    this.size = 42,
    this.iconSize = 18,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final double resolvedSize = size.clamp(40.0, 72.0).toDouble();

    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onTap != null,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: resolvedSize,
        pressedOpacity: 0.82,
        onPressed: onTap == null
            ? null
            : () {
                AppHaptics.select();
                onTap!();
              },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: onTap == null ? 0.45 : 1.0,
          child: Container(
            width: resolvedSize,
            height: resolvedSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor ?? AppColors.white.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.white.withValues(alpha: 0.09)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
  }
}
