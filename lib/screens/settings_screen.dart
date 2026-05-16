// ignore_for_file: unused_element

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_puck_style.dart';
import '../navigation/app_routes.dart';
import '../services/settings_service.dart';
import '../widgets/app_console_widget.dart';
import '../widgets/location_puck_widget.dart';
import '../widgets/settings/location_puck_style_selector.dart';
import 'diagnostics/diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _s = SettingsService.instance;

  LocationPermission _locationPermission = LocationPermission.denied;
  bool _checkingPermission = true;
  bool _busyReset = false;

  static const Color _bg = Color(0xFF000000);
  static const Color _surface = Color(0xFF101012);
  static const Color _gold = Color(0xFFD4A843);
  static const Color _goldSoft = Color(0xFFFFD54F);
  static const Color _green = Color(0xFF32D74B);
  static const Color _red = Color(0xFFFF453A);
  static const Color _blue = Color(0xFF4A9EFF);
  static const Color _muted = Color(0xFF777777);

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSettingsChanged);
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
      AppConsole.log(
        'Location permission checked',
        tag: 'PERMISSION',
        data: <String, Object?>{'status': permission.name},
      );
    } catch (error, stackTrace) {
      debugPrint('SettingsScreen permission check failed: $error\n$stackTrace');
      AppConsole.error(
        'Permission check failed',
        tag: 'PERMISSION',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _requestLocationPermission() async {
    HapticFeedback.lightImpact();
    try {
      final LocationPermission permission = await Geolocator.requestPermission();
      if (!mounted) return;
      setState(() => _locationPermission = permission);
      AppConsole.log(
        'Location permission requested',
        tag: 'PERMISSION',
        data: <String, Object?>{'status': permission.name},
      );
      if (permission == LocationPermission.deniedForever) {
        await _openLocationSettings();
      }
    } catch (error, stackTrace) {
      debugPrint('SettingsScreen permission request failed: $error\n$stackTrace');
      AppConsole.error(
        'Permission request failed',
        tag: 'PERMISSION',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _openLocationSettings() async {
    HapticFeedback.lightImpact();
    try {
      await Geolocator.openAppSettings();
      AppConsole.log('Opened app settings', tag: 'PERMISSION');
    } catch (error, stackTrace) {
      debugPrint('Open app settings failed: $error\n$stackTrace');
      AppConsole.error(
        'Open app settings failed',
        tag: 'PERMISSION',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _checkPermission();
  }

  void _showMapStylePicker() {
    HapticFeedback.mediumImpact();

    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: const Text('Map Style'),
          message: const Text('Choose how the live map should look.'),
          actions: AppMapStyle.values.map((AppMapStyle style) {
            final bool selected = style == _s.mapStyle;
            return CupertinoActionSheetAction(
              isDefaultAction: selected,
              onPressed: () {
                HapticFeedback.selectionClick();
                _s.setMapStyle(style);
                AppConsole.success(
                  'Map style changed',
                  tag: 'SETTINGS',
                  data: <String, Object?>{'style': style.name},
                );
                Navigator.pop(popupContext);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (selected) ...<Widget>[
                    const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      size: 18,
                      color: _gold,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(style.name.toUpperCase()),
                ],
              ),
            );
          }).toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
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
            (screenSize.height - safe.top - safe.bottom - 28).clamp(360.0, 720.0);

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
                                color: _goldSoft,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: _SafeText(
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
                                minSize: 0,
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
                            AppConsole.success(
                              'Location puck style changed',
                              tag: 'SETTINGS',
                              data: <String, Object?>{'style': style.name},
                            );
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

  Future<void> _confirmClearData() async {
    HapticFeedback.heavyImpact();
    final bool? confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Reset All Data?'),
          content: const Text(
            'This returns settings to defaults and clears your local trip cache.',
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
      AppConsole.warn('Factory settings reset complete', tag: 'SETTINGS');
      if (!mounted) return;
      _showSnack(message: 'Settings reset complete.', color: _green);
    } catch (error, stackTrace) {
      debugPrint('Clear settings failed: $error\n$stackTrace');
      AppConsole.error(
        'Clear settings failed',
        tag: 'SETTINGS',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _showSnack(message: 'Failed to reset settings.', color: _red);
    } finally {
      if (mounted) setState(() => _busyReset = false);
    }
  }

  void _showSnack({required String message, required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
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
    if (_checkingPermission) return _goldSoft;
    if (_hasLocationAccess) return _green;
    if (_locationPermission == LocationPermission.deniedForever) return _red;
    return _goldSoft;
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: _bg,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: _SettingsBackground()),
            CustomScrollView(
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
                      letterSpacing: -0.8,
                    ),
                  ),
                  backgroundColor: _bg.withValues(alpha: 0.78),
                  border: null,
                  stretch: true,
                ),
                CupertinoSliverRefreshControl(onRefresh: _checkPermission),
                SliverSafeArea(
                  top: false,
                  bottom: true,
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 44),
                      child: Column(
                        children: <Widget>[
                          _HeroStatusCard(
                            permissionLabel: _permissionLabel,
                            permissionColor: _permissionColor,
                            hasLocationAccess: _hasLocationAccess,
                            gpsLabel: _s.gpsAccuracyLabel,
                            unitLabel: _s.useKmh ? 'METRIC' : 'IMPERIAL',
                            onRequestLocation: _requestLocationPermission,
                            onOpenSettings: _openLocationSettings,
                          ),
                          const SizedBox(height: 18),
                          _Section(
                            title: 'TRACKING SETUP',
                            children: <Widget>[
                              _SettingTile(
                                icon: CupertinoIcons.location_fill,
                                iconColor: _permissionColor,
                                title: 'Location Access',
                                subtitle: _hasLocationAccess
                                    ? 'Ready for live GPS tracking'
                                    : 'Required for route recording',
                                trailing: _StatusPill(
                                  label: _permissionLabel,
                                  color: _permissionColor,
                                ),
                                onTap: _hasLocationAccess
                                    ? _openLocationSettings
                                    : _requestLocationPermission,
                              ),
                              const _Sep(),
                              _SettingTile(
                                icon: CupertinoIcons.map_fill,
                                iconColor: _goldSoft,
                                title: 'Map Style',
                                subtitle: 'Live route visualization mode',
                                trailing: _ValueLabel(
                                  value: _s.mapStyle.name.toUpperCase(),
                                  color: _goldSoft,
                                ),
                                onTap: _showMapStylePicker,
                              ),
                              const _Sep(),
                              _SettingTile(
                                icon: _s.locationPuckStyle.icon,
                                iconColor: _s.locationPuckStyle.accentColor,
                                title: 'Location Puck',
                                subtitle: _s.locationPuckStyle.description,
                                trailing: _LocationPuckPreview(
                                  style: _s.locationPuckStyle,
                                ),
                                onTap: _showLocationPuckStylePicker,
                              ),
                            ],
                          ),
                          _Section(
                            title: 'UNITS & DISPLAY',
                            children: <Widget>[
                              _SwitchTile(
                                icon: CupertinoIcons.speedometer,
                                iconColor: _green,
                                title: 'Metric System',
                                subtitle: 'Use km/h, kilometers and meters',
                                value: _s.useKmh,
                                onChanged: (bool value) {
                                  _s.setUseKmh(value);
                                  AppConsole.log(
                                    'Metric system changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'enabled': value},
                                  );
                                },
                              ),
                              const _Sep(),
                              _SwitchTile(
                                icon: CupertinoIcons.cloud_sun_fill,
                                iconColor: _goldSoft,
                                title: 'Weather Card',
                                subtitle: 'Show live weather on tracking screen',
                                value: _s.showWeather,
                                onChanged: (bool value) {
                                  _s.setShowWeather(value);
                                  AppConsole.log(
                                    'Weather card changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'enabled': value},
                                  );
                                },
                              ),
                              const _Sep(),
                              _SwitchTile(
                                icon: CupertinoIcons.arrow_up_arrow_down,
                                iconColor: _blue,
                                title: 'Show Altitude',
                                subtitle: 'Display elevation during tracking',
                                value: _s.showAltitude,
                                onChanged: (bool value) {
                                  _s.setShowAltitude(value);
                                  AppConsole.log(
                                    'Altitude display changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'enabled': value},
                                  );
                                },
                              ),
                              const _Sep(),
                              _SwitchTile(
                                icon: CupertinoIcons.compass_fill,
                                iconColor: _goldSoft,
                                title: 'Show Heading',
                                subtitle: 'Display compass and route direction',
                                value: _s.showHeading,
                                onChanged: (bool value) {
                                  _s.setShowHeading(value);
                                  AppConsole.log(
                                    'Heading display changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'enabled': value},
                                  );
                                },
                              ),
                            ],
                          ),
                          _Section(
                            title: 'GPS PERFORMANCE',
                            children: <Widget>[
                              _GpsAccuracyPanel(
                                label: _s.gpsAccuracyLabel,
                                selectedMode: _s.gpsAccuracyMode,
                                onSelect: (int mode) {
                                  _s.setGpsAccuracyMode(mode);
                                  AppConsole.log(
                                    'GPS accuracy mode changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'mode': mode},
                                  );
                                },
                              ),
                            ],
                          ),
                          _Section(
                            title: 'SAFETY',
                            children: <Widget>[
                              _SwitchTile(
                                icon: CupertinoIcons.exclamationmark_triangle_fill,
                                iconColor: _red,
                                title: 'Speed Alert',
                                subtitle: 'Warn when speed exceeds your limit',
                                value: _s.speedAlertEnabled,
                                onChanged: (bool value) {
                                  _s.setSpeedAlertEnabled(value);
                                  AppConsole.log(
                                    'Speed alert changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'enabled': value},
                                  );
                                },
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                child: _s.speedAlertEnabled
                                    ? Column(
                                        key: const ValueKey<String>('speed-alert-slider'),
                                        children: <Widget>[
                                          const _Sep(),
                                          _SpeedAlertPanel(
                                            value: _s.speedAlertDisplayValue,
                                            min: _s.useKmh ? 30.0 : 20.0,
                                            max: _s.speedAlertMax,
                                            unit: _s.speedUnit,
                                            onChanged: (double value) {
                                              _s.setSpeedAlertDisplayValue(value);
                                            },
                                          ),
                                        ],
                                      )
                                    : const SizedBox(
                                        key: ValueKey<String>('speed-alert-disabled'),
                                        height: 0,
                                      ),
                              ),
                            ],
                          ),
                          _Section(
                            title: 'POWER & SENSORS',
                            children: <Widget>[
                              _SwitchTile(
                                icon: CupertinoIcons.device_phone_portrait,
                                iconColor: _goldSoft,
                                title: 'Keep Screen On',
                                subtitle: 'Active during tracking when allowed',
                                value: _s.keepScreenOn,
                                onChanged: (bool value) {
                                  _s.setKeepScreenOn(value);
                                  AppConsole.log(
                                    'Keep screen on changed',
                                    tag: 'SETTINGS',
                                    data: <String, Object?>{'enabled': value},
                                  );
                                },
                              ),
                              const _WakeLockNote(),
                            ],
                          ),
                          _Section(
                            title: 'STORAGE',
                            children: <Widget>[
                              _SettingTile(
                                icon: CupertinoIcons.trash_fill,
                                iconColor: _red,
                                title: 'Reset Factory Settings',
                                subtitle: 'Restore defaults and clear local cache',
                                trailing: _busyReset
                                    ? const CupertinoActivityIndicator(
                                        color: _red,
                                        radius: 9,
                                      )
                                    : const Icon(
                                        CupertinoIcons.chevron_right,
                                        color: Colors.white24,
                                        size: 15,
                                      ),
                                onTap: _busyReset ? null : _confirmClearData,
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const AppConsoleSettingsCard(),
                          _Section(
                            title: 'SYSTEM',
                            children: <Widget>[
                              _SettingTile(
                                icon: CupertinoIcons.wrench_fill,
                                iconColor: _blue,
                                title: 'Diagnostics',
                                subtitle: 'Check GPS, permissions and Mapbox',
                                trailing: const Icon(
                                  CupertinoIcons.chevron_right,
                                  color: Colors.white24,
                                  size: 15,
                                ),
                                onTap: _openDiagnostics,
                              ),
                              const _Sep(),
                              const _SettingTile(
                                icon: CupertinoIcons.info_circle_fill,
                                iconColor: _blue,
                                title: 'Version',
                                subtitle: 'TrackPro AI',
                                trailing: _ValueLabel(value: '1.5.0', color: _muted),
                              ),
                              const _Sep(),
                              const _SettingTile(
                                icon: CupertinoIcons.checkmark_shield_fill,
                                iconColor: _green,
                                title: 'API Status',
                                subtitle: 'Cloud services are reachable',
                                trailing: _StatusPill(label: 'ONLINE', color: _green),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
      width: 48,
      height: 44,
      child: Center(
        child: AppLocationPuck(
          style: style,
          bearing: 30,
          speed: 28,
          size: 42,
        ),
      ),
    );
  }
}

class _SettingsBackground extends StatelessWidget {
  const _SettingsBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.65, -0.85),
          radius: 1.18,
          colors: <Color>[
            _SettingsScreenState._gold.withValues(alpha: 0.16),
            const Color(0xFF080808),
            _SettingsScreenState._bg,
          ],
          stops: const <double>[0.0, 0.42, 1.0],
        ),
      ),
    );
  }
}

class _HeroStatusCard extends StatelessWidget {
  const _HeroStatusCard({
    required this.permissionLabel,
    required this.permissionColor,
    required this.hasLocationAccess,
    required this.gpsLabel,
    required this.unitLabel,
    required this.onRequestLocation,
    required this.onOpenSettings,
  });

  final String permissionLabel;
  final Color permissionColor;
  final bool hasLocationAccess;
  final String gpsLabel;
  final String unitLabel;
  final VoidCallback onRequestLocation;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 28,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: permissionColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: permissionColor.withValues(alpha: 0.24)),
                ),
                child: Icon(
                  hasLocationAccess ? CupertinoIcons.location_fill : CupertinoIcons.location_slash,
                  color: permissionColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SafeText(
                      hasLocationAccess ? 'Ready to Track' : 'Location Setup Needed',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SafeText(
                      hasLocationAccess
                          ? 'GPS, speed and route recording are available.'
                          : 'Allow location access to record live trips.',
                      maxLines: 2,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
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
                child: _HeroMiniStat(
                  label: 'LOCATION',
                  value: permissionLabel,
                  color: permissionColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniStat(
                  label: 'GPS MODE',
                  value: gpsLabel.toUpperCase(),
                  color: _SettingsScreenState._goldSoft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniStat(
                  label: 'UNITS',
                  value: unitLabel,
                  color: _SettingsScreenState._blue,
                ),
              ),
            ],
          ),
          if (!hasLocationAccess) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ActionButton(
                    label: 'ALLOW LOCATION',
                    color: _SettingsScreenState._green,
                    onTap: onRequestLocation,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'APP SETTINGS',
                    color: _SettingsScreenState._goldSoft,
                    onTap: onOpenSettings,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMiniStat extends StatelessWidget {
  const _HeroMiniStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Column(
          children: <Widget>[
            _SafeText(
              value,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            _SafeText(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 22, 8, 9),
            child: _SafeText(
              title,
              maxLines: 1,
              style: const TextStyle(
                color: _SettingsScreenState._goldSoft,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          _GlassCard(
            radius: 22,
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16), this.radius = 22});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _SettingsScreenState._surface.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: <Widget>[
          _IconBox(icon: icon, color: iconColor),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SafeText(
                  title,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                _SafeText(
                  subtitle,
                  maxLines: 2,
                  softWrap: true,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap!();
      },
      child: content,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingTile(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: _SettingsScreenState._gold,
        onChanged: (bool next) {
          HapticFeedback.selectionClick();
          onChanged(next);
        },
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

class _GpsAccuracyPanel extends StatelessWidget {
  const _GpsAccuracyPanel({required this.label, required this.selectedMode, required this.onSelect});

  final String label;
  final int selectedMode;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 16),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const _IconBox(icon: CupertinoIcons.scope, color: _SettingsScreenState._goldSoft),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SafeText(
                      'Accuracy Mode',
                      maxLines: 1,
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    _SafeText(
                      'Balance GPS precision and battery usage',
                      maxLines: 2,
                      softWrap: true,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        height: 1.22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ValueLabel(value: label.toUpperCase(), color: _SettingsScreenState._goldSoft),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _AccuracyChip(label: 'BEST', selected: selectedMode == 0, onTap: () => onSelect(0))),
              const SizedBox(width: 8),
              Expanded(child: _AccuracyChip(label: 'BALANCED', selected: selectedMode == 1, onTap: () => onSelect(1))),
              const SizedBox(width: 8),
              Expanded(child: _AccuracyChip(label: 'ECO', selected: selectedMode == 2, onTap: () => onSelect(2))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedAlertPanel extends StatelessWidget {
  const _SpeedAlertPanel({required this.value, required this.min, required this.max, required this.unit, required this.onChanged});

  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final double safeMin = min.isFinite ? min : 0.0;
    final double safeMax = max.isFinite && max > safeMin ? max : safeMin + 1.0;
    final double safeValue = value.clamp(safeMin, safeMax).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const _SafeText(
                'Alert Threshold',
                maxLines: 1,
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              _ValueLabel(value: '${safeValue.round()} $unit', color: _SettingsScreenState._red),
            ],
          ),
          const SizedBox(height: 8),
          CupertinoSlider(value: safeValue, min: safeMin, max: safeMax, activeColor: _SettingsScreenState._red, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _WakeLockNote extends StatelessWidget {
  const _WakeLockNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _SettingsScreenState._gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _SettingsScreenState._gold.withValues(alpha: 0.12)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Icon(CupertinoIcons.exclamationmark_circle_fill, color: _SettingsScreenState._goldSoft, size: 16),
              SizedBox(width: 9),
              Expanded(
                child: _SafeText(
                  'On Web, screen wake lock may be blocked by browser policy.',
                  maxLines: 2,
                  softWrap: true,
                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.25, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccuracyChip extends StatelessWidget {
  const _AccuracyChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? _SettingsScreenState._goldSoft : Colors.white38;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _SettingsScreenState._gold.withValues(alpha: 0.13) : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _SettingsScreenState._goldSoft.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.06),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: _SafeText(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6),
        ),
      ),
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _SafeText(
      value,
      maxLines: 1,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.4),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.7),
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 62, right: 15),
      color: Colors.white.withValues(alpha: 0.04),
    );
  }
}

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: softWrap,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
