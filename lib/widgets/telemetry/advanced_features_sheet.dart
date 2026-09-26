import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'gforce_meter_widget.dart';
import 'obd2_telemetry_sheet.dart';
import 'anti_theft_sheet.dart';
import 'lidar_road_scanner_sheet.dart';
import 'satellite_sos_sheet.dart';
import 'glosa_speed_sheet.dart';
import 'ferromagnetic_radar_sheet.dart';
import 'holographic_hud_screen.dart';

/// Unified Pro Hub modal hosting G-Force, OBD-II, Anti-Theft Sentry, LiDAR,
/// Satellite SOS, GLOSA Speed Advisory, and Ferromagnetic Radar.
class AdvancedFeaturesSheet extends StatefulWidget {
  const AdvancedFeaturesSheet({
    super.key,
    this.initialTab = 0,
  });

  final int initialTab;

  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdvancedFeaturesSheet(initialTab: initialTab),
    );
  }

  @override
  State<AdvancedFeaturesSheet> createState() => _AdvancedFeaturesSheetState();
}

class _AdvancedFeaturesSheetState extends State<AdvancedFeaturesSheet> {
  late int _selectedTab;

  static const List<(String, IconData)> _kTabs = <(String, IconData)>[
    ('G-Force', CupertinoIcons.speedometer),
    ('OBD-II', CupertinoIcons.car_detailed),
    ('Sentry', CupertinoIcons.shield_fill),
    ('LiDAR', CupertinoIcons.waveform_path_ecg),
    ('Sat SOS', CupertinoIcons.antenna_radiowaves_left_right),
    ('GLOSA', Icons.traffic),
    ('Radar', CupertinoIcons.compass_fill),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, _kTabs.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double maxH = size.height * 0.90;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Sheet Drag Handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),

              // Pro Hub Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.sparkles, size: 16, color: AppColors.blueSoft),
                    const SizedBox(width: 8),
                    const Text(
                      'PRO TELEMETRY & SECURITY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    // 1-Tap Windshield HUD Mode Trigger
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      color: AppColors.blue.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      minSize: 30,
                      onPressed: () {
                        Navigator.pop(context);
                        HolographicHudScreen.open(context);
                      },
                      child: const Row(
                        children: <Widget>[
                          Icon(CupertinoIcons.moon_stars_fill, size: 12, color: AppColors.blueSoft),
                          SizedBox(width: 5),
                          Text(
                            'HUD MODE',
                            style: TextStyle(
                              color: AppColors.blueSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: () => Navigator.pop(context),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.xmark, size: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Horizontal Scrollable Segmented Tab Selector
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _kTabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (BuildContext context, int index) {
                    final (String label, IconData icon) = _kTabs[index];
                    final bool isSelected = _selectedTab == index;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_selectedTab == index) return;
                        HapticFeedback.selectionClick();
                        setState(() => _selectedTab = index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.blue.withValues(alpha: 0.35)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(color: AppColors.blueSoft.withValues(alpha: 0.55), width: 1.0)
                              : Border.all(color: Colors.white.withValues(alpha: 0.07)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              icon,
                              size: 13,
                              color: isSelected ? Colors.white : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white60,
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),

              // Tab View Content
              Flexible(
                child: IndexedStack(
                  index: _selectedTab,
                  children: const <Widget>[
                    SingleChildScrollView(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: GForceMeterWidget(size: 250),
                    ),
                    Obd2TelemetrySheet(),
                    AntiTheftSheet(),
                    LidarRoadScannerSheet(),
                    SatelliteSosSheet(),
                    GlosaSpeedSheet(),
                    FerromagneticRadarSheet(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
