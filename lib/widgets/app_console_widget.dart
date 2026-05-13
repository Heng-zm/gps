import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        kProfileMode,
        kReleaseMode;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// AppConsole — in-app debug console for TrackPro.
///
/// How to use:
///
/// 1) Add this file:
///    lib/widgets/app_console_widget.dart
///
/// 2) Put this widget inside settings_screen.dart:
///
///    import '../widgets/app_console_widget.dart';
///
///    const AppConsoleSettingsCard(),
///
/// 3) Add logs anywhere:
///
///    AppConsole.log('GPS started');
///    AppConsole.success('Trip saved to Supabase');
///    AppConsole.warn('GPS accuracy weak');
///    AppConsole.error('Supabase save failed', error: e, stackTrace: st);
///
/// 4) Optional: capture Flutter framework errors in main.dart:
///
///    FlutterError.onError = (FlutterErrorDetails details) {
///      FlutterError.presentError(details);
///      AppConsole.flutterError(details);
///    };
///
///    PlatformDispatcher.instance.onError = (error, stackTrace) {
///      AppConsole.error('Platform error', error: error, stackTrace: stackTrace);
///      return true;
///    };
///
/// This console is UI-only and stores logs in memory for the current app session.
/// It does not upload logs anywhere.
class AppConsole {
  AppConsole._();

  static final ValueNotifier<List<AppConsoleEntry>> entries =
      ValueNotifier<List<AppConsoleEntry>>(<AppConsoleEntry>[]);

  static const int _maxEntries = 250;

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

  static void clear() {
    entries.value = const <AppConsoleEntry>[];
  }

  static Future<void> copyToClipboard() async {
    final String logs = entries.value.map((AppConsoleEntry e) {
      return e.toPlainText();
    }).join('\n');

    await Clipboard.setData(
      ClipboardData(
        text: logs.isEmpty ? 'TrackPro App Console: no logs.' : logs,
      ),
    );
  }

  static void _add(AppConsoleEntry entry) {
    final List<AppConsoleEntry> next = <AppConsoleEntry>[
      entry,
      ...entries.value,
    ];

    if (next.length > _maxEntries) {
      entries.value = List<AppConsoleEntry>.unmodifiable(
        next.take(_maxEntries),
      );
    } else {
      entries.value = List<AppConsoleEntry>.unmodifiable(next);
    }

    if (kDebugMode) {
      debugPrint(entry.toPlainText());
    }
  }

  static String _trimStack(StackTrace stackTrace) {
    final List<String> lines = stackTrace.toString().split('\n');
    return lines.take(8).join('\n');
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

  Color get color {
    switch (level) {
      case AppConsoleLevel.info:
        return const Color(0xFF4A9EFF);
      case AppConsoleLevel.success:
        return const Color(0xFF32D74B);
      case AppConsoleLevel.warning:
        return const Color(0xFFFFD86B);
      case AppConsoleLevel.error:
        return const Color(0xFFFF453A);
    }
  }

  IconData get icon {
    switch (level) {
      case AppConsoleLevel.info:
        return CupertinoIcons.info_circle_fill;
      case AppConsoleLevel.success:
        return CupertinoIcons.check_mark_circled_solid;
      case AppConsoleLevel.warning:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case AppConsoleLevel.error:
        return CupertinoIcons.xmark_octagon_fill;
    }
  }

  String toPlainText() {
    final String dataText =
        data == null || data!.isEmpty ? '' : ' | data=${data.toString()}';
    return '[$timeText][$tag][${level.name.toUpperCase()}] $message$dataText';
  }
}

/// Compact Settings card. Use this directly inside settings_screen.dart.
class AppConsoleSettingsCard extends StatelessWidget {
  const AppConsoleSettingsCard({
    super.key,
    this.initialExpanded = false,
  });

  final bool initialExpanded;

  @override
  Widget build(BuildContext context) {
    return _ConsoleShell(
      initialExpanded: initialExpanded,
    );
  }
}

class _ConsoleShell extends StatefulWidget {
  const _ConsoleShell({
    required this.initialExpanded,
  });

  final bool initialExpanded;

  @override
  State<_ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<_ConsoleShell> {
  late bool _expanded;
  AppConsoleLevel? _filter;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;

    if (AppConsole.entries.value.isEmpty) {
      AppConsole.log(
        'App console ready',
        tag: 'CONSOLE',
        data: <String, Object?>{
          'mode': kReleaseMode
              ? 'release'
              : kProfileMode
                  ? 'profile'
                  : 'debug',
          'platform': _platformName,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppConsoleEntry>>(
      valueListenable: AppConsole.entries,
      builder: (_, List<AppConsoleEntry> entries, __) {
        final int errorCount = entries
            .where((AppConsoleEntry e) => e.level == AppConsoleLevel.error)
            .length;
        final int warnCount = entries
            .where((AppConsoleEntry e) => e.level == AppConsoleLevel.warning)
            .length;

        final List<AppConsoleEntry> visible = _filter == null
            ? entries
            : entries
                .where((AppConsoleEntry e) => e.level == _filter)
                .toList(growable: false);

        return ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.075),
                    Colors.white.withValues(alpha: 0.035),
                    Colors.white.withValues(alpha: 0.015),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                color: const Color(0xFF111114),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _ConsoleHeader(
                    expanded: _expanded,
                    entryCount: entries.length,
                    errorCount: errorCount,
                    warnCount: warnCount,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      setState(() => _expanded = !_expanded);
                    },
                  ),
                  if (_expanded) ...<Widget>[
                    const Divider(
                      height: 1,
                      color: Color(0x1AFFFFFF),
                    ),
                    _ConsoleTools(
                      filter: _filter,
                      onFilterChanged: (AppConsoleLevel? level) {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = level);
                      },
                    ),
                    _SystemInfoStrip(entryCount: entries.length),
                    SizedBox(
                      height: 320,
                      child: visible.isEmpty
                          ? const _EmptyConsole()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                              physics: const BouncingScrollPhysics(),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) {
                                return const SizedBox(height: 8);
                              },
                              itemBuilder: (_, int index) {
                                return _ConsoleEntryTile(
                                  entry: visible[index],
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
}

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({
    required this.expanded,
    required this.entryCount,
    required this.errorCount,
    required this.warnCount,
    required this.onToggle,
  });

  final bool expanded;
  final int entryCount;
  final int errorCount;
  final int warnCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = errorCount > 0
        ? const Color(0xFFFF453A)
        : warnCount > 0
            ? const Color(0xFFFFD86B)
            : const Color(0xFF32D74B);

    final String statusText = errorCount > 0
        ? '$errorCount errors'
        : warnCount > 0
            ? '$warnCount warnings'
            : 'Running OK';

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.20),
                ),
              ),
              child: Icon(
                CupertinoIcons.chevron_left_slash_chevron_right,
                color: statusColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _ConsoleText(
                    'APP CONSOLE',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _ConsoleText(
                    '$statusText · $entryCount logs',
                    maxLines: 1,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
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

class _ConsoleTools extends StatelessWidget {
  const _ConsoleTools({
    required this.filter,
    required this.onFilterChanged,
  });

  final AppConsoleLevel? filter;
  final ValueChanged<AppConsoleLevel?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _ToolButton(
                  label: 'COPY LOGS',
                  icon: CupertinoIcons.doc_on_doc_fill,
                  color: const Color(0xFF4A9EFF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    AppConsole.copyToClipboard();
                    _showConsoleSnack(context, 'Console logs copied.');
                  },
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ToolButton(
                  label: 'TEST LOG',
                  icon: CupertinoIcons.play_circle_fill,
                  color: const Color(0xFFFFD86B),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    AppConsole.log(
                      'Manual test log',
                      tag: 'TEST',
                      data: <String, Object?>{
                        'time': DateTime.now().toIso8601String(),
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ToolButton(
                  label: 'CLEAR',
                  icon: CupertinoIcons.trash_fill,
                  color: const Color(0xFFFF453A),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    AppConsole.clear();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: <Widget>[
                _FilterChip(
                  label: 'ALL',
                  selected: filter == null,
                  color: Colors.white,
                  onTap: () => onFilterChanged(null),
                ),
                _FilterChip(
                  label: 'INFO',
                  selected: filter == AppConsoleLevel.info,
                  color: const Color(0xFF4A9EFF),
                  onTap: () => onFilterChanged(AppConsoleLevel.info),
                ),
                _FilterChip(
                  label: 'OK',
                  selected: filter == AppConsoleLevel.success,
                  color: const Color(0xFF32D74B),
                  onTap: () => onFilterChanged(AppConsoleLevel.success),
                ),
                _FilterChip(
                  label: 'WARN',
                  selected: filter == AppConsoleLevel.warning,
                  color: const Color(0xFFFFD86B),
                  onTap: () => onFilterChanged(AppConsoleLevel.warning),
                ),
                _FilterChip(
                  label: 'ERROR',
                  selected: filter == AppConsoleLevel.error,
                  color: const Color(0xFFFF453A),
                  onTap: () => onFilterChanged(AppConsoleLevel.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemInfoStrip extends StatelessWidget {
  const _SystemInfoStrip({
    required this.entryCount,
  });

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final String mode = kReleaseMode
        ? 'Release'
        : kProfileMode
            ? 'Profile'
            : 'Debug';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _InfoMini(label: 'MODE', value: mode),
          ),
          Expanded(
            child: _InfoMini(label: 'PLATFORM', value: _platformName),
          ),
          Expanded(
            child: _InfoMini(label: 'LOGS', value: '$entryCount'),
          ),
        ],
      ),
    );
  }
}

class _InfoMini extends StatelessWidget {
  const _InfoMini({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _ConsoleText(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        _ConsoleText(
          value,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ConsoleEntryTile extends StatelessWidget {
  const _ConsoleEntryTile({
    required this.entry,
  });

  final AppConsoleEntry entry;

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? data = entry.data;
    final bool hasData = data != null && data.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: entry.color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.color.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(entry.icon, color: entry.color, size: 16),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _ConsoleText(
                      entry.timeText,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 7),
                    _TagPill(text: entry.tag, color: entry.color),
                  ],
                ),
                const SizedBox(height: 6),
                _ConsoleText(
                  entry.message,
                  maxLines: 3,
                  softWrap: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasData) ...<Widget>[
                  const SizedBox(height: 6),
                  _ConsoleText(
                    data.toString(),
                    maxLines: 4,
                    softWrap: true,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 10,
                      height: 1.25,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: _ConsoleText(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              _ConsoleText(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? color : Colors.white.withValues(alpha: 0.50);

    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: _ConsoleText(
            label,
            maxLines: 1,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _ConsoleText(
        'No console logs yet.',
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConsoleText extends StatelessWidget {
  const _ConsoleText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        softWrap: softWrap,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
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

void _showConsoleSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF4A9EFF),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
}
