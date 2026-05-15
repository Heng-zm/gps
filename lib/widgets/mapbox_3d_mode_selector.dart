import 'package:flutter/cupertino.dart';

import '../models/mapbox_3d_config.dart';
import '../theme/app_theme.dart';

class Mapbox3DModeSelector extends StatelessWidget {
  const Mapbox3DModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final Mapbox3DMode selected;
  final ValueChanged<Mapbox3DMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: Mapbox3DMode.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (BuildContext context, int index) {
            final Mapbox3DMode mode = Mapbox3DMode.values[index];

            return _ModeChip(
              mode: mode,
              selected: selected == mode,
              onTap: () => onChanged(mode),
            );
          },
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: Mapbox3DMode.values.map((Mapbox3DMode mode) {
        return _ModeCard(
          mode: mode,
          selected: selected == mode,
          onTap: () => onChanged(mode),
        );
      }).toList(growable: false),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final Mapbox3DMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = mode.accentColor;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : AppColors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.35)
                : AppColors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(mode.icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              mode.label,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final Mapbox3DMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = mode.accentColor;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 164,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : AppColors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.35)
                : AppColors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(mode.icon, color: color, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mode.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.white : AppColors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${mode.pitch.toStringAsFixed(0)}° pitch',
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
            if (selected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: color,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
