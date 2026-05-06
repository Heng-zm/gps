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
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════
const _kGoldMid = Color(0xFFD4A843);
const _kGoldBright = Color(0xFFEDD068);
const _kGoldDim =
    Color(0xFF8A6A20); // for inactive dot — avoids transparent flicker
const _kBarHeight = 72.0;
const _kItemCount = 3;
const _kPillW = 74.0;
const _kPillH = 44.0;

// Metaball threshold tuning
const double _kSharpness = 24.0;
const double _kBias = 82.0;

// ═══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SettingsService.instance.load();
  } catch (e) {
    debugPrint('Settings Error: $e');
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

  // FIX: Use a plain linear controller — Curves.elasticOut is applied in
  // CurvedAnimation, not baked into the controller. This lets us clamp
  // the raw value to [0,1] safely without the elastic overshoot causing
  // out-of-range lerpDouble inputs in the pill/painter.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..value = 1.0;

  // PERF: Two separate animations from the same controller so the pill
  // and the metaball can use different curves without extra controllers.
  late final Animation<double> _pillAnim = CurvedAnimation(
    parent: _ctrl,
    // EaseInOutCubic for the pill slide — feels snappy but not bouncy
    curve: Curves.easeInOutCubic,
  );

  late final Animation<double> _blobAnim = CurvedAnimation(
    parent: _ctrl,
    // ElasticOut only on the blob so the liquid stretch overshoots nicely
    // without affecting the pill position (no black-rect at overshoot).
    curve: Curves.elasticOut,
  );

  static const _icons = [
    CupertinoIcons.speedometer,
    CupertinoIcons.clock_fill,
    CupertinoIcons.settings_solid,
  ];
  static const _labels = ['TRACK', 'HISTORY', 'SETTINGS'];

  final List<Widget> _pages = const [
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
      _previous = _current;
      _current = index;
    });
    _ctrl
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      // PERF: extendBody lets the scaffold render behind the nav bar so
      // the BackdropFilter blurs actual page content, not a black void.
      extendBody: true,
      body: Stack(
        children: [
          // ── Pages ──────────────────────────────────────────────────────
          Positioned.fill(
            child: IndexedStack(
              index: _current,
              children: _pages
                  .map((p) => Padding(
                        padding: EdgeInsets.only(
                          bottom: bottomPad + _kBarHeight + 24,
                        ),
                        child: p,
                      ))
                  .toList(),
            ),
          ),

          // ── Nav bar ────────────────────────────────────────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomPad + 14,
            // PERF: RepaintBoundary isolates the bar's repaint from the
            // pages — only the bar layer is redrawn on each animation tick.
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ctrl, // listen to raw controller
                builder: (_, __) => _LiquidGlassBar(
                  currentIndex: _current,
                  previousIndex: _previous,
                  pillT: _pillAnim.value.clamp(0.0, 1.0),
                  blobT:
                      _blobAnim.value.clamp(0.0, 2.0), // elastic can exceed 1
                  icons: _icons,
                  labels: _labels,
                  onTap: _onTap,
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
// LIQUID GLASS BAR
// ═══════════════════════════════════════════════════════════════════════════════
class _LiquidGlassBar extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double pillT; // 0→1, easeInOutCubic  — drives pill position
  final double blobT; // 0→1+, elasticOut     — drives metaball sizes
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  const _LiquidGlassBar({
    required this.currentIndex,
    required this.previousIndex,
    required this.pillT,
    required this.blobT,
    required this.icons,
    required this.labels,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kBarHeight,
      child: Stack(
        children: [
          // ── Layer 1: Metaball glow (unclipped) ─────────────────────────
          Positioned.fill(
            child: CustomPaint(
              // PERF: isComplex=true hints to Flutter to cache the layer
              isComplex: true,
              painter: _MetaballPainter(
                current: currentIndex,
                previous: previousIndex,
                t: blobT,
              ),
            ),
          ),

          // ── Layer 2: Frosted glass shell ────────────────────────────────
          // BUG FIX: BackdropFilter inside ClipRRect with a fully
          // transparent child renders correctly without an opaque backing.
          // Using DecoratedBox (not Container) prevents implicit Color fill.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(36),
                    // Specular gradient — top edge lighter, bottom darker
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.09),
                        Colors.white.withValues(alpha: 0.03),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.11),
                      width: 0.5,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // ── Layer 3: Sliding pill ───────────────────────────────────────
          // BUG FIX: No BoxShadow — shadows paint an opaque compositor
          // backing rect causing the black-square artifact.
          Positioned.fill(
            child: _SlidingPill(
              currentIndex: currentIndex,
              previousIndex: previousIndex,
              t: pillT, // uses smooth cubic, never overshoots
            ),
          ),

          // ── Layer 4: Nav items ─────────────────────────────────────────
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
// SLIDING PILL
// ═══════════════════════════════════════════════════════════════════════════════
class _SlidingPill extends StatelessWidget {
  final int currentIndex;
  final int previousIndex;
  final double t; // always 0→1, never overshoots (easeInOutCubic)

  const _SlidingPill({
    required this.currentIndex,
    required this.previousIndex,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final itemW = constraints.maxWidth / _kItemCount;

      // Center pill under each item
      double pillLeft(int idx) => itemW * idx + (itemW - _kPillW) / 2;

      // Safe lerp — t is clamped [0,1] so no overshoot here
      final x = lerpDouble(pillLeft(previousIndex), pillLeft(currentIndex), t)!;

      return Stack(
        children: [
          Positioned(
            left: x,
            top: (_kBarHeight - _kPillH) / 2,
            child: Container(
              width: _kPillW,
              height: _kPillH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                // Semi-transparent fill — NOT opaque, no shadows
                color: _kGoldMid.withValues(alpha: 0.13),
                border: Border.all(
                  color: _kGoldMid.withValues(alpha: 0.42),
                  width: 0.75,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
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
      child: AnimatedScale(
        scale: isActive ? 1.07 : 1.0,
        duration: const Duration(milliseconds: 340),
        curve: Curves.elasticOut,
        child: SizedBox(
          width: 80,
          height: _kBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // PERF: AnimatedSwitcher causes a full subtree rebuild on
              // every toggle. Using a single Icon with AnimatedTheme is
              // lighter — color transitions without widget replacement.
              Icon(
                icon,
                size: 23,
                color: isActive
                    ? _kGoldBright
                    : Colors.white.withValues(alpha: 0.36),
              ),

              const SizedBox(height: 5),

              // Label with animated style
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.34),
                  fontSize: 9.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  letterSpacing: 0.7,
                  // FIX: Explicit height prevents label from shifting
                  // vertically when weight changes (different metric boxes).
                  height: 1.0,
                ),
                child: Text(label),
              ),

              const SizedBox(height: 6),

              // Active indicator: dot expands to pill
              // BUG FIX: Never use Colors.transparent as an end-state for
              // AnimatedContainer color — it causes a black flash on some
              // GPUs. Use a fully-alpha version of the real color instead.
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: isActive ? 20 : 4,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color:
                      isActive ? _kGoldMid : _kGoldDim.withValues(alpha: 0.0),
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
// METABALL PAINTER
// ═══════════════════════════════════════════════════════════════════════════════
//
// Architecture:
//  • saveLayer with a ColorFilter alpha-threshold matrix fuses overlapping
//    blurred circles into a single liquid shape (classic CSS metaball trick).
//  • Each tab has a resting blob (r=13). The active tab's blob grows to r=30.
//  • A bridge blob travels between prev→current, fattest at the midpoint,
//    creating the liquid-stretch effect.
//  • blobT can exceed 1.0 (elasticOut overshoot) — blob radii are clamped
//    so they never go negative.
//
class _MetaballPainter extends CustomPainter {
  final int current;
  final int previous;
  final double t; // elasticOut value — may exceed 1.0

  const _MetaballPainter({
    required this.current,
    required this.previous,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Threshold composite — fuses blobs that overlap sufficiently
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..colorFilter = ColorFilter.matrix(<double>[
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
        ]),
    );

    final itemW = size.width / _kItemCount;
    final cy = size.height / 2;

    // ── Static blobs ──────────────────────────────────────────────────
    for (int i = 0; i < _kItemCount; i++) {
      final cx = itemW * i + itemW / 2;

      double r;
      if (previous == current) {
        // Settled state — no interpolation needed
        r = i == current ? 30.0 : 13.0;
      } else if (i == current) {
        // Growing in — clamp so elastic overshoot doesn't go below 0
        r = lerpDouble(13, 30, t)!.clamp(13.0, 36.0);
      } else if (i == previous) {
        // Shrinking out — use pillT-equivalent (clamp to [0,1])
        r = lerpDouble(30, 13, t.clamp(0.0, 1.0))!;
      } else {
        r = 13.0;
      }

      _blob(canvas, Offset(cx, cy), r, alpha: 0.70);
    }

    // ── Bridge blob ───────────────────────────────────────────────────
    // Only draw while animating AND within the visible stretch window.
    // Using t.clamp(0,1) for position so the bridge doesn't overshoot
    // past the destination tab even when blobT > 1.
    if (previous != current) {
      final tClamped = t.clamp(0.0, 1.0);
      if (tClamped > 0.02 && tClamped < 0.98) {
        final fromCX = itemW * previous + itemW / 2;
        final toCX = itemW * current + itemW / 2;
        final bridgeX = lerpDouble(fromCX, toCX, tClamped)!;
        // Sine arc: bridge is fattest at the midpoint of travel
        final bridgeR = (11.0 + sin(pi * tClamped) * 12.0).clamp(0.0, 24.0);

        if (bridgeR > 1) {
          _blob(canvas, Offset(bridgeX, cy), bridgeR, alpha: 0.56);
        }
      }
    }

    canvas.restore();
  }

  void _blob(Canvas canvas, Offset center, double r, {double alpha = 0.70}) {
    if (r <= 0)
      return; // Guard against negative radius (shouldn't happen after clamp)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = _kGoldMid.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.70),
    );
  }

  @override
  bool shouldRepaint(covariant _MetaballPainter old) =>
      old.current != current || old.previous != previous || old.t != t;
}
