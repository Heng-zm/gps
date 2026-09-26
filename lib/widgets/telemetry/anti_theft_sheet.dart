import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../services/anti_theft_service.dart';
import '../../services/gps_service.dart';
import '../../theme/app_theme.dart';
import '../common/app_glass_card.dart';

class AntiTheftSheet extends StatefulWidget {
  const AntiTheftSheet({super.key});

  @override
  State<AntiTheftSheet> createState() => _AntiTheftSheetState();
}

class _AntiTheftSheetState extends State<AntiTheftSheet> {
  final AntiTheftService _service = AntiTheftService.instance;
  final GpsService _gps = GpsService.instance;

  final TextEditingController _botTokenCtrl = TextEditingController();
  final TextEditingController _chatIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _service.init();
  }

  @override
  void dispose() {
    _botTokenCtrl.dispose();
    _chatIdCtrl.dispose();
    super.dispose();
  }

  void _toggleArm() {
    HapticFeedback.heavyImpact();
    if (_service.stateN.value == SentryState.armed ||
        _service.stateN.value == SentryState.breached) {
      _service.disarm();
    } else {
      final LatLng? pos = _gps.lastKnownPosition;
      if (pos != null) {
        _service.arm(pos);
      } else {
        // Fallback Phnom Penh coordinate if GPS acquiring
        _service.arm(const LatLng(11.5564, 104.9282));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SentryState>(
      valueListenable: _service.stateN,
      builder: (BuildContext context, SentryState state, _) {
        final bool isArmed = state == SentryState.armed;
        final bool isBreached =
            state == SentryState.breached || state == SentryState.tampered;

        final Color themeColor = isBreached
            ? AppColors.red
            : isArmed
                ? AppColors.blueSoft
                : Colors.white54;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Animated Shield Status Hero
              _buildShieldHero(state, themeColor),
              const SizedBox(height: 18),

              // Big Arm / Disarm Action Button
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _toggleArm,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: isBreached
                        ? const LinearGradient(
                            colors: <Color>[Color(0xFFFF3B30), Color(0xFFD70015)],
                          )
                        : isArmed
                            ? const LinearGradient(
                                colors: <Color>[Color(0xFFFF9500), Color(0xFFFF5E3A)],
                              )
                            : const LinearGradient(
                                colors: <Color>[Color(0xFF007AFF), Color(0xFF0051D5)],
                              ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: themeColor.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        isArmed || isBreached
                            ? CupertinoIcons.lock_open_fill
                            : CupertinoIcons.shield_fill,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isArmed || isBreached ? 'DISARM SENTRY' : 'ARM SENTRY GUARD',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Geofence Radius Slider Card
              _buildGeofenceCard(),
              const SizedBox(height: 14),

              // Telegram Webhook Card
              _buildTelegramCard(),
              const SizedBox(height: 14),

              // Security Event Log
              _buildEventLogCard(),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShieldHero(SentryState state, Color themeColor) {
    final bool isArmed = state == SentryState.armed;
    final bool isBreached =
        state == SentryState.breached || state == SentryState.tampered;

    return AppGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      borderRadius: 24,
      child: Column(
        children: <Widget>[
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: themeColor.withValues(alpha: 0.12),
              border: Border.all(color: themeColor.withValues(alpha: 0.35), width: 1.5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.25),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(
              isBreached
                  ? CupertinoIcons.exclamationmark_shield_fill
                  : isArmed
                      ? CupertinoIcons.shield_lefthalf_fill
                      : CupertinoIcons.shield,
              size: 40,
              color: themeColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isBreached
                ? 'SECURITY BREACH DETECTED'
                : isArmed
                    ? 'VEHICLE SENTRY ACTIVE'
                    : 'SENTRY GUARD DISARMED',
            style: TextStyle(
              color: themeColor,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<double>(
            valueListenable: _service.driftMetersN,
            builder: (_, double drift, __) {
              return Text(
                isArmed
                    ? 'Current drift: ${drift.toStringAsFixed(1)}m from parked spot'
                    : 'Locks GPS anchor and triggers instant Telegram SOS if vehicle is towed or moved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11.5,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGeofenceCard() {
    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'GEOFENCE RADIUS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _service.geofenceRadiusN,
                builder: (_, double radius, __) {
                  return Text(
                    '${radius.round()} METERS',
                    style: const TextStyle(
                      color: AppColors.blueSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<double>(
            valueListenable: _service.geofenceRadiusN,
            builder: (_, double radius, __) {
              return CupertinoSlider(
                value: radius,
                min: 15.0,
                max: 120.0,
                divisions: 21,
                activeColor: AppColors.blueSoft,
                onChanged: (double val) {
                  _service.geofenceRadiusN.value = val;
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTelegramCard() {
    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(CupertinoIcons.paperplane_fill, size: 16, color: AppColors.blueSoft),
              SizedBox(width: 8),
              Text(
                'TELEGRAM SOS DISPATCH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure your Telegram Bot token to receive instant live GPS tracking links when movement is detected.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            minSize: 36,
            onPressed: _showTelegramConfigDialog,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(CupertinoIcons.settings, size: 14, color: Colors.white70),
                SizedBox(width: 6),
                Text(
                  'Configure Bot Webhook',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventLogCard() {
    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'SENTRY SECURITY LOG',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<List<String>>(
            valueListenable: _service.eventLogN,
            builder: (_, List<String> logs, __) {
              if (logs.isEmpty) {
                return Text(
                  'No security events recorded. Sentry standing by.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: logs.map((String e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      e,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showTelegramConfigDialog() {
    showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return CupertinoAlertDialog(
          title: const Text('Telegram Alert Bot'),
          content: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: _botTokenCtrl,
                placeholder: 'Bot Token (e.g. 123456:ABC...)',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _chatIdCtrl,
                placeholder: 'Chat ID (e.g. 987654321)',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Save'),
              onPressed: () {
                _service.saveTelegramConfig(
                  botToken: _botTokenCtrl.text,
                  chatId: _chatIdCtrl.text,
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }
}
