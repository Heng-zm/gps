import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _s = SettingsService.instance;
  LocationPermission _locationPermission = LocationPermission.denied;

  static const Color _teal = Color(0xFF4ECDC4);
  static const Color _bg = Color(0xFF070707);
  static const Color _card = Color(0xFF121212);

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSettingsChanged);
    _checkPermission();

    if (!_s.isLoaded) {
      _s.load();
    }
  }

  @override
  void dispose() {
    _s.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkPermission() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();

      if (!mounted) return;

      setState(() {
        _locationPermission = permission;
      });
    } catch (e, st) {
      debugPrint('SettingsScreen permission check failed: $e\n$st');
    }
  }

  Future<void> _openLocationSettings() async {
    HapticFeedback.lightImpact();

    try {
      await Geolocator.openAppSettings();
    } catch (e, st) {
      debugPrint('Open app settings failed: $e\n$st');
    }

    await _checkPermission();
  }

  void _showMapStylePicker() {
    HapticFeedback.mediumImpact();

    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('Map Engine Style'),
          message: const Text('Select your preferred visualization mode'),
          actions: AppMapStyle.values.map((AppMapStyle style) {
            return CupertinoActionSheetAction(
              onPressed: () {
                _s.setMapStyle(style);
                Navigator.pop(context);
              },
              child: Text(style.name.toUpperCase()),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }

  void _confirmClearData() {
    HapticFeedback.heavyImpact();

    showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: const Text('Reset All Data?'),
          content: const Text(
            'This will return all settings to factory defaults and clear your trip cache.',
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.of(context).pop();

                try {
                  await _s.clearAllData();
                } catch (e, st) {
                  debugPrint('Clear settings failed: $e\n$st');
                }
              },
              child: const Text('Reset Everything'),
            ),
          ],
        );
      },
    );
  }

  bool get _hasLocationAccess {
    return _locationPermission == LocationPermission.always ||
        _locationPermission == LocationPermission.whileInUse;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bg,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          CupertinoSliverNavigationBar(
            largeTitle: const Text(
              'Settings',
              style: TextStyle(
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            backgroundColor: _bg.withValues(alpha: 0.8),
            border: null,
          ),
          SliverSafeArea(
            top: false,
            bottom: true,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 40),
                child: Column(
                  children: <Widget>[
                    _Section(
                      title: 'PERMISSIONS',
                      children: <Widget>[
                        _InfoRow(
                          label: 'Location Access',
                          value: _locationPermission.name.toUpperCase(),
                          valueColor:
                              _hasLocationAccess ? _teal : Colors.redAccent,
                          onTap: _openLocationSettings,
                        ),
                      ],
                    ),
                    _Section(
                      title: 'VISUALS & UNITS',
                      children: <Widget>[
                        _ToggleRow(
                          label: 'Metric System',
                          subtitle: 'Use KM/H and meters',
                          value: _s.useKmh,
                          onChanged: _s.setUseKmh,
                        ),
                        const _Sep(),
                        _InfoRow(
                          label: 'Map Style',
                          value: _s.mapStyle.name.toUpperCase(),
                          onTap: _showMapStylePicker,
                        ),
                      ],
                    ),
                    _Section(
                      title: 'SENSORS',
                      children: <Widget>[
                        _ToggleRow(
                          label: 'Keep Screen On',
                          subtitle: 'Active during tracking',
                          value: _s.keepScreenOn,
                          onChanged: _s.setKeepScreenOn,
                        ),
                        const _Sep(),
                        _ToggleRow(
                          label: 'Show Altitude',
                          value: _s.showAltitude,
                          onChanged: _s.setShowAltitude,
                        ),
                        const _Sep(),
                        _ToggleRow(
                          label: 'Show Heading',
                          value: _s.showHeading,
                          onChanged: _s.setShowHeading,
                        ),
                      ],
                    ),
                    _Section(
                      title: 'GPS PERFORMANCE',
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: <Widget>[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  const Text(
                                    'Accuracy Mode',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _s.gpsAccuracyLabel,
                                    style: const TextStyle(
                                      color: _teal,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  _AccuracyChip(
                                    label: 'BEST',
                                    selected: _s.gpsAccuracyMode == 0,
                                    onTap: () => _s.setGpsAccuracyMode(0),
                                  ),
                                  _AccuracyChip(
                                    label: 'BALANCED',
                                    selected: _s.gpsAccuracyMode == 1,
                                    onTap: () => _s.setGpsAccuracyMode(1),
                                  ),
                                  _AccuracyChip(
                                    label: 'ECO',
                                    selected: _s.gpsAccuracyMode == 2,
                                    onTap: () => _s.setGpsAccuracyMode(2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'SAFETY',
                      children: <Widget>[
                        _ToggleRow(
                          label: 'Speed Alert',
                          subtitle: 'Visual warning when exceeding limit',
                          value: _s.speedAlertEnabled,
                          onChanged: _s.setSpeedAlertEnabled,
                        ),
                        if (_s.speedAlertEnabled) ...<Widget>[
                          const _Sep(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Row(
                              children: <Widget>[
                                const Text(
                                  'Alert Threshold',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_s.speedAlertDisplayValue.toInt()} ${_s.speedUnit}',
                                  style: const TextStyle(
                                    color: _teal,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _SliderRow(
                            value: _s.speedAlertDisplayValue,
                            min: _s.useKmh ? 30 : 20,
                            max: _s.speedAlertMax,
                            onChanged: _s.setSpeedAlertDisplayValue,
                          ),
                        ],
                      ],
                    ),
                    _Section(
                      title: 'STORAGE',
                      children: <Widget>[
                        _InfoRow(
                          label: 'Reset Factory Settings',
                          value: '',
                          valueColor: Colors.redAccent,
                          onTap: _confirmClearData,
                        ),
                      ],
                    ),
                    _Section(
                      title: 'SYSTEM',
                      children: const <Widget>[
                        _InfoRow(
                          label: 'Version',
                          value: '1.5.0',
                        ),
                        _Sep(),
                        _InfoRow(
                          label: 'API Status',
                          value: 'ONLINE',
                          valueColor: _teal,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: _SettingsScreenState._teal,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _SettingsScreenState._card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: _SettingsScreenState._teal,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (value.isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? Colors.white.withValues(alpha: 0.3),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (onTap != null) ...<Widget>[
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                color: Colors.white.withValues(alpha: 0.1),
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final double safeValue = value.clamp(min, max).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: CupertinoSlider(
        value: safeValue,
        min: min,
        max: max,
        activeColor: _SettingsScreenState._teal,
        onChanged: onChanged,
      ),
    );
  }
}

class _AccuracyChip extends StatelessWidget {
  const _AccuracyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const Color teal = _SettingsScreenState._teal;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? teal.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? teal : Colors.white.withValues(alpha: 0.05),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? teal : Colors.white.withValues(alpha: 0.3),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
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
      color: Colors.white.withValues(alpha: 0.03),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
