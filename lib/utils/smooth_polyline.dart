import 'dart:collection';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Polyline utilities for GPS routes.
///
/// Features:
/// - Removes invalid GPS points.
/// - Removes duplicate / near-duplicate points.
/// - Uses iterative Douglas-Peucker simplification to avoid recursion overflow.
/// - Guards against bad epsilon, tension, subdivisions, and output sizes.
/// - Supports adaptive map optimization based on route size.
/// - Supports chart downsampling.
/// - Supports approximate route length calculation.
/// - Supports lightweight bounds without depending on flutter_map.
/// - Keeps first and last route points stable.
/// - Avoids expensive sqrt where possible.

const double _kDefaultEpsilon = 0.00005;
const double _kDefaultDuplicateTolerance = 0.000006;
const int _kDefaultMaxOutputPoints = 1800;

const double _kMinLatitude = -90.0;
const double _kMaxLatitude = 90.0;
const double _kMinLongitude = -180.0;
const double _kMaxLongitude = 180.0;

const double _kEarthRadiusMeters = 6371008.8;

/// Simplifies a polyline using Douglas-Peucker.
///
/// [epsilon] is in degrees:
/// - 0.00002 ≈ 2.2 m
/// - 0.00005 ≈ 5.5 m
/// - 0.00010 ≈ 11 m
///
/// This version is iterative instead of recursive, which is safer for long
/// tracking routes.
List<LatLng> simplifyPolyline(
  List<LatLng> points, {
  double epsilon = _kDefaultEpsilon,
  bool removeDuplicates = true,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
  bool preserveClosedLoop = false,
}) {
  final List<LatLng> cleaned = _cleanPoints(
    points,
    removeDuplicates: removeDuplicates,
    duplicateTolerance: duplicateTolerance,
  );

  if (cleaned.length <= 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final bool isClosedLoop = preserveClosedLoop && _isClosedLoop(cleaned);
  final List<LatLng> source =
      isClosedLoop ? cleaned.sublist(0, cleaned.length - 1) : cleaned;

  if (source.length <= 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final double safeEpsilon =
      epsilon.isFinite && epsilon > 0.0 ? epsilon : _kDefaultEpsilon;

  final double epsilonSq = safeEpsilon * safeEpsilon;
  final List<bool> keep = List<bool>.filled(source.length, false);

  keep[0] = true;
  keep[source.length - 1] = true;

  final Queue<_SegmentRange> stack = Queue<_SegmentRange>()
    ..add(_SegmentRange(0, source.length - 1));

  while (stack.isNotEmpty) {
    final _SegmentRange range = stack.removeLast();

    if (range.last <= range.first + 1) continue;

    double maxDistSq = 0.0;
    int maxIndex = range.first;

    final LatLng start = source[range.first];
    final LatLng end = source[range.last];

    for (int i = range.first + 1; i < range.last; i++) {
      final double distanceSq = _getSqSegDist(source[i], start, end);

      if (distanceSq > maxDistSq) {
        maxDistSq = distanceSq;
        maxIndex = i;
      }
    }

    if (maxDistSq > epsilonSq) {
      keep[maxIndex] = true;

      stack
        ..add(_SegmentRange(range.first, maxIndex))
        ..add(_SegmentRange(maxIndex, range.last));
    }
  }

  final List<LatLng> result = <LatLng>[];

  for (int i = 0; i < source.length; i++) {
    if (keep[i]) result.add(source[i]);
  }

  if (isClosedLoop && result.isNotEmpty) {
    result.add(result.first);
  }

  return List<LatLng>.unmodifiable(result);
}

/// Smooths a list of [LatLng] points using Catmull-Rom interpolation.
///
/// [tension]:
/// - 0.0 = loose curve
/// - 0.5 = balanced/default
/// - 1.0 = tighter curve
///
/// [subdivisions] controls inserted points between route points.
/// Use 4-10 for mobile maps. Higher values are expensive.
///
/// [maxOutputPoints] prevents generating too many render points.
List<LatLng> smoothPolyline(
  List<LatLng> points, {
  double tension = 0.5,
  int subdivisions = 10,
  int maxOutputPoints = _kDefaultMaxOutputPoints,
  bool removeDuplicates = true,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
  bool preserveClosedLoop = false,
}) {
  final List<LatLng> cleaned = _cleanPoints(
    points,
    removeDuplicates: removeDuplicates,
    duplicateTolerance: duplicateTolerance,
  );

  final int len = cleaned.length;

  if (len < 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final double safeTension =
      tension.isFinite ? tension.clamp(0.0, 1.0).toDouble() : 0.5;

  final int safeSubdivisions = subdivisions.clamp(1, 24);
  final int safeMaxOutput = math.max(2, maxOutputPoints);

  if (len == 2) {
    return List<LatLng>.unmodifiable(
      _linearSubdivide(
        cleaned[0],
        cleaned[1],
        safeSubdivisions,
        maxOutputPoints: safeMaxOutput,
      ),
    );
  }

  final bool isClosedLoop = preserveClosedLoop && _isClosedLoop(cleaned);
  final List<LatLng> source =
      isClosedLoop ? cleaned.sublist(0, cleaned.length - 1) : cleaned;

  if (source.length < 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final int estimatedOutput = ((source.length - 1) * safeSubdivisions) + 1;
  final int outputStride = estimatedOutput <= safeMaxOutput
      ? 1
      : (estimatedOutput / safeMaxOutput).ceil();

  final List<LatLng> result = <LatLng>[];

  int outputCounter = 0;

  for (int i = 0; i < source.length - 1; i++) {
    final LatLng p0 = _controlPointBefore(source, i, isClosedLoop);
    final LatLng p1 = source[i];
    final LatLng p2 = source[i + 1];
    final LatLng p3 = _controlPointAfter(source, i + 1, isClosedLoop);

    _maybeAddPoint(
      result,
      p1,
      outputCounter++,
      outputStride,
      duplicateTolerance,
    );

    for (int s = 1; s < safeSubdivisions; s++) {
      final double t = s / safeSubdivisions;

      final LatLng interpolated = _catmullRom(
        p0,
        p1,
        p2,
        p3,
        t,
        safeTension,
      );

      _maybeAddPoint(
        result,
        interpolated,
        outputCounter++,
        outputStride,
        duplicateTolerance,
      );
    }
  }

  _addIfDifferent(result, source.last, duplicateTolerance);

  if (isClosedLoop && result.isNotEmpty) {
    _addIfDifferent(result, result.first, duplicateTolerance);
  }

  return List<LatLng>.unmodifiable(result);
}

/// Simplifies first, then smooths.
///
/// This is the recommended helper for UI maps because it keeps route quality
/// while avoiding thousands of expensive polyline points.
List<LatLng> optimizePolylineForMap(
  List<LatLng> points, {
  double epsilon = 0.00004,
  double tension = 0.5,
  int subdivisions = 8,
  int maxOutputPoints = _kDefaultMaxOutputPoints,
  bool preserveClosedLoop = false,
}) {
  final List<LatLng> simplified = simplifyPolyline(
    points,
    epsilon: epsilon,
    preserveClosedLoop: preserveClosedLoop,
  );

  return smoothPolyline(
    simplified,
    tension: tension,
    subdivisions: subdivisions,
    maxOutputPoints: maxOutputPoints,
    preserveClosedLoop: preserveClosedLoop,
  );
}

/// Adaptive optimization for live GPS maps.
///
/// This automatically adjusts epsilon/subdivisions based on route size.
/// Use this when you do not want to manually tune values.
List<LatLng> optimizePolylineAdaptive(
  List<LatLng> points, {
  int maxOutputPoints = _kDefaultMaxOutputPoints,
  bool preserveClosedLoop = false,
}) {
  final int count = points.length;

  if (count <= 2) {
    return _cleanPoints(points);
  }

  double epsilon;
  int subdivisions;

  if (count < 100) {
    epsilon = 0.000025;
    subdivisions = 10;
  } else if (count < 500) {
    epsilon = 0.00004;
    subdivisions = 8;
  } else if (count < 1500) {
    epsilon = 0.00007;
    subdivisions = 6;
  } else {
    epsilon = 0.00011;
    subdivisions = 4;
  }

  return optimizePolylineForMap(
    points,
    epsilon: epsilon,
    tension: 0.5,
    subdivisions: subdivisions,
    maxOutputPoints: maxOutputPoints,
    preserveClosedLoop: preserveClosedLoop,
  );
}

/// Downsamples points by keeping first, last, and evenly spaced middle points.
///
/// Good for charts, previews, thumbnails, or mini maps.
List<LatLng> downsamplePolyline(
  List<LatLng> points, {
  int maxPoints = 300,
}) {
  final List<LatLng> cleaned = _cleanPoints(points);

  final int safeMax = math.max(2, maxPoints);

  if (cleaned.length <= safeMax) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final int lastIndex = cleaned.length - 1;
  final double step = lastIndex / (safeMax - 1);

  final List<LatLng> result = <LatLng>[];

  for (int i = 0; i < safeMax; i++) {
    final int index = (i * step).round().clamp(0, lastIndex);
    final LatLng point = cleaned[index];

    _addIfDifferent(result, point, 0.0);
  }

  _addIfDifferent(result, cleaned.last, 0.0);

  return List<LatLng>.unmodifiable(result);
}

/// Downsamples numeric values for charts.
List<double> downsampleValues(
  List<double> values, {
  int maxPoints = 120,
}) {
  final List<double> cleaned = values.where((double value) {
    return value.isFinite;
  }).toList(growable: false);

  final int safeMax = math.max(2, maxPoints);

  if (cleaned.length <= safeMax) {
    return List<double>.unmodifiable(cleaned);
  }

  final int lastIndex = cleaned.length - 1;
  final double step = lastIndex / (safeMax - 1);

  final List<double> result = <double>[];

  for (int i = 0; i < safeMax; i++) {
    final int index = (i * step).round().clamp(0, lastIndex);
    result.add(cleaned[index]);
  }

  return List<double>.unmodifiable(result);
}

/// Calculates approximate route bounds.
///
/// Returns null if no valid points exist.
LatLngBoundsLite? calculatePolylineBounds(List<LatLng> points) {
  final List<LatLng> cleaned = _cleanPoints(
    points,
    removeDuplicates: false,
  );

  if (cleaned.isEmpty) return null;

  double minLat = cleaned.first.latitude;
  double maxLat = cleaned.first.latitude;
  double minLng = cleaned.first.longitude;
  double maxLng = cleaned.first.longitude;

  for (final LatLng point in cleaned) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLng = math.min(minLng, point.longitude);
    maxLng = math.max(maxLng, point.longitude);
  }

  return LatLngBoundsLite(
    southWest: LatLng(minLat, minLng),
    northEast: LatLng(maxLat, maxLng),
  );
}

/// Calculates approximate total route length in meters.
///
/// Uses haversine distance and ignores invalid points.
double calculatePolylineDistanceMeters(List<LatLng> points) {
  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.length < 2) return 0.0;

  double total = 0.0;

  for (int i = 1; i < cleaned.length; i++) {
    total += calculateDistanceMeters(cleaned[i - 1], cleaned[i]);
  }

  return total.isFinite ? total : 0.0;
}

/// Calculates approximate distance between two points in meters.
double calculateDistanceMeters(LatLng a, LatLng b) {
  if (!_isValidLatLng(a) || !_isValidLatLng(b)) return 0.0;

  final double lat1 = _degToRad(a.latitude);
  final double lat2 = _degToRad(b.latitude);
  final double dLat = _degToRad(b.latitude - a.latitude);
  final double dLng = _degToRad(b.longitude - a.longitude);

  final double sinLat = math.sin(dLat / 2.0);
  final double sinLng = math.sin(dLng / 2.0);

  final double h =
      sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;

  final double c = 2.0 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));

  final double meters = _kEarthRadiusMeters * c;

  return meters.isFinite ? meters : 0.0;
}

/// Calculates heading/bearing from [from] to [to] in degrees.
/// Returns 0 when input is invalid.
double calculateBearingDegrees(LatLng from, LatLng to) {
  if (!_isValidLatLng(from) || !_isValidLatLng(to)) return 0.0;

  final double lat1 = _degToRad(from.latitude);
  final double lat2 = _degToRad(to.latitude);
  final double dLng = _degToRad(to.longitude - from.longitude);

  final double y = math.sin(dLng) * math.cos(lat2);
  final double x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

  final double degrees = _radToDeg(math.atan2(y, x));

  return normalizeDegrees(degrees);
}

/// Normalizes degrees to 0-360.
double normalizeDegrees(double degrees) {
  if (!degrees.isFinite) return 0.0;

  final double normalized = degrees % 360.0;
  return normalized < 0.0 ? normalized + 360.0 : normalized;
}

/// Gets the last valid point in a list.
LatLng? lastValidPoint(List<LatLng> points) {
  for (int i = points.length - 1; i >= 0; i--) {
    final LatLng point = points[i];
    if (_isValidLatLng(point)) return point;
  }

  return null;
}

/// Gets the first valid point in a list.
LatLng? firstValidPoint(List<LatLng> points) {
  for (final LatLng point in points) {
    if (_isValidLatLng(point)) return point;
  }

  return null;
}

/// Squared perpendicular distance from [point] to segment [start]-[end].
///
/// Uses longitude as x and latitude as y.
/// Avoids sqrt for performance.
double _getSqSegDist(LatLng point, LatLng start, LatLng end) {
  double x = start.longitude;
  double y = start.latitude;

  double dx = end.longitude - x;
  double dy = end.latitude - y;

  if (dx != 0.0 || dy != 0.0) {
    final double denominator = dx * dx + dy * dy;

    if (denominator > 0.0) {
      final double t =
          ((point.longitude - x) * dx + (point.latitude - y) * dy) /
              denominator;

      if (t > 1.0) {
        x = end.longitude;
        y = end.latitude;
      } else if (t > 0.0) {
        x += dx * t;
        y += dy * t;
      }
    }
  }

  dx = point.longitude - x;
  dy = point.latitude - y;

  return dx * dx + dy * dy;
}

/// Catmull-Rom interpolation between [p1] and [p2].
LatLng _catmullRom(
  LatLng p0,
  LatLng p1,
  LatLng p2,
  LatLng p3,
  double t,
  double tension,
) {
  final double t2 = t * t;
  final double t3 = t2 * t;

  final double b0 = -tension * t3 + 2.0 * tension * t2 - tension * t;
  final double b1 = (2.0 - tension) * t3 + (tension - 3.0) * t2 + 1.0;
  final double b2 =
      (tension - 2.0) * t3 + (3.0 - 2.0 * tension) * t2 + tension * t;
  final double b3 = tension * t3 - tension * t2;

  return LatLng(
    b0 * p0.latitude + b1 * p1.latitude + b2 * p2.latitude + b3 * p3.latitude,
    b0 * p0.longitude +
        b1 * p1.longitude +
        b2 * p2.longitude +
        b3 * p3.longitude,
  );
}

/// Linear interpolation for 2-point polylines.
List<LatLng> _linearSubdivide(
  LatLng a,
  LatLng b,
  int subdivisions, {
  required int maxOutputPoints,
}) {
  final int safeSubdivisions = subdivisions.clamp(1, 24);
  final int count = math.min(safeSubdivisions + 1, maxOutputPoints);

  if (count <= 2) {
    return <LatLng>[a, b];
  }

  final List<LatLng> result = <LatLng>[];

  for (int i = 0; i < count; i++) {
    final double t = i / (count - 1);

    result.add(
      LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
    );
  }

  return result;
}

LatLng _controlPointBefore(
  List<LatLng> points,
  int index,
  bool isClosedLoop,
) {
  if (index > 0) return points[index - 1];

  if (isClosedLoop && points.length > 2) {
    return points[points.length - 2];
  }

  return _reflectPoint(points[1], points[0]);
}

LatLng _controlPointAfter(
  List<LatLng> points,
  int index,
  bool isClosedLoop,
) {
  final int nextIndex = index + 1;

  if (nextIndex < points.length) return points[nextIndex];

  if (isClosedLoop && points.length > 2) {
    return points[1];
  }

  return _reflectPoint(points[points.length - 2], points.last);
}

/// Point reflection for spline control points.
LatLng _reflectPoint(LatLng anchor, LatLng pivot) {
  return LatLng(
    2.0 * pivot.latitude - anchor.latitude,
    2.0 * pivot.longitude - anchor.longitude,
  );
}

void _maybeAddPoint(
  List<LatLng> result,
  LatLng point,
  int outputCounter,
  int outputStride,
  double duplicateTolerance,
) {
  if (outputCounter % outputStride != 0) return;
  _addIfDifferent(result, point, duplicateTolerance);
}

void _addIfDifferent(
  List<LatLng> result,
  LatLng point,
  double tolerance,
) {
  if (!_isValidLatLng(point)) return;

  if (result.isEmpty || !_nearlySame(result.last, point, tolerance)) {
    result.add(point);
  }
}

List<LatLng> _cleanPoints(
  List<LatLng> points, {
  bool removeDuplicates = true,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
}) {
  if (points.isEmpty) return const <LatLng>[];

  final double safeTolerance =
      duplicateTolerance.isFinite && duplicateTolerance >= 0.0
          ? duplicateTolerance
          : _kDefaultDuplicateTolerance;

  final List<LatLng> cleaned = <LatLng>[];

  for (final LatLng point in points) {
    if (!_isValidLatLng(point)) continue;

    if (removeDuplicates &&
        cleaned.isNotEmpty &&
        _nearlySame(cleaned.last, point, safeTolerance)) {
      continue;
    }

    cleaned.add(point);
  }

  return cleaned;
}

bool _isValidLatLng(LatLng point) {
  final double lat = point.latitude;
  final double lng = point.longitude;

  return lat.isFinite &&
      lng.isFinite &&
      lat >= _kMinLatitude &&
      lat <= _kMaxLatitude &&
      lng >= _kMinLongitude &&
      lng <= _kMaxLongitude;
}

bool _nearlySame(LatLng a, LatLng b, double tolerance) {
  if (tolerance <= 0.0) {
    return a.latitude == b.latitude && a.longitude == b.longitude;
  }

  final double dLat = a.latitude - b.latitude;
  final double dLng = a.longitude - b.longitude;

  return (dLat * dLat + dLng * dLng) <= tolerance * tolerance;
}

bool _isClosedLoop(List<LatLng> points) {
  if (points.length < 3) return false;
  return _nearlySame(points.first, points.last, _kDefaultDuplicateTolerance);
}

double _degToRad(double degrees) {
  return degrees * math.pi / 180.0;
}

double _radToDeg(double radians) {
  return radians * 180.0 / math.pi;
}

class _SegmentRange {
  const _SegmentRange(this.first, this.last);

  final int first;
  final int last;
}

/// Lightweight bounds object so this utility does not depend on flutter_map.
class LatLngBoundsLite {
  const LatLngBoundsLite({
    required this.southWest,
    required this.northEast,
  });

  final LatLng southWest;
  final LatLng northEast;

  LatLng get center {
    return LatLng(
      (southWest.latitude + northEast.latitude) / 2.0,
      (southWest.longitude + northEast.longitude) / 2.0,
    );
  }

  double get widthDegrees {
    return (northEast.longitude - southWest.longitude).abs();
  }

  double get heightDegrees {
    return (northEast.latitude - southWest.latitude).abs();
  }

  bool get isPoint {
    return southWest.latitude == northEast.latitude &&
        southWest.longitude == northEast.longitude;
  }

  bool contains(LatLng point) {
    return point.latitude >= southWest.latitude &&
        point.latitude <= northEast.latitude &&
        point.longitude >= southWest.longitude &&
        point.longitude <= northEast.longitude;
  }

  LatLngBoundsLite pad({
    double latitudePadding = 0.0005,
    double longitudePadding = 0.0005,
  }) {
    final double safeLatPadding =
        latitudePadding.isFinite && latitudePadding > 0.0
            ? latitudePadding
            : 0.0;

    final double safeLngPadding =
        longitudePadding.isFinite && longitudePadding > 0.0
            ? longitudePadding
            : 0.0;

    return LatLngBoundsLite(
      southWest: LatLng(
        (southWest.latitude - safeLatPadding).clamp(
          _kMinLatitude,
          _kMaxLatitude,
        ),
        (southWest.longitude - safeLngPadding).clamp(
          _kMinLongitude,
          _kMaxLongitude,
        ),
      ),
      northEast: LatLng(
        (northEast.latitude + safeLatPadding).clamp(
          _kMinLatitude,
          _kMaxLatitude,
        ),
        (northEast.longitude + safeLngPadding).clamp(
          _kMinLongitude,
          _kMaxLongitude,
        ),
      ),
    );
  }

  @override
  String toString() {
    return 'LatLngBoundsLite(southWest: $southWest, northEast: $northEast)';
  }
}
