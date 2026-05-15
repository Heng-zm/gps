import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show
        DebugPrintCallback,
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        kProfileMode,
        kReleaseMode;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// TrackPro terminal-style in-app console.
///
/// Add to settings_screen.dart:
///   import '../widgets/app_console_widget.dart';
///   const AppConsoleSettingsCard(),
///
/// Add logs anywhere:
///   AppConsole.log('GPS started', tag: 'GPS');
///   AppConsole.success('Trip saved', tag: 'SUPABASE');
///   AppConsole.warn('GPS accuracy weak', tag: 'GPS');
///   AppConsole.error('Save failed', tag: 'SUPABASE', error: e, stackTrace: st);
///
/// In main.dart:
///   FlutterError.onError = (details) {
///     FlutterError.presentError(details);
///     AppConsole.flutterError(details);
///   };
class AppConsole {
  AppConsole._();

  static final ValueNotifier<List<AppConsoleEntry>> entries =
      ValueNotifier<List<AppConsoleEntry>>(<AppConsoleEntry>[]);

  static const int _maxEntries = 500;

  static final List<AppConsoleEntry> _pendingFrameEntries = <AppConsoleEntry>[];
  static bool _flushScheduled = false;

  static DebugPrintCallback? _originalDebugPrint;
  static bool _debugPrintCaptureInstalled = false;
  static bool _writingToDebugPrint = false;

  static bool get isDebugPrintCaptureInstalled => _debugPrintCaptureInstalled;

  /// Captures all Flutter debugPrint() output into this console.
  ///
  /// Call once in main.dart after WidgetsFlutterBinding.ensureInitialized():
  ///
  ///   AppConsole.installDebugPrintCapture();
  ///
  /// This makes messages like "Fetched", GPS logs, Supabase logs,
  /// WeatherService logs and other debugPrint output visible in Settings.
  static void installDebugPrintCapture() {
    if (_debugPrintCaptureInstalled) return;

    _originalDebugPrint = debugPrint;
    _debugPrintCaptureInstalled = true;

    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);

      if (_writingToDebugPrint) return;
      if (message == null || message.trim().isEmpty) return;

      _captureDebugPrintLine(message);
    };

    success('debugPrint capture installed', tag: 'CONSOLE');
  }

  static void _captureDebugPrintLine(String rawMessage) {
    final List<String> lines = rawMessage
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);

    for (final String line in lines) {
      final String lower = line.toLowerCase();

      if (_looksLikeConsoleEcho(line)) continue;

      if (lower.contains('error') ||
          lower.contains('exception') ||
          lower.contains('failed') ||
          lower.contains('crash')) {
        _add(
          AppConsoleEntry(
            time: DateTime.now(),
            level: AppConsoleLevel.error,
            tag: 'DEBUG',
            message: line,
          ),
          echoToDebugPrint: false,
        );
      } else if (lower.contains('warn') ||
          lower.contains('denied') ||
          lower.contains('weak')) {
        _add(
          AppConsoleEntry(
            time: DateTime.now(),
            level: AppConsoleLevel.warning,
            tag: 'DEBUG',
            message: line,
          ),
          echoToDebugPrint: false,
        );
      } else if (lower.contains('fetched') ||
          lower.contains('loaded') ||
          lower.contains('saved') ||
          lower.contains('synced') ||
          lower.contains('initialized') ||
          lower.contains('success')) {
        _add(
          AppConsoleEntry(
            time: DateTime.now(),
            level: AppConsoleLevel.success,
            tag: lower.contains('fetched') ? 'FETCHED' : 'DEBUG',
            message: line,
          ),
          echoToDebugPrint: false,
        );
      } else {
        _add(
          AppConsoleEntry(
            time: DateTime.now(),
            level: AppConsoleLevel.info,
            tag: 'DEBUG',
            message: line,
          ),
          echoToDebugPrint: false,
        );
      }
    }
  }

  static bool _looksLikeConsoleEcho(String line) {
    return line.startsWith('[') &&
        (line.contains('][INFO]') ||
            line.contains('][OK]') ||
            line.contains('][WARN]') ||
            line.contains('][ERR]'));
  }

  static void log(
    String message, {
    String tag = 'APP',
    Map<String, Object?>? data,
  }) {
    _add(
      AppConsoleEntry(
        time: DateTime.now(),
        level: AppConsoleLevel.info,
        tag: tag,
        message: message,
        data: data,
      ),
    );
  }

  static void success(
    String message, {
    String tag = 'OK',
    Map<String, Object?>? data,
  }) {
    _add(
      AppConsoleEntry(
        time: DateTime.now(),
        level: AppConsoleLevel.success,
        tag: tag,
        message: message,
        data: data,
      ),
    );
  }

  static void warn(
    String message, {
    String tag = 'WARN',
    Map<String, Object?>? data,
  }) {
    _add(
      AppConsoleEntry(
        time: DateTime.now(),
        level: AppConsoleLevel.warning,
        tag: tag,
        message: message,
        data: data,
      ),
    );
  }

  static void error(
    String message, {
    String tag = 'ERROR',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    final Map<String, Object?> merged = <String, Object?>{
      if (data != null) ...data,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': _trimStack(stackTrace),
    };

    _add(
      AppConsoleEntry(
        time: DateTime.now(),
        level: AppConsoleLevel.error,
        tag: tag,
        message: message,
        data: merged.isEmpty ? null : merged,
      ),
    );
  }

  static void flutterError(FlutterErrorDetails details) {
    error(
      details.exceptionAsString(),
      tag: 'FLUTTER',
      stackTrace: details.stack,
      data: <String, Object?>{
        if (details.library != null) 'library': details.library,
        if (details.context != null) 'context': details.context.toString(),
      },
    );
  }

  /// Quick helper for successful fetch/load events.
  static void fetched(
    String message, {
    String tag = 'FETCHED',
    Map<String, Object?>? data,
  }) {
    success(message, tag: tag, data: data);
  }

  /// Run a small API request from the in-app terminal.
  ///
  /// Supported methods: GET, POST, DELETE, OPTIONS.
  static Future<AppConsoleApiResult> apiFetch({
    required String method,
    required String url,
    String? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final String normalizedMethod = method.trim().toUpperCase();
    final String trimmedUrl = url.trim();

    if (trimmedUrl.isEmpty) {
      const AppConsoleApiResult result = AppConsoleApiResult(
        ok: false,
        statusCode: 0,
        method: '',
        url: '',
        elapsedMs: 0,
        bodyPreview: '',
        error: 'URL is empty.',
      );
      warn('API fetch blocked: URL is empty', tag: 'API');
      return result;
    }

    final Uri? uri = Uri.tryParse(trimmedUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      final AppConsoleApiResult result = AppConsoleApiResult(
        ok: false,
        statusCode: 0,
        method: normalizedMethod,
        url: trimmedUrl,
        elapsedMs: 0,
        bodyPreview: '',
        error: 'Invalid URL. Include https:// or http://',
      );
      warn(
        'API fetch blocked: invalid URL',
        tag: 'API',
        data: <String, Object?>{'url': trimmedUrl},
      );
      return result;
    }

    if (!<String>{'GET', 'POST', 'DELETE', 'OPTIONS'}
        .contains(normalizedMethod)) {
      final AppConsoleApiResult result = AppConsoleApiResult(
        ok: false,
        statusCode: 0,
        method: normalizedMethod,
        url: trimmedUrl,
        elapsedMs: 0,
        bodyPreview: '',
        error: 'Unsupported method.',
      );
      warn(
        'API fetch blocked: unsupported method',
        tag: 'API',
        data: <String, Object?>{'method': normalizedMethod},
      );
      return result;
    }

    final Stopwatch stopwatch = Stopwatch()..start();

    final Map<String, String> safeHeaders = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      if (normalizedMethod == 'POST') 'Content-Type': 'application/json',
      if (headers != null) ...headers,
    };

    log(
      'API $normalizedMethod request started',
      tag: 'API',
      data: <String, Object?>{
        'url': trimmedUrl,
      },
    );

    try {
      final http.Client client = http.Client();

      try {
        final http.Response response = await _sendApiRequest(
          client: client,
          method: normalizedMethod,
          uri: uri,
          headers: safeHeaders,
          body: body,
        ).timeout(timeout);

        stopwatch.stop();

        final String preview = _bodyPreview(response.body);
        final bool ok = response.statusCode >= 200 && response.statusCode < 300;

        final AppConsoleApiResult result = AppConsoleApiResult(
          ok: ok,
          statusCode: response.statusCode,
          method: normalizedMethod,
          url: trimmedUrl,
          elapsedMs: stopwatch.elapsedMilliseconds,
          bodyPreview: preview,
          error: null,
        );

        if (ok) {
          success(
            'API $normalizedMethod ${response.statusCode}',
            tag: 'API',
            data: <String, Object?>{
              'url': trimmedUrl,
              'timeMs': result.elapsedMs,
              'body': preview,
            },
          );
        } else {
          warn(
            'API $normalizedMethod ${response.statusCode}',
            tag: 'API',
            data: <String, Object?>{
              'url': trimmedUrl,
              'timeMs': result.elapsedMs,
              'body': preview,
            },
          );
        }

        return result;
      } finally {
        client.close();
      }
    } on TimeoutException {
      stopwatch.stop();
      final AppConsoleApiResult result = AppConsoleApiResult(
        ok: false,
        statusCode: 0,
        method: normalizedMethod,
        url: trimmedUrl,
        elapsedMs: stopwatch.elapsedMilliseconds,
        bodyPreview: '',
        error: 'Request timed out.',
      );

      error(
        'API $normalizedMethod timeout',
        tag: 'API',
        data: <String, Object?>{
          'url': trimmedUrl,
          'timeMs': result.elapsedMs,
        },
      );

      return result;
    } catch (e, st) {
      stopwatch.stop();
      final AppConsoleApiResult result = AppConsoleApiResult(
        ok: false,
        statusCode: 0,
        method: normalizedMethod,
        url: trimmedUrl,
        elapsedMs: stopwatch.elapsedMilliseconds,
        bodyPreview: '',
        error: e.toString(),
      );

      error(
        'API $normalizedMethod failed',
        tag: 'API',
        error: e,
        stackTrace: st,
        data: <String, Object?>{
          'url': trimmedUrl,
          'timeMs': result.elapsedMs,
        },
      );

      return result;
    }
  }

  static Future<http.Response> _sendApiRequest({
    required http.Client client,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    switch (method) {
      case 'GET':
        return client.get(uri, headers: headers);
      case 'POST':
        return client.post(uri, headers: headers, body: body ?? '{}');
      case 'DELETE':
        return client.delete(uri, headers: headers, body: body);
      case 'OPTIONS':
        return client
            .send(
              http.Request('OPTIONS', uri)..headers.addAll(headers),
            )
            .then(http.Response.fromStream);
      default:
        throw UnsupportedError('Unsupported method: $method');
    }
  }

  static String _bodyPreview(String body) {
    final String compact = body
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (compact.length <= 500) return compact;
    return '${compact.substring(0, 500)}...';
  }

  static void clear() {
    entries.value = const <AppConsoleEntry>[];
  }

  static Future<void> copyToClipboard({
    AppConsoleLevel? filter,
    String query = '',
  }) async {
    final String normalizedQuery = query.trim().toLowerCase();

    final Iterable<AppConsoleEntry> source = entries.value.where(
      (AppConsoleEntry entry) {
        if (filter != null && entry.level != filter) return false;
        if (normalizedQuery.isEmpty) return true;
        return entry.searchText.contains(normalizedQuery);
      },
    );

    final String logs = source
        .map((AppConsoleEntry e) => e.toPlainText())
        .toList(growable: false)
        .reversed
        .join('\n');

    await Clipboard.setData(
      ClipboardData(
        text: logs.isEmpty ? 'TrackPro Terminal: no matching logs.' : logs,
      ),
    );
  }

  static void _add(
    AppConsoleEntry entry, {
    bool echoToDebugPrint = true,
  }) {
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool unsafeDuringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
            phase == SchedulerPhase.postFrameCallbacks ||
            phase == SchedulerPhase.midFrameMicrotasks;

    if (unsafeDuringFrame) {
      _pendingFrameEntries.add(entry);
      _scheduleFlushPendingEntries();
    } else {
      _insertEntries(<AppConsoleEntry>[entry]);
    }

    if (kDebugMode && echoToDebugPrint) {
      _writingToDebugPrint = true;
      try {
        final DebugPrintCallback printer = _originalDebugPrint ?? debugPrint;
        printer(entry.toPlainText());
      } finally {
        _writingToDebugPrint = false;
      }
    }
  }

  static void _scheduleFlushPendingEntries() {
    if (_flushScheduled) return;

    _flushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;

      if (_pendingFrameEntries.isEmpty) return;

      final List<AppConsoleEntry> pending =
          List<AppConsoleEntry>.from(_pendingFrameEntries);
      _pendingFrameEntries.clear();
      _insertEntries(pending);
    });
  }

  static void _insertEntries(List<AppConsoleEntry> newEntries) {
    if (newEntries.isEmpty) return;

    final List<AppConsoleEntry> next = <AppConsoleEntry>[
      ...newEntries.reversed,
      ...entries.value,
    ];

    entries.value = List<AppConsoleEntry>.unmodifiable(
      next.length > _maxEntries ? next.take(_maxEntries) : next,
    );
  }

  static String _trimStack(StackTrace stackTrace) {
    return stackTrace.toString().split('\n').take(10).join('\n');
  }
}

enum AppConsoleLevel {
  info,
  success,
  warning,
  error,
}

class AppConsoleEntry {
  const AppConsoleEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.data,
  });

  final DateTime time;
  final AppConsoleLevel level;
  final String tag;
  final String message;
  final Map<String, Object?>? data;

  String get timeText {
    final String h = time.hour.toString().padLeft(2, '0');
    final String m = time.minute.toString().padLeft(2, '0');
    final String s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get levelText {
    switch (level) {
      case AppConsoleLevel.info:
        return 'INFO';
      case AppConsoleLevel.success:
        return 'OK';
      case AppConsoleLevel.warning:
        return 'WARN';
      case AppConsoleLevel.error:
        return 'ERR';
    }
  }

  Color get color {
    switch (level) {
      case AppConsoleLevel.info:
        return const Color(0xFF64D2FF);
      case AppConsoleLevel.success:
        return const Color(0xFF32D74B);
      case AppConsoleLevel.warning:
        return const Color(0xFFFFD60A);
      case AppConsoleLevel.error:
        return const Color(0xFFFF453A);
    }
  }

  String get searchText {
    return '$timeText $levelText $tag $message ${data ?? ''}'.toLowerCase();
  }

  String toPlainText() {
    final String dataText =
        data == null || data!.isEmpty ? '' : ' ${data.toString()}';
    return '[$timeText][$levelText][$tag] $message$dataText';
  }
}

/// Use this inside Settings page.

class AppConsoleApiResult {
  const AppConsoleApiResult({
    required this.ok,
    required this.statusCode,
    required this.method,
    required this.url,
    required this.elapsedMs,
    required this.bodyPreview,
    required this.error,
  });

  final bool ok;
  final int statusCode;
  final String method;
  final String url;
  final int elapsedMs;
  final String bodyPreview;
  final String? error;
}

class AppConsoleSettingsCard extends StatelessWidget {
  const AppConsoleSettingsCard({
    super.key,
    this.initialExpanded = false,
  });

  final bool initialExpanded;

  @override
  Widget build(BuildContext context) {
    return _TerminalConsole(initialExpanded: initialExpanded);
  }
}

class _TerminalConsole extends StatefulWidget {
  const _TerminalConsole({
    required this.initialExpanded,
  });

  final bool initialExpanded;

  @override
  State<_TerminalConsole> createState() => _TerminalConsoleState();
}

class _TerminalConsoleState extends State<_TerminalConsole> {
  late bool _expanded;
  AppConsoleLevel? _filter;
  bool _tail = true;
  bool _pausedView = false;
  bool _largeView = false;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _apiUrlCtrl = TextEditingController();
  final TextEditingController _apiBodyCtrl = TextEditingController();

  String _query = '';
  String _apiMethod = 'GET';
  bool _apiPanelOpen = false;
  bool _apiLoading = false;
  AppConsoleApiResult? _lastApiResult;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;

    if (AppConsole.entries.value.isEmpty) {
      AppConsole.log(
        'terminal initialized',
        tag: 'CONSOLE',
        data: <String, Object?>{
          'mode': _runtimeMode,
          'platform': _platformName,
          'debugPrintCapture': AppConsole.isDebugPrintCaptureInstalled,
        },
      );
    }

    _searchCtrl.addListener(_onSearchChanged);
    AppConsole.entries.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _apiUrlCtrl.dispose();
    _apiBodyCtrl.dispose();
    AppConsole.entries.removeListener(_onEntriesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final String next = _searchCtrl.text;
    if (next == _query) return;
    setState(() => _query = next);
  }

  void _onEntriesChanged() {
    if (!_expanded || !_tail || _pausedView || !_scrollController.hasClients) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _runApiFetch() async {
    if (_apiLoading) return;

    setState(() => _apiLoading = true);
    HapticFeedback.selectionClick();

    final AppConsoleApiResult result = await AppConsole.apiFetch(
      method: _apiMethod,
      url: _apiUrlCtrl.text,
      body: _apiBodyCtrl.text.trim().isEmpty ? null : _apiBodyCtrl.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _apiLoading = false;
      _lastApiResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppConsoleEntry>>(
      valueListenable: AppConsole.entries,
      builder: (_, List<AppConsoleEntry> entries, __) {
        final _ConsoleCounts counts = _ConsoleCounts.from(entries);
        final List<AppConsoleEntry> visible = _filterEntries(entries);
        final Color statusColor = counts.statusColor;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: const Color(0xFF050608).withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: statusColor.withValues(alpha: 0.24)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 22,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _TerminalHeader(
                    expanded: _expanded,
                    statusColor: statusColor,
                    entryCount: entries.length,
                    counts: counts,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      setState(() => _expanded = !_expanded);
                    },
                  ),
                  if (_expanded) ...<Widget>[
                    _TerminalToolbar(
                      filter: _filter,
                      tail: _tail,
                      pausedView: _pausedView,
                      largeView: _largeView,
                      apiPanelOpen: _apiPanelOpen,
                      queryController: _searchCtrl,
                      apiUrlController: _apiUrlCtrl,
                      apiBodyController: _apiBodyCtrl,
                      apiMethod: _apiMethod,
                      apiLoading: _apiLoading,
                      lastApiResult: _lastApiResult,
                      onApiPanelChanged: (bool value) {
                        HapticFeedback.selectionClick();
                        setState(() => _apiPanelOpen = value);
                      },
                      onApiMethodChanged: (String value) {
                        HapticFeedback.selectionClick();
                        setState(() => _apiMethod = value);
                      },
                      onApiFetch: _runApiFetch,
                      onFilterChanged: (AppConsoleLevel? level) {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = level);
                      },
                      onTailChanged: (bool value) {
                        HapticFeedback.selectionClick();
                        setState(() => _tail = value);
                      },
                      onPausedChanged: (bool value) {
                        HapticFeedback.selectionClick();
                        setState(() => _pausedView = value);
                      },
                      onLargeViewChanged: (bool value) {
                        HapticFeedback.selectionClick();
                        setState(() => _largeView = value);
                      },
                      onCopy: () {
                        HapticFeedback.selectionClick();
                        unawaited(
                          AppConsole.copyToClipboard(
                            filter: _filter,
                            query: _query,
                          ),
                        );
                        _snack(context, 'Terminal output copied.');
                      },
                      onTest: () {
                        HapticFeedback.selectionClick();
                        AppConsole.log(
                          'manual test command executed',
                          tag: 'TEST',
                          data: <String, Object?>{
                            'timestamp': DateTime.now().toIso8601String(),
                            'filter': _filter?.name ?? 'all',
                          },
                        );
                      },
                      onClear: () {
                        HapticFeedback.mediumImpact();
                        AppConsole.clear();
                      },
                    ),
                    _TerminalMetaBar(
                      counts: counts,
                      visibleCount: visible.length,
                      filter: _filter,
                      query: _query,
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: _largeView ? 440 : 280,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: visible.isEmpty
                          ? const _TerminalEmpty()
                          : ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                              itemCount: visible.length + 1,
                              itemBuilder: (_, int index) {
                                if (index == 0) {
                                  return _TerminalPromptLine(
                                    paused: _pausedView,
                                    query: _query,
                                  );
                                }

                                return _TerminalLogLine(
                                  entry: visible[index - 1],
                                  highlightQuery: _query,
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<AppConsoleEntry> _filterEntries(List<AppConsoleEntry> entries) {
    final String q = _query.trim().toLowerCase();

    return entries.where((AppConsoleEntry entry) {
      if (_filter != null && entry.level != _filter) return false;
      if (q.isEmpty) return true;
      return entry.searchText.contains(q);
    }).toList(growable: false);
  }
}

class _ConsoleCounts {
  const _ConsoleCounts({
    required this.total,
    required this.info,
    required this.success,
    required this.warning,
    required this.error,
  });

  final int total;
  final int info;
  final int success;
  final int warning;
  final int error;

  Color get statusColor {
    if (error > 0) return const Color(0xFFFF453A);
    if (warning > 0) return const Color(0xFFFFD60A);
    return const Color(0xFF32D74B);
  }

  String get statusText {
    if (error > 0) return 'errors:$error';
    if (warning > 0) return 'warnings:$warning';
    return 'online';
  }

  static _ConsoleCounts from(List<AppConsoleEntry> entries) {
    int info = 0;
    int success = 0;
    int warning = 0;
    int error = 0;

    for (final AppConsoleEntry entry in entries) {
      switch (entry.level) {
        case AppConsoleLevel.info:
          info++;
        case AppConsoleLevel.success:
          success++;
        case AppConsoleLevel.warning:
          warning++;
        case AppConsoleLevel.error:
          error++;
      }
    }

    return _ConsoleCounts(
      total: entries.length,
      info: info,
      success: success,
      warning: warning,
      error: error,
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.expanded,
    required this.statusColor,
    required this.entryCount,
    required this.counts,
    required this.onToggle,
  });

  final bool expanded;
  final Color statusColor;
  final int entryCount;
  final _ConsoleCounts counts;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: expanded ? 0.08 : 0.0),
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            const _TerminalWindowDots(),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: <Widget>[
                    Text(
                      'trackpro@console',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      ' ~ ${_runtimeMode.toLowerCase()} · ${counts.statusText} · $entryCount logs',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              duration: const Duration(milliseconds: 180),
              turns: expanded ? 0.5 : 0,
              child: Icon(
                CupertinoIcons.chevron_down,
                color: Colors.white.withValues(alpha: 0.70),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalWindowDots extends StatelessWidget {
  const _TerminalWindowDots();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        _Dot(color: Color(0xFFFF453A)),
        SizedBox(width: 5),
        _Dot(color: Color(0xFFFFD60A)),
        SizedBox(width: 5),
        _Dot(color: Color(0xFF32D74B)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 10, height: 10),
    );
  }
}

class _TerminalToolbar extends StatelessWidget {
  const _TerminalToolbar({
    required this.filter,
    required this.tail,
    required this.pausedView,
    required this.largeView,
    required this.apiPanelOpen,
    required this.queryController,
    required this.apiUrlController,
    required this.apiBodyController,
    required this.apiMethod,
    required this.apiLoading,
    required this.lastApiResult,
    required this.onApiPanelChanged,
    required this.onApiMethodChanged,
    required this.onApiFetch,
    required this.onFilterChanged,
    required this.onTailChanged,
    required this.onPausedChanged,
    required this.onLargeViewChanged,
    required this.onCopy,
    required this.onTest,
    required this.onClear,
  });

  final AppConsoleLevel? filter;
  final bool tail;
  final bool pausedView;
  final bool largeView;
  final bool apiPanelOpen;
  final TextEditingController queryController;
  final TextEditingController apiUrlController;
  final TextEditingController apiBodyController;
  final String apiMethod;
  final bool apiLoading;
  final AppConsoleApiResult? lastApiResult;
  final ValueChanged<bool> onApiPanelChanged;
  final ValueChanged<String> onApiMethodChanged;
  final VoidCallback onApiFetch;
  final ValueChanged<AppConsoleLevel?> onFilterChanged;
  final ValueChanged<bool> onTailChanged;
  final ValueChanged<bool> onPausedChanged;
  final ValueChanged<bool> onLargeViewChanged;
  final VoidCallback onCopy;
  final VoidCallback onTest;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      child: Column(
        children: <Widget>[
          _TerminalSearchField(controller: queryController),
          const SizedBox(height: 8),
          _ApiFetchToggle(
            open: apiPanelOpen,
            onTap: () => onApiPanelChanged(!apiPanelOpen),
          ),
          if (apiPanelOpen) ...<Widget>[
            const SizedBox(height: 8),
            _ApiFetchPanel(
              urlController: apiUrlController,
              bodyController: apiBodyController,
              method: apiMethod,
              loading: apiLoading,
              result: lastApiResult,
              onMethodChanged: onApiMethodChanged,
              onFetch: onApiFetch,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _TerminalButton(
                  text: 'copy',
                  icon: CupertinoIcons.doc_on_doc,
                  color: const Color(0xFF64D2FF),
                  onTap: onCopy,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TerminalButton(
                  text: 'test',
                  icon: CupertinoIcons.play_circle,
                  color: const Color(0xFFFFD60A),
                  onTap: onTest,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _TerminalButton(
                  text: 'clear',
                  icon: CupertinoIcons.trash,
                  color: const Color(0xFFFF453A),
                  onTap: onClear,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: <Widget>[
                _TerminalFilter(
                  text: 'all',
                  selected: filter == null,
                  color: Colors.white,
                  onTap: () => onFilterChanged(null),
                ),
                _TerminalFilter(
                  text: 'info',
                  selected: filter == AppConsoleLevel.info,
                  color: const Color(0xFF64D2FF),
                  onTap: () => onFilterChanged(AppConsoleLevel.info),
                ),
                _TerminalFilter(
                  text: 'ok',
                  selected: filter == AppConsoleLevel.success,
                  color: const Color(0xFF32D74B),
                  onTap: () => onFilterChanged(AppConsoleLevel.success),
                ),
                _TerminalFilter(
                  text: 'warn',
                  selected: filter == AppConsoleLevel.warning,
                  color: const Color(0xFFFFD60A),
                  onTap: () => onFilterChanged(AppConsoleLevel.warning),
                ),
                _TerminalFilter(
                  text: 'err',
                  selected: filter == AppConsoleLevel.error,
                  color: const Color(0xFFFF453A),
                  onTap: () => onFilterChanged(AppConsoleLevel.error),
                ),
                _TerminalToggle(
                  text: 'fetched',
                  selected:
                      queryController.text.toLowerCase().contains('fetched'),
                  icon: CupertinoIcons.arrow_down_doc_fill,
                  color: const Color(0xFF32D74B),
                  onTap: () {
                    if (queryController.text
                        .toLowerCase()
                        .contains('fetched')) {
                      queryController.clear();
                    } else {
                      queryController.text = 'fetched';
                      queryController.selection = TextSelection.fromPosition(
                        TextPosition(offset: queryController.text.length),
                      );
                    }
                  },
                ),
                _TerminalToggle(
                  text: 'tail',
                  selected: tail,
                  icon: tail
                      ? CupertinoIcons.arrow_down_circle_fill
                      : CupertinoIcons.arrow_down_circle,
                  color: const Color(0xFF32D74B),
                  onTap: () => onTailChanged(!tail),
                ),
                _TerminalToggle(
                  text: pausedView ? 'paused' : 'live',
                  selected: pausedView,
                  icon: pausedView
                      ? CupertinoIcons.pause_circle_fill
                      : CupertinoIcons.play_circle_fill,
                  color: const Color(0xFFFFD60A),
                  onTap: () => onPausedChanged(!pausedView),
                ),
                _TerminalToggle(
                  text: largeView ? 'large' : 'small',
                  selected: largeView,
                  icon: largeView
                      ? CupertinoIcons.arrow_down_right_arrow_up_left
                      : CupertinoIcons.arrow_up_left_arrow_down_right,
                  color: const Color(0xFF64D2FF),
                  onTap: () => onLargeViewChanged(!largeView),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalSearchField extends StatelessWidget {
  const _TerminalSearchField({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: 'grep logs...',
      prefix: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Text(
          r'$',
          style: TextStyle(
            color: const Color(0xFF32D74B).withValues(alpha: 0.95),
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ),
      suffix: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, TextEditingValue value, __) {
          if (value.text.isEmpty) return const SizedBox.shrink();

          return CupertinoButton(
            padding: const EdgeInsets.only(right: 8),
            minSize: 0,
            onPressed: controller.clear,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Colors.white.withValues(alpha: 0.42),
              size: 16,
            ),
          );
        },
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      cursorColor: const Color(0xFF32D74B),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        fontFamily: 'monospace',
      ),
      placeholderStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.32),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }
}

class _ApiFetchToggle extends StatelessWidget {
  const _ApiFetchToggle({
    required this.open,
    required this.onTap,
  });

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        open ? const Color(0xFF32D74B) : const Color(0xFF64D2FF);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: <Widget>[
            Text(
              r'$',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 7),
            Icon(
              open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
              color: color,
              size: 13,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                open
                    ? 'api fetch panel open'
                    : 'open api fetch: GET POST DELETE OPTIONS',
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiFetchPanel extends StatelessWidget {
  const _ApiFetchPanel({
    required this.urlController,
    required this.bodyController,
    required this.method,
    required this.loading,
    required this.result,
    required this.onMethodChanged,
    required this.onFetch,
  });

  final TextEditingController urlController;
  final TextEditingController bodyController;
  final String method;
  final bool loading;
  final AppConsoleApiResult? result;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onFetch;

  @override
  Widget build(BuildContext context) {
    final bool showBody = method == 'POST' || method == 'DELETE';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _ApiMethodChip(
                value: 'GET',
                selected: method == 'GET',
                color: const Color(0xFF64D2FF),
                onTap: () => onMethodChanged('GET'),
              ),
              _ApiMethodChip(
                value: 'POST',
                selected: method == 'POST',
                color: const Color(0xFF32D74B),
                onTap: () => onMethodChanged('POST'),
              ),
              _ApiMethodChip(
                value: 'DELETE',
                selected: method == 'DELETE',
                color: const Color(0xFFFF453A),
                onTap: () => onMethodChanged('DELETE'),
              ),
              _ApiMethodChip(
                value: 'OPTIONS',
                selected: method == 'OPTIONS',
                color: const Color(0xFFFFD60A),
                onTap: () => onMethodChanged('OPTIONS'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ApiTextField(
            controller: urlController,
            placeholder: 'https://api.example.com/data',
            prefix: 'url',
            minLines: 1,
            maxLines: 1,
          ),
          if (showBody) ...<Widget>[
            const SizedBox(height: 8),
            _ApiTextField(
              controller: bodyController,
              placeholder: '{"key":"value"}',
              prefix: 'json',
              minLines: 2,
              maxLines: 4,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _ApiResultPreview(result: result),
              ),
              const SizedBox(width: 8),
              _ApiSendButton(
                loading: loading,
                method: method,
                onTap: onFetch,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApiMethodChip extends StatelessWidget {
  const _ApiMethodChip({
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String value;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 5),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.055),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color:
                      selected ? color : Colors.white.withValues(alpha: 0.46),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiTextField extends StatelessWidget {
  const _ApiTextField({
    required this.controller,
    required this.placeholder,
    required this.prefix,
    required this.minLines,
    required this.maxLines,
  });

  final TextEditingController controller;
  final String placeholder;
  final String prefix;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      placeholder: placeholder,
      prefix: Padding(
        padding: const EdgeInsets.only(left: 9),
        child: Text(
          '$prefix:',
          style: TextStyle(
            color: const Color(0xFF64D2FF).withValues(alpha: 0.85),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      cursorColor: const Color(0xFF32D74B),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.5,
        height: 1.2,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
      placeholderStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.30),
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF050608),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
    );
  }
}

class _ApiSendButton extends StatelessWidget {
  const _ApiSendButton({
    required this.loading,
    required this.method,
    required this.onTap,
  });

  final bool loading;
  final String method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        loading ? const Color(0xFFFFD60A) : const Color(0xFF32D74B);

    return CupertinoButton(
      minSize: 0,
      padding: EdgeInsets.zero,
      onPressed: loading ? null : onTap,
      child: Container(
        height: 34,
        width: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: <Widget>[
              if (loading)
                const CupertinoActivityIndicator(radius: 6)
              else
                Icon(CupertinoIcons.paperplane_fill, color: color, size: 12),
              const SizedBox(width: 6),
              Text(
                loading ? 'wait' : method,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiResultPreview extends StatelessWidget {
  const _ApiResultPreview({
    required this.result,
  });

  final AppConsoleApiResult? result;

  @override
  Widget build(BuildContext context) {
    final AppConsoleApiResult? r = result;
    if (r == null) {
      return const _MiniTerminalText('status: idle');
    }

    final Color color =
        r.ok ? const Color(0xFF32D74B) : const Color(0xFFFF453A);
    final String text = r.error != null
        ? 'error: ${r.error}'
        : 'status:${r.statusCode} time:${r.elapsedMs}ms';

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _TerminalMetaBar extends StatelessWidget {
  const _TerminalMetaBar({
    required this.counts,
    required this.visibleCount,
    required this.filter,
    required this.query,
  });

  final _ConsoleCounts counts;
  final int visibleCount;
  final AppConsoleLevel? filter;
  final String query;

  @override
  Widget build(BuildContext context) {
    final String filterText = filter?.name ?? 'all';
    final String queryText = query.trim().isEmpty ? '-' : query.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _TerminalMetaItem(label: 'mode', value: _runtimeMode),
              _TerminalMetaItem(label: 'platform', value: _platformName),
              _TerminalMetaItem(
                label: 'visible',
                value: '$visibleCount/${counts.total}',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              _CountPill(
                  label: 'info',
                  value: counts.info,
                  color: const Color(0xFF64D2FF)),
              _CountPill(
                  label: 'ok',
                  value: counts.success,
                  color: const Color(0xFF32D74B)),
              _CountPill(
                  label: 'warn',
                  value: counts.warning,
                  color: const Color(0xFFFFD60A)),
              _CountPill(
                  label: 'err',
                  value: counts.error,
                  color: const Color(0xFFFF453A)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniTerminalText('filter:$filterText'),
              ),
              Expanded(
                child: _MiniTerminalText('grep:$queryText'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerminalMetaItem extends StatelessWidget {
  const _TerminalMetaItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: <TextSpan>[
              TextSpan(
                text: '$label:',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(color: Color(0xFF32D74B)),
              ),
            ],
          ),
          maxLines: 1,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$label:$value',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTerminalText extends StatelessWidget {
  const _MiniTerminalText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _TerminalLogLine extends StatelessWidget {
  const _TerminalLogLine({
    required this.entry,
    required this.highlightQuery,
  });

  final AppConsoleEntry entry;
  final String highlightQuery;

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? data = entry.data;
    final bool hasData = data != null && data.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: entry.level == AppConsoleLevel.error
              ? entry.color.withValues(alpha: 0.035)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '${entry.timeText} ',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                ),
                TextSpan(
                  text: '${entry.levelText.padRight(4)} ',
                  style: TextStyle(
                    color: entry.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: '[${entry.tag}] ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: entry.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasData)
                  TextSpan(
                    text: '\n  ${_compactData(data)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.46),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.22,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  static String _compactData(Map<String, Object?> data) {
    final String raw = data.toString().replaceAll('\n', ' ');
    if (raw.length <= 180) return raw;
    return '${raw.substring(0, 180)}...';
  }
}

class _TerminalPromptLine extends StatelessWidget {
  const _TerminalPromptLine({
    required this.paused,
    required this.query,
  });

  final bool paused;
  final String query;

  @override
  Widget build(BuildContext context) {
    final String command = query.trim().isEmpty
        ? 'watch --app TrackProAI'
        : 'grep "${query.trim()}"';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Row(
        children: <Widget>[
          const Text(
            r'$',
            style: TextStyle(
              color: Color(0xFF32D74B),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              paused ? '$command --paused' : command,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (!paused) const _Cursor(),
        ],
      ),
    );
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> {
  bool _show = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 620),
      (_) {
        if (!mounted) return;
        setState(() => _show = !_show);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: 7,
        height: 13,
        color: const Color(0xFF32D74B),
      ),
    );
  }
}

class _TerminalButton extends StatelessWidget {
  const _TerminalButton({
    required this.text,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  r'$',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 5),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalFilter extends StatelessWidget {
  const _TerminalFilter({
    required this.text,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TerminalSmallButton(
      text: text,
      selected: selected,
      color: color,
      onTap: onTap,
    );
  }
}

class _TerminalToggle extends StatelessWidget {
  const _TerminalToggle({
    required this.text,
    required this.selected,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TerminalSmallButton(
      text: text,
      selected: selected,
      color: color,
      icon: icon,
      onTap: onTap,
    );
  }
}

class _TerminalSmallButton extends StatelessWidget {
  const _TerminalSmallButton({
    required this.text,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String text;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? color : Colors.white.withValues(alpha: 0.46);

    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.11)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: fg, size: 12),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  color: fg,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalEmpty extends StatelessWidget {
  const _TerminalEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'no output',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

String get _runtimeMode {
  if (kReleaseMode) return 'Release';
  if (kProfileMode) return 'Profile';
  return 'Debug';
}

String get _platformName {
  if (kIsWeb) return 'Web';

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iOS';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.macOS:
      return 'macOS';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.fuchsia:
      return 'Fuchsia';
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0B0D10),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: const Color(0xFF32D74B).withValues(alpha: 0.25),
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF32D74B),
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
}
