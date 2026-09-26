import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'screens/history/history_screen.dart';
import 'screens/settings_screen.dart' as settings_ui;
import 'screens/tracking/tracking_screen.dart';
import 'services/settings_service.dart';
import 'config/mapbox_config.dart';
import 'services/offline_sync_queue.dart';
import 'widgets/app_console_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DESIGN TOKENS — APPLE HIG LIQUID GLASS OLED
// ═══════════════════════════════════════════════════════════════════════════════

const Color _kAppleBlue = Color(0xFF0A84FF);
const Color _kAppleCyan = Color(0xFF00C7BE);

const Color _kGlassBorder = Color(0x2EFFFFFF);
const Color _kGlassInner = Color(0x14FFFFFF);
const Color _kGlassBodyTint = Color(0xD9121216);

const Color _kPillFill = Color(0x280A84FF);
const Color _kPillRim = Color(0x4D0A84FF);
const Color _kPillShine = Color(0x4064D2FF);

const double _kBarHeight = 68.0;
const double _kBarRadius = 34.0;
const int _kItemCount = 3;

const double _kPillW = 88.0;
const double _kPillH = 48.0;
const double _kPillRadius = 24.0;

const double _kBarOffsetWithNav = 12.0;
const double _kBarOffsetWithoutNav = 20.0;
const double _kBarSideMargin = 18.0;
const double _kMaxBarWidth = 480.0;

const double _kBarBlurX = 28.0;
const double _kBarBlurY = 28.0;

// ═══════════════════════════════════════════════════════════════════════════════
// SUPABASE CONFIG
// ═══════════════════════════════════════════════════════════════════════════════

const String _kSupabaseUrl = 'https://uozzhvzewdsxpxmxsntr.supabase.co';
const String _kSupabaseAnonKey =
    'sb_publishable_nrR6DFCgBKlgRnyINe5z0w_XDGmIsN2';

const String _kAppVersion = '1.5.1';
const Duration _kOfflineSyncBootDelay = Duration(seconds: 2);

DateTime? _lastKeyboardAssertionLogAt;
int _suppressedKeyboardAssertionCount = 0;

bool _isBenignHardwareKeyboardAssertion(Object error) {
  final String message = error.toString();

  if (!message.contains('hardware_keyboard.dart')) return false;

  final bool isDuplicateKeyDown =
      message.contains('!_pressedKeys.containsKey(event.physicalKey)') &&
          message.contains('KeyDownEvent is dispatched') &&
          message.contains('physical key is already pressed');

  final bool isDuplicateKeyUp =
      message.contains('_pressedKeys.containsKey(event.physicalKey)') &&
          message.contains('KeyUpEvent is dispatched') &&
          message.contains('physical key is not pressed');

  final bool isControlKey = message.contains('Control Left') ||
      message.contains('Control Right') ||
      message.contains('PhysicalKeyboardKey#700e0') ||
      message.contains('PhysicalKeyboardKey#700e4');

  // Flutter Web/hotbuilder can occasionally send duplicated synthesized Ctrl
  // key events. These are noisy framework assertions, not app logic errors.
  return isControlKey && (isDuplicateKeyDown || isDuplicateKeyUp);
}

void _logIgnoredKeyboardAssertion(Object error) {
  _suppressedKeyboardAssertionCount++;

  final DateTime now = DateTime.now();
  final DateTime? last = _lastKeyboardAssertionLogAt;

  // Prevent App Console spam when Flutter web/hotbuilder sends many duplicate
  // synthesized Control key-up events in the same second.
  if (last != null && now.difference(last) < const Duration(seconds: 10)) {
    return;
  }

  _lastKeyboardAssertionLogAt = now;

  AppConsole.warn(
    'Suppressed Flutter web duplicate keyboard assertion',
    tag: 'KEYBOARD',
    data: <String, Object?>{
      'count': _suppressedKeyboardAssertionCount,
      'reason': 'benign Flutter/HotBuilder hardware keyboard state mismatch',
    },
  );

  _suppressedKeyboardAssertionCount = 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      AppConsole.installDebugPrintCapture();

      // mapbox_maps_flutter is a native Android/iOS SDK.
      // Do not initialize it on Flutter Web/hotbuilder.
      if (!kIsWeb) {
        mb.MapboxOptions.setAccessToken(MapboxConfig.accessToken);
      } else {
        AppConsole.warn(
          'Native Mapbox SDK disabled on Web',
          tag: 'MAPBOX',
          data: <String, Object?>{
            'reason': 'mapbox_maps_flutter supports native platform views only',
          },
        );
      }

      FlutterError.onError = (FlutterErrorDetails details) {
        if (_isBenignHardwareKeyboardAssertion(details.exception)) {
          _logIgnoredKeyboardAssertion(details.exception);
          return;
        }

        FlutterError.presentError(details);
        debugPrint('Flutter error: ${details.exceptionAsString()}');
        if (details.stack != null) {
          debugPrint(details.stack.toString());
        }

        AppConsole.flutterError(details);
      };

      ui.PlatformDispatcher.instance.onError = (
        Object error,
        StackTrace stackTrace,
      ) {
        if (_isBenignHardwareKeyboardAssertion(error)) {
          _logIgnoredKeyboardAssertion(error);
          return true;
        }

        debugPrint('Platform error: $error\n$stackTrace');
        AppConsole.error(
          'Platform error',
          tag: 'APP',
          error: error,
          stackTrace: stackTrace,
        );
        return true;
      };

      AppConsole.log(
        'TrackPro AI booting',
        tag: 'APP',
        data: <String, Object?>{
          'version': _kAppVersion,
          'mapboxConfigured': MapboxConfig.accessToken.isNotEmpty,
        },
      );

      if (!kIsWeb) {
        AppConsole.success('Native Mapbox token configured', tag: 'MAPBOX');
      }

      await _configureSystemUi();
      await _bootstrapServices();

      runApp(const TrackProAI());
    },
    (Object error, StackTrace stackTrace) {
      if (_isBenignHardwareKeyboardAssertion(error)) {
        _logIgnoredKeyboardAssertion(error);
        return;
      }

      debugPrint('Uncaught zone error: $error\n$stackTrace');
      AppConsole.error(
        'Uncaught zone error',
        tag: 'APP',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

Future<void> _configureSystemUi() async {
  try {
    await SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[DeviceOrientation.portraitUp],
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _applySystemUiStyle();
    AppConsole.success('System UI configured', tag: 'APP');
  } catch (e, st) {
    debugPrint('System UI config failed: $e\n$st');
    AppConsole.error(
      'System UI config failed',
      tag: 'APP',
      error: e,
      stackTrace: st,
    );
  }
}

Future<void> _bootstrapServices() async {
  AppConsole.log('Bootstrapping services', tag: 'APP');

  await Future.wait<void>(
    <Future<void>>[
      _initSupabase(),
      _initSettings(),
      _initOfflineSyncQueue(),
    ],
    eagerError: false,
  );

  AppConsole.success('Bootstrap completed', tag: 'APP');
}

Future<void> _initOfflineSyncQueue() async {
  try {
    await OfflineSyncQueue.instance.loadStatus();

    AppConsole.success(
      'Offline sync queue loaded',
      tag: 'SYNC',
      data: <String, Object?>{
        'pending': OfflineSyncQueue.instance.pendingCount.value,
      },
    );
  } catch (e, st) {
    debugPrint('Offline sync queue load error: $e\n$st');
    AppConsole.error(
      'Offline sync queue load failed',
      tag: 'SYNC',
      error: e,
      stackTrace: st,
    );
  }
}

Future<void> _initSupabase() async {
  if (_kSupabaseUrl.trim().isEmpty || _kSupabaseAnonKey.trim().isEmpty) {
    debugPrint('Supabase skipped: missing URL or anon key.');
    AppConsole.warn('Supabase skipped: missing URL or anon key',
        tag: 'SUPABASE');
    return;
  }

  try {
    await Supabase.initialize(
      url: _kSupabaseUrl,
      // ignore: deprecated_member_use
      anonKey: _kSupabaseAnonKey,
    );

    debugPrint('Supabase initialized successfully.');
    AppConsole.success(
      'Supabase initialized',
      tag: 'SUPABASE',
      data: <String, Object?>{
        'url': _kSupabaseUrl,
      },
    );
  } catch (e, st) {
    // Keep the app usable even if Supabase is offline/misconfigured.
    debugPrint('Supabase init error: $e\n$st');
    AppConsole.error(
      'Supabase init failed',
      tag: 'SUPABASE',
      error: e,
      stackTrace: st,
    );
  }
}

Future<void> _initSettings() async {
  try {
    await SettingsService.instance.load();
    AppConsole.success(
      'Settings loaded',
      tag: 'SETTINGS',
      data: <String, Object?>{
        'mapStyle': SettingsService.instance.mapStyle.name,
        'units': SettingsService.instance.useKmh ? 'metric' : 'imperial',
      },
    );
  } catch (e, st) {
    debugPrint('Settings load error: $e\n$st');
    AppConsole.error(
      'Settings load failed',
      tag: 'SETTINGS',
      error: e,
      stackTrace: st,
    );
  }
}

void _applySystemUiStyle() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP ROOT
// ═══════════════════════════════════════════════════════════════════════════════

class TrackProAI extends StatelessWidget {
  const TrackProAI({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = _buildTheme();

    return MaterialApp(
      title: 'TrackPro AI',
      restorationScopeId: 'trackpro_ai',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: theme,
      darkTheme: theme,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      scrollBehavior: const CupertinoScrollBehavior(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);

        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.18,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppShell(),
    );
  }

  ThemeData _buildTheme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _kAppleBlue,
      brightness: Brightness.dark,
      surface: Colors.black,
    );

    return ThemeData(
      platform: TargetPlatform.iOS,
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      fontFamilyFallback: const <String>[
        '.AppleSystemUIFont',
        'SF Pro Display',
        'SF Pro Text',
        '-apple-system',
        'BlinkMacSystemFont',
        'Helvetica Neue',
        'Arial',
      ],
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: _kAppleBlue,
        scaffoldBackgroundColor: Colors.black,
        barBackgroundColor: Color(0xCC1C1C1E),
        textTheme: CupertinoTextThemeData(
          primaryColor: _kAppleBlue,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1C1C1E),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x38545458), width: 0.5),
        ),
      ),
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _current = 0;
  int _previous = 0;
  double _pillStartFraction = 0.0;

  bool _offlineSyncScheduled = false;
  bool _offlineSyncRunning = false;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 430),
    value: 1.0,
  );

  late final Animation<double> _pillAnim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOutCubic,
  );

  late final Animation<double> _shimmerAnim = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(
      0.0,
      0.52,
      curve: Curves.easeOutCubic,
    ),
  );

  static const List<IconData> _activeIcons = <IconData>[
    CupertinoIcons.speedometer,
    CupertinoIcons.clock_fill,
    CupertinoIcons.gear_alt_fill,
  ];

  static const List<IconData> _inactiveIcons = <IconData>[
    CupertinoIcons.speedometer,
    CupertinoIcons.clock,
    CupertinoIcons.gear_alt,
  ];

  static const List<String> _labels = <String>[
    'TRACK',
    'HISTORY',
    'SETTINGS',
  ];

  late final List<Widget> _pages = <Widget>[
    const TrackingScreen(),
    const HistoryScreen(),
    const settings_ui.SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    AppConsole.log('App shell initialized', tag: 'APP');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applySystemUiStyle();
      _scheduleOfflineQueueSync();
    });
  }

  void _scheduleOfflineQueueSync() {
    if (_offlineSyncScheduled || _offlineSyncRunning) return;

    _offlineSyncScheduled = true;

    Future<void>.delayed(_kOfflineSyncBootDelay, () async {
      _offlineSyncScheduled = false;

      if (!mounted || _offlineSyncRunning) return;

      final int pending = OfflineSyncQueue.instance.pendingCount.value;
      if (pending <= 0) return;

      _offlineSyncRunning = true;

      AppConsole.log(
        'Boot offline sync started',
        tag: 'SYNC',
        data: <String, Object?>{'pending': pending},
      );

      try {
        final OfflineSyncResult result =
            await OfflineSyncQueue.instance.syncNow();

        AppConsole.log(
          result.hasPending
              ? 'Boot offline sync still pending'
              : 'Boot offline sync complete',
          tag: 'SYNC',
          data: <String, Object?>{
            'attempted': result.attempted,
            'succeeded': result.succeeded,
            'failed': result.failed,
            'pending': result.pending,
          },
        );
      } catch (error, stackTrace) {
        AppConsole.error(
          'Boot offline sync failed',
          tag: 'SYNC',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _offlineSyncRunning = false;
      }
    });
  }

  @override
  void dispose() {
    AppConsole.log('App shell disposed', tag: 'APP');
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    AppConsole.log(
      'Lifecycle changed',
      tag: 'APP',
      data: <String, Object?>{
        'state': state.name,
      },
    );

    if (state == AppLifecycleState.resumed) {
      _applySystemUiStyle();
      _scheduleOfflineQueueSync();
    }
  }

  void _onTap(int index) {
    if (index == _current) {
      HapticFeedback.lightImpact();
      return;
    }

    HapticFeedback.selectionClick();

    AppConsole.log(
      'Tab changed',
      tag: 'NAV',
      data: <String, Object?>{
        'from': _labels[_current],
        'to': _labels[index],
      },
    );

    final double currentVisualT = _pillAnim.value.clamp(0.0, 1.0);

    setState(() {
      _pillStartFraction = currentVisualT;
      _previous = _current;
      _current = index;
    });

    _ctrl
      ..stop()
      ..value = 0.0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double bottomPad = mq.padding.bottom;
    final double barOffset =
        bottomPad > 0 ? _kBarOffsetWithNav : _kBarOffsetWithoutNav;

    final double pagePaddingBottom = bottomPad + _kBarHeight + barOffset + 16.0;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IndexedStack(
              index: _current,
              sizing: StackFit.expand,
              children: List<Widget>.generate(
                _pages.length,
                (int index) {
                  return _TabPageWrapper(
                    active: index == _current,
                    pagePaddingBottom: pagePaddingBottom,
                    child: _pages[index],
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad + barOffset,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxBarWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _kBarSideMargin,
                  ),
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) {
                        return _LiquidGlassBar(
                          currentIndex: _current,
                          previousIndex: _previous,
                          pillT: _pillAnim.value.clamp(0.0, 1.0),
                          pillStartFraction: _pillStartFraction.clamp(0.0, 1.0),
                          shimmerT: _shimmerAnim.value.clamp(0.0, 1.0),
                          activeIcons: _activeIcons,
                          inactiveIcons: _inactiveIcons,
                          labels: _labels,
                          onTap: _onTap,
                        );
                      },
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
// ═══════════════════════════════════════════════════════════════════════════════

class _TabPageWrapper extends StatefulWidget {
  const _TabPageWrapper({
    required this.active,
    required this.pagePaddingBottom,
    required this.child,
  });

  final bool active;
  final double pagePaddingBottom;
  final Widget child;

  @override
  State<_TabPageWrapper> createState() => _TabPageWrapperState();
}

class _TabPageWrapperState extends State<_TabPageWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final MediaQueryData mq = MediaQuery.of(context);
    final EdgeInsets safePadding = mq.padding.copyWith(
      bottom: math.max(
        mq.padding.bottom,
        widget.pagePaddingBottom,
      ),
    );

    return TickerMode(
      enabled: widget.active,
      child: IgnorePointer(
        ignoring: !widget.active,
        child: AnimatedOpacity(
          opacity: widget.active ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: MediaQuery(
            data: mq.copyWith(padding: safePadding),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// APPLE HIG LIQUID GLASS NAVIGATION BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _LiquidGlassBar extends StatelessWidget {
  const _LiquidGlassBar({
    required this.currentIndex,
    required this.previousIndex,
    required this.pillT,
    required this.pillStartFraction,
    required this.shimmerT,
    required this.activeIcons,
    required this.inactiveIcons,
    required this.labels,
    required this.onTap,
  });

  final int currentIndex;
  final int previousIndex;
  final double pillT;
  final double pillStartFraction;
  final double shimmerT;
  final List<IconData> activeIcons;
  final List<IconData> inactiveIcons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kBarHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kBarRadius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 32.0,
            offset: const Offset(0, 10),
            spreadRadius: -2.0,
          ),
          BoxShadow(
            color: _kAppleBlue.withValues(alpha: 0.08),
            blurRadius: 24.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // 1. Frosted Glass Backdrop
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kBarRadius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: _kBarBlurX,
                  sigmaY: _kBarBlurY,
                ),
                child: const ColoredBox(
                  color: _kGlassBodyTint,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),

          // 2. Glass Surface & Specular Highlights Painter
          const Positioned.fill(
            child: CustomPaint(
              painter: _GlassSurfacePainter(),
            ),
          ),

          // 3. Sliding Fluid Pill (Active Tab Highlight)
          Positioned.fill(
            child: _SlidingPill(
              currentIndex: currentIndex,
              previousIndex: previousIndex,
              t: pillT,
              startFraction: pillStartFraction,
            ),
          ),

          // 4. Subtle Shimmer / Specular Sweep
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

          // 5. Interactive Tab Items
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List<Widget>.generate(
                _kItemCount,
                (int index) {
                  return _NavItem(
                    activeIcon: activeIcons[index],
                    inactiveIcon: inactiveIcons[index],
                    label: labels[index],
                    isActive: currentIndex == index,
                    onTap: () => onTap(index),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLASS SURFACE PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassSurfacePainter extends CustomPainter {
  const _GlassSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Rect rect = Offset.zero & size;
    final RRect rr = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_kBarRadius),
    );

    // Subtle internal surface gradient
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x18FFFFFF),
            Color(0x04FFFFFF),
          ],
        ).createShader(rect),
    );

    // Outer hairline glass border
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = _kGlassBorder,
    );

    // Inner rim stroke
    final RRect inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(_kBarRadius - 1),
    );

    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = _kGlassInner,
    );

    // Top specular highlight (physical light reflection on curved glass rim)
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, 3));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x66FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassSurfacePainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLIDING PILL
// ═══════════════════════════════════════════════════════════════════════════════

class _SlidingPill extends StatelessWidget {
  const _SlidingPill({
    required this.currentIndex,
    required this.previousIndex,
    required this.t,
    required this.startFraction,
  });

  final int currentIndex;
  final int previousIndex;
  final double t;
  final double startFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, BoxConstraints constraints) {
        final double itemW = constraints.maxWidth / _kItemCount;

        double leftFor(int index) {
          return itemW * index + (itemW - _kPillW) / 2;
        }

        final double fromX = leftFor(previousIndex);
        final double toX = leftFor(currentIndex);
        final double visualStart =
            ui.lerpDouble(fromX, toX, startFraction) ?? fromX;

        final double x = ui.lerpDouble(visualStart, toX, t) ?? toX;

        return Stack(
          children: <Widget>[
            Positioned(
              left: x,
              top: (_kBarHeight - _kPillH) / 2,
              child: const SizedBox(
                width: _kPillW,
                height: _kPillH,
                child: CustomPaint(
                  painter: _PillPainter(),
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
// PILL PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _PillPainter extends CustomPainter {
  const _PillPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Rect rect = Offset.zero & size;
    final RRect rr = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_kPillRadius),
    );

    // Pill fill with subtle electric blue / cyan glow
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _kPillFill,
            Color(0x1800C7BE),
          ],
        ).createShader(rect),
    );

    // Pill border
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = _kPillRim,
    );

    // Top specular shine of the pill
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, 2.5));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _kPillShine,
    );
    canvas.restore();

    // Soft subtle radial glow in the center-top
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.35),
        width: size.width * 0.55,
        height: size.height * 0.40,
      ),
      Paint()
        ..color = _kAppleBlue.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );
  }

  @override
  bool shouldRepaint(covariant _PillPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHIMMER PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter({
    required this.currentIndex,
    required this.previousIndex,
    required this.shimmerT,
    required this.pillT,
    required this.startFraction,
  });

  final int currentIndex;
  final int previousIndex;
  final double shimmerT;
  final double pillT;
  final double startFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (previousIndex == currentIndex || size.isEmpty) return;

    final double itemW = size.width / _kItemCount;

    double leftFor(int index) {
      return itemW * index + (itemW - _kPillW) / 2;
    }

    final double fromX = leftFor(previousIndex);
    final double toX = leftFor(currentIndex);
    final double visualStart =
        ui.lerpDouble(fromX, toX, startFraction) ?? fromX;
    final double pillX = ui.lerpDouble(visualStart, toX, pillT) ?? toX;

    final bool goRight = currentIndex > previousIndex;
    final double shimmerX =
        goRight ? pillX + _kPillW * 0.74 : pillX + _kPillW * 0.26;
    final double shimmerY = _kBarHeight / 2;

    final double opacity =
        (shimmerT < 0.5 ? shimmerT * 2.0 : (1.0 - shimmerT) * 2.0)
            .clamp(0.0, 1.0);

    if (opacity < 0.01) return;

    canvas.save();
    canvas.translate(shimmerX, shimmerY);
    canvas.rotate(-0.35);
    canvas.translate(-shimmerX, -shimmerY);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(shimmerX, shimmerY),
        width: 8.0,
        height: _kBarHeight * 1.4,
      ),
      Paint()
        ..color = _kAppleCyan.withValues(alpha: opacity * 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(shimmerX, shimmerY),
        width: 2.0,
        height: _kBarHeight * 1.1,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter oldDelegate) {
    return oldDelegate.shimmerT != shimmerT ||
        oldDelegate.pillT != pillT ||
        oldDelegate.currentIndex != currentIndex ||
        oldDelegate.previousIndex != previousIndex ||
        oldDelegate.startFraction != startFraction;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAV ITEM
// ═══════════════════════════════════════════════════════════════════════════════

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  static const Map<String, double> _indicatorWidths = <String, double>{
    'TRACK': 18.0,
    'HISTORY': 22.0,
    'SETTINGS': 22.0,
  };

  @override
  Widget build(BuildContext context) {
    final Color inactiveText = Colors.white.withValues(alpha: 0.38);

    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: _kBarHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedScale(
                  scale: isActive ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: isActive ? 1.0 : 0.40,
                    duration: const Duration(milliseconds: 180),
                    child: isActive
                        ? ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (Rect bounds) {
                              return const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  _kAppleBlue,
                                  _kAppleCyan,
                                ],
                              ).createShader(bounds);
                            },
                            child: Icon(
                              activeIcon,
                              size: 21,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            inactiveIcon,
                            size: 21,
                            color: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    color: isActive ? Colors.white : inactiveText,
                    fontSize: 10.0,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: isActive ? 0.4 : 0.2,
                    height: 1.0,
                  ),
                  child: Text(label),
                ),
                const SizedBox(height: 4),
                _ActiveIndicator(
                  targetWidth: _indicatorWidths[label] ?? 20.0,
                  isActive: isActive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveIndicator extends StatelessWidget {
  const _ActiveIndicator({
    required this.targetWidth,
    required this.isActive,
  });

  final double targetWidth;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: isActive ? targetWidth : 0.0,
      height: 2.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2.0),
        gradient: isActive
            ? const LinearGradient(
                colors: <Color>[
                  _kAppleBlue,
                  _kAppleCyan,
                ],
              )
            : null,
        boxShadow: isActive
            ? <BoxShadow>[
                BoxShadow(
                  color: _kAppleBlue.withValues(alpha: 0.60),
                  blurRadius: 6.0,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
    );
  }
}
