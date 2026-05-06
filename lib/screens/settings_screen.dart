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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF4ECDC4);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Text('SETTINGS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
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
                          const Text('Precision Mode',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(_s.gpsAccuracyLabel,
                              style: const TextStyle(
                                  color: teal,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                              label: 'Eco',
                              selected: _s.gpsAccuracyMode == 2,
                              onTap: () => _s.setGpsAccuracyMode(2)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _s.gpsAccuracyMode == 0
                            ? 'Maximum precision for professional driving. High battery.'
                            : _s.gpsAccuracyMode == 1
                                ? 'Standard accuracy for typical city driving.'
                                : 'Aggressive battery conservation. Less precise tracking.',
                        style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ]),

              // Speed Alert
              _Section(title: 'SPEED ALERT', children: [
                _ToggleRow(
                  label: 'Over-speed Notification',
                  subtitle: 'Dashboard turns red when limit is exceeded',
                  value: _s.speedAlertEnabled,
                  onChanged: (v) => _s.setSpeedAlertEnabled(v),
                ),
                if (_s.speedAlertEnabled) ...[
                  const _Sep(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(children: [
                      const Text('Alert Threshold',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        '${_s.speedAlertDisplayValue.toInt()} ${_s.speedUnit}',
                        style: const TextStyle(
                            color: teal,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
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
                      divisions: _s.useKmh ? 27 : 18,
                      activeColor: teal,
                      onChanged: (v) => _s.setSpeedAlertDisplayValue(v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_s.useKmh ? '30' : '20',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        Text(_s.useKmh ? '300' : '180',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ]),

              // About
              _Section(title: 'SYSTEM', children: [
                const _InfoRow(label: 'TrackPro Version', value: '1.2.0'),
                const _Sep(),
                const _InfoRow(label: 'Map Engine', value: 'CartoDB Dark'),
                const _Sep(),
                const _InfoRow(label: 'Weather API', value: 'Open-Meteo'),
              ]),

              // Danger zone
              _Section(title: 'STORAGE', children: [
                GestureDetector(
                  onTap: _confirmClearData,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(children: [
                      Icon(CupertinoIcons.trash,
                          color: Color(0xFFE74C3C), size: 18),
                      SizedBox(width: 12),
                      Text('Delete All Cached Trips',
                          style: TextStyle(
                              color: Color(0xFFE74C3C),
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),

              const SizedBox(height: 60),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Text(title,
                style: const TextStyle(
                    color: Color(0xFF4ECDC4),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF222222)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF666666), fontSize: 12, height: 1.3)),
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
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? const Color(0xFF666666),
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          if (onTap != null) ...[
            const SizedBox(width: 8),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(color: const Color(0xFF222222), height: 1),
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
    const teal = Color(0xFF4ECDC4);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? teal.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? teal : const Color(0xFF333333),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? teal : const Color(0xFF777777),
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}
