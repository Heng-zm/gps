import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/location_puck_style.dart';
import '../../theme/app_theme.dart';
import '../location_puck_widget.dart';

class LocationPuckStyleSelector extends StatelessWidget {
  const LocationPuckStyleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final LocationPuckStyle selected;
  final ValueChanged<LocationPuckStyle> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final int columns = maxWidth >= 560 ? 3 : 2;
        final double gap = compact ? 8 : 12;
        final double itemWidth =
            ((maxWidth - (gap * (columns - 1))) / columns).clamp(128.0, 210.0);

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: LocationPuckStyle.values.map((LocationPuckStyle style) {
            return _LocationPuckStyleCard(
              width: itemWidth,
              style: style,
              selected: selected == style,
              compact: compact,
              onTap: () => onChanged(style),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _LocationPuckStyleCard extends StatefulWidget {
  const _LocationPuckStyleCard({
    required this.width,
    required this.style,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final double width;
  final LocationPuckStyle style;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_LocationPuckStyleCard> createState() => _LocationPuckStyleCardState();
}

class _LocationPuckStyleCardState extends State<_LocationPuckStyleCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.style.accentColor;
    final double cardHeight = widget.compact ? 118 : 174;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: cardHeight,
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 10 : 12,
            widget.compact ? 10 : 14,
            widget.compact ? 10 : 12,
            widget.compact ? 10 : 13,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? color.withValues(alpha: 0.14)
                : AppColors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.selected
                  ? color.withValues(alpha: 0.80)
                  : AppColors.white.withValues(alpha: 0.075),
              width: widget.selected ? 1.4 : 1.0,
            ),
            boxShadow: widget.selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.20),
                      blurRadius: 22,
                      offset: const Offset(0, 9),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: widget.selected
                          ? RadialGradient(
                              center: Alignment.topCenter,
                              radius: 1.0,
                              colors: <Color>[
                                color.withValues(alpha: 0.12),
                                Colors.transparent,
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    AppLocationPuck(
                      style: widget.style,
                      bearing: 28,
                      speed: 28,
                      size: widget.compact ? 38 : 58,
                      showPulse: widget.selected,
                      isActive: widget.selected,
                    ),
                    SizedBox(height: widget.compact ? 8 : 13),
                    Text(
                      widget.style.shortLabel.isEmpty
                          ? 'Puck'
                          : widget.style.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.selected
                            ? AppColors.white
                            : AppColors.white70,
                        fontSize: widget.compact ? 12 : 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (!widget.compact) ...<Widget>[
                      const SizedBox(height: 7),
                      Text(
                        widget.style.description.isEmpty
                            ? 'Location puck style.'
                            : widget.style.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.white54,
                          fontSize: 11,
                          height: 1.22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: widget.compact ? 22 : 28,
                      height: widget.compact ? 22 : 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(
                        CupertinoIcons.checkmark,
                        color: Colors.white,
                        size: widget.compact ? 13 : 17,
                      ),
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
