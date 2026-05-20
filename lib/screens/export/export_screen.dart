import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common/app_action_button.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_glass_card.dart';
import '../../widgets/common/app_page_shell.dart';
import '../../widgets/common/app_section_card.dart';
import '../../widgets/common/app_status_pill.dart';

// pubspec.yaml: share_plus: ^10.0.0
// SharePlus / ShareParams were introduced in share_plus v10.
// Older versions only expose Share.shareXFiles() — upgrade to fix the
// "Undefined name 'SharePlus'" and "'ShareParams' isn't defined" errors.

enum ExportFormat {
  gpx,
  kml,
  csv,
  json,
  summaryImage,
}

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
        ExportFormat.gpx          => 'GPX',
        ExportFormat.kml          => 'KML',
        ExportFormat.csv          => 'CSV',
        ExportFormat.json         => 'JSON',
        ExportFormat.summaryImage => 'Summary Image',
      };

  String get description => switch (this) {
        ExportFormat.gpx          => 'Best for GPS apps and route import.',
        ExportFormat.kml          => 'Best for Google Earth and map viewers.',
        ExportFormat.csv          => 'Best for spreadsheets and analysis.',
        ExportFormat.json         => 'Best for backup and developers.',
        ExportFormat.summaryImage => 'Best for sharing a clean trip card.',
      };

  IconData get icon => switch (this) {
        ExportFormat.gpx          => CupertinoIcons.location_fill,
        ExportFormat.kml          => CupertinoIcons.map_fill,
        ExportFormat.csv          => CupertinoIcons.table,
        ExportFormat.json         => CupertinoIcons.doc_text_fill,
        ExportFormat.summaryImage => CupertinoIcons.photo_fill,
      };

  /// MIME type passed to the OS share sheet so receiving apps can filter
  /// by file type (e.g. only GPS apps appear when sharing GPX).
  String get mimeType => switch (this) {
        ExportFormat.gpx          => 'application/gpx+xml',
        ExportFormat.kml          => 'application/vnd.google-earth.kml+xml',
        ExportFormat.csv          => 'text/csv',
        ExportFormat.json         => 'application/json',
        ExportFormat.summaryImage => 'image/png',
      };

  /// File extension used when building the default share filename.
  String get fileExtension => switch (this) {
        ExportFormat.gpx          => 'gpx',
        ExportFormat.kml          => 'kml',
        ExportFormat.csv          => 'csv',
        ExportFormat.json         => 'json',
        ExportFormat.summaryImage => 'png',
      };

  String get uppercaseLabel => label.toUpperCase();
}

/// Result returned by [ExportScreen.onExport].
///
/// - [ExportResult.file] — the screen opens the OS share sheet for the file.
/// - [ExportResult.handled] — the caller handled sharing itself; the screen
///   shows a success snackbar only (e.g. server upload with its own UI).
sealed class ExportResult {
  const ExportResult();

  const factory ExportResult.file(File file) = _FileResult;
  const factory ExportResult.handled() = _HandledResult;
}

class _FileResult extends ExportResult {
  const _FileResult(this.file);
  final File file;
}

class _HandledResult extends ExportResult {
  const _HandledResult();
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    this.onExport,
  });

  /// Called when the user taps Export.
  ///
  /// Return [ExportResult.file] with the written [File] to let the screen
  /// open the OS share sheet automatically.
  /// Return [ExportResult.handled] when the caller already handled sharing.
  /// Omit the callback entirely to show the "not connected" empty state.
  final Future<ExportResult> Function(ExportFormat format)? onExport;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  static const double _headerAvatarSize   = 54;
  static const double _headerAvatarIcon   = 24;
  static const double _headerTitleSize    = 18;
  static const double _headerSubtitleSize = 12;
  static const double _headerSpacing      = 14;

  // FIX: AppColors.error does not exist in this codebase. Using a local
  // constant instead of adding a dependency on a colour that may not be
  // defined in AppColors. Add AppColors.error to app_theme.dart if you
  // want to centralise it later.
  static const Color _errorColor = Color(0xFFFF453A); // iOS-system red

  ExportFormat _selected = ExportFormat.gpx;
  bool _busy = false;

  /// Anchors the iPad share-sheet popover to the Export button.
  /// On iPhone this origin is ignored by the OS.
  final GlobalKey _exportButtonKey = GlobalKey();

  Future<void> _export() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final ExportResult result = await widget.onExport!.call(_selected);
      if (!mounted) return;

      switch (result) {
        case _FileResult(:final File file):
          await _shareFile(file);

        case _HandledResult():
          _showSnackBar('${_selected.label} export started.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the OS share sheet for [file].
  ///
  /// Requires share_plus ≥ 10.0.0 for SharePlus / ShareParams.
  /// Anchors to [_exportButtonKey] on iPad for a proper popover position.
  /// Only shows the success snackbar when the user completed the share —
  /// not when they dismissed the sheet.
  Future<void> _shareFile(File file) async {
    final XFile xFile = XFile(
      file.path,
      mimeType: _selected.mimeType,
      name: _buildFileName(),
    );

    // Resolve the Export button's screen rect for the iPad popover.
    final RenderBox? box =
        _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;

    final ShareResult shareResult = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[xFile],
        subject: _buildFileName(),
        sharePositionOrigin: shareOrigin,
      ),
    );

    if (!mounted) return;

    // STATUS_DISMISSED means the user cancelled — no feedback needed.
    if (shareResult.status == ShareResultStatus.success) {
      _showSnackBar('${_selected.label} shared successfully.');
    }
  }

  /// Builds a timestamped filename: `trip_export_<ISO8601>.<ext>`.
  String _buildFileName() {
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    return 'trip_export_$timestamp.${_selected.fileExtension}';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        // FIX: AppColors.error is not defined. Falling back to the local
        // _errorColor constant. Define AppColors.error in app_theme.dart
        // to unify error colours across the app.
        backgroundColor: isError ? _errorColor : AppColors.card,
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageShell(
      title: 'Export Center',
      subtitle: 'Share, backup or analyze your trip data',
      showBackButton: true,
      trailing: AppStatusPill(
        label: _selected.uppercaseLabel,
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
                  width: _headerAvatarSize,
                  height: _headerAvatarSize,
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
                    size: _headerAvatarIcon,
                  ),
                ),
                const SizedBox(width: _headerSpacing),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Choose export format',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: _headerTitleSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Export your route, trip stats or a visual summary.',
                        style: TextStyle(
                          color: AppColors.white54,
                          fontSize: _headerSubtitleSize,
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
            }).toList(),
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
                // KeyedSubtree lets us resolve the button's screen position
                // for the iPad share-sheet popover without modifying AppActionButton.
                KeyedSubtree(
                  key: _exportButtonKey,
                  child: AppActionButton(
                    label: _busy ? 'Exporting...' : 'Export ${_selected.label}',
                    icon: _selected.icon,
                    primary: true,
                    enabled: !_busy,
                    onTap: _export,
                  ),
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

  static const double _tileLabelSize    = 13;
  static const double _tileSubtitleSize = 11;
  static const double _tileIconSize     = 18;
  static const double _tileIconSpacing  = 11;
  static const double _tilePadding      = 13;
  static const double _tileBorderRadius = 18;

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.blueSoft : AppColors.white54;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(_tilePadding),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: 0.14)
              : AppColors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(_tileBorderRadius),
          border: Border.all(
            color: selected
                ? AppColors.blueSoft.withValues(alpha: 0.25)
                : AppColors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(format.icon, color: color, size: _tileIconSize),
            const SizedBox(width: _tileIconSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    format.label,
                    style: TextStyle(
                      color: selected ? AppColors.white : AppColors.white70,
                      fontSize: _tileLabelSize,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    format.description,
                    style: const TextStyle(
                      color: AppColors.white54,
                      fontSize: _tileSubtitleSize,
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
              size: _tileIconSize,
            ),
          ],
        ),
      ),
    );
  }
}