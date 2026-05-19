import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/mapbox_styles.dart';
import '../theme/app_theme.dart';

class MapboxStyleOptionGrid extends StatelessWidget {
  const MapboxStyleOptionGrid({
    super.key,
    required this.selected,
    required this.onChanged,
    this.styles = MapboxStyleCatalog.all,
  });

  final MapboxVisualStyle selected;
  final ValueChanged<MapboxVisualStyle> onChanged;
  final List<MapboxVisualStyle> styles;

  @override
  Widget build(BuildContext context) {
    if (styles.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bool compact = maxWidth < 390.0;
        final double spacing = compact ? 7.0 : 8.0;
        final double itemWidth = compact
            ? maxWidth
            : ((maxWidth - spacing) / 2).clamp(150.0, 210.0).toDouble();

        return RepaintBoundary(
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: styles.map((MapboxVisualStyle style) {
              return _MapboxStyleOptionTile(
                style: style,
                active: selected == style,
                width: itemWidth,
                compact: compact,
                onTap: () => onChanged(style),
              );
            }).toList(growable: false),
          ),
        );
      },
    );
  }
}

class _MapboxStyleOptionTile extends StatelessWidget {
  const _MapboxStyleOptionTile({
    required this.style,
    required this.active,
    required this.width,
    required this.compact,
    required this.onTap,
  });

  final MapboxVisualStyle style;
  final bool active;
  final double width;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = style.accentColor;

    return Semantics(
      button: true,
      selected: active,
      label: style.shortLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 44,
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: width,
          constraints: const BoxConstraints(minHeight: 58),
          padding: EdgeInsets.all(compact ? 11 : 12),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.18)
                : AppColors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.38)
                  : AppColors.white.withValues(alpha: 0.08),
            ),
            boxShadow: active
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      style.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: active ? AppColors.white : AppColors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _familyLabel(style),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(
                        color: AppColors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (active) ...<Widget>[
                const SizedBox(width: 6),
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: color,
                  size: 17,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _familyLabel(MapboxVisualStyle style) {
    if (style.isStandardFamily) return 'Standard';
    if (style.isSatelliteFamily) return 'Satellite';
    if (style.isNavigationFamily) return 'Navigation';
    return 'Classic';
  }
}
