import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip_data.dart';
import '../models/weather_data.dart';
import 'settings_service.dart';

class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  // Your Render endpoint URL
  static const String _endpointUrl = 'https://bot-voice-sqnz.onrender.com/ai-assistant';
  
  // NOTE: If you configured the AI_API_KEY environment variable on Render, 
  // put it here. If not, you can leave it empty.
  static const String _apiKey = 'AIzaSyA_u1xkFG6i1JzT_LrakEj1Yz9pCUmLcbc';

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
      1. Provide a "Safety Score" (1-100) and "Efficiency Score" (1-100).
      2. Give 2 highly specific insights about this journey.
      3. Be concise and professional. Use bolding for key metrics.
    ''';

    try {
      final response = await http.post(
        Uri.parse(_endpointUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': _apiKey, // Sent to your Render backend
        },
        body: jsonEncode({
          'message': prompt,
          'stream': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          return data['reply'];
        } else {
          return "Analysis error: ${data['error']}";
        }
      }
      
      return "Server error: ${response.statusCode}";
    } catch (e) {
      return "AI Link offline. Please check your data connection.";
    }
  }

  /// Specialized chat with history
  /// Note: The 'history' type changed from List<Content> to List<Map<String, String>>
  Future<String> chatWithAi(
      TripSummary s, String query, List<Map<String, String>> history) async {
    
    final context = "The user is asking about a trip of ${s.distanceMiles.toStringAsFixed(2)} miles. Answer helpfully.\n\nQuestion: $query";

    try {
      final response = await http.post(
        Uri.parse(_endpointUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': _apiKey, // Sent to your Render backend
        },
        body: jsonEncode({
          'message': context,
          'history': history,
          'stream': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          return data['reply'];
        } else {
          return "I'm sorry, I couldn't process that: ${data['error']}";
        }
      }
      return "Server Error: ${response.statusCode}";
    } catch (e) {
      return "Chat error. Please check your connection.";
    }
  }
}
