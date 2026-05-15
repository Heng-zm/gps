import 'package:flutter/cupertino.dart';

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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: styles.map((MapboxVisualStyle style) {
        final bool active = selected == style;
        final Color color = style.accentColor;

        return CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: () => onChanged(style),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 164,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.18)
                  : AppColors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? color.withValues(alpha: 0.35)
                    : AppColors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(style.icon, color: color, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        style.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  const SizedBox(width: 5),
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: color,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  static String _familyLabel(MapboxVisualStyle style) {
    if (style.isStandardFamily) return 'Standard';
    if (style.isSatelliteFamily) return 'Satellite';
    if (style.isNavigationFamily) return 'Navigation';
    return 'Classic';
  }
}
