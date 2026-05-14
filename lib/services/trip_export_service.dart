import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_data.dart';

/// Real file export service for GPX / CSV / KML.
///
/// Requires pubspec.yaml:
///
/// dependencies:
///   path_provider: ^2.1.5
///   share_plus: ^10.1.4
///
/// Mobile/Desktop writes files to temporary storage and opens the share sheet.
/// Web uses XFile.fromData when the browser supports Web Share.
class TripExportService {
  const TripExportService._();

  static Future<TripExportResult> shareTripFiles({
    required String tripId,
    required DateTime date,
    required List<TripPoint> points,
    String appName = 'TrackPro AI',
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

    final String gpx = buildGpx(
      name: title,
      date: date,
      points: valid,
      creator: appName,
    );

    final String csv = buildCsv(points: valid);

    final String kml = buildKml(
      name: title,
      points: valid,
    );

    try {
      final List<XFile> files = <XFile>[];

      if (kIsWeb) {
        files.addAll(<XFile>[
          XFile.fromData(
            utf8.encode(gpx),
            name: '$safeName.gpx',
            mimeType: 'application/gpx+xml',
          ),
          XFile.fromData(
            utf8.encode(csv),
            name: '$safeName.csv',
            mimeType: 'text/csv',
          ),
          XFile.fromData(
            utf8.encode(kml),
            name: '$safeName.kml',
            mimeType: 'application/vnd.google-earth.kml+xml',
          ),
        ]);
      } else {
        final Directory dir = await getTemporaryDirectory();

        final File gpxFile = File('${dir.path}/$safeName.gpx');
        final File csvFile = File('${dir.path}/$safeName.csv');
        final File kmlFile = File('${dir.path}/$safeName.kml');

        await Future.wait<void>(<Future<void>>[
          gpxFile.writeAsString(gpx, flush: true),
          csvFile.writeAsString(csv, flush: true),
          kmlFile.writeAsString(kml, flush: true),
        ]);

        files.addAll(<XFile>[
          XFile(
            gpxFile.path,
            mimeType: 'application/gpx+xml',
            name: '$safeName.gpx',
          ),
          XFile(
            csvFile.path,
            mimeType: 'text/csv',
            name: '$safeName.csv',
          ),
          XFile(
            kmlFile.path,
            mimeType: 'application/vnd.google-earth.kml+xml',
            name: '$safeName.kml',
          ),
        ]);
      }

      final ShareResult result = await Share.shareXFiles(
        files,
        subject: '$appName Trip Export',
        text: 'TrackPro AI trip export: GPX, CSV and KML files.',
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
          'lat,lng,speed_mph,speed_kmh,altitude_ft,altitude_m,timestamp,accuracy_m');

    for (final TripPoint point in _validPoints(points)) {
      final double lat = point.position.latitude;
      final double lng = point.position.longitude;
      final double speedMph = _safeDouble(point.speedMph);
      final double speedKmh = speedMph * 1.609344;
      final double altFt = _safeDouble(point.altitudeFt);
      final double altM = altFt * 0.3048;
      final String time = point.timestamp.toUtc().toIso8601String();
      final double acc = _safeDouble(point.accuracyMeters);

      buffer.writeln(
        <String>[
          lat.toStringAsFixed(7),
          lng.toStringAsFixed(7),
          speedMph.toStringAsFixed(2),
          speedKmh.toStringAsFixed(2),
          altFt.toStringAsFixed(2),
          altM.toStringAsFixed(2),
          _csvEscape(time),
          acc.toStringAsFixed(1),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  static String buildKml({
    required String name,
    required List<TripPoint> points,
  }) {
    final List<TripPoint> valid = _validPoints(points);
    final String safeName = _xmlEscape(name);

    final String coordinates = valid.map((TripPoint point) {
      final double lng = point.position.longitude;
      final double lat = point.position.latitude;
      final double eleMeters = _safeDouble(point.altitudeFt) * 0.3048;

      return '${lng.toStringAsFixed(7)},${lat.toStringAsFixed(7)},${eleMeters.toStringAsFixed(2)}';
    }).join(' ');

    final TripPoint start = valid.first;
    final TripPoint end = valid.last;

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$safeName</name>
    <Style id="trackproRoute">
      <LineStyle>
        <color>ff43a8d4</color>
        <width>5</width>
      </LineStyle>
    </Style>
    <Placemark>
      <name>$safeName Route</name>
      <styleUrl>#trackproRoute</styleUrl>
      <LineString>
        <tessellate>1</tessellate>
        <altitudeMode>clampToGround</altitudeMode>
        <coordinates>$coordinates</coordinates>
      </LineString>
    </Placemark>
    <Placemark>
      <name>Start</name>
      <Point>
        <coordinates>${start.position.longitude.toStringAsFixed(7)},${start.position.latitude.toStringAsFixed(7)},0</coordinates>
      </Point>
    </Placemark>
    <Placemark>
      <name>End</name>
      <Point>
        <coordinates>${end.position.longitude.toStringAsFixed(7)},${end.position.latitude.toStringAsFixed(7)},0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>
''';
  }

  static List<TripPoint> _validPoints(List<TripPoint> points) {
    final List<TripPoint> valid = <TripPoint>[];
    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double lat = point.position.latitude;
      final double lng = point.position.longitude;

      final bool ok = lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90.0 &&
          lng.abs() <= 180.0;

      if (!ok) continue;

      if (lastLat != null &&
          lastLng != null &&
          lastLat == lat &&
          lastLng == lng) {
        continue;
      }

      valid.add(point);
      lastLat = lat;
      lastLng = lng;
    }

    return List<TripPoint>.unmodifiable(valid);
  }

  static String _safeFileName(String value) {
    final String cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return cleaned.isEmpty ? 'trackpro_trip' : cleaned;
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
