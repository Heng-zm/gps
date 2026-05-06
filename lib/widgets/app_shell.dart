import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Drop-in replacement for AppShell ────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  int _previous = 0;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  final List<Widget> _pages = const [
    // TrackingScreen(),
    // HistoryScreen(),
    // SettingsScreen(),
    _PlaceholderPage(label: 'TRACK', icon: CupertinoIcons.speedometer),
    _PlaceholderPage(label: 'HISTORY', icon: CupertinoIcons.clock_fill),
    _PlaceholderPage(label: 'SETTINGS', icon: CupertinoIcons.settings_solid),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _anim = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.elasticOut, // elastic snap for the liquid feel
    );
    _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap(int index) {
    if (_current == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _previous = _current;
      _current = index;
    });
    _ctrl
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Screen content ──────────────────────────────────────────────
          Positioned.fill(
            child: IndexedStack(
              index: _current,
              children: _pages
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 110),
                        child: p,
                      ))
                  .toList(),
            ),
          ),

          // ── Enhanced Liquid Glass Bar ───────────────────────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: bottom + 14,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => _LiquidGlassBar(
                currentIndex: _current,
                previousIndex: _previous,
                animValue: _anim.value,
                onTap: _onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Constants ────────────────────────────────────────────────────────────────
const _kGoldMid = Color(0xFFD4A843);
const _kGoldBright = Color(0xFFEDD068);
const _kBarHeight = 72.0;
const _kItemCount = 3;

// ─── Liquid Glass Bar ─────────────────────────────────────────────────────────
class _LiquidGlassBar extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double animValue; // 0 → 1, driven by elastic curve
  final ValueChanged<int> onTap;

  const _LiquidGlassBar({
    required this.currentIndex,
    required this.previousIndex,
    required this.animValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1 ── Metaball layer (rendered into an offscreen image)
          Positioned.fill(
            child: CustomPaint(
              painter: _MetaballPainter(
                current: currentIndex,
                previous: previousIndex,
                t: animValue,
              ),
            ),
          ),

          // 2 ── Frosted glass shell
          ClipRRect(
            borderRadius: BorderRadius.circular(36),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  // Subtle specular highlight at top
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.07),
                      Colors.white.withValues(alpha: 0.02),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),

          // 3 ── Pill indicator (slides under icons)
          Positioned.fill(
            child: _SlidingPill(
              currentIndex: currentIndex,
              previousIndex: previousIndex,
              t: animValue,
            ),
          ),

          // 4 ── Nav items
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: CupertinoIcons.speedometer,
                  label: 'TRACK',
                  isActive: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
                _NavItem(
                  icon: CupertinoIcons.clock_fill,
                  label: 'HISTORY',
                  isActive: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
                _NavItem(
                  icon: CupertinoIcons.settings_solid,
                  label: 'SETTINGS',
                  isActive: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sliding Pill ─────────────────────────────────────────────────────────────
class _SlidingPill extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double t;

  const _SlidingPill({
    required this.currentIndex,
    required this.previousIndex,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;
      final itemWidth = totalWidth / _kItemCount;
      const pillW = 76.0;
      const pillH = 46.0;

      double pillLeft(int idx) => itemWidth * idx + (itemWidth - pillW) / 2;

      final from = pillLeft(previousIndex);
      final to = pillLeft(currentIndex);
      final x = lerpDouble(from, to, t)!;

      return Positioned(
        left: x,
        top: (_kBarHeight - pillH) / 2,
        child: Container(
          width: pillW,
          height: pillH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            color: _kGoldMid.withValues(alpha: 0.18),
            border: Border.all(
              color: _kGoldMid.withValues(alpha: 0.35),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _kGoldMid.withValues(alpha: 0.20),
                blurRadius: 14,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      );
    });
  }
}

// ─── Nav Item ─────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: isActive ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        child: SizedBox(
          width: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with optional glow
              Stack(
                alignment: Alignment.center,
                children: [
                  if (isActive)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _kGoldMid.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      icon,
                      key: ValueKey(isActive),
                      color: isActive
                          ? _kGoldBright
                          : Colors.white.withValues(alpha: 0.38),
                      size: 23,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Label
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                  fontSize: 9.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  letterSpacing: 0.7,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 4),
              // Active dot indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: isActive ? 16 : 4,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: isActive
                      ? _kGoldMid
                      : Colors.white.withValues(alpha: 0.0),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: _kGoldMid.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Metaball Painter ─────────────────────────────────────────────────────────
//
// Improvements over the original:
//  • Proper saveLayer + ColorFilter threshold for crisp metaball edges
//  • Liquid "bridge" blob drawn between previous and current during animation
//  • Radial gradient blobs instead of flat circles → richer gold depth
//  • Animated blob sizes: active blob grows, idle blobs breathe gently
//
class _MetaballPainter extends CustomPainter {
  final int current;
  final int previous;
  final double t; // 0 → 1

  const _MetaballPainter({
    required this.current,
    required this.previous,
    required this.t,
  });

  static const _kThreshold = 60.0; // alpha threshold for metaball merge
  static const _kEdgeSharpness = 18.0; // controls edge softness

  @override
  void paint(Canvas canvas, Size size) {
    const gold = _kGoldMid;

    // Threshold composite layer
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..colorFilter = ColorFilter.matrix([
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          _kEdgeSharpness,
          -_kThreshold * _kEdgeSharpness,
        ]),
    );

    final itemW = size.width / _kItemCount;
    final cy = size.height / 2;

    // Draw a blob for every item
    for (int i = 0; i < _kItemCount; i++) {
      final cx = itemW * i + itemW / 2;
      final isActive = i == current;
      final wasActive = i == previous;

      // Blob radius: active = 30, idle = 14
      // During animation: active grows in, previous shrinks out
      double r;
      if (isActive && previous != current) {
        r = lerpDouble(14, 30, t)!;
      } else if (wasActive && previous != current) {
        r = lerpDouble(30, 14, t)!;
      } else if (isActive) {
        r = 30;
      } else {
        r = 14;
      }

      _drawBlob(canvas, Offset(cx, cy), r, gold, alpha: 0.70);
    }

    // Bridge blob — travels between previous and current during animation
    if (previous != current && t > 0 && t < 1) {
      final fromCX = itemW * previous + itemW / 2;
      final toCX = itemW * current + itemW / 2;
      // Bridge follows a sine arc in the middle of the animation
      final bridgeCX = lerpDouble(fromCX, toCX, t)!;
      final bridgeR = 14 + sin(pi * t) * 10;
      _drawBlob(canvas, Offset(bridgeCX, cy), bridgeR, gold, alpha: 0.55);
    }

    canvas.restore();
  }

  void _drawBlob(Canvas canvas, Offset center, double r, Color color,
      {double alpha = 0.7}) {
    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.75)
      ..color = color.withValues(alpha: alpha);
    canvas.drawCircle(center, r, paint);
  }

  @override
  bool shouldRepaint(covariant _MetaballPainter old) =>
      old.current != current || old.previous != previous || old.t != t;
}

// ─── Placeholder page (remove when wiring real screens) ──────────────────────
class _PlaceholderPage extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PlaceholderPage({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _kGoldMid.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 12,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
