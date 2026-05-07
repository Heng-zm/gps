import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../models/trip_data.dart';
import '../models/weather_data.dart';
import 'settings_service.dart';

class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  static const String _endpointUrl =
      'https://bot-voice-sqnz.onrender.com/ai-assistant';
<<<<<<< HEAD

  // PERFORMANCE IMPROVEMENT:
  // Using a persistent client enables HTTP Keep-Alive.
  // This avoids the overhead of establishing a new TCP/TLS connection for every request.
  final http.Client _client = http.Client();
=======
>>>>>>> 88c2e0948bfb8e17fadabe40b0cc4fcc6d18f473

  /// Analyzes trip data with environmental context
  Future<String> analyzeTrip(TripSummary s, {WeatherData? weather}) async {
    final settings = SettingsService.instance;

<<<<<<< HEAD
    // Pre-calculate to keep the prompt template clean
    final distance =
        settings.toDisplayDistance(s.distanceMiles).toStringAsFixed(2);
    final avgSpeed = settings.toDisplaySpeed(s.avgSpeedMph).toInt();
    final maxSpeed = settings.toDisplaySpeed(s.maxSpeedMph).toInt();

    final prompt = '''
You are "TrackPro AI," a professional driving coach.

TRIP DATA:
- Distance: $distance ${settings.distanceUnit}
- Avg Speed: $avgSpeed ${settings.speedUnit}
- Max Speed: $maxSpeed ${settings.speedUnit}
=======
    final prompt = '''
You are "TrackPro AI," a professional driving coach.

TRIP DATA:
- Distance: ${settings.toDisplayDistance(s.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}
- Avg Speed: ${settings.toDisplaySpeed(s.avgSpeedMph).toInt()} ${settings.speedUnit}
- Max Speed: ${settings.toDisplaySpeed(s.maxSpeedMph).toInt()} ${settings.speedUnit}
>>>>>>> 88c2e0948bfb8e17fadabe40b0cc4fcc6d18f473
- Duration: ${s.formattedTotalTime} (Stopped: ${s.formattedStoppedTime})
${weather != null ? "- Weather: ${weather.condition}, ${weather.temperature}°" : ""}

TASK:
1. Provide a "Safety Score" and "Efficiency Score".
2. Give 2 highly specific insights.

FORMATTING RULES:
- Use **Bold** for all numbers and scores.
- Use bullet points for the insights.
- Be concise.
''';

    try {
<<<<<<< HEAD
      // Increased timeout to 30s. LLM servers on platforms like Render
      // often need extra time to wake up or generate tokens.
      final response = await _client
=======
      final response = await http
>>>>>>> 88c2e0948bfb8e17fadabe40b0cc4fcc6d18f473
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': prompt, 'stream': false}),
          )
<<<<<<< HEAD
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          return data['reply']?.toString() ??
              'Received empty response from AI.';
        }
        return 'Analysis error: ${data['error'] ?? 'Unknown error'}';
      }
      return 'Server error: ${response.statusCode}';
    } on TimeoutException {
      return 'AI Link timeout. The server took too long to respond.';
    } on SocketException {
      return 'Network error. Please check your internet connection.';
=======
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true) return data['reply'] as String;
        return 'Analysis error: ${data['error']}';
      }
      return 'Server error: ${response.statusCode}';
>>>>>>> 88c2e0948bfb8e17fadabe40b0cc4fcc6d18f473
    } catch (e) {
      return 'AI Link offline. Please check your data connection.';
    }
  }

  /// Specialized chat with history
  Future<String> chatWithAi(
    TripSummary s,
    String query,
    List<Map<String, String>> history,
  ) async {
<<<<<<< HEAD
    final settings = SettingsService.instance;

    // BUG FIX: Now respects user settings (Metric vs Imperial)
    // instead of hardcoding distanceMiles.
    final distance =
        settings.toDisplayDistance(s.distanceMiles).toStringAsFixed(2);
    final unit = settings.distanceUnit;

    final prompt = 'The user is asking about a trip of $distance $unit. '
        'Answer helpfully.\n\nQuestion: $query';

    try {
      final response = await _client
=======
    final prompt = 'The user is asking about a trip of '
        '${s.distanceMiles.toStringAsFixed(2)} miles. '
        'Answer helpfully.\n\nQuestion: $query';

    try {
      final response = await http
>>>>>>> 88c2e0948bfb8e17fadabe40b0cc4fcc6d18f473
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': prompt,
              'history': history,
              'stream': false,
            }),
          )
<<<<<<< HEAD
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          return data['reply']?.toString() ??
              'Received empty response from AI.';
        }
        return "I'm sorry, I couldn't process that: ${data['error'] ?? 'Unknown error'}";
      }
      return 'Server error: ${response.statusCode}';
    } on TimeoutException {
      return 'Request timed out. The AI took too long to respond.';
    } on SocketException {
      return 'Network error. Please check your internet connection.';
=======
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true) return data['reply'] as String;
        return "I'm sorry, I couldn't process that: ${data['error']}";
      }
      return 'Server error: ${response.statusCode}';
>>>>>>> 88c2e0948bfb8e17fadabe40b0cc4fcc6d18f473
    } catch (e) {
      return 'Chat error. Please check your connection.';
    }
  }

  /// Closes the persistent client when no longer needed
  void dispose() {
    _client.close();
  }
}
