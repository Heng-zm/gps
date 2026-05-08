import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- Design Tokens ---
const _kGoldCore = Color(0xFFEDD068);
const _kGoldMid = Color(0xFFD4A843);
const _kBarHeight = 72.0;
const _kBarRadius = 36.0;
const _kItemCount = 3;

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  int _previous = 0;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..value = 1.0;

  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutBack,
  );

  final List<Widget> _pages = const [
    _PlaceholderPage(label: 'TRACK', icon: CupertinoIcons.speedometer),
    _PlaceholderPage(label: 'HISTORY', icon: CupertinoIcons.clock_fill),
    _PlaceholderPage(label: 'SETTINGS', icon: CupertinoIcons.settings_solid),
  ];

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
    _ctrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;
    const barMargin = 16.0;

    // Calculate precise padding so pages don't overlap the bar
    final totalBarHeight = _kBarHeight + bottomPad + barMargin;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody:
          true, // Crucial for BackdropFilter to see pixels behind the bar
      body: Stack(
        children: [
          // 1. Optimized Page Stack with Cross-fade and Ticker management
          Positioned.fill(
            child: IndexedStack(
              index: _current,
              children: _pages.asMap().entries.map((e) {
                return _TabPageWrapper(
                  active: e.key == _current,
                  bottomPadding: totalBarHeight,
                  child: e.value,
                );
              }).toList(),
            ),
          ),

          // 2. Liquid Glass Navigation Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 12,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: RepaintBoundary(
                  // Isolate bar repaints from page content
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Page Wrapper for Performance ---
class _TabPageWrapper extends StatelessWidget {
  final bool active;
  final double bottomPadding;
  final Widget child;

  const _TabPageWrapper({
    required this.active,
    required this.bottomPadding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: active, // Stops background animations/sensors on hidden tabs
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: child,
        ),
      ),
    );
  }
}

// --- Bar Component ---
class _LiquidGlassBar extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double animValue;
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
        children: [
          // A. Ambient Metaball Glow
          Positioned.fill(
            child: CustomPaint(
              painter: _MetaballPainter(
                current: currentIndex,
                previous: previousIndex,
                t: animValue,
              ),
            ),
          ),

          // B. Frosted Glass Body
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kBarRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(_kBarRadius),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.5),
                  ),
                ),
              ),
            ),
          ),

          // C. Sliding Pill Lens
          Positioned.fill(
            child: _SlidingPill(
              currentIndex: currentIndex,
              previousIndex: previousIndex,
              t: animValue,
            ),
          ),

          // D. Interaction layer
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                    icon: CupertinoIcons.speedometer,
                    label: 'TRACK',
                    active: currentIndex == 0,
                    onTap: () => onTap(0)),
                _NavItem(
                    icon: CupertinoIcons.clock_fill,
                    label: 'HISTORY',
                    active: currentIndex == 1,
                    onTap: () => onTap(1)),
                _NavItem(
                    icon: CupertinoIcons.settings_solid,
                    label: 'SETTINGS',
                    active: currentIndex == 2,
                    onTap: () => onTap(2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Sliding Pill logic ---
class _SlidingPill extends StatelessWidget {
  final int currentIndex, previousIndex;
  final double t;
  const _SlidingPill(
      {required this.currentIndex,
      required this.previousIndex,
      required this.t});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final itemW = c.maxWidth / _kItemCount;
      const pW = 82.0, pH = 46.0;
      double left(int i) => itemW * i + (itemW - pW) / 2;

      return Stack(children: [
        Positioned(
          left: lerpDouble(left(previousIndex), left(currentIndex), t)!,
          top: (_kBarHeight - pH) / 2,
          child: Container(
            width: pW,
            height: pH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              color: _kGoldMid.withValues(alpha: 0.15),
              border: Border.all(
                  color: _kGoldMid.withValues(alpha: 0.3), width: 0.5),
            ),
          ),
        )
      ]);
    });
  }
}

// --- Nav Item logic ---
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 22,
              color: active ? _kGoldCore : Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                color:
                    active ? Colors.white : Colors.white.withValues(alpha: 0.3),
                fontSize: 9,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: active ? 12 : 0,
            height: 2.5,
            decoration: BoxDecoration(
                color: _kGoldMid, borderRadius: BorderRadius.circular(1)),
          )
        ],
      ),
    );
  }
}

// --- Metaball Painter logic ---
class _MetaballPainter extends CustomPainter {
  final int current, previous;
  final double t;

  _MetaballPainter(
      {required this.current, required this.previous, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final itemW = size.width / _kItemCount;
    final cy = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _kItemCount; i++) {
      final cx = itemW * i + itemW / 2;
      double r = (i == current)
          ? lerpDouble(12, 28, t)!
          : (i == previous)
              ? lerpDouble(28, 12, t)!
              : 12;

      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.7);
      paint.color = _kGoldMid.withValues(alpha: 0.35);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MetaballPainter old) => old.t != t;
}

class _PlaceholderPage extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PlaceholderPage({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: _kGoldMid.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(label,
                style:
                    const TextStyle(color: Colors.white24, letterSpacing: 4)),
          ],
        ),
      ),
    );
  }
}
