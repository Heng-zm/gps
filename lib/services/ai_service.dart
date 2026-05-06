import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip_data.dart';
import '../models/weather_data.dart';
import 'settings_service.dart';

class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  static const String _endpointUrl =
      'https://bot-voice-sqnz.onrender.com/ai-assistant';

  /// Analyzes trip data with environmental context
  Future<String> analyzeTrip(TripSummary s, {WeatherData? weather}) async {
    final settings = SettingsService.instance;

    final prompt = '''
You are "TrackPro AI," a professional driving coach.

TRIP DATA:
- Distance: ${settings.toDisplayDistance(s.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}
- Avg Speed: ${settings.toDisplaySpeed(s.avgSpeedMph).toInt()} ${settings.speedUnit}
- Max Speed: ${settings.toDisplaySpeed(s.maxSpeedMph).toInt()} ${settings.speedUnit}
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
      final response = await http
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': prompt, 'stream': false}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true) return data['reply'] as String;
        return 'Analysis error: ${data['error']}';
      }
      return 'Server error: ${response.statusCode}';
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
    final prompt = 'The user is asking about a trip of '
        '${s.distanceMiles.toStringAsFixed(2)} miles. '
        'Answer helpfully.\n\nQuestion: $query';

    try {
      final response = await http
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': prompt,
              'history': history,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true) return data['reply'] as String;
        return "I'm sorry, I couldn't process that: ${data['error']}";
      }
      return 'Server error: ${response.statusCode}';
    } catch (e) {
      return 'Chat error. Please check your connection.';
    }
  }
}
