import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppErrorBanner {
  const AppErrorBanner._();

  static void show(
    BuildContext context,
    String message, {
    Color color = AppColors.red,
    IconData icon = Icons.error_rounded,
    Duration duration = const Duration(seconds: 3),
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.card,
          elevation: 12,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: color.withValues(alpha: 0.35)),
          ),
          content: Row(
            children: <Widget>[
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  static void success(BuildContext context, String message) {
    show(
      context,
      message,
      color: AppColors.green,
      icon: Icons.check_circle_rounded,
    );
  }

  static void info(BuildContext context, String message) {
    show(
      context,
      message,
      color: AppColors.blueSoft,
      icon: Icons.info_rounded,
    );
  }
}
