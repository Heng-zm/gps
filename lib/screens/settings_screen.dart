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

  void _showMapStylePicker() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Map Engine Style'),
        message: const Text('Select your preferred visualization mode'),
        actions: AppMapStyle.values.map((style) {
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
      ),
    );
  }

  void _confirmClearData() {
    HapticFeedback.heavyImpact();
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Reset All Data?'),
        content: const Text(
            'This will return all settings to factory defaults and clear your trip cache.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(context).pop();
              await _s.clearAllData();
            },
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF4ECDC4);
    const bg = Color(0xFF070707);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      // Removed generic SafeArea here to allow SliverNavbar to reach the top
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Settings',
                style: TextStyle(color: Colors.white, letterSpacing: -1)),
            backgroundColor: bg.withOpacity(0.8),
            border: null,
          ),
          // SliverSafeArea ensures content doesn't hit the bottom indicator or side notches
          SliverSafeArea(
            top: false, // Top is already handled by the Navigation Bar
            bottom: true,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 40),
                child: Column(
                  children: [
                    // Permissions
                    _Section(title: 'PERMISSIONS', children: [
                      _InfoRow(
                        label: 'Location Access',
                        value: _locationPermission.name.toUpperCase(),
                        valueColor:
                            (_locationPermission == LocationPermission.always ||
                                    _locationPermission ==
                                        LocationPermission.whileInUse)
                                ? teal
                                : Colors.redAccent,
                        onTap: () async {
                          await Geolocator.openAppSettings();
                          _checkPermission();
                        },
                      ),
                    ]),

                    // Customization
                    _Section(title: 'VISUALS & UNITS', children: [
                      _ToggleRow(
                        label: 'Metric System',
                        subtitle: 'Use KM/H and Meters',
                        value: _s.useKmh,
                        onChanged: (v) => _s.setUseKmh(v),
                      ),
                      const _Sep(),
                      _InfoRow(
                        label: 'Map Style',
                        value: _s.mapStyle.name.toUpperCase(),
                        onTap: _showMapStylePicker,
                      ),
                    ]),

                    // GPS & Sensors
                    _Section(title: 'SENSORS', children: [
                      _ToggleRow(
                        label: 'Keep Screen On',
                        subtitle: 'Active during tracking',
                        value: _s.keepScreenOn,
                        onChanged: (v) => _s.setKeepScreenOn(v),
                      ),
                      const _Sep(),
                      _ToggleRow(
                        label: 'Show Altitude',
                        value: _s.showAltitude,
                        onChanged: (v) => _s.setShowAltitude(v),
                      ),
                      const _Sep(),
                      _ToggleRow(
                        label: 'Show Heading',
                        value: _s.showHeading,
                        onChanged: (v) => _s.setShowHeading(v),
                      ),
                    ]),

                    // GPS Accuracy
                    _Section(title: 'GPS PERFORMANCE', children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Accuracy Mode',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
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
                                    label: 'BEST',
                                    selected: _s.gpsAccuracyMode == 0,
                                    onTap: () => _s.setGpsAccuracyMode(0)),
                                _AccuracyChip(
                                    label: 'BALANCED',
                                    selected: _s.gpsAccuracyMode == 1,
                                    onTap: () => _s.setGpsAccuracyMode(1)),
                                _AccuracyChip(
                                    label: 'ECO',
                                    selected: _s.gpsAccuracyMode == 2,
                                    onTap: () => _s.setGpsAccuracyMode(2)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ]),

                    // Speed Alert
                    _Section(title: 'SAFETY', children: [
                      _ToggleRow(
                        label: 'Speed Alert',
                        subtitle: 'Visual warning when exceeding limit',
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        _SliderRow(
                          value: _s.speedAlertDisplayValue,
                          min: _s.useKmh ? 30 : 20,
                          max: _s.speedAlertMax,
                          onChanged: (v) => _s.setSpeedAlertDisplayValue(v),
                        ),
                      ],
                    ]),

                    // Storage/Danger Zone
                    _Section(title: 'STORAGE', children: [
                      _InfoRow(
                        label: 'Reset Factory Settings',
                        value: '',
                        valueColor: Colors.redAccent,
                        onTap: _confirmClearData,
                      ),
                    ]),

                    // System Info
                    _Section(title: 'SYSTEM', children: [
                      _InfoRow(label: 'Version', value: '1.5.0'),
                      const _Sep(),
                      _InfoRow(
                          label: 'API Status',
                          value: 'ONLINE',
                          valueColor: teal),
                    ]),
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

// ── Reusable Widgets remains the same ─────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text(title,
              style: const TextStyle(
                  color: Color(0xFF4ECDC4),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow(
      {required this.label,
      this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4), fontSize: 12)),
                ]
              ],
            ),
          ),
          CupertinoSwitch(
              value: value,
              activeTrackColor: const Color(0xFF4ECDC4),
              onChanged: onChanged),
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? Colors.white.withOpacity(0.3),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right,
                color: Colors.white.withOpacity(0.1), size: 14),
          ],
        ]),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _SliderRow(
      {required this.value,
      required this.min,
      required this.max,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: CupertinoSlider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        activeColor: const Color(0xFF4ECDC4),
        onChanged: onChanged,
      ),
    );
  }
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
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? teal.withOpacity(0.1) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? teal : Colors.white.withOpacity(0.05),
              width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? teal : Colors.white.withOpacity(0.3),
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
      height: 1,
      color: Colors.white.withOpacity(0.03),
      margin: const EdgeInsets.symmetric(horizontal: 16));
}
