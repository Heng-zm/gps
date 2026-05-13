import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip_data.dart';
import '../models/weather_data.dart';
import 'settings_service.dart';

/// TrackPro AI service.
///
/// Optimized version:
/// - retry once on temporary timeout/server/network issues
/// - stronger response parsing for multiple backend response formats
/// - route quality / point density / GPS accuracy context
/// - local fallback analysis when the remote AI endpoint is unavailable
/// - safer prompt/history limits
/// - persistent HTTP client with explicit dispose()
class AiService {
  AiService._internal();

  static final AiService instance = AiService._internal();

  static const String _endpointUrl =
      'https://bot-voice-sqnz.onrender.com/ai-assistant';

  static final Uri _endpointUri = Uri.parse(_endpointUrl);

  static const Duration _requestTimeout = Duration(seconds: 28);
  static const Duration _retryDelay = Duration(milliseconds: 650);

  static const int _maxHistoryItems = 20;
  static const int _maxPromptChars = 12000;
  static const int _maxUserQueryChars = 1500;
  static const int _maxHistoryItemChars = 1800;

  http.Client? _client;

  http.Client get _httpClient {
    _client ??= http.Client();
    return _client!;
  }

  Future<String> analyzeTrip(
    TripSummary summary, {
    WeatherData? weather,
  }) async {
    final SettingsService settings = SettingsService.instance;
    final _TripAiContext ctx = _TripAiContext.fromSummary(summary, settings);

    final String weatherLine = weather == null
        ? '- Weather: Not available\n'
        : '- Weather: ${weather.condition}, '
            '${weather.temperature.round()}${settings.useKmh ? "°C" : "°F"}, '
            'wind ${_formatWind(weather.windSpeed, settings)}\n';

    final String prompt = _limitText('''
You are "TrackPro AI", a professional driving, riding, and GPS route coach.

TRIP DATA:
- Distance: ${ctx.distanceText}
- Avg Speed: ${ctx.avgSpeedText}
- Max Speed: ${ctx.maxSpeedText}
- Duration: ${summary.formattedTotalTime}
- Stopped Time: ${summary.formattedStoppedTime}
- Moving Time: ${summary.formattedMovingTime}
- Route Points: ${ctx.pointCount}
- Point Density: ${ctx.pointDensityText}
- GPS Accuracy: ${ctx.accuracyText}
- Route Quality: ${ctx.routeQualityScore}/100 (${ctx.routeQualityLabel})
- Stopped Ratio: ${ctx.stoppedPercentText}
$weatherLine
TASK:
1. Provide a Safety Score out of 100.
2. Provide an Efficiency Score out of 100.
3. Give 2 highly specific insights based on the numbers above.
4. Give 1 practical improvement tip.

FORMATTING RULES:
- Use **bold** for all scores and important numbers.
- Use bullet points for insights.
- Be concise.
- Do not invent location names or weather details that are not provided.
''');

    return _sendAiRequest(
      message: prompt,
      history: const <Map<String, String>>[],
      timeoutMessage: _localAnalysis(summary, weather: weather),
      networkMessage: _localAnalysis(summary, weather: weather),
      fallbackMessage: _localAnalysis(summary, weather: weather),
    );
  }

  Future<String> chatWithAi(
    TripSummary summary,
    String query,
    List<Map<String, String>> history,
  ) async {
    final SettingsService settings = SettingsService.instance;
    final _TripAiContext ctx = _TripAiContext.fromSummary(summary, settings);

    final String safeQuery = _limitText(
      query.trim(),
      maxChars: _maxUserQueryChars,
    );

    if (safeQuery.isEmpty) {
      return 'Please type a question first.';
    }

    final String prompt = _limitText('''
You are TrackPro AI, a helpful driving and trip coach.

CURRENT TRIP CONTEXT:
- Distance: ${ctx.distanceText}
- Avg Speed: ${ctx.avgSpeedText}
- Max Speed: ${ctx.maxSpeedText}
- Duration: ${summary.formattedTotalTime}
- Stopped Time: ${summary.formattedStoppedTime}
- Moving Time: ${summary.formattedMovingTime}
- Route Points: ${ctx.pointCount}
- Point Density: ${ctx.pointDensityText}
- GPS Accuracy: ${ctx.accuracyText}
- Route Quality: ${ctx.routeQualityScore}/100 (${ctx.routeQualityLabel})
- Stopped Ratio: ${ctx.stoppedPercentText}

USER QUESTION:
$safeQuery

ANSWER RULES:
- Answer clearly and practically.
- Use the trip data when relevant.
- If the question asks for safety, mention safe driving advice.
- If data is missing, say what is missing instead of guessing.
- Be concise unless the user asks for detail.
''');

    return _sendAiRequest(
      message: prompt,
      history: _sanitizeHistory(history),
      timeoutMessage: _localChatFallback(summary, safeQuery),
      networkMessage: _localChatFallback(summary, safeQuery),
      fallbackMessage: _localChatFallback(summary, safeQuery),
    );
  }

  Future<String> _sendAiRequest({
    required String message,
    required List<Map<String, String>> history,
    required String timeoutMessage,
    required String networkMessage,
    required String fallbackMessage,
  }) async {
    final _AiRequestResult first = await _trySendAiRequest(
      message: message,
      history: history,
    );

    if (first.reply != null) return first.reply!;

    if (first.retryable) {
      await Future<void>.delayed(_retryDelay);

      final _AiRequestResult second = await _trySendAiRequest(
        message: message,
        history: history,
      );

      if (second.reply != null) return second.reply!;

      return _fallbackForError(
        second.errorType,
        timeoutMessage: timeoutMessage,
        networkMessage: networkMessage,
        fallbackMessage: fallbackMessage,
      );
    }

    return _fallbackForError(
      first.errorType,
      timeoutMessage: timeoutMessage,
      networkMessage: networkMessage,
      fallbackMessage: fallbackMessage,
    );
  }

  Future<_AiRequestResult> _trySendAiRequest({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    try {
      final http.Response response = await _httpClient
          .post(
            _endpointUri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'message': message,
              'history': history,
              'stream': false,
              'app': 'TrackPro AI',
              'client': 'flutter',
            }),
          )
          .timeout(_requestTimeout);

      final _ParsedAiResponse parsed = _parseAiResponse(response);

      if (parsed.reply != null) {
        return _AiRequestResult.success(parsed.reply!);
      }

      return _AiRequestResult.failure(
        parsed.errorType,
        retryable: parsed.retryable,
      );
    } on TimeoutException catch (e, st) {
      debugPrint('AiService timeout: $e\n$st');
      return const _AiRequestResult.failure(
        _AiErrorType.timeout,
        retryable: true,
      );
    } on http.ClientException catch (e, st) {
      debugPrint('AiService network error: $e\n$st');
      return const _AiRequestResult.failure(
        _AiErrorType.network,
        retryable: true,
      );
    } on FormatException catch (e, st) {
      debugPrint('AiService JSON format error: $e\n$st');
      return const _AiRequestResult.failure(
        _AiErrorType.invalidResponse,
        retryable: false,
      );
    } catch (e, st) {
      debugPrint('AiService request failed: $e\n$st');
      return const _AiRequestResult.failure(
        _AiErrorType.unknown,
        retryable: true,
      );
    }
  }

  _ParsedAiResponse _parseAiResponse(http.Response response) {
    final int statusCode = response.statusCode;
    final String body = response.body.trim();

    if (statusCode == 408 ||
        statusCode == 409 ||
        statusCode == 425 ||
        statusCode == 429 ||
        (statusCode >= 500 && statusCode <= 599)) {
      debugPrint('AiService temporary server error: $statusCode $body');
      return const _ParsedAiResponse.failure(
        _AiErrorType.server,
        retryable: true,
      );
    }

    if (statusCode < 200 || statusCode >= 300) {
      debugPrint('AiService server error: $statusCode $body');
      return const _ParsedAiResponse.failure(
        _AiErrorType.server,
        retryable: false,
      );
    }

    if (body.isEmpty) {
      return const _ParsedAiResponse.failure(
        _AiErrorType.emptyResponse,
        retryable: true,
      );
    }

    final dynamic decoded = jsonDecode(body);

    if (decoded is String) {
      final String trimmed = decoded.trim();
      return trimmed.isEmpty
          ? const _ParsedAiResponse.failure(_AiErrorType.emptyResponse)
          : _ParsedAiResponse.success(trimmed);
    }

    if (decoded is! Map) {
      return const _ParsedAiResponse.failure(_AiErrorType.invalidResponse);
    }

    final Map<String, dynamic> data = decoded.map(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>(
        key.toString(),
        value,
      ),
    );

    final dynamic okValue = data['ok'] ?? data['success'];
    final bool explicitlyFailed = okValue == false;

    if (explicitlyFailed) {
      final String error = data['error']?.toString().trim() ??
          data['message']?.toString().trim() ??
          'Analysis error: Unknown error';
      debugPrint('AiService backend error: $error');
      return const _ParsedAiResponse.failure(_AiErrorType.server);
    }

    final String reply = _extractReply(data).trim();

    if (reply.isEmpty) {
      return const _ParsedAiResponse.failure(
        _AiErrorType.emptyResponse,
        retryable: true,
      );
    }

    return _ParsedAiResponse.success(reply);
  }

  String _extractReply(Map<String, dynamic> data) {
    final List<Object?> candidates = <Object?>[
      data['reply'],
      data['message'],
      data['text'],
      data['content'],
      data['response'],
      data['answer'],
      data['output'],
      data['result'],
      data['data'],
    ];

    for (final Object? candidate in candidates) {
      final String extracted = _extractText(candidate);
      if (extracted.trim().isNotEmpty) return extracted;
    }

    return '';
  }

  String _extractText(Object? value) {
    if (value == null) return '';

    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    if (value is List) {
      final StringBuffer buffer = StringBuffer();

      for (final Object? item in value) {
        final String text = _extractText(item).trim();
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(text);
        }
      }

      return buffer.toString();
    }

    if (value is Map) {
      final Map<String, dynamic> map = value.map(
        (dynamic key, dynamic nested) => MapEntry<String, dynamic>(
          key.toString(),
          nested,
        ),
      );

      for (final String key in <String>[
        'content',
        'text',
        'reply',
        'message',
        'answer',
        'output',
        'result',
      ]) {
        final String nested = _extractText(map[key]).trim();
        if (nested.isNotEmpty) return nested;
      }

      final String choices = _extractText(map['choices']).trim();
      if (choices.isNotEmpty) return choices;
    }

    return value.toString();
  }

  List<Map<String, String>> _sanitizeHistory(
    List<Map<String, String>> history,
  ) {
    if (history.isEmpty) return const <Map<String, String>>[];

    final List<Map<String, String>> cleaned = <Map<String, String>>[];

    for (final Map<String, String> item in history) {
      final String role = item['role']?.trim() ?? '';
      final String content = item['content']?.trim() ?? '';

      if (content.isEmpty) continue;

      final bool validRole = role == 'user' || role == 'assistant';
      if (!validRole) continue;

      cleaned.add(<String, String>{
        'role': role,
        'content': _limitText(content, maxChars: _maxHistoryItemChars),
      });
    }

    if (cleaned.length <= _maxHistoryItems) {
      return List<Map<String, String>>.unmodifiable(cleaned);
    }

    return List<Map<String, String>>.unmodifiable(
      cleaned.sublist(cleaned.length - _maxHistoryItems),
    );
  }

  String _fallbackForError(
    _AiErrorType type, {
    required String timeoutMessage,
    required String networkMessage,
    required String fallbackMessage,
  }) {
    switch (type) {
      case _AiErrorType.timeout:
        return timeoutMessage;
      case _AiErrorType.network:
        return networkMessage;
      case _AiErrorType.server:
      case _AiErrorType.invalidResponse:
      case _AiErrorType.emptyResponse:
      case _AiErrorType.unknown:
        return fallbackMessage;
    }
  }

  String _localAnalysis(
    TripSummary summary, {
    WeatherData? weather,
  }) {
    final SettingsService settings = SettingsService.instance;
    final _TripAiContext ctx = _TripAiContext.fromSummary(summary, settings);

    final int safetyScore = _estimateSafetyScore(summary, ctx);
    final int efficiencyScore = _estimateEfficiencyScore(summary, ctx);

    final String weatherText = weather == null
        ? ''
        : '\n- Weather note: ${weather.condition}, '
            '${weather.temperature.round()}${settings.useKmh ? "°C" : "°F"}, '
            'wind ${_formatWind(weather.windSpeed, settings)}.';

    return '''
AI Link offline - local trip analysis:

- **Safety Score: $safetyScore/100**
- **Efficiency Score: $efficiencyScore/100**
- Route quality: **${ctx.routeQualityScore}/100 (${ctx.routeQualityLabel})**
- Distance: **${ctx.distanceText}**, average speed **${ctx.avgSpeedText}**, max speed **${ctx.maxSpeedText}**.
- GPS data: ${ctx.pointCount} points, ${ctx.pointDensityText}, accuracy ${ctx.accuracyText}.$weatherText

Tip: Keep GPS accuracy below ±20m and avoid long idle time for a cleaner route summary.
''';
  }

  String _localChatFallback(TripSummary summary, String query) {
    final SettingsService settings = SettingsService.instance;
    final _TripAiContext ctx = _TripAiContext.fromSummary(summary, settings);
    final String lower = query.toLowerCase();

    if (lower.contains('safe') || lower.contains('score')) {
      final int safety = _estimateSafetyScore(summary, ctx);
      return 'AI Link offline. Local safety estimate: **$safety/100**. '
          'Your route quality is **${ctx.routeQualityScore}/100**, max speed was '
          '**${ctx.maxSpeedText}**, and stopped ratio was **${ctx.stoppedPercentText}**.';
    }

    if (lower.contains('gps') || lower.contains('quality')) {
      return 'AI Link offline. Local GPS review: route quality is '
          '**${ctx.routeQualityScore}/100 (${ctx.routeQualityLabel})**, with '
          '${ctx.pointCount} points, ${ctx.pointDensityText}, and accuracy ${ctx.accuracyText}.';
    }

    if (lower.contains('speed')) {
      return 'AI Link offline. Local speed summary: average speed was '
          '**${ctx.avgSpeedText}** and max speed was **${ctx.maxSpeedText}** over '
          '**${ctx.distanceText}**.';
    }

    return 'AI Link offline. Local summary: distance **${ctx.distanceText}**, '
        'average speed **${ctx.avgSpeedText}**, max speed **${ctx.maxSpeedText}**, '
        'route quality **${ctx.routeQualityScore}/100 (${ctx.routeQualityLabel})**.';
  }

  int _estimateSafetyScore(TripSummary summary, _TripAiContext ctx) {
    int score = 92;

    final double maxSpeed = summary.maxSpeedMph;
    final double avgSpeed = summary.avgSpeedMph;

    if (maxSpeed > 90) score -= 18;
    if (maxSpeed > 70) score -= 10;
    if (avgSpeed > 55) score -= 8;
    if (ctx.stoppedRatio > 0.45) score -= 8;
    if (ctx.routeQualityScore < 70) score -= 10;

    return score.clamp(0, 100);
  }

  int _estimateEfficiencyScore(TripSummary summary, _TripAiContext ctx) {
    int score = 88;

    if (ctx.stoppedRatio > 0.30) score -= 12;
    if (ctx.stoppedRatio > 0.50) score -= 12;
    if (summary.avgSpeedMph <= 1.0 && summary.distanceMiles > 0.2) score -= 18;
    if (ctx.routeQualityScore < 60) score -= 8;

    return score.clamp(0, 100);
  }

  String _formatWind(double windSpeed, SettingsService settings) {
    if (settings.useKmh) {
      return '${(windSpeed * 3.6).round()} km/h';
    }

    return '${windSpeed.round()} mph';
  }

  String _limitText(String value, {int maxChars = _maxPromptChars}) {
    if (value.length <= maxChars) return value;

    return '${value.substring(0, maxChars)}\n\n[Text shortened for request size.]';
  }

  void dispose() {
    _client?.close();
    _client = null;
  }
}

class _TripAiContext {
  const _TripAiContext({
    required this.distanceText,
    required this.avgSpeedText,
    required this.maxSpeedText,
    required this.pointCount,
    required this.routeQualityScore,
    required this.routeQualityLabel,
    required this.pointDensityText,
    required this.accuracyText,
    required this.stoppedRatio,
    required this.stoppedPercentText,
  });

  final String distanceText;
  final String avgSpeedText;
  final String maxSpeedText;
  final int pointCount;
  final int routeQualityScore;
  final String routeQualityLabel;
  final String pointDensityText;
  final String accuracyText;
  final double stoppedRatio;
  final String stoppedPercentText;

  static _TripAiContext fromSummary(
    TripSummary summary,
    SettingsService settings,
  ) {
    final String distanceText =
        '${settings.toDisplayDistance(summary.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}';
    final String avgSpeedText =
        '${settings.toDisplaySpeed(summary.avgSpeedMph).round()} ${settings.speedUnit}';
    final String maxSpeedText =
        '${settings.toDisplaySpeed(summary.maxSpeedMph).round()} ${settings.speedUnit}';

    final List<TripPoint> points = summary.points;
    final int pointCount = points.length;

    double accuracySum = 0.0;
    int accuracyCount = 0;
    int weakAccuracy = 0;
    int duplicateLike = 0;
    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double acc = point.accuracyMeters;
      if (acc.isFinite && acc > 0.0) {
        accuracySum += acc;
        accuracyCount++;
        if (acc > 35.0) weakAccuracy++;
      }

      final double lat = point.position.latitude;
      final double lng = point.position.longitude;
      if (lastLat != null &&
          lastLng != null &&
          lat == lastLat &&
          lng == lastLng) {
        duplicateLike++;
      }
      lastLat = lat;
      lastLng = lng;
    }

    final double avgAccuracy =
        accuracyCount == 0 ? 0.0 : accuracySum / accuracyCount;

    int quality = 100;
    if (pointCount < 10) quality -= 16;
    if (pointCount < 5) quality -= 20;
    quality -= (weakAccuracy * 4).clamp(0, 28);
    quality -= (duplicateLike * 3).clamp(0, 18);
    if (avgAccuracy > 10) quality -= 6;
    if (avgAccuracy > 20) quality -= 10;
    if (avgAccuracy > 35) quality -= 14;
    quality = quality.clamp(0, 100);

    final String label;
    if (quality >= 88) {
      label = 'Excellent';
    } else if (quality >= 72) {
      label = 'Good';
    } else if (quality >= 50) {
      label = 'Fair';
    } else {
      label = 'Weak';
    }

    final double density =
        summary.distanceMiles <= 0 ? 0.0 : pointCount / summary.distanceMiles;

    final String densityText = density <= 0.0
        ? 'not enough distance for density'
        : '${density.toStringAsFixed(0)} points/mile';

    final String accuracyText = accuracyCount == 0
        ? 'not available'
        : '±${avgAccuracy.clamp(0.0, 99.0).round()}m average';

    final int totalSeconds = math.max(0, summary.totalTime.inSeconds);
    final int stoppedSeconds =
        summary.stoppedTime.inSeconds.clamp(0, totalSeconds);
    final double stoppedRatio =
        totalSeconds == 0 ? 0.0 : stoppedSeconds / totalSeconds;

    return _TripAiContext(
      distanceText: distanceText,
      avgSpeedText: avgSpeedText,
      maxSpeedText: maxSpeedText,
      pointCount: pointCount,
      routeQualityScore: quality,
      routeQualityLabel: label,
      pointDensityText: densityText,
      accuracyText: accuracyText,
      stoppedRatio: stoppedRatio,
      stoppedPercentText: '${(stoppedRatio * 100).round()}%',
    );
  }
}

enum _AiErrorType {
  timeout,
  network,
  server,
  invalidResponse,
  emptyResponse,
  unknown,
}

class _AiRequestResult {
  const _AiRequestResult._({
    required this.reply,
    required this.errorType,
    required this.retryable,
  });

  const _AiRequestResult.success(String reply)
      : this._(
          reply: reply,
          errorType: _AiErrorType.unknown,
          retryable: false,
        );

  const _AiRequestResult.failure(
    _AiErrorType errorType, {
    bool retryable = false,
  }) : this._(
          reply: null,
          errorType: errorType,
          retryable: retryable,
        );

  final String? reply;
  final _AiErrorType errorType;
  final bool retryable;
}

class _ParsedAiResponse {
  const _ParsedAiResponse._({
    required this.reply,
    required this.errorType,
    required this.retryable,
  });

  const _ParsedAiResponse.success(String reply)
      : this._(
          reply: reply,
          errorType: _AiErrorType.unknown,
          retryable: false,
        );

  const _ParsedAiResponse.failure(
    _AiErrorType errorType, {
    bool retryable = false,
  }) : this._(
          reply: null,
          errorType: errorType,
          retryable: retryable,
        );

  final String? reply;
  final _AiErrorType errorType;
  final bool retryable;
}
