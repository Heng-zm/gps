import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/settings_service.dart' as settings_svc;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final settings_svc.SettingsService _s = settings_svc.SettingsService.instance;
  LocationPermission _locationPermission = LocationPermission.denied;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSettingsChanged);
    _checkPermission();
    if (!_s.isLoaded) _s.load();
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
    final perm = await Geolocator.checkPermission();
    if (mounted) setState(() => _locationPermission = perm);
  }

  String get _permissionLabel {
    switch (_locationPermission) {
      case LocationPermission.always:
        return 'Always';
      case LocationPermission.whileInUse:
        return 'While Using';
      case LocationPermission.deniedForever:
        return 'Denied Forever';
      default:
        return 'Denied';
    }
  }

  Color get _permissionColor {
    switch (_locationPermission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return const Color(0xFF4ECDC4);
      default:
        return const Color(0xFFE74C3C);
    }
  }

  void _confirmClearData() {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
            'This will reset all settings to defaults and delete saved trips.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(context).pop();
              await _s.clearAllData();
            },
            child: const Text('Clear'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Text('SETTINGS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
              ),

              // Permissions
              _Section(title: 'PERMISSIONS', children: [
                _InfoRow(
                  label: 'Location Access',
                  value: _permissionLabel,
                  valueColor: _permissionColor,
                  onTap: () async {
                    if (_locationPermission == LocationPermission.denied) {
                      await Geolocator.requestPermission();
                    } else if (_locationPermission ==
                        LocationPermission.deniedForever) {
                      await Geolocator.openAppSettings();
                    }
                    await _checkPermission();
                  },
                ),
              ]),

              // Units
              _Section(title: 'UNITS', children: [
                _ToggleRow(
                  label: 'Use km/h & km',
                  subtitle: 'Display speed and distance in metric units',
                  value: _s.useKmh,
                  onChanged: (v) => _s.setUseKmh(v),
                ),
              ]),

              // Display
              _Section(title: 'DISPLAY', children: [
                _ToggleRow(
                  label: 'Keep Screen On',
                  subtitle: 'Prevent sleep while tracking',
                  value: _s.keepScreenOn,
                  onChanged: (v) => _s.setKeepScreenOn(v),
                ),
                const _Sep(),
                _ToggleRow(
                  label: 'Show Weather',
                  subtitle: 'Live weather card on tracker screen',
                  value: _s.showWeather,
                  onChanged: (v) => _s.setShowWeather(v),
                ),
                const _Sep(),
                _ToggleRow(
                  label: 'Show Altitude',
                  subtitle: 'Display altitude in the stats grid',
                  value: _s.showAltitude,
                  onChanged: (v) => _s.setShowAltitude(v),
                ),
                const _Sep(),
                _ToggleRow(
                  label: 'Show Heading',
                  subtitle: 'Show compass direction below speedometer',
                  value: _s.showHeading,
                  onChanged: (v) => _s.setShowHeading(v),
                ),
              ]),

              // GPS Accuracy
              _Section(title: 'GPS ACCURACY', children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Mode',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Text(_s.gpsAccuracyLabel,
                              style: const TextStyle(
                                  color: Color(0xFF4ECDC4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _AccuracyChip(
                              label: 'Best',
                              selected: _s.gpsAccuracyMode == 0,
                              onTap: () => _s.setGpsAccuracyMode(0)),
                          _AccuracyChip(
                              label: 'Balanced',
                              selected: _s.gpsAccuracyMode == 1,
                              onTap: () => _s.setGpsAccuracyMode(1)),
                          _AccuracyChip(
                              label: 'Low Power',
                              selected: _s.gpsAccuracyMode == 2,
                              onTap: () => _s.setGpsAccuracyMode(2)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _s.gpsAccuracyMode == 0
                            ? 'Maximum accuracy. Uses more battery.'
                            : _s.gpsAccuracyMode == 1
                                ? 'Balanced accuracy and battery usage.'
                                : 'Conserves battery. Less precise.',
                        style: const TextStyle(
                            color: Color(0xFF555555), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ]),

              // Trips
              _Section(title: 'TRIPS', children: [
                _ToggleRow(
                  label: 'Auto-Save Trips',
                  subtitle: 'Save trips automatically on stop',
                  value: _s.autoSaveTrips,
                  onChanged: (v) => _s.setAutoSaveTrips(v),
                ),
              ]),

              // Speed Alert
              _Section(title: 'SPEED ALERT', children: [
                _ToggleRow(
                  label: 'Speed Alert',
                  subtitle: 'Notify when exceeding the speed limit',
                  value: _s.speedAlertEnabled,
                  onChanged: (v) => _s.setSpeedAlertEnabled(v),
                ),
                if (_s.speedAlertEnabled) ...[
                  const _Sep(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Alert Speed',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500)),
                          Text(
                            '${_s.speedAlertDisplayValue.toInt()} ${_s.speedUnit}',
                            style: const TextStyle(
                                color: Color(0xFF4ECDC4),
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: CupertinoSlider(
                      value: _s.speedAlertDisplayValue
                          .clamp(_s.useKmh ? 30.0 : 20.0, _s.speedAlertMax),
                      min: _s.useKmh ? 30.0 : 20.0,
                      max: _s.speedAlertMax,
                      divisions: _s.useKmh ? 290 : 180,
                      activeColor: const Color(0xFF4ECDC4),
                      onChanged: (v) => _s.setSpeedAlertDisplayValue(v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_s.useKmh ? '30 km/h' : '20 mph',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 11)),
                        Text(_s.useKmh ? '320 km/h' : '200 mph',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ]),

              // About
              _Section(title: 'ABOUT', children: [
                const _InfoRow(label: 'Version', value: '1.0.0'),
                const _Sep(),
                const _InfoRow(label: 'Map Provider', value: 'OpenStreetMap'),
                const _Sep(),
                const _InfoRow(label: 'Weather Provider', value: 'Open-Meteo'),
                const _Sep(),
                const _InfoRow(label: 'Accuracy Filter', value: '15m (GPS)'),
              ]),

              // Danger zone
              _Section(title: 'DATA', children: [
                GestureDetector(
                  onTap: _confirmClearData,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Icon(CupertinoIcons.trash,
                          color: Color(0xFFE74C3C), size: 18),
                      SizedBox(width: 12),
                      Text('Clear All Data & Settings',
                          style: TextStyle(
                              color: Color(0xFFE74C3C),
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ]),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable layout widgets ───────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title,
                style: const TextStyle(
                    color: Color(0xFF4ECDC4),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF555555), fontSize: 12)),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: const Color(0xFF4ECDC4),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final VoidCallback? onTap;
  const _InfoRow(
      {required this.label, required this.value, this.valueColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? const Color(0xFF666666),
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(CupertinoIcons.chevron_right,
                color: Color(0xFF444444), size: 14),
          ],
        ]),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 16),
        child: Divider(color: Color(0xFF252525), height: 1),
      );
}

class _AccuracyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AccuracyChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
              : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF4ECDC4) : const Color(0xFF333333),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected
                    ? const Color(0xFF4ECDC4)
                    : const Color(0xFF666666),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
