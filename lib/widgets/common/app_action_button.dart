import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_haptics.dart';

class AppActionButton extends StatefulWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.enabled = true,
    this.isLoading = false,
    this.height = 52,
    this.minWidth = 88,
    this.semanticHint,
    this.color,
    this.textColor = AppColors.white,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool enabled;
  final bool isLoading;
  final double height;
  final double minWidth;
  final String? semanticHint;
  final Color? color;
  final Color textColor;

  @override
  State<AppActionButton> createState() => _AppActionButtonState();
}

class _AppActionButtonState extends State<AppActionButton> {
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (!_active) return;
    AppHaptics.select();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final double resolvedHeight = math.max(44.0, widget.height);
    final double resolvedMinWidth = math.max(44.0, widget.minWidth);
    final Color foreground = widget.primary ? AppColors.white : widget.textColor;

    return Semantics(
      button: true,
      enabled: _active,
      label: widget.label,
      hint: widget.semanticHint,
      child: MouseRegion(
        cursor: _active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _active ? (_) => _setPressed(true) : null,
          onTapCancel: _active ? () => _setPressed(false) : null,
          onTapUp: _active
              ? (_) {
                  _setPressed(false);
                  _handleTap();
                }
              : null,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 110),
            scale: _pressed ? 0.975 : 1.0,
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _active || widget.isLoading ? 1.0 : 0.45,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: resolvedHeight,
                  minWidth: resolvedMinWidth,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: widget.primary ? AppColors.blueButtonGradient : null,
                    color: widget.primary
                        ? null
                        : (widget.color ?? AppColors.white.withValues(alpha: 0.075)),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.primary
                          ? AppColors.blueSoft.withValues(alpha: 0.22)
                          : AppColors.white.withValues(alpha: 0.10),
                    ),
                    boxShadow: widget.primary
                        ? <BoxShadow>[
                            BoxShadow(
                              color: AppColors.blue.withValues(alpha: 0.26),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      height: resolvedHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (widget.isLoading) ...<Widget>[
                            CupertinoActivityIndicator(color: foreground),
                            const SizedBox(width: 9),
                          ] else if (widget.icon != null) ...<Widget>[
                            Icon(widget.icon, color: foreground, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              widget.isLoading ? 'Loading…' : widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
