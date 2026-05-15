import 'package:flutter/cupertino.dart';

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
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onTap != null,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: onTap == null
            ? null
            : () {
                AppHaptics.select();
                onTap!();
              },
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor ?? AppColors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.09),
              ),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
  }
}
