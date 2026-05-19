import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_glass_card.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.iconColor = AppColors.blueSoft,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.spacing = 0,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iconColor.withValues(alpha: 0.12),
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(icon, color: iconColor, size: 14),
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.blueSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      child: trailing!,
                    ),
                  ],
                ],
              ),
            ),
            AppGlassCard(
              padding: padding,
              borderRadius: 24,
              child: _SectionChildren(
                spacing: spacing,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionChildren extends StatelessWidget {
  const _SectionChildren({
    required this.children,
    required this.spacing,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    if (spacing <= 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );
  }
}
