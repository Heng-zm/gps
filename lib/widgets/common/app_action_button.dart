import 'package:flutter/cupertino.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_haptics.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.enabled = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && onTap != null;

    return Semantics(
      button: true,
      enabled: active,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: active
            ? () {
                AppHaptics.select();
                onTap!();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: active ? 1.0 : 0.45,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: primary ? AppColors.blueButtonGradient : null,
              color: primary ? null : AppColors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: primary
                    ? AppColors.blueSoft.withValues(alpha: 0.18)
                    : AppColors.white.withValues(alpha: 0.10),
              ),
              boxShadow: primary
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.blue.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    color: AppColors.white,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
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
