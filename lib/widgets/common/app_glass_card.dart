import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = 22,
    this.color,
    this.borderColor,
    this.blur = 16,
    this.shadow = true,
    this.clip = true,
    this.margin,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;
  final double blur;
  final bool shadow;
  final bool clip;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final double radius = borderRadius.clamp(0.0, 80.0).toDouble();
    final BorderRadiusGeometry resolvedRadius = BorderRadius.circular(radius);

    final Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null
            ? (color ?? AppColors.card.withValues(alpha: 0.88))
            : null,
        gradient: gradient,
        borderRadius: resolvedRadius,
        border: Border.all(
          color: borderColor ?? AppColors.border.withValues(alpha: 0.78),
        ),
        boxShadow: shadow
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    final Widget blurred = blur <= 0
        ? content
        : BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: content,
          );

    Widget result = clip
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: blurred,
          )
        : blurred;

    if (margin != null) result = Padding(padding: margin!, child: result);
    return result;
  }
}
