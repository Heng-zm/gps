import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/settings_service.dart';
import 'screens/tracking_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DESIGN TOKENS — Liquid Glass  (OLED Dark Mode)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Visual language:
//  • Bar   — thick frosted-glass slab floating above content.
//            extendBody:true → page pixels fill behind it → BackdropFilter
//            blurs real content, not a black void.
//  • Pill  — concave water-drop lens: dark interior, bright raised rim,
//            top-left inner shadow, bottom-right catch-light.
//  • Blobs — dual-layer metaballs: wide ambient outer halo + tight specular
//            inner core. Threshold matrix fuses overlapping blobs.
//  • Shimmer — diagonal refraction stripe that leads the pill on transition.
//
// BackdropFilter fix:
//  The compositor REQUIRES a non-zero paint child to engage the blur.
//  A fully-transparent SizedBox skips the blur → black bar.
//  Solution: ColoredBox with alpha=0x10 (≈6% warm amber — invisible but valid).

// ── Gold palette ──────────────────────────────────────────────────────────────
const _kGoldCore = Color(0xFFEDD068); // bright specular / catch-light
const _kGoldMid = Color(0xFFD4A843); // primary glow / pill border
const _kGoldDim = Color(0xFF6B5016); // inactive indicator (never transparent)

// ── Glass surface palette ─────────────────────────────────────────────────────
const _kGlassBorder = Color(0x33FFFFFF); // outer rim
const _kGlassInner = Color(0x1AFFFFFF); // inner bevel
const _kGlassBodyTint = Color(0x10C89B3C); // α=16 warm amber — blur compositor

// ── Pill palette ──────────────────────────────────────────────────────────────
const _kPillFill = Color(0x2AD4A843); // concave depression fill
const _kPillRim = Color(0x80D4A843); // raised lip border
const _kPillShadow = Color(0x44000000); // top-left inner shadow
const _kPillShine = Color(0x55EDD068); // bottom-right exit-surface reflection

// ── Bar geometry ──────────────────────────────────────────────────────────────
const _kBarHeight = 72.0;
const _kBarRadius = 36.0;
const _kItemCount = 3;
const _kPillW = 82.0;
const _kPillH = 46.0;
const _kPillRadius = 23.0;

// Bottom offset: snug above gesture indicator / extra breathing room without one.
const _kBarOffsetWithNav = 12.0;
const _kBarOffsetWithoutNav = 22.0;
const _kBarSideMargin = 16.0; // horizontal margin each side

// Backdrop blur — heavier = more glass mass.
const _kBarBlurX = 32.0;
const _kBarBlurY = 32.0;

// Metaball threshold matrix.
// alpha_out = alpha_in × sharpness  −  (bias × sharpness)
const double _kSharpness = 26.0;
const double _kBias = 80.0;

// Dual-layer blob radii.
const double _kBlobRestOuter = 15.0;
const double _kBlobActiveOuter = 34.0;
const double _kBlobRestInner = 6.0;
const double _kBlobActiveInner = 18.0;

// Min blur sigma — prevents GPU artifacts on tiny radii.
const double _kMinBlurSigma = 1.0;

// ═══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SettingsService.instance.load();
  } catch (e) {
    debugPrint('Settings load error: $e');
  }

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const TrackProAI());
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP ROOT
// ═══════════════════════════════════════════════════════════════════════════════
class TrackProAI extends StatelessWidget {
  const TrackProAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackPro AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        cupertinoOverrideTheme: const CupertinoThemeData(
          primaryColor: _kGoldMid,
          brightness: Brightness.dark,
        ),
      ),
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      home: const AppShell(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP SHELL
// ═══════════════════════════════════════════════════════════════════════════════
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  int _previous = 0;
  // Captures the pill's visual position the moment a tap interrupts an ongoing
  // animation — prevents mid-flight hard jumps.
  double _pillStartFraction = 0.0;

  // ── Animation controller (linear — curves applied per CurvedAnimation) ──────
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..value = 1.0;

  // Pill: smooth cubic, never overshoots (lerpDouble is safe).
  late final Animation<double> _pillAnim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOutCubic,
  );

  // Blob: easeOutBack gives a satisfying settle without the extreme elasticOut
  // lag on low-end devices. Still overshoots mildly (~1.07× target).
  late final Animation<double> _blobAnim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutBack,
  );

  // Shimmer: fast leading flash — peaks then dies before pill lands.
  late final Animation<double> _shimmerAnim = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.50, curve: Curves.easeIn),
  );

  static const _icons = [
    CupertinoIcons.speedometer,
    CupertinoIcons.clock_fill,
    CupertinoIcons.settings_solid,
  ];
  static const _labels = ['TRACK', 'HISTORY', 'SETTINGS'];

  // late final — screens with future runtime args can be wired here without
  // restructuring the shell.
  late final List<Widget> _pages = const [
    TrackingScreen(),
    HistoryScreen(),
    SettingsScreen(),
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
      // Snapshot visual position BEFORE index swap.
      _pillStartFraction = _pillAnim.value.clamp(0.0, 1.0);
      _previous = _current;
      _current = index;
    });
    _ctrl
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;
    final barOffset =
        bottomPad > 0 ? _kBarOffsetWithNav : _kBarOffsetWithoutNav;

    // Page content scrolls to just above the bar underside.
    // This exact value is passed into each page's MediaQuery so SafeArea and
    // ListView.padding still "just work" inside each screen.
    final pagePaddingBottom = bottomPad + _kBarHeight + barOffset + 8;

    return Scaffold(
      backgroundColor: Colors.black,
      // CRITICAL: extendBody renders pages behind the bar so BackdropFilter
      // blurs real content pixels — not the scaffold's black background.
      extendBody: true,
      body: Stack(
        children: [
          // ── Pages ──────────────────────────────────────────────────────
          Positioned.fill(
            child: IndexedStack(
              index: _current,
              children: _pages
                  .asMap()
                  .entries
                  .map((e) => _TabPageWrapper(
                        active: e.key == _current,
                        pagePaddingBottom: pagePaddingBottom,
                        child: e.value,
                      ))
                  .toList(),
            ),
          ),

          // ── Floating nav bar ────────────────────────────────────────────
          // Center + ConstrainedBox makes layout correct on iPads / wide screens.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad + barOffset,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _kBarSideMargin),
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => _LiquidGlassBar(
                        currentIndex: _current,
                        previousIndex: _previous,
                        pillT: _pillAnim.value.clamp(0.0, 1.0),
                        pillStartFraction: _pillStartFraction,
                        // easeOutBack can slightly exceed 1.0 — clamp to safe range.
                        blobT: _blobAnim.value.clamp(0.0, 1.10),
                        shimmerT: _shimmerAnim.value.clamp(0.0, 1.0),
                        icons: _icons,
                        labels: _labels,
                        onTap: _onTap,
                      ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// TAB PAGE WRAPPER
//
// Three jobs:
//  1. TickerMode(enabled: active) — suspends inactive screens' AnimationCon-
//     trollers / sensors so they don't burn CPU/battery between tab visits.
//  2. AnimatedOpacity — cross-fades pages on switch (300 ms easeOut).
//  3. MediaQuery override — injects the correct bottom padding so SafeArea,
//     ListView, and SingleChildScrollView all respect the floating bar height
//     without the shell needing to know each screen's internal layout.
// ═══════════════════════════════════════════════════════════════════════════════
class _TabPageWrapper extends StatefulWidget {
  final bool active;
  final double pagePaddingBottom;
  final Widget child;

  const _TabPageWrapper({
    required this.active,
    required this.pagePaddingBottom,
    required this.child,
  });

  @override
  State<_TabPageWrapper> createState() => _TabPageWrapperState();
}

class _TabPageWrapperState extends State<_TabPageWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // preserve scroll / state across switches

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mq = MediaQuery.of(context);

    return TickerMode(
      enabled: widget.active,
      child: AnimatedOpacity(
        opacity: widget.active ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        // Replace bottom padding in the subtree's MediaQuery so screens don't
        // need to know about the bar at all — they just use SafeArea normally.
        child: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: widget.pagePaddingBottom),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIQUID GLASS BAR
//
// Layer order (back → front):
//   1. Ambient metaball glow   — CustomPaint, unclipped, soft dual-layer halos
//   2. Frosted glass body      — ClipRRect + BackdropFilter + warm tint child
//   3. Glass surface details   — CustomPaint: body grad, dual rim, top specular,
//                                bottom sheen  (static, shouldRepaint=false)
//   4. Sliding pill            — concave water-drop lens (CustomPaint)
//   5. Refraction shimmer      — diagonal stripe that leads the pill
//   6. Nav items               — icons + labels + animated indicator
// ═══════════════════════════════════════════════════════════════════════════════
class _LiquidGlassBar extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double pillT; // [0,1] easeInOutCubic
  final double pillStartFraction; // visual position captured at interrupt
  final double blobT; // [0,~1.1] easeOutBack
  final double shimmerT; // [0,1] fast Interval
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  const _LiquidGlassBar({
    required this.currentIndex,
    required this.previousIndex,
    required this.pillT,
    required this.pillStartFraction,
    required this.blobT,
    required this.shimmerT,
    required this.icons,
    required this.labels,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kBarHeight,
      child: Stack(
        clipBehavior: Clip.none, // outer glow bleeds past bar bounds
        children: [
          // 1 ── Ambient metaball glow ────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              isComplex: true,
              painter: _MetaballPainter(
                current: currentIndex,
                previous: previousIndex,
                t: blobT,
              ),
            ),
          ),

          // 2 ── Frosted glass body ───────────────────────────────────────
          // ClipRRect shapes the blur; ColoredBox child with α=0x10 is the
          // minimum non-zero paint that activates the BackdropFilter compositor.
          // Without it Flutter skips the blur entirely → opaque dark bar.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kBarRadius),
              child: BackdropFilter(
                filter:
                    ImageFilter.blur(sigmaX: _kBarBlurX, sigmaY: _kBarBlurY),
                child: const ColoredBox(
                  color: _kGlassBodyTint,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),

          // 3 ── Glass surface details ────────────────────────────────────
          const Positioned.fill(
            child: CustomPaint(painter: _GlassSurfacePainter()),
          ),

          // 4 ── Sliding pill ─────────────────────────────────────────────
          Positioned.fill(
            child: _SlidingPill(
              currentIndex: currentIndex,
              previousIndex: previousIndex,
              t: pillT,
              startFraction: pillStartFraction,
            ),
          ),

          // 5 ── Refraction shimmer ───────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _ShimmerPainter(
                currentIndex: currentIndex,
                previousIndex: previousIndex,
                shimmerT: shimmerT,
                pillT: pillT,
                startFraction: pillStartFraction,
              ),
            ),
          ),

          // 6 ── Nav items ────────────────────────────────────────────────
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                _kItemCount,
                (i) => _NavItem(
                  icon: icons[i],
                  label: labels[i],
                  isActive: currentIndex == i,
                  onTap: () => onTap(i),
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
// GLASS SURFACE PAINTER  (static — shouldRepaint = false)
//
// Five visual passes over the rounded-rect slab:
//  1. Body gradient      — near-invisible warm tint (heavier top, fades bottom)
//  2. Outer rim stroke   — 0.75px, the physical glass edge
//  3. Inner bevel stroke — 0.5px at 1px inset, simulates the ground bevel
//  4. Top specular       — 2px bright, top-3px clip only
//  5. Bottom sheen       — 1.5px soft, bottom-4px clip only
//
// Two rim strokes are the secret to depth. A single border reads flat;
// two concentric lines read as a bevelled glass edge with volume.
// ═══════════════════════════════════════════════════════════════════════════════
class _GlassSurfacePainter extends CustomPainter {
  const _GlassSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr =
        RRect.fromRectAndRadius(rect, const Radius.circular(_kBarRadius));

    // 1. Body gradient — near-invisible warm tint.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x12FFFFFF), Color(0x02FFFFFF)],
        ).createShader(rect),
    );

    // 2. Outer rim.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = _kGlassBorder,
    );

    // 3. Inner bevel — 1px inset.
    final rrI = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(_kBarRadius - 1),
    );
    canvas.drawRRect(
      rrI,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = _kGlassInner,
    );

    // 4. Top specular — bright line, top 3px only.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, 3));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = const Color(0x47FFFFFF),
    );
    canvas.restore();

    // 5. Bottom sheen — secondary reflection, bottom 4px only.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, size.height - 4, size.width, 4));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x0FFFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassSurfacePainter _) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLIDING PILL
//
// Mid-flight-aware position:
//   effectiveFrom = lerp(fromX, toX, startFraction)
//   x             = lerp(effectiveFrom, toX, t)
//
// When startFraction=0 this collapses to the normal lerp(fromX, toX, t).
// When startFraction=0.6 (tap during animation) the pill continues from its
// current visual position rather than snapping back to fromX. No hard jump.
// ═══════════════════════════════════════════════════════════════════════════════
class _SlidingPill extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double t;
  final double startFraction;

  const _SlidingPill({
    required this.currentIndex,
    required this.previousIndex,
    required this.t,
    required this.startFraction,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final itemW = c.maxWidth / _kItemCount;
      double left(int i) => itemW * i + (itemW - _kPillW) / 2;

      final fromX = left(previousIndex);
      final toX = left(currentIndex);
      final x = lerpDouble(lerpDouble(fromX, toX, startFraction)!, toX, t)!;

      return Stack(children: [
        Positioned(
          left: x,
          top: (_kBarHeight - _kPillH) / 2,
          child: const SizedBox(
            width: _kPillW,
            height: _kPillH,
            child: CustomPaint(painter: _PillPainter()),
          ),
        ),
      ]);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PILL PAINTER — Concave Water-Drop Lens  (static — shouldRepaint = false)
//
// Anatomy (single CustomPaint pass, no nested Containers, no BoxShadow):
//  1. Base fill        — dark gold tint, the concave depression.
//  2. Inner shadow     — radial gradient from top-left; rim shadowing cavity.
//  3. Outer rim        — 1.5px bright gold, the raised lip.
//  4. Top specular     — 2px gold sliver clipped to top 2.5px arc.
//  5. Catch-light      — blurred ellipse at bottom-right, exit-surface reflex.
// ═══════════════════════════════════════════════════════════════════════════════
class _PillPainter extends CustomPainter {
  const _PillPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rr =
        RRect.fromRectAndRadius(rect, const Radius.circular(_kPillRadius));

    // 1. Base fill.
    canvas.drawRRect(rr, Paint()..color = _kPillFill);

    // 2. Inner shadow (top-left radial).
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.65, -0.65),
          radius: 1.0,
          colors: [_kPillShadow, Colors.transparent],
        ).createShader(rect),
    );

    // 3. Outer rim — raised lip.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _kPillRim,
    );

    // 4. Top specular — gold sliver on the rim arc.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, 2.5));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = _kGoldCore.withValues(alpha: 0.65),
    );
    canvas.restore();

    // 5. Catch-light — exit-surface reflection, bottom-right.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.68, h * 0.72),
        width: w * 0.40,
        height: h * 0.26,
      ),
      Paint()
        ..color = _kPillShine
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );
  }

  @override
  bool shouldRepaint(covariant _PillPainter _) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHIMMER PAINTER — Refraction Highlight Stripe
//
// A ~24° rotated ellipse pair sweeps through the pill on each transition,
// simulating light bending as it exits the curved glass exit surface.
//
// Timing: Interval(0, 0.50) → the flash leads and dissolves BEFORE the pill
// lands. Triangular opacity (peaks at shimmerT=0.5) → clean fade in/out,
// no abrupt pop at either boundary.
// ═══════════════════════════════════════════════════════════════════════════════
class _ShimmerPainter extends CustomPainter {
  final int currentIndex;
  final int previousIndex;
  final double shimmerT; // [0,1]
  final double pillT; // pill position for x-alignment
  final double startFraction;

  const _ShimmerPainter({
    required this.currentIndex,
    required this.previousIndex,
    required this.shimmerT,
    required this.pillT,
    required this.startFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (previousIndex == currentIndex) return;

    final itemW = size.width / _kItemCount;
    double left(int i) => itemW * i + (itemW - _kPillW) / 2;

    final fromX = left(previousIndex);
    final toX = left(currentIndex);
    final pillX =
        lerpDouble(lerpDouble(fromX, toX, startFraction)!, toX, pillT)!;

    // Shimmer at the leading edge of the pill.
    final goRight = currentIndex > previousIndex;
    final shimmerX = goRight ? pillX + _kPillW * 0.74 : pillX + _kPillW * 0.26;
    final shimmerY = _kBarHeight / 2;

    // Triangular envelope — peaks mid-transition.
    final opacity = (shimmerT < 0.5 ? shimmerT * 2.0 : (1.0 - shimmerT) * 2.0)
        .clamp(0.0, 1.0);
    if (opacity < 0.01) return;

    canvas.save();
    canvas.translate(shimmerX, shimmerY);
    canvas.rotate(-0.42); // 24° — classic glass-flare angle
    canvas.translate(-shimmerX, -shimmerY);

    // Wide soft outer glow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(shimmerX, shimmerY),
        width: 7.0,
        height: _kBarHeight * 1.5,
      ),
      Paint()
        ..color = _kGoldCore.withValues(alpha: opacity * 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    // Tight bright core.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(shimmerX, shimmerY),
        width: 2.0,
        height: _kBarHeight * 1.2,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter old) =>
      old.shimmerT != shimmerT ||
      old.pillT != pillT ||
      old.currentIndex != currentIndex ||
      old.previousIndex != previousIndex;
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAV ITEM
// ═══════════════════════════════════════════════════════════════════════════════
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
      child: SizedBox(
        width: 90,
        height: _kBarHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon — gold gradient when active, dim when not.
            AnimatedScale(
              scale: isActive ? 1.10 : 1.0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              child: ShaderMask(
                blendMode: isActive ? BlendMode.srcIn : BlendMode.dst,
                shaderCallback: (b) => isActive
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_kGoldCore, _kGoldMid],
                      ).createShader(b)
                    : const LinearGradient(
                        colors: [Colors.white, Colors.white],
                      ).createShader(b),
                child: AnimatedOpacity(
                  opacity: isActive ? 1.0 : 0.30,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(icon, size: 22),
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Label.
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.28),
                fontSize: 9.0,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: 1.0,
                height: 1.0,
              ),
              child: Text(label),
            ),

            const SizedBox(height: 5),

            // Animated underline — expands to label width, never transparent.
            _ActiveIndicator(label: label, isActive: isActive),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTIVE INDICATOR
//
// Width measured via TextPainter at runtime so the gold underline is
// precisely anchored under the word, not a generic fixed size.
//
// Inactive colour = _kGoldDim at alpha=0 (never Colors.transparent, which
// causes a GPU black flash on certain Android drivers during the colour lerp).
// ═══════════════════════════════════════════════════════════════════════════════
class _ActiveIndicator extends StatelessWidget {
  final String label;
  final bool isActive;
  const _ActiveIndicator({required this.label, required this.isActive});

  double _textWidth() {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final w = _textWidth().clamp(10.0, 54.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: isActive ? w : 4.0,
      height: 2.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1.5),
        gradient: isActive
            ? const LinearGradient(colors: [_kGoldCore, _kGoldMid])
            : null,
        // Never use Colors.transparent — GPU flash on Android.
        color: isActive ? null : _kGoldDim.withValues(alpha: 0.0),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// METABALL PAINTER — Dual-Layer Liquid Glow
//
// Two saveLayer passes share the same alpha-threshold matrix, but use
// different blob radii and sigma factors:
//
//   Outer pass  r=15→34, σ×0.88 → wide soft ambient halo (warm gold cloud)
//   Inner pass  r=6→18,  σ×0.50 → tight specular core (glassy bead)
//
// Together they read as a glass bead catching light, not a flat coloured dot.
//
// Bridge blob:
//   Travels between previous→current on BOTH passes.
//   Radius peaks mid-transit via sin(π·t).
//   Opacity also follows sin(π·t) → smooth crossfade, zero pop at endpoints.
//   Position uses t.clamp(0,1) — no spatial overshoot past destination.
// ═══════════════════════════════════════════════════════════════════════════════
class _MetaballPainter extends CustomPainter {
  final int current;
  final int previous;
  final double t; // [0, ~1.1] easeOutBack

  const _MetaballPainter({
    required this.current,
    required this.previous,
    required this.t,
  });

  // Threshold composite:
  // alpha_out = alpha_in × _kSharpness  −  (_kBias × _kSharpness)
  static Paint _threshold() => Paint()
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
      _kSharpness,
      -_kBias * _kSharpness,
    ]);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final itemW = size.width / _kItemCount;
    final cy = size.height / 2;
    final tPos = t.clamp(0.0, 1.0); // position clamp — no spatial overshoot

    // ── Outer pass: ambient halo ────────────────────────────────────────
    canvas.saveLayer(rect, _threshold());
    for (int i = 0; i < _kItemCount; i++) {
      _blob(canvas, Offset(itemW * i + itemW / 2, cy), _outerR(i, tPos),
          alpha: 0.50, sf: 0.88);
    }
    _bridge(canvas, itemW, cy, tPos,
        base: 13.0, peak: 14.0, alpha: 0.36, sf: 0.88);
    canvas.restore();

    // ── Inner pass: specular core ───────────────────────────────────────
    canvas.saveLayer(rect, _threshold());
    for (int i = 0; i < _kItemCount; i++) {
      _blob(canvas, Offset(itemW * i + itemW / 2, cy), _innerR(i, tPos),
          alpha: 0.80, sf: 0.50);
    }
    _bridge(canvas, itemW, cy, tPos,
        base: 6.0, peak: 8.0, alpha: 0.65, sf: 0.50);
    canvas.restore();
  }

  // ── Radius helpers ────────────────────────────────────────────────────
  double _outerR(int i, double tPos) {
    if (previous == current) {
      return i == current ? _kBlobActiveOuter : _kBlobRestOuter;
    }
    if (i == current) {
      // Allow mild overshoot on incoming blob (easeOutBack settles to 1.0).
      return lerpDouble(_kBlobRestOuter, _kBlobActiveOuter, t)!
          .clamp(_kBlobRestOuter, _kBlobActiveOuter * 1.10);
    }
    if (i == previous) {
      return lerpDouble(_kBlobActiveOuter, _kBlobRestOuter, tPos)!;
    }
    return _kBlobRestOuter;
  }

  double _innerR(int i, double tPos) {
    if (previous == current) {
      return i == current ? _kBlobActiveInner : _kBlobRestInner;
    }
    if (i == current) {
      return lerpDouble(_kBlobRestInner, _kBlobActiveInner, t)!
          .clamp(_kBlobRestInner, _kBlobActiveInner * 1.10);
    }
    if (i == previous) {
      return lerpDouble(_kBlobActiveInner, _kBlobRestInner, tPos)!;
    }
    return _kBlobRestInner;
  }

  // ── Bridge ────────────────────────────────────────────────────────────
  void _bridge(
    Canvas canvas,
    double itemW,
    double cy,
    double tPos, {
    required double base,
    required double peak,
    required double alpha,
    required double sf,
  }) {
    if (previous == current) return;
    final fromX = itemW * previous + itemW / 2;
    final toX = itemW * current + itemW / 2;
    final bx = lerpDouble(fromX, toX, tPos)!;
    final sinT = sin(pi * tPos);
    final br = (base + sinT * peak).clamp(0.0, base + peak);
    final ba = (alpha * sinT).clamp(0.0, alpha);
    if (br > 1 && ba > 0.01) {
      _blob(canvas, Offset(bx, cy), br, alpha: ba, sf: sf);
    }
  }

  // ── Blob primitive ────────────────────────────────────────────────────
  void _blob(Canvas canvas, Offset c, double r,
      {required double alpha, required double sf}) {
    if (r <= 0) return;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _kGoldMid.withValues(alpha: alpha)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, max(r * sf, _kMinBlurSigma)),
    );
  }

  @override
  bool shouldRepaint(covariant _MetaballPainter o) =>
      o.current != current || o.previous != previous || o.t != t;
}
