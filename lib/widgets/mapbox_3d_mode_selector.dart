import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
        height: 44,
        child: RepaintBoundary(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.zero,
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
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bool singleColumn = maxWidth < 390.0;
        final double spacing = singleColumn ? 7.0 : 8.0;
        final double width = singleColumn
            ? maxWidth
            : ((maxWidth - spacing) / 2).clamp(150.0, 260.0).toDouble();

        return RepaintBoundary(
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: Mapbox3DMode.values.map((Mapbox3DMode mode) {
              return _ModeCard(
                mode: mode,
                width: width,
                selected: selected == mode,
                onTap: () => onChanged(mode),
              );
            }).toList(growable: false),
          ),
        );
      },
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

    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 44,
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 78),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : AppColors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.36)
                  : AppColors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(mode.icon, color: color, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: selected ? AppColors.white : AppColors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final Mapbox3DMode mode;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = mode.accentColor;

    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 58,
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: width,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : AppColors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.38)
                  : AppColors.white.withValues(alpha: 0.08),
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.13),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(mode.icon, color: color, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: selected ? AppColors.white : AppColors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${mode.pitch.toStringAsFixed(0)}° pitch',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: 6),
                Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
