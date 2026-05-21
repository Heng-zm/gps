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

enum ExportFormat {
  gpx,
  kml,
  csv,
  json,
  summaryImage,
}

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
        ExportFormat.gpx => 'GPX',
        ExportFormat.kml => 'KML',
        ExportFormat.csv => 'CSV',
        ExportFormat.json => 'JSON',
        ExportFormat.summaryImage => 'Summary Image',
      };

  String get description => switch (this) {
        ExportFormat.gpx => 'Best for GPS apps and route import.',
        ExportFormat.kml => 'Best for Google Earth and map viewers.',
        ExportFormat.csv => 'Best for spreadsheets and analysis.',
        ExportFormat.json => 'Best for backup and developers.',
        ExportFormat.summaryImage => 'Best for sharing a clean trip card.',
      };

  String get helperText => switch (this) {
        ExportFormat.gpx => 'Route geometry + GPS timestamps',
        ExportFormat.kml => 'Map viewer friendly route layer',
        ExportFormat.csv => 'Rows for spreadsheet filtering',
        ExportFormat.json => 'Complete structured backup',
        ExportFormat.summaryImage => 'Image card for social sharing',
      };

  IconData get icon => switch (this) {
        ExportFormat.gpx => CupertinoIcons.location_fill,
        ExportFormat.kml => CupertinoIcons.map_fill,
        ExportFormat.csv => CupertinoIcons.table,
        ExportFormat.json => CupertinoIcons.doc_text_fill,
        ExportFormat.summaryImage => CupertinoIcons.photo_fill,
      };

  String get mimeType => switch (this) {
        ExportFormat.gpx => 'application/gpx+xml',
        ExportFormat.kml => 'application/vnd.google-earth.kml+xml',
        ExportFormat.csv => 'text/csv',
        ExportFormat.json => 'application/json',
        ExportFormat.summaryImage => 'image/png',
      };

  String get fileExtension => switch (this) {
        ExportFormat.gpx => 'gpx',
        ExportFormat.kml => 'kml',
        ExportFormat.csv => 'csv',
        ExportFormat.json => 'json',
        ExportFormat.summaryImage => 'png',
      };

  Color get accentColor => switch (this) {
        ExportFormat.gpx => AppColors.blueSoft,
        ExportFormat.kml => AppColors.green,
        ExportFormat.csv => const Color(0xFF34D399),
        ExportFormat.json => const Color(0xFFA78BFA),
        ExportFormat.summaryImage => const Color(0xFFFBBF24),
      };

  String get uppercaseLabel => label.toUpperCase();
}

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

  final Future<ExportResult> Function(ExportFormat format)? onExport;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  static const double _headerAvatarSize = 56;
  static const double _headerAvatarIcon = 24;
  static const double _headerTitleSize = 18;
  static const double _headerSubtitleSize = 12;
  static const double _headerSpacing = 14;
  static const Color _errorColor = Color(0xFFFF453A);

  ExportFormat _selected = ExportFormat.gpx;
  bool _busy = false;

  final GlobalKey _exportButtonKey = GlobalKey();

  Future<void> _export() async {
    if (_busy) return;

    final Future<ExportResult> Function(ExportFormat format)? handler =
        widget.onExport;

    if (handler == null) {
      _showSnackBar(
        'Export handler is not connected.',
        isError: true,
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final ExportResult result = await handler(_selected);
      if (!mounted) return;

      switch (result) {
        case _FileResult(:final File file):
          if (!await file.exists()) {
            _showSnackBar('Export file was not created.', isError: true);
            return;
          }
          await _shareFile(file);

        case _HandledResult():
          _showSnackBar('${_selected.label} export started.');
      }
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Export failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareFile(File file) async {
    final String fileName = _buildFileName();

    final XFile xFile = XFile(
      file.path,
      mimeType: _selected.mimeType,
      name: fileName,
    );

    final RenderObject? renderObject =
        _exportButtonKey.currentContext?.findRenderObject();

    final Rect shareOrigin = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : Rect.zero;

    final ShareResult shareResult = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[xFile],
        subject: fileName,
        text: 'Trip export: ${_selected.label}',
        sharePositionOrigin: shareOrigin,
      ),
    );

    if (!mounted) return;

    if (shareResult.status == ShareResultStatus.success) {
      _showSnackBar('${_selected.label} shared successfully.');
    }
  }

  String _buildFileName() {
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);

    return 'trip_export_$timestamp.${_selected.fileExtension}';
  }

  void _selectFormat(ExportFormat format) {
    if (_busy || _selected == format) return;
    setState(() => _selected = format);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? _errorColor : AppColors.card,
        content: Row(
          children: <Widget>[
            Icon(
              isError
                  ? CupertinoIcons.exclamationmark_triangle_fill
                  : CupertinoIcons.checkmark_circle_fill,
              color: AppColors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ExportFormat selected = _selected;

    return AppPageShell(
      title: 'Export Center',
      subtitle: 'Share, backup or analyze your trip data',
      showBackButton: true,
      trailing: AppStatusPill(
        label: selected.uppercaseLabel,
        color: selected.accentColor,
        icon: selected.icon,
      ),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: <Widget>[
          AppGlassCard(
            padding: const EdgeInsets.all(18),
            borderRadius: 30,
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: _headerAvatarSize,
                  height: _headerAvatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.blueButtonGradient,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: selected.accentColor.withValues(alpha: 0.34),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      selected.icon,
                      key: ValueKey<ExportFormat>(selected),
                      color: AppColors.white,
                      size: _headerAvatarIcon,
                    ),
                  ),
                ),
                const SizedBox(width: _headerSpacing),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Column(
                      key: ValueKey<ExportFormat>(selected),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Export as ${selected.label}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: _headerTitleSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          selected.helperText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white54,
                            fontSize: _headerSubtitleSize,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppSectionCard(
            title: 'Formats',
            subtitle: _busy
                ? 'Export is running'
                : 'Select one export option',
            icon: CupertinoIcons.doc_on_doc_fill,
            spacing: 10,
            children: ExportFormat.values.map((ExportFormat format) {
              return _ExportFormatTile(
                format: format,
                selected: selected == format,
                enabled: !_busy,
                onTap: () => _selectFormat(format),
              );
            }).toList(growable: false),
          ),
          AppSectionCard(
            title: 'Action',
            subtitle: widget.onExport == null
                ? 'Connect export handler first'
                : 'Generate and share file',
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
                KeyedSubtree(
                  key: _exportButtonKey,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: AppActionButton(
                      key: ValueKey<String>(
                        _busy ? 'busy' : selected.storageKey,
                      ),
                      label: _busy
                          ? 'Exporting...'
                          : 'Export ${selected.label}',
                      icon: _busy
                          ? CupertinoIcons.hourglass
                          : selected.icon,
                      primary: true,
                      enabled: !_busy,
                      onTap: _export,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

extension _ExportFormatStorageX on ExportFormat {
  String get storageKey => name;
}

class _ExportFormatTile extends StatefulWidget {
  const _ExportFormatTile({
    required this.format,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ExportFormatTile> createState() => _ExportFormatTileState();
}

class _ExportFormatTileState extends State<_ExportFormatTile> {
  static const double _tileLabelSize = 13;
  static const double _tileSubtitleSize = 11;
  static const double _tileIconSize = 18;
  static const double _tileIconSpacing = 11;
  static const double _tilePadding = 13;
  static const double _tileBorderRadius = 18;

  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final ExportFormat format = widget.format;
    final bool selected = widget.selected;
    final bool enabled = widget.enabled;
    final Color color = selected ? format.accentColor : AppColors.white54;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${format.label} export format',
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled ? 1 : 0.55,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(_tilePadding),
              decoration: BoxDecoration(
                color: selected
                    ? format.accentColor.withValues(alpha: 0.15)
                    : AppColors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(_tileBorderRadius),
                border: Border.all(
                  color: selected
                      ? format.accentColor.withValues(alpha: 0.30)
                      : AppColors.white.withValues(alpha: 0.07),
                ),
              ),
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: selected ? 0.15 : 0.08),
                    ),
                    child: Icon(
                      format.icon,
                      color: color,
                      size: _tileIconSize,
                    ),
                  ),
                  const SizedBox(width: _tileIconSpacing),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          format.label,
                          style: TextStyle(
                            color: selected
                                ? AppColors.white
                                : AppColors.white70,
                            fontSize: _tileLabelSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          format.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white54,
                            fontSize: _tileSubtitleSize,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      selected
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      key: ValueKey<bool>(selected),
                      color: color,
                      size: _tileIconSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
