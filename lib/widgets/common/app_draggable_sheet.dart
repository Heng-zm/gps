import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppDraggableSheet extends StatelessWidget {
  const AppDraggableSheet({
    super.key,
    required this.children,
    this.initialChildSize = 0.34,
    this.minChildSize = 0.18,
    this.maxChildSize = 0.86,
    this.title,
    this.trailing,
    this.maxWidth = 680,
  });

  final List<Widget> children;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final String? title;
  final Widget? trailing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final double minSize = minChildSize.clamp(0.08, 0.95).toDouble();
    final double maxSize = maxChildSize.clamp(minSize, 0.98).toDouble();
    final double initialSize =
        initialChildSize.clamp(minSize, maxSize).toDouble();

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      snap: true,
      builder: (BuildContext context, ScrollController controller) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.92),
                    border: Border(
                      top: BorderSide(
                        color: AppColors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.black.withValues(alpha: 0.34),
                        blurRadius: 24,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: ListView(
                      controller: controller,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: 0.24),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        if (title != null || trailing != null) ...<Widget>[
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              if (title != null)
                                Expanded(
                                  child: Text(
                                    title!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              if (trailing != null) ...<Widget>[
                                const SizedBox(width: 10),
                                Flexible(
                                  flex: 0,
                                  child: trailing!,
                                ),
                              ],
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
