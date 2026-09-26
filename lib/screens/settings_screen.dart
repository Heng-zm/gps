import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_puck_style.dart';
import '../navigation/app_routes.dart';
import '../services/anti_theft_service.dart';
import '../services/holographic_hud_service.dart';
import '../services/offline_sync_queue.dart';
import '../services/settings_service.dart';
import '../widgets/app_console_widget.dart';
import '../widgets/location_puck_widget.dart';
import '../widgets/settings/location_puck_style_selector.dart';
import 'diagnostics/diagnostics_screen.dart';

/// Apple HIG Minimalist Settings UI/UX with iOS 18 Inset Grouped Sections,
/// Pro Telemetry Configuration, Live Location Badges, and Tactile Haptics.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _s = SettingsService.instance;
  final AntiTheftService _antiTheft = AntiTheftService.instance;
  final HolographicHudService _hud = HolographicHudService.instance;

  LocationPermission _locationPermission = LocationPermission.denied;
  bool _checkingPermission = true;
  bool _busyReset = false;

  static const Color _bg = Color(0xFF000000);
  static const Color _surface = Color(0xFF121214);
  static const Color _cardBorder = Color(0x1AFFFFFF);

  // Apple System Palette
  static const Color _appleBlue = Color(0xFF007AFF);
  static const Color _appleGreen = Color(0xFF34C759);
  static const Color _appleRed = Color(0xFFFF3B30);
  static const Color _applePurple = Color(0xFFAF52DE);
  static const Color _appleIndigo = Color(0xFF5856D6);
  static const Color _appleYellow = Color(0xFFFFCC00);

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSettingsChanged);
    _antiTheft.init();
    if (!_s.isLoaded) _s.load();

    AppConsole.log(
      'Settings screen opened',
      tag: 'SETTINGS',
      data: <String, Object?>{
        'mapStyle': _s.mapStyle.name,
        'locationPuckStyle': _s.locationPuckStyle.name,
        'units': _s.useKmh ? 'metric' : 'imperial',
      },
    );

    _checkPermission();
  }

  @override
  void dispose() {
    _s.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkPermission() async {
    if (mounted) setState(() => _checkingPermission = true);

    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _locationPermission = permission;
        _checkingPermission = false;
      });
    } catch (error, stackTrace) {
      debugPrint('SettingsScreen permission check failed: $error\n$stackTrace');
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _requestLocationPermission() async {
    HapticFeedback.lightImpact();
    try {
      final LocationPermission permission = await Geolocator.requestPermission();
      if (!mounted) return;
      setState(() => _locationPermission = permission);
      if (permission == LocationPermission.deniedForever) {
        await _openLocationSettings();
      }
    } catch (_) {}
  }

  Future<void> _openLocationSettings() async {
    HapticFeedback.lightImpact();
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
    await _checkPermission();
  }

  void _showMapStylePicker() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: const Text('Map Appearance'),
          message: const Text('Select the visual layer for live navigation.'),
          actions: AppMapStyle.values.map((AppMapStyle style) {
            final bool selected = style == _s.mapStyle;
            return CupertinoActionSheetAction(
              isDefaultAction: selected,
              onPressed: () {
                HapticFeedback.selectionClick();
                _s.setMapStyle(style);
                Navigator.pop(popupContext);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (selected) ...<Widget>[
                    const Icon(CupertinoIcons.checkmark_alt_circle_fill,
                        size: 18, color: _appleBlue),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    style.name.toUpperCase(),
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext),
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }

  void _showLocationPuckStylePicker() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext popupContext) {
        final Size screenSize = MediaQuery.of(popupContext).size;
        final EdgeInsets safe = MediaQuery.of(popupContext).padding;
        final double maxPopupHeight =
            (screenSize.height - safe.top - safe.bottom - 28)
                .clamp(360.0, 720.0)
                .toDouble();

        return Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              constraints: BoxConstraints(maxHeight: maxPopupHeight),
              decoration: BoxDecoration(
                color: _surface.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.48),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              const Icon(
                                CupertinoIcons.location_fill,
                                color: _appleBlue,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Location Puck Style',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                onPressed: () => Navigator.pop(popupContext),
                                child: const Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  color: Colors.white38,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        primary: false,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: LocationPuckStyleSelector(
                          selected: _s.locationPuckStyle,
                          onChanged: (LocationPuckStyle style) {
                            HapticFeedback.selectionClick();
                            _s.setLocationPuckStyle(style);
                            Navigator.pop(popupContext);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTelegramConfigSheet() {
    HapticFeedback.mediumImpact();
    final TextEditingController tokenCtrl =
        TextEditingController(text: _antiTheft.telegramBotToken ?? '');
    final TextEditingController chatCtrl =
        TextEditingController(text: _antiTheft.telegramChatId ?? '');
    bool isTesting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext modalCtx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setModalState) {
            final double bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;

            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: <Widget>[
                      _AppleIconBadge(
                        icon: CupertinoIcons.shield_fill,
                        gradient: LinearGradient(
                          colors: <Color>[Color(0xFFFF2D55), Color(0xFFFF375F)],
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Telegram Sentry Alert',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Instant anti-theft shock alerts & coordinates',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'BOT API TOKEN',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  CupertinoTextField(
                    controller: tokenCtrl,
                    placeholder: '123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ',
                    placeholderStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'CHAT ID / USER ID',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  CupertinoTextField(
                    controller: chatCtrl,
                    placeholder: 'e.g. 987654321',
                    placeholderStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setModalState(() => isTesting = true);
                                  await _antiTheft.saveTelegramConfig(
                                    botToken: tokenCtrl.text,
                                    chatId: chatCtrl.text,
                                  );
                                  final bool ok = await _antiTheft.sendTestAlert();
                                  setModalState(() => isTesting = false);
                                  if (mounted) {
                                    _showSnack(
                                      message: ok
                                          ? '✅ Test alert delivered to Telegram!'
                                          : '❌ Test dispatch failed. Check token & ID.',
                                      color: ok ? _appleGreen : _appleRed,
                                    );
                                  }
                                },
                          child: isTesting
                              ? const CupertinoActivityIndicator(color: Colors.white)
                              : const Text(
                                  'Send Test Alert',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          color: _appleBlue,
                          borderRadius: BorderRadius.circular(14),
                          onPressed: () async {
                            HapticFeedback.heavyImpact();
                            await _antiTheft.saveTelegramConfig(
                              botToken: tokenCtrl.text,
                              chatId: chatCtrl.text,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            setState(() {});
                            _showSnack(
                              message: 'Telegram settings saved.',
                              color: _appleGreen,
                            );
                          },
                          child: const Text(
                            'Save Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showHudThemePicker() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: const Text('OLED HUD Color Palette'),
          message: const Text('Optimized for high-contrast windshield projection.'),
          actions: HudColorTheme.values.map((HudColorTheme theme) {
            final bool selected = theme == _hud.themeN.value;
            return CupertinoActionSheetAction(
              isDefaultAction: selected,
              onPressed: () {
                HapticFeedback.selectionClick();
                _hud.themeN.value = theme;
                Navigator.pop(popupContext);
                setState(() {});
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: theme.color,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: theme.color.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    theme.label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext),
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }

  Future<void> _confirmClearData() async {
    HapticFeedback.heavyImpact();
    final bool? confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Reset All Settings?'),
          content: const Text(
            'This restores all configurations to factory defaults and flushes the trip cache.',
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset Everything'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || _busyReset) return;
    setState(() => _busyReset = true);

    try {
      await _s.clearAllData();
      await OfflineSyncQueue.instance.clear();
      if (!mounted) return;
      _showSnack(message: 'Settings reset complete.', color: _appleGreen);
    } catch (_) {
      if (!mounted) return;
      _showSnack(message: 'Failed to reset settings.', color: _appleRed);
    } finally {
      if (mounted) setState(() => _busyReset = false);
    }
  }

  void _showSnack({required String message, required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }

  bool get _hasLocationAccess {
    return _locationPermission == LocationPermission.always ||
        _locationPermission == LocationPermission.whileInUse;
  }

  String get _permissionLabel {
    if (_checkingPermission) return 'CHECKING';
    switch (_locationPermission) {
      case LocationPermission.always:
        return 'ALWAYS';
      case LocationPermission.whileInUse:
        return 'WHILE USING';
      case LocationPermission.denied:
        return 'DENIED';
      case LocationPermission.deniedForever:
        return 'BLOCKED';
      case LocationPermission.unableToDetermine:
        return 'UNKNOWN';
    }
  }

  Color get _permissionColor {
    if (_checkingPermission) return _appleYellow;
    if (_hasLocationAccess) return _appleGreen;
    if (_locationPermission == LocationPermission.deniedForever) return _appleRed;
    return _appleYellow;
  }

  void _openDiagnostics() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.diagnostics),
        builder: (_) => const DiagnosticsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: _bg,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: <Widget>[
            CupertinoSliverNavigationBar(
              largeTitle: const Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              backgroundColor: _bg.withValues(alpha: 0.85),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              stretch: true,
            ),
            CupertinoSliverRefreshControl(onRefresh: _checkPermission),
            SliverSafeArea(
              top: false,
              bottom: true,
              minimum: EdgeInsets.only(bottom: bottomPad + 60.0),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: <Widget>[
                      // 1. Pro Status Hero Card
                      _buildHeroCard(),
                      const SizedBox(height: 18),

                      // 2. Navigation & Map Experience
                      _AppleGroupedSection(
                        header: 'NAVIGATION & MAP',
                        children: <Widget>[
                          _AppleSettingTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.location_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF007AFF), Color(0xFF0A84FF)],
                              ),
                            ),
                            title: 'Location Permission',
                            subtitle: _hasLocationAccess
                                ? 'Precise GPS tracking active'
                                : 'Required to record journeys',
                            trailing: _StatusPill(
                              label: _permissionLabel,
                              color: _permissionColor,
                            ),
                            onTap: _hasLocationAccess
                                ? _openLocationSettings
                                : _requestLocationPermission,
                          ),
                          const _AppleDivider(),
                          _AppleSettingTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.map_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF5856D6), Color(0xFF5E5CE6)],
                              ),
                            ),
                            title: 'Map Appearance',
                            subtitle: 'Street, Satellite, Dark mode',
                            trailing: _ValueBadge(
                              value: _s.mapStyle.name.toUpperCase(),
                              color: _appleIndigo,
                            ),
                            onTap: _showMapStylePicker,
                          ),
                          const _AppleDivider(),
                          _AppleSettingTile(
                            badge: _AppleIconBadge(
                              icon: _s.locationPuckStyle.icon,
                              gradient: LinearGradient(
                                colors: <Color>[
                                  _s.locationPuckStyle.accentColor,
                                  _s.locationPuckStyle.accentColor.withValues(alpha: 0.8),
                                ],
                              ),
                            ),
                            title: 'Location Puck',
                            subtitle: _s.locationPuckStyle.description,
                            trailing: _LocationPuckPreview(
                              style: _s.locationPuckStyle,
                            ),
                            onTap: _showLocationPuckStylePicker,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 3. Units & Driving Speedometer
                      _AppleGroupedSection(
                        header: 'UNITS & TELEMETRY DISPLAY',
                        children: <Widget>[
                          _buildUnitSegmentedTile(),
                          const _AppleDivider(),
                          _AppleSwitchTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.cloud_sun_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF32ADE6), Color(0xFF64D2FF)],
                              ),
                            ),
                            title: 'Live Weather',
                            subtitle: 'Real-time temperature and conditions',
                            value: _s.showWeather,
                            onChanged: (bool val) => _s.setShowWeather(val),
                          ),
                          const _AppleDivider(),
                          _AppleSwitchTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.arrow_up_arrow_down,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF30B0C7), Color(0xFF40C8E0)],
                              ),
                            ),
                            title: 'Altitude Elevation',
                            subtitle: 'Live barometric & GPS height',
                            value: _s.showAltitude,
                            onChanged: (bool val) => _s.setShowAltitude(val),
                          ),
                          const _AppleDivider(),
                          _AppleSwitchTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.compass_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFFFF9500), Color(0xFFFF9F0A)],
                              ),
                            ),
                            title: 'Compass Heading',
                            subtitle: 'Degrees and route orientation',
                            value: _s.showHeading,
                            onChanged: (bool val) => _s.setShowHeading(val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 4. Pro Telemetry & Deep-Tech Wave 2
                      _AppleGroupedSection(
                        header: 'PRO TELEMETRY & SECURITY',
                        children: <Widget>[
                          _AppleSettingTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.shield_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFFFF2D55), Color(0xFFFF375F)],
                              ),
                            ),
                            title: 'Anti-Theft Sentry Alerts',
                            subtitle: 'Telegram webhook & shock telemetry',
                            trailing: _StatusPill(
                              label: _antiTheft.isTelegramConfigured
                                  ? 'CONNECTED'
                                  : 'SETUP',
                              color: _antiTheft.isTelegramConfigured
                                  ? _appleGreen
                                  : _appleYellow,
                            ),
                            onTap: _showTelegramConfigSheet,
                          ),
                          const _AppleDivider(),
                          _AppleSettingTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.viewfinder,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF00F0FF), Color(0xFF007AFF)],
                              ),
                            ),
                            title: 'Holographic HUD Theme',
                            subtitle: 'Windshield reflection color palette',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _hud.themeN.value.color,
                                    shape: BoxShape.circle,
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: _hud.themeN.value.color
                                            .withValues(alpha: 0.6),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _ValueBadge(
                                  value: _hud.themeN.value.label,
                                  color: _hud.themeN.value.color,
                                ),
                              ],
                            ),
                            onTap: _showHudThemePicker,
                          ),
                          const _AppleDivider(),
                          const _AppleSettingTile(
                            badge: _AppleIconBadge(
                              icon: CupertinoIcons.timer,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF34C759), Color(0xFF00FF66)],
                              ),
                            ),
                            title: 'GLOSA Green Wave (V2I)',
                            subtitle: 'Phnom Penh SPaT synchronized',
                            trailing: _StatusPill(
                              label: 'ACTIVE',
                              color: _appleGreen,
                            ),
                            onTap: null,
                          ),
                          const _AppleDivider(),
                          const _AppleSettingTile(
                            badge: _AppleIconBadge(
                              icon: CupertinoIcons.antenna_radiowaves_left_right,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFFBF5AF2), Color(0xFF5E5CE6)],
                              ),
                            ),
                            title: 'LEO Satellite SOS Uplink',
                            subtitle: 'Iridium NEXT direct transceiver ready',
                            trailing: _StatusPill(
                              label: 'READY',
                              color: _applePurple,
                            ),
                            onTap: null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 5. GPS Accuracy & Power Management
                      _AppleGroupedSection(
                        header: 'GPS ACCURACY & POWER',
                        children: <Widget>[
                          _buildGpsPrecisionTile(),
                          const _AppleDivider(),
                          _AppleSwitchTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.exclamationmark_triangle_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFFFF3B30), Color(0xFFFF453A)],
                              ),
                            ),
                            title: 'Speed Limit Warning',
                            subtitle: 'Visual alert when exceeding threshold',
                            value: _s.speedAlertEnabled,
                            onChanged: (bool val) => _s.setSpeedAlertEnabled(val),
                          ),
                          if (_s.speedAlertEnabled) ...<Widget>[
                            const _AppleDivider(),
                            _buildSpeedAlertSlider(),
                          ],
                          const _AppleDivider(),
                          _AppleSwitchTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.device_phone_portrait,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFFFFCC00), Color(0xFFFFD60A)],
                              ),
                            ),
                            title: 'Keep Screen Awake',
                            subtitle: 'Prevents display sleep during journeys',
                            value: _s.keepScreenOn,
                            onChanged: (bool val) => _s.setKeepScreenOn(val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 6. Diagnostics, System & Storage
                      _AppleGroupedSection(
                        header: 'SYSTEM & DIAGNOSTICS',
                        children: <Widget>[
                          _AppleSettingTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.wrench_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF8E8E93), Color(0xFF636366)],
                              ),
                            ),
                            title: 'Hardware Diagnostics',
                            subtitle: 'Sensors, GPS signal, battery & logs',
                            trailing: const Icon(
                              CupertinoIcons.chevron_forward,
                              color: Colors.white24,
                              size: 16,
                            ),
                            onTap: _openDiagnostics,
                          ),
                          const _AppleDivider(),
                          const _AppleSettingTile(
                            badge: _AppleIconBadge(
                              icon: CupertinoIcons.info_circle_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFF007AFF), Color(0xFF5856D6)],
                              ),
                            ),
                            title: 'TrackPro AI Version',
                            subtitle: 'Build 1.5.0 · Pro Edition',
                            trailing: _ValueBadge(
                              value: 'v1.5.0',
                              color: Colors.white54,
                            ),
                          ),
                          const _AppleDivider(),
                          _AppleSettingTile(
                            badge: const _AppleIconBadge(
                              icon: CupertinoIcons.trash_fill,
                              gradient: LinearGradient(
                                colors: <Color>[Color(0xFFFF3B30), Color(0xFFD70015)],
                              ),
                            ),
                            title: 'Reset to Factory Defaults',
                            subtitle: 'Clear cached routes and preferences',
                            trailing: _busyReset
                                ? const CupertinoActivityIndicator(radius: 8)
                                : const Icon(
                                    CupertinoIcons.chevron_forward,
                                    color: Colors.white24,
                                    size: 16,
                                  ),
                            onTap: _busyReset ? null : _confirmClearData,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const AppConsoleSettingsCard(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SUB-BUILDERS
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      _permissionColor,
                      _permissionColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _permissionColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  _hasLocationAccess
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.location_slash,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _hasLocationAccess ? 'GPS Engine Ready' : 'Permission Required',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hasLocationAccess
                          ? 'Satellite telemetry & live tracking active'
                          : 'Grant location access to record routes',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _HeroStatPill(
                  label: 'LOCATION',
                  value: _permissionLabel,
                  color: _permissionColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStatPill(
                  label: 'GPS MODE',
                  value: _s.gpsAccuracyLabel.toUpperCase(),
                  color: _appleBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStatPill(
                  label: 'SYSTEM',
                  value: _s.useKmh ? 'METRIC' : 'IMPERIAL',
                  color: _appleGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSegmentedTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          const _AppleIconBadge(
            icon: CupertinoIcons.speedometer,
            gradient: LinearGradient(
              colors: <Color>[Color(0xFF34C759), Color(0xFF30D158)],
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Measurement Units',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Speed & distance calculation standard',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          CupertinoSlidingSegmentedControl<bool>(
            groupValue: _s.useKmh,
            thumbColor: const Color(0xFF3A3A3C),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            children: const <bool, Widget>{
              true: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  'KM/H',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              false: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  'MPH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            },
            onValueChanged: (bool? val) {
              if (val != null) {
                HapticFeedback.selectionClick();
                _s.setUseKmh(val);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGpsPrecisionTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              _AppleIconBadge(
                icon: CupertinoIcons.scope,
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF00C7BE), Color(0xFF63E6E2)],
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'GPS Precision Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Accuracy distance filter & battery draw',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _s.gpsAccuracyMode,
              thumbColor: const Color(0xFF3A3A3C),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              children: const <int, Widget>{
                0: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    'NAV (1m)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                1: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    'HIGH (4m)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                2: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    'ECO (10m)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              },
              onValueChanged: (int? val) {
                if (val != null) {
                  HapticFeedback.selectionClick();
                  _s.setGpsAccuracyMode(val);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedAlertSlider() {
    final double safeMin = _s.useKmh ? 30.0 : 20.0;
    final double safeMax = _s.speedAlertMax;
    final double currentVal = _s.speedAlertDisplayValue.clamp(safeMin, safeMax);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Speed Limit Trigger',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _ValueBadge(
                value: '${currentVal.round()} ${_s.speedUnit}',
                color: _appleRed,
              ),
            ],
          ),
          const SizedBox(height: 6),
          CupertinoSlider(
            value: currentVal,
            min: safeMin,
            max: safeMax,
            activeColor: _appleRed,
            onChanged: (double v) => _s.setSpeedAlertDisplayValue(v),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE APPLE HIG COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _AppleGroupedSection extends StatelessWidget {
  const _AppleGroupedSection({
    required this.header,
    required this.children,
  });

  final String header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 7),
          child: Text(
            header,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class _AppleSettingTile extends StatelessWidget {
  const _AppleSettingTile({
    required this.badge,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget badge;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          badge,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: row,
    );
  }
}

class _AppleSwitchTile extends StatelessWidget {
  const _AppleSwitchTile({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget badge;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _AppleSettingTile(
      badge: badge,
      title: title,
      subtitle: subtitle,
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: const Color(0xFF34C759),
        onChanged: (bool next) {
          HapticFeedback.selectionClick();
          onChanged(next);
        },
      ),
    );
  }
}

class _AppleIconBadge extends StatelessWidget {
  const _AppleIconBadge({
    required this.icon,
    required this.gradient,
  });

  final IconData icon;
  final Gradient gradient;
  static const double _size = 32.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(9),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: _size * 0.58),
    );
  }
}

class _AppleDivider extends StatelessWidget {
  const _AppleDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 60,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ValueBadge extends StatelessWidget {
  const _ValueBadge({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPuckPreview extends StatelessWidget {
  const _LocationPuckPreview({required this.style});

  final LocationPuckStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 40,
      child: Center(
        child: AppLocationPuck(
          style: style,
          bearing: 30,
          speed: 28,
          size: 38,
        ),
      ),
    );
  }
}
