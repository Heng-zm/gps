import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/trip_data.dart';
import '../models/weather_data.dart';
import 'settings_service.dart';

class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  final GenerativeModel _model = GenerativeModel(
    model: 'gemma-4-31b-it',
    apiKey: 'AIzaSyA_u1xkFG6i1JzT_LrakEj1Yz9pCUmLcbc',
  );

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
      final res = await _model.generateContent([Content.text(prompt)]);
      return res.text ?? "Analysis currently unavailable.";
    } catch (e) {
      return "AI Link offline. Please check your data connection.";
    }
  }

  /// Specialized chat with history
  Future<String> chatWithAi(
      TripSummary s, String query, List<Content> history) async {
    final chat = _model.startChat(history: history);
    final context =
        "The user is asking about a trip of ${s.distanceMiles.toStringAsFixed(2)} miles. Answer helpfuly.";

    try {
      final res =
          await chat.sendMessage(Content.text("$context\nQuestion: $query"));
      return res.text ?? "I'm sorry, I couldn't process that.";
    } catch (e) {
      return "Chat error.";
    }
  }
}
