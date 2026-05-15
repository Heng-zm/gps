import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common/app_action_button.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_glass_card.dart';
import '../../widgets/common/app_page_shell.dart';
import '../../widgets/common/app_section_card.dart';
import '../../widgets/common/app_status_pill.dart';

enum ExportFormat {
  gpx,
  kml,
  csv,
  json,
  summaryImage,
}

extension ExportFormatX on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.gpx:
        return 'GPX';
      case ExportFormat.kml:
        return 'KML';
      case ExportFormat.csv:
        return 'CSV';
      case ExportFormat.json:
        return 'JSON';
      case ExportFormat.summaryImage:
        return 'Summary Image';
    }
  }

  String get description {
    switch (this) {
      case ExportFormat.gpx:
        return 'Best for GPS apps and route import.';
      case ExportFormat.kml:
        return 'Best for Google Earth and map viewers.';
      case ExportFormat.csv:
        return 'Best for spreadsheets and analysis.';
      case ExportFormat.json:
        return 'Best for backup and developers.';
      case ExportFormat.summaryImage:
        return 'Best for sharing a clean trip card.';
    }
  }

  IconData get icon {
    switch (this) {
      case ExportFormat.gpx:
        return CupertinoIcons.location_fill;
      case ExportFormat.kml:
        return CupertinoIcons.map_fill;
      case ExportFormat.csv:
        return CupertinoIcons.table;
      case ExportFormat.json:
        return CupertinoIcons.doc_text_fill;
      case ExportFormat.summaryImage:
        return CupertinoIcons.photo_fill;
    }
  }
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    this.onExport,
  });

  final Future<void> Function(ExportFormat format)? onExport;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportFormat _selected = ExportFormat.gpx;
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await widget.onExport?.call(_selected);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.card,
          content: Text(
            '${_selected.label} export started.',
            style: const TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageShell(
      title: 'Export Center',
      subtitle: 'Share, backup or analyze your trip data',
      showBackButton: true,
      trailing: AppStatusPill(
        label: _selected.label.toUpperCase(),
        color: AppColors.blueSoft,
        icon: _selected.icon,
      ),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          AppGlassCard(
            padding: const EdgeInsets.all(18),
            borderRadius: 30,
            child: Row(
              children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.blueButtonGradient,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.blue.withValues(alpha: 0.30),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.square_arrow_up_fill,
                    color: AppColors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Choose export format',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Export your route, trip stats or a visual summary.',
                        style: TextStyle(
                          color: AppColors.white54,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSectionCard(
            title: 'Formats',
            subtitle: 'Select one export option',
            icon: CupertinoIcons.doc_on_doc_fill,
            spacing: 10,
            children: ExportFormat.values.map((ExportFormat format) {
              return _ExportFormatTile(
                format: format,
                selected: _selected == format,
                onTap: () => setState(() => _selected = format),
              );
            }).toList(growable: false),
          ),
          AppSectionCard(
            title: 'Action',
            subtitle: 'Generate and share file',
            icon: CupertinoIcons.paperplane_fill,
            children: <Widget>[
              if (widget.onExport == null)
                const AppEmptyState(
                  icon: CupertinoIcons.info_circle_fill,
                  title: 'Export handler not connected',
                  message:
                      'Pass onExport from Summary or History to connect this screen to your TripExportService.',
                )
              else
                AppActionButton(
                  label: _busy ? 'Exporting...' : 'Export ${_selected.label}',
                  icon: _selected.icon,
                  primary: true,
                  enabled: !_busy,
                  onTap: _export,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportFormatTile extends StatelessWidget {
  const _ExportFormatTile({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.blueSoft : AppColors.white54;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: 0.14)
              : AppColors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.blueSoft.withValues(alpha: 0.25)
                : AppColors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(format.icon, color: color, size: 18),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    format.label,
                    style: TextStyle(
                      color: selected ? AppColors.white : AppColors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    format.description,
                    style: const TextStyle(
                      color: AppColors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: color,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
