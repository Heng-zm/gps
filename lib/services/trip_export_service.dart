import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_data.dart';

/// Real file export/share service for GPX / CSV / KML / JSON / TXT.
///
/// Uses the current `share_plus` API:
/// `SharePlus.instance.share(ShareParams(...))`.
class TripExportService {
  const TripExportService._();

  /// Shares the standard trip export bundle used by SummaryScreen.
  static Future<TripExportResult> shareTripFiles({
    required String tripId,
    required DateTime date,
    required List<TripPoint> points,
    String appName = 'TrackPro AI',
    BuildContext? context,
  }) async {
    final List<TripPoint> valid = _validPoints(points);

    if (valid.length < 2) {
      return const TripExportResult(
        success: false,
        message: 'Not enough route points to export files.',
        fileCount: 0,
      );
    }

    final String safeName = _safeFileName(
      'trackpro_${tripId.isEmpty ? date.millisecondsSinceEpoch : tripId}',
    );

    final String title =
        '$appName Trip ${tripId.isEmpty ? date.millisecondsSinceEpoch : tripId}';

    final List<XFile> files = <XFile>[
      _xFileFromText(
        name: '$safeName.gpx',
        mimeType: 'application/gpx+xml',
        content: buildGpx(
          name: title,
          date: date,
          points: valid,
          creator: appName,
        ),
      ),
      _xFileFromText(
        name: '$safeName.csv',
        mimeType: 'text/csv',
        content: buildCsv(points: valid),
      ),
      _xFileFromText(
        name: '$safeName.kml',
        mimeType: 'application/vnd.google-earth.kml+xml',
        content: buildKml(name: title, points: valid),
      ),
    ];

    try {
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: '$appName Trip Export',
          text: '$appName trip export: GPX, CSV and KML files.',
          sharePositionOrigin:
              context == null ? null : _shareOrigin(context),
        ),
      );

      final bool dismissed = result.status == ShareResultStatus.dismissed;

      return TripExportResult(
        success: !dismissed,
        message: dismissed
            ? 'Export prepared, but sharing was cancelled.'
            : 'GPX, CSV and KML files shared.',
        fileCount: files.length,
      );
    } catch (error) {
      return TripExportResult(
        success: false,
        message: 'Export failed: $error',
        fileCount: 0,
      );
    }
  }

  /// Shares one generated export file. Used by History export formats.
  static Future<bool> shareRawFile({
    required BuildContext context,
    required String filename,
    required String content,
    required String mimeType,
    String? subject,
    String? text,
  }) async {
    try {
      final XFile file = _xFileFromText(
        name: filename,
        mimeType: mimeType,
        content: content,
      );

      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[file],
          subject: subject ?? filename,
          text: text,
          sharePositionOrigin: _shareOrigin(context),
        ),
      );

      return result.status != ShareResultStatus.dismissed;
    } catch (_) {
      return false;
    }
  }

  static XFile _xFileFromText({
    required String name,
    required String mimeType,
    required String content,
  }) {
    return XFile.fromData(
      Uint8List.fromList(utf8.encode(content)),
      name: _safeFileName(name),
      mimeType: mimeType,
      lastModified: DateTime.now(),
    );
  }

  static Rect? _shareOrigin(BuildContext context) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  static String buildGpx({
    required String name,
    required DateTime date,
    required List<TripPoint> points,
    String creator = 'TrackPro AI',
  }) {
    final String safeName = _xmlEscape(name);
    final String time = date.toUtc().toIso8601String();

    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="${_xmlEscape(creator)}" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>$safeName</name>')
      ..writeln('    <time>$time</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>$safeName</name>')
      ..writeln('    <trkseg>');

    for (final TripPoint point in _validPoints(points)) {
      final double lat = point.position.latitude;
      final double lng = point.position.longitude;
      final double eleMeters = _safeDouble(point.altitudeFt) * 0.3048;
      final String pointTime = point.timestamp.toUtc().toIso8601String();

      buffer
        ..write('      <trkpt lat="${lat.toStringAsFixed(7)}" ')
        ..writeln('lon="${lng.toStringAsFixed(7)}">')
        ..writeln('        <ele>${eleMeters.toStringAsFixed(2)}</ele>')
        ..writeln('        <time>$pointTime</time>')
        ..writeln('        <extensions>')
        ..writeln(
          '          <speed_mph>${_safeDouble(point.speedMph).toStringAsFixed(2)}</speed_mph>',
        )
        ..writeln(
          '          <accuracy_m>${_safeDouble(point.accuracyMeters).toStringAsFixed(1)}</accuracy_m>',
        )
        ..writeln('        </extensions>')
        ..writeln('      </trkpt>');
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');

    return buffer.toString();
  }

  static String buildCsv({
    required List<TripPoint> points,
  }) {
    final StringBuffer buffer = StringBuffer()
      ..writeln(
        'lat,lng,speed_mph,speed_kmh,altitude_ft,altitude_m,accuracy_m,timestamp',
      );

    for (final TripPoint point in _validPoints(points)) {
      final List<String> row = <String>[
        point.position.latitude.toStringAsFixed(7),
        point.position.longitude.toStringAsFixed(7),
        _safeDouble(point.speedMph).toStringAsFixed(2),
        (_safeDouble(point.speedMph) * 1.609344).toStringAsFixed(2),
        _safeDouble(point.altitudeFt).toStringAsFixed(2),
        (_safeDouble(point.altitudeFt) * 0.3048).toStringAsFixed(2),
        _safeDouble(point.accuracyMeters).toStringAsFixed(1),
        point.timestamp.toUtc().toIso8601String(),
      ];

      buffer.writeln(row.map(_csvEscape).join(','));
    }

    return buffer.toString();
  }

  static String buildKml({
    required String name,
    required List<TripPoint> points,
  }) {
    final String safeName = _xmlEscape(name);
    final String coordinates = _validPoints(points).map((TripPoint point) {
      final double lng = point.position.longitude;
      final double lat = point.position.latitude;
      final double eleMeters = _safeDouble(point.altitudeFt) * 0.3048;
      return '${lng.toStringAsFixed(7)},${lat.toStringAsFixed(7)},${eleMeters.toStringAsFixed(2)}';
    }).join(' ');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$safeName</name>
    <Placemark>
      <name>$safeName</name>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>$coordinates</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
''';
  }

  static String buildJson({
    required String tripId,
    required DateTime date,
    required List<TripPoint> points,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'id': tripId,
      'date': date.toUtc().toIso8601String(),
      'points': _validPoints(points).map((TripPoint point) {
        return <String, dynamic>{
          'lat': point.position.latitude,
          'lng': point.position.longitude,
          'speedMph': _safeDouble(point.speedMph),
          'altitudeFt': _safeDouble(point.altitudeFt),
          'accuracyMeters': _safeDouble(point.accuracyMeters),
          'timestamp': point.timestamp.toUtc().toIso8601String(),
        };
      }).toList(growable: false),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static List<TripPoint> _validPoints(List<TripPoint> points) {
    return points
        .where((TripPoint point) => point.isValid)
        .toList(growable: false);
  }

  static String _safeFileName(String value) {
    final String cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'trip_export.txt' : cleaned;
  }

  static String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _csvEscape(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }

    return '"${value.replaceAll('"', '""')}"';
  }

  static double _safeDouble(double value) {
    if (!value.isFinite) return 0.0;
    return value;
  }
}

class TripExportResult {
  const TripExportResult({
    required this.success,
    required this.message,
    required this.fileCount,
  });

  final bool success;
  final String message;
  final int fileCount;
}
