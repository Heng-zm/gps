import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppMapStyleButton extends StatelessWidget {
  const AppMapStyleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
    this.accent = const Color(0xFF3B82F6),
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final double height = compact ? 42.0 : 46.0;
    final double radius = compact ? 15.0 : 17.0;
    final String semanticLabel = label.trim().isEmpty ? 'Map style' : label;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: height,
        onPressed: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: height,
                constraints: BoxConstraints(
                  minWidth: compact ? height : 96.0,
                  maxWidth: compact ? height : 190.0,
                ),
                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B13).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: accent.withValues(alpha: 0.24)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: compact
                      ? Icon(icon, color: accent, size: 17)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(icon, color: accent, size: 17),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                semanticLabel.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
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
    );
  }
}
