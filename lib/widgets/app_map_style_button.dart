import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppMapStyleButton extends StatelessWidget {
  const AppMapStyleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
    this.accent = const Color(0xFFFFD54F),
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: compact ? 40 : 44,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: const Color(0xFF070B13).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          border: Border.all(color: accent.withValues(alpha: 0.20)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: accent, size: compact ? 16 : 17),
            if (!compact) ...<Widget>[
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
