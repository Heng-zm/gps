import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LIQUID GLASS APP SHELL — Optimized Premium Gold Edition
// ═══════════════════════════════════════════════════════════════════════════════

// ── Design tokens ─────────────────────────────────────────────────────────────
const Color _kGoldCore = Color(0xFFEDD068);
const Color _kGoldMid = Color(0xFFD4A843);
const Color _kGoldDim = Color(0xFF7A5A16);

const double _kBarHeight = 72.0;
const double _kBarRadius = 36.0;
const double _kBarHorizontalMargin = 16.0;
const double _kBarBottomSpacing = 12.0;
const double _kMaxBarWidth = 500.0;

const double _kPillWidth = 84.0;
const double _kPillHeight = 46.0;

const int _kItemCount = 3;

const Duration _kNavDuration = Duration(milliseconds: 460);
const Duration _kFadeDuration = Duration(milliseconds: 260);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _previousIndex = 0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kNavDuration,
  )..value = 1.0;

  late final Animation<double> _pillAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );

  static const List<_NavDestinationData> _destinations = [
    _NavDestinationData(
      label: 'TRACK',
      icon: CupertinoIcons.speedometer,
    ),
    _NavDestinationData(
      label: 'HISTORY',
      icon: CupertinoIcons.clock_fill,
    ),
    _NavDestinationData(
      label: 'SETTINGS',
      icon: CupertinoIcons.settings_solid,
    ),
  ];

  static const List<Widget> _pages = [
    _PlaceholderPage(
      label: 'TRACK',
      icon: CupertinoIcons.speedometer,
    ),
    _PlaceholderPage(
      label: 'HISTORY',
      icon: CupertinoIcons.clock_fill,
    ),
    _PlaceholderPage(
      label: 'SETTINGS',
      icon: CupertinoIcons.settings_solid,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    if (index == _currentIndex) {
      HapticFeedback.lightImpact();
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = index;
    });

    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double bottomInset = mediaQuery.padding.bottom;

    final double reservedBottomSpace =
        _kBarHeight + bottomInset + _kBarBottomSpacing + 16.0;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: List<Widget>.generate(_pages.length, (index) {
                return _TabPageWrapper(
                  active: index == _currentIndex,
                  bottomPadding: reservedBottomSpace,
                  child: _pages[index],
                );
              }),
            ),
          ),
          Positioned(
            left: _kBarHorizontalMargin,
            right: _kBarHorizontalMargin,
            bottom: bottomInset + _kBarBottomSpacing,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxBarWidth),
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pillAnimation,
                    builder: (context, child) {
                      return _LiquidGlassBar(
                        currentIndex: _currentIndex,
                        previousIndex: _previousIndex,
                        animationValue: _pillAnimation.value,
                        destinations: _destinations,
                        onTap: _handleTap,
                      );
                    },
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

// ═══════════════════════════════════════════════════════════════════════════════
// PAGE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

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
      enabled: active,
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1.0 : 0.0,
          duration: _kFadeDuration,
          curve: Curves.easeOut,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAV DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _NavDestinationData {
  final String label;
  final IconData icon;

  const _NavDestinationData({
    required this.label,
    required this.icon,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIQUID GLASS BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _LiquidGlassBar extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double animationValue;
  final List<_NavDestinationData> destinations;
  final ValueChanged<int> onTap;

  const _LiquidGlassBar({
    required this.currentIndex,
    required this.previousIndex,
    required this.animationValue,
    required this.destinations,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kBarHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _MetaballPainter(
                currentIndex: currentIndex,
                previousIndex: previousIndex,
                value: animationValue,
              ),
            ),
          ),
          const Positioned.fill(
            child: _GlassBody(),
          ),
          Positioned.fill(
            child: _SlidingPill(
              currentIndex: currentIndex,
              previousIndex: previousIndex,
              value: animationValue,
            ),
          ),
          Positioned.fill(
            child: Row(
              children: List<Widget>.generate(destinations.length, (index) {
                final _NavDestinationData item = destinations[index];

                return Expanded(
                  child: _NavItem(
                    icon: item.icon,
                    label: item.label,
                    active: currentIndex == index,
                    onTap: () => onTap(index),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLASS BODY
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassBody extends StatelessWidget {
  const _GlassBody();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kBarRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 26,
          sigmaY: 26,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kBarRadius),
            color: Colors.white.withValues(alpha: 0.055),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: _kGoldDim.withValues(alpha: 0.10),
                blurRadius: 30,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 18,
                right: 18,
                top: 1,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 2,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: Colors.black.withValues(alpha: 0.16),
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

// ═══════════════════════════════════════════════════════════════════════════════
// SLIDING PILL
// ═══════════════════════════════════════════════════════════════════════════════

class _SlidingPill extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double value;

  const _SlidingPill({
    required this.currentIndex,
    required this.previousIndex,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = constraints.maxWidth / _kItemCount;

        double pillLeftForIndex(int index) {
          return itemWidth * index + (itemWidth - _kPillWidth) / 2;
        }

        final double left = lerpDouble(
          pillLeftForIndex(previousIndex),
          pillLeftForIndex(currentIndex),
          value,
        )!;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: (_kBarHeight - _kPillHeight) / 2,
              width: _kPillWidth,
              height: _kPillHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_kPillHeight / 2),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _kGoldCore.withValues(alpha: 0.24),
                      _kGoldMid.withValues(alpha: 0.13),
                      Colors.white.withValues(alpha: 0.055),
                    ],
                  ),
                  border: Border.all(
                    color: _kGoldCore.withValues(alpha: 0.34),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kGoldMid.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAV ITEM
// ═══════════════════════════════════════════════════════════════════════════════

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        active ? _kGoldCore : Colors.white.withValues(alpha: 0.36);

    final Color labelColor =
        active ? Colors.white : Colors.white.withValues(alpha: 0.36);

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: active ? 1.0 : 0.94,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(2),
                child: Icon(
                  icon,
                  size: active ? 23 : 21,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.85,
                  height: 1,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: active ? 14 : 0,
                height: 2.5,
                decoration: BoxDecoration(
                  color: _kGoldMid,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _kGoldMid.withValues(alpha: 0.55),
                            blurRadius: 8,
                            spreadRadius: 0.5,
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

// ═══════════════════════════════════════════════════════════════════════════════
// METABALL GLOW PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _MetaballPainter extends CustomPainter {
  final int currentIndex;
  final int previousIndex;
  final double value;

  const _MetaballPainter({
    required this.currentIndex,
    required this.previousIndex,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double itemWidth = size.width / _kItemCount;
    final double centerY = size.height / 2;

    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (int i = 0; i < _kItemCount; i++) {
      final double centerX = itemWidth * i + itemWidth / 2;

      final bool isCurrent = i == currentIndex;
      final bool isPrevious = i == previousIndex;

      final double radius = isCurrent
          ? lerpDouble(14, 30, value)!
          : isPrevious
              ? lerpDouble(30, 14, value)!
              : 12;

      final double alpha = isCurrent
          ? lerpDouble(0.16, 0.36, value)!
          : isPrevious
              ? lerpDouble(0.36, 0.16, value)!
              : 0.12;

      paint
        ..color = _kGoldMid.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          radius * 0.72,
        );

      canvas.drawCircle(
        Offset(centerX, centerY),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetaballPainter oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.previousIndex != previousIndex ||
        oldDelegate.value != value;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLACEHOLDER PAGES
// Replace these with your real screens.
// ═══════════════════════════════════════════════════════════════════════════════

class _PlaceholderPage extends StatelessWidget {
  final String label;
  final IconData icon;

  const _PlaceholderPage({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black,
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [
            Color(0xFF15120A),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 66,
                color: _kGoldMid.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 16),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.24),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
