import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip_data.dart';
import '../models/weather_data.dart';
import 'settings_service.dart';

class AiService {
  AiService._internal();

  static final AiService instance = AiService._internal();

  static const String _endpointUrl =
      'https://bot-voice-sqnz.onrender.com/ai-assistant';

  static final Uri _endpointUri = Uri.parse(_endpointUrl);

  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxHistoryItems = 20;
  static const int _maxPromptChars = 12000;
  static const int _maxUserQueryChars = 1500;

  http.Client? _client;

  http.Client get _httpClient {
    _client ??= http.Client();
    return _client!;
  }

  /// Analyzes trip data with optional weather context.
  Future<String> analyzeTrip(
    TripSummary summary, {
    WeatherData? weather,
  }) async {
    final SettingsService settings = SettingsService.instance;

    final String distance =
        settings.toDisplayDistance(summary.distanceMiles).toStringAsFixed(2);

    final int avgSpeed = settings.toDisplaySpeed(summary.avgSpeedMph).round();
    final int maxSpeed = settings.toDisplaySpeed(summary.maxSpeedMph).round();

    final String weatherLine = weather == null
        ? ''
        : '- Weather: ${weather.condition}, '
            '${weather.temperature.round()}${settings.useKmh ? "°C" : "°F"}, '
            'wind ${_formatWind(weather.windSpeed, settings)}\n';

    final String prompt = _limitText('''
You are "TrackPro AI," a professional driving coach.

TRIP DATA:
- Distance: $distance ${settings.distanceUnit}
- Avg Speed: $avgSpeed ${settings.speedUnit}
- Max Speed: $maxSpeed ${settings.speedUnit}
- Duration: ${summary.formattedTotalTime}
- Stopped Time: ${summary.formattedStoppedTime}
- Moving Time: ${summary.formattedMovingTime}
$weatherLine
TASK:
1. Provide a Safety Score out of 100.
2. Provide an Efficiency Score out of 100.
3. Give 2 highly specific insights.
4. Give 1 practical improvement tip.

FORMATTING RULES:
- Use **bold** for all scores and important numbers.
- Use bullet points for insights.
- Be concise.
''');

    return _sendAiRequest(
      message: prompt,
      history: const <Map<String, String>>[],
      timeoutMessage: 'AI Link timeout. The server took too long to respond.',
      networkMessage: 'Network error. Please check your internet connection.',
      fallbackMessage: 'AI Link offline. Please check your data connection.',
    );
  }

  /// Chat with history.
  Future<String> chatWithAi(
    TripSummary summary,
    String query,
    List<Map<String, String>> history,
  ) async {
    final SettingsService settings = SettingsService.instance;

    final String safeQuery = _limitText(
      query.trim(),
      maxChars: _maxUserQueryChars,
    );

    if (safeQuery.isEmpty) {
      return 'Please type a question first.';
    }

    final String distance =
        settings.toDisplayDistance(summary.distanceMiles).toStringAsFixed(2);

    final int avgSpeed = settings.toDisplaySpeed(summary.avgSpeedMph).round();
    final int maxSpeed = settings.toDisplaySpeed(summary.maxSpeedMph).round();

    final String prompt = _limitText('''
You are TrackPro AI, a helpful driving and trip coach.

CURRENT TRIP CONTEXT:
- Distance: $distance ${settings.distanceUnit}
- Avg Speed: $avgSpeed ${settings.speedUnit}
- Max Speed: $maxSpeed ${settings.speedUnit}
- Duration: ${summary.formattedTotalTime}
- Stopped Time: ${summary.formattedStoppedTime}
- Moving Time: ${summary.formattedMovingTime}

USER QUESTION:
$safeQuery

ANSWER RULES:
- Answer clearly and practically.
- Use the trip data when relevant.
- If the question asks for safety, mention safe driving advice.
- Be concise unless the user asks for detail.
''');

    return _sendAiRequest(
      message: prompt,
      history: _sanitizeHistory(history),
      timeoutMessage: 'Request timed out. The AI took too long to respond.',
      networkMessage: 'Network error. Please check your internet connection.',
      fallbackMessage: 'Chat error. Please check your connection.',
    );
  }

  Future<String> _sendAiRequest({
    required String message,
    required List<Map<String, String>> history,
    required String timeoutMessage,
    required String networkMessage,
    required String fallbackMessage,
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
            }),
          )
          .timeout(_requestTimeout);

      return _parseAiResponse(response);
    } on TimeoutException {
      return timeoutMessage;
    } on http.ClientException catch (e, st) {
      debugPrint('AiService network error: $e\n$st');
      return networkMessage;
    } on FormatException catch (e, st) {
      debugPrint('AiService JSON format error: $e\n$st');
      return 'AI returned an invalid response. Please try again.';
    } catch (e, st) {
      debugPrint('AiService request failed: $e\n$st');
      return fallbackMessage;
    }
  }

  String _parseAiResponse(http.Response response) {
    final int statusCode = response.statusCode;
    final String body = response.body.trim();

    if (statusCode < 200 || statusCode >= 300) {
      return 'Server error: $statusCode';
    }

    if (body.isEmpty) {
      return 'Received empty response from AI.';
    }

    final dynamic decoded = jsonDecode(body);

    if (decoded is! Map) {
      return 'AI returned an unexpected response format.';
    }

    final Map<String, dynamic> data = decoded.map(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>(
        key.toString(),
        value,
      ),
    );

    final bool ok = data['ok'] == true;

    if (!ok) {
      final String error = data['error']?.toString().trim() ?? '';
      return error.isEmpty
          ? 'Analysis error: Unknown error'
          : 'Analysis error: $error';
    }

    final String reply = _extractReply(data);

    if (reply.trim().isEmpty) {
      return 'Received empty response from AI.';
    }

    return reply.trim();
  }

  String _extractReply(Map<String, dynamic> data) {
    final dynamic reply = data['reply'] ??
        data['message'] ??
        data['text'] ??
        data['content'] ??
        data['response'];

    if (reply == null) return '';

    if (reply is String) return reply;

    if (reply is Map) {
      final dynamic nested =
          reply['content'] ?? reply['text'] ?? reply['reply'];
      return nested?.toString() ?? '';
    }

    return reply.toString();
  }

  List<Map<String, String>> _sanitizeHistory(
      List<Map<String, String>> history) {
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
        'content': _limitText(content, maxChars: 2000),
      });
    }

    if (cleaned.length <= _maxHistoryItems) {
      return List<Map<String, String>>.unmodifiable(cleaned);
    }

    return List<Map<String, String>>.unmodifiable(
      cleaned.sublist(cleaned.length - _maxHistoryItems),
    );
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

  /// Closes the persistent HTTP client.
  ///
  /// Safe to call when the app is shutting down. The next request will recreate
  /// the client automatically.
  void dispose() {
    _client?.close();
    _client = null;
  }
}
