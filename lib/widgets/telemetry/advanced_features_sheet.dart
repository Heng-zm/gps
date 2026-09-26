import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'gforce_meter_widget.dart';
import 'obd2_telemetry_sheet.dart';
import 'anti_theft_sheet.dart';
import 'lidar_road_scanner_sheet.dart';

/// Unified Pro Hub modal hosting G-Force, OBD-II, Anti-Theft Sentry, and LiDAR Scanner
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

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double maxH = size.height * 0.88;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Row(
                      children: <Widget>[
                        Icon(CupertinoIcons.sparkles, size: 16, color: AppColors.blueSoft),
                        SizedBox(width: 8),
                        Text(
                          'PRO TELEMETRY & SECURITY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 32,
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

              // Segmented Tab Selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: <Widget>[
                      _buildTabButton(0, 'G-Force', CupertinoIcons.speedometer),
                      _buildTabButton(1, 'OBD-II', CupertinoIcons.car_detailed),
                      _buildTabButton(2, 'Sentry', CupertinoIcons.shield_fill),
                      _buildTabButton(3, 'LiDAR', CupertinoIcons.waveform_path_ecg),
                    ],
                  ),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final bool isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_selectedTab == index) return;
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.blue.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: isSelected
                ? Border.all(color: AppColors.blueSoft.withValues(alpha: 0.5), width: 1.0)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 13,
                color: isSelected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 5),
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
      ),
    );
  }
}
