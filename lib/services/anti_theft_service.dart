import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SentryState {
  disarmed,
  arming,
  armed,
  breached,
  tampered,
}

class AntiTheftService {
  AntiTheftService._();
  static final AntiTheftService instance = AntiTheftService._();

  final ValueNotifier<SentryState> stateN =
      ValueNotifier<SentryState>(SentryState.disarmed);

  final ValueNotifier<double> driftMetersN = ValueNotifier<double>(0.0);
  final ValueNotifier<double> geofenceRadiusN = ValueNotifier<double>(35.0);
  final ValueNotifier<LatLng?> anchorPosN = ValueNotifier<LatLng?>(null);
  final ValueNotifier<List<String>> eventLogN = ValueNotifier<List<String>>(<String>[]);

  String? _telegramBotToken;
  String? _telegramChatId;

  static const Distance _distance = Distance();

  Future<void> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _telegramBotToken = prefs.getString('antitheft_tg_token');
    _telegramChatId = prefs.getString('antitheft_tg_chat_id');
    final double? radius = prefs.getDouble('antitheft_radius');
    if (radius != null && radius > 10.0) {
      geofenceRadiusN.value = radius;
    }
  }

  Future<void> saveTelegramConfig({
    required String botToken,
    required String chatId,
  }) async {
    _telegramBotToken = botToken.trim();
    _telegramChatId = chatId.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('antitheft_tg_token', _telegramBotToken!);
    await prefs.setString('antitheft_tg_chat_id', _telegramChatId!);
  }

  void arm(LatLng position, {double? radiusMeters}) {
    if (radiusMeters != null) {
      geofenceRadiusN.value = radiusMeters;
    }
    anchorPosN.value = position;
    driftMetersN.value = 0.0;
    stateN.value = SentryState.armed;
    _logEvent('🛡️ Sentry Guard ARMED at ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)} (Radius: ${geofenceRadiusN.value.round()}m)');
  }

  void disarm() {
    stateN.value = SentryState.disarmed;
    anchorPosN.value = null;
    driftMetersN.value = 0.0;
    _logEvent('🔓 Sentry Guard DISARMED');
  }

  void updateLocation(LatLng currentPos) {
    if (stateN.value != SentryState.armed) return;

    final LatLng? anchor = anchorPosN.value;
    if (anchor == null) return;

    final double drift = _distance.as(LengthUnit.Meter, anchor, currentPos);
    driftMetersN.value = drift;

    if (drift > geofenceRadiusN.value) {
      stateN.value = SentryState.breached;
      final String alertMsg =
          '🚨 SENTRY BREACH: Vehicle moved ${drift.round()}m away from parking spot!';
      _logEvent(alertMsg);
      _dispatchTelegramAlert(
        title: '🚨 VEHICLE THEFT / MOVEMENT ALERT',
        message: 'Your vehicle has moved ${drift.round()}m outside its secure zone!\n\n'
            '📍 Live Location: https://maps.google.com/?q=${currentPos.latitude},${currentPos.longitude}\n'
            '⏰ Time: ${DateTime.now().toLocal().toString().split(".")[0]}',
      );
    }
  }

  void reportPhysicalTampering() {
    if (stateN.value != SentryState.armed) return;
    stateN.value = SentryState.tampered;
    final String alertMsg =
        '⚠️ SHOCK DETECTED: Physical intrusion / tampering detected on vehicle!';
    _logEvent(alertMsg);
    final LatLng? pos = anchorPosN.value;
    _dispatchTelegramAlert(
      title: '⚠️ SENTRY TAMPER / SHOCK ALERT',
      message: 'Suspicious physical impact or vibration detected on your parked vehicle!\n'
          '${pos != null ? "📍 Last Known Location: https://maps.google.com/?q=${pos.latitude},${pos.longitude}\n" : ""}'
          '⏰ Time: ${DateTime.now().toLocal().toString().split(".")[0]}',
    );
  }

  void _logEvent(String text) {
    final String timestamp = DateTime.now().toLocal().toString().split(' ')[1].split('.')[0];
    eventLogN.value = <String>[
      '[$timestamp] $text',
      ...eventLogN.value.take(20),
    ];
  }

  Future<void> _dispatchTelegramAlert({
    required String title,
    required String message,
  }) async {
    final String? token = _telegramBotToken;
    final String? chat = _telegramChatId;
    if (token == null || token.isEmpty || chat == null || chat.isEmpty) {
      debugPrint('Telegram alert skipped: bot credentials not configured.');
      return;
    }

    try {
      final Uri url = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final String fullText = '*$title*\n\n$message';
      await http.post(
        url,
        body: <String, String>{
          'chat_id': chat,
          'text': fullText,
          'parse_mode': 'Markdown',
        },
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Failed to send Telegram alert: $e');
    }
  }
}
