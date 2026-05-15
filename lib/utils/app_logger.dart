import 'package:flutter/foundation.dart';

enum AppLogLevel {
  ok,
  info,
  warn,
  error,
}

class AppLogger {
  const AppLogger._();

  static bool enabled = true;

  static void ok(String tag, String message, {Object? data}) {
    _write(AppLogLevel.ok, tag, message, data: data);
  }

  static void info(String tag, String message, {Object? data}) {
    _write(AppLogLevel.info, tag, message, data: data);
  }

  static void warn(String tag, String message, {Object? data}) {
    _write(AppLogLevel.warn, tag, message, data: data);
  }

  static void err(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? data,
  }) {
    _write(
      AppLogLevel.error,
      tag,
      message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _write(
    AppLogLevel level,
    String tag,
    String message, {
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled || kReleaseMode) return;

    final String levelText = switch (level) {
      AppLogLevel.ok => 'OK',
      AppLogLevel.info => 'INFO',
      AppLogLevel.warn => 'WARN',
      AppLogLevel.error => 'ERR',
    };

    final StringBuffer buffer = StringBuffer()
      ..write('[$levelText]')
      ..write('[$tag] ')
      ..write(message);

    if (data != null) buffer.write(' {$data}');
    if (error != null) buffer.write(' error=$error');

    debugPrint(buffer.toString());

    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
