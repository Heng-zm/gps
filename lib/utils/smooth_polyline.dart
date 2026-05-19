import 'dart:collection';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Polyline utilities for GPS routes.
///
/// ## Changes in this version
///
/// ### Bug fixes
/// - `_nearlySame` now uses real distance (`sqrt`) and clamps positive
///   tolerances to at least `1e-10` to avoid unstable comparisons at extremely
///   small values.
/// - `_getSqSegDist` and `_projectPointOnSegment` now treat near-zero segments
///   as points before division.
/// - Catmull-Rom interpolation clamps `t` to `[0, 1]` before basis evaluation.
/// - Closed-loop simplification/smoothing no longer creates `sublist` copies.
/// - `downsamplePolyline` and `downsampleValues` avoid intermediate cleaned
///   list copies in their hot paths.
///
/// ### Performance notes
/// Most helpers are O(N). For very large live routes, prefer
/// [optimizeLiveRoutePolyline], [optimizePolylineAdaptive], or
/// [optimizePolylineForZoom] before rendering. Douglas-Peucker simplification
/// is typically O(N log N), but can degrade toward O(N²) on adversarial input.
const double _kDefaultEpsilon = 0.00005;
const double _kDefaultDuplicateTolerance = 0.000006;
const int _kDefaultMaxOutputPoints = 1800;

const double _kMinLatitude = -90.0;
const double _kMaxLatitude = 90.0;
const double _kMinLongitude = -180.0;
const double _kMaxLongitude = 180.0;

const double _kEarthRadiusMeters = 6371008.8;
const double _kGeometryEpsilon = 1e-10;

// ---------------------------------------------------------------------------
// Simplification
// ---------------------------------------------------------------------------

/// Simplifies a polyline using iterative Douglas-Peucker.
///
/// [epsilon] is in degrees:
/// - 0.00002 ≈ 2.2 m
/// - 0.00005 ≈ 5.5 m
/// - 0.00010 ≈ 11 m
///
/// The iterative implementation is safe for arbitrarily long routes because it
/// avoids Dart's call-stack limit.
///
/// Complexity: usually O(N log N), but can approach O(N²) on worst-case routes.
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

  final int cleanedLength = cleaned.length;
  if (cleanedLength <= 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final bool isClosedLoop = preserveClosedLoop && _isClosedLoop(cleaned);
  final int sourceLength = isClosedLoop ? cleanedLength - 1 : cleanedLength;

  if (sourceLength <= 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final double safeEpsilon =
      epsilon.isFinite && epsilon > 0.0 ? epsilon : _kDefaultEpsilon;
  final double epsilonSq = safeEpsilon * safeEpsilon;

  final List<bool> keep = List<bool>.filled(sourceLength, false);
  keep[0] = true;
  keep[sourceLength - 1] = true;

  // Array-backed stack improves cache locality and avoids recursion.
  final ListQueue<_SegmentRange> stack = ListQueue<_SegmentRange>()
    ..add(_SegmentRange(0, sourceLength - 1));

  while (stack.isNotEmpty) {
    final _SegmentRange range = stack.removeLast();

    if (range.last <= range.first + 1) continue;

    double maxDistSq = 0.0;
    int maxIndex = range.first;

    final LatLng start = cleaned[range.first];
    final LatLng end = cleaned[range.last];

    for (int i = range.first + 1; i < range.last; i++) {
      final double distanceSq = _getSqSegDist(cleaned[i], start, end);

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

  for (int i = 0; i < sourceLength; i++) {
    if (keep[i]) result.add(cleaned[i]);
  }

  if (isClosedLoop && result.isNotEmpty) {
    result.add(result.first);
  }

  return List<LatLng>.unmodifiable(result);
}

// ---------------------------------------------------------------------------
// Smoothing
// ---------------------------------------------------------------------------

/// Smooths a list of [LatLng] points using Catmull-Rom interpolation.
///
/// [tension]:
/// - 0.0 = loose curve
/// - 0.5 = balanced default
/// - 1.0 = tighter curve
///
/// [subdivisions] controls how many points are inserted between each pair of
/// route points. Use 4–10 for mobile maps. Higher values are expensive.
///
/// Complexity: O(N * subdivisions). Use [maxOutputPoints] for large routes.
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

  final int cleanedLength = cleaned.length;

  if (cleanedLength < 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final double safeTension =
      tension.isFinite ? tension.clamp(0.0, 1.0).toDouble() : 0.5;
  final int safeSubdivisions = subdivisions.clamp(1, 24).toInt();
  final int safeMaxOutput = math.max(2, maxOutputPoints);

  if (cleanedLength == 2) {
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
  final int sourceLength = isClosedLoop ? cleanedLength - 1 : cleanedLength;

  if (sourceLength < 2) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final int estimatedOutput = ((sourceLength - 1) * safeSubdivisions) + 1;
  final int outputStride = estimatedOutput <= safeMaxOutput
      ? 1
      : (estimatedOutput / safeMaxOutput).ceil();

  final List<LatLng> result = <LatLng>[];
  int emitCounter = 0;

  for (int i = 0; i < sourceLength - 1; i++) {
    final LatLng p0 =
        _controlPointBefore(cleaned, i, sourceLength, isClosedLoop);
    final LatLng p1 = cleaned[i];
    final LatLng p2 = cleaned[i + 1];
    final LatLng p3 =
        _controlPointAfter(cleaned, i + 1, sourceLength, isClosedLoop);

    if (emitCounter % outputStride == 0) {
      _addIfDifferent(result, p1, duplicateTolerance);
    }
    emitCounter++;

    for (int s = 1; s < safeSubdivisions; s++) {
      if (emitCounter % outputStride == 0) {
        final double t = s / safeSubdivisions;
        final LatLng interpolated = _catmullRom(p0, p1, p2, p3, t, safeTension);
        _addIfDifferent(result, interpolated, duplicateTolerance);
      }
      emitCounter++;
    }
  }

  _addIfDifferent(result, cleaned[sourceLength - 1], duplicateTolerance);

  if (isClosedLoop && result.isNotEmpty) {
    _addIfDifferent(result, result.first, duplicateTolerance);
  }

  return List<LatLng>.unmodifiable(result);
}

// ---------------------------------------------------------------------------
// Combined helpers
// ---------------------------------------------------------------------------

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
  double duplicateTolerance = _kDefaultDuplicateTolerance,
  bool preserveClosedLoop = false,
}) {
  final List<LatLng> simplified = simplifyPolyline(
    points,
    epsilon: epsilon,
    duplicateTolerance: duplicateTolerance,
    preserveClosedLoop: preserveClosedLoop,
  );

  return smoothPolyline(
    simplified,
    tension: tension,
    subdivisions: subdivisions,
    maxOutputPoints: maxOutputPoints,
    duplicateTolerance: duplicateTolerance,
    preserveClosedLoop: preserveClosedLoop,
  );
}

/// Adaptive optimization for live GPS maps.
///
/// Automatically adjusts epsilon/subdivisions based on route size so you do
/// not need to manually tune values.
List<LatLng> optimizePolylineAdaptive(
  List<LatLng> points, {
  int maxOutputPoints = _kDefaultMaxOutputPoints,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
  bool preserveClosedLoop = false,
}) {
  final int count = points.length;

  if (count <= 2) {
    return _cleanPoints(points, duplicateTolerance: duplicateTolerance);
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
    duplicateTolerance: duplicateTolerance,
    preserveClosedLoop: preserveClosedLoop,
  );
}

/// Optimizes a route for a map zoom level.
///
/// Lower zooms get stronger simplification. High zooms preserve more detail.
/// [devicePixelRatio] allows high-density displays to retain slightly more
/// detail without overproducing render points.
List<LatLng> optimizePolylineForZoom(
  List<LatLng> points, {
  required double zoom,
  double devicePixelRatio = 1.0,
  int maxOutputPoints = _kDefaultMaxOutputPoints,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
  bool preserveClosedLoop = false,
}) {
  final double safeZoom =
      zoom.isFinite ? zoom.clamp(3.0, 22.0).toDouble() : 16.0;
  final double dpr = devicePixelRatio.isFinite
      ? devicePixelRatio.clamp(1.0, 4.0).toDouble()
      : 1.0;

  final double epsilon = safeZoom >= 18
      ? 0.000018 / dpr
      : safeZoom >= 16
          ? 0.000030 / dpr
          : safeZoom >= 14
              ? 0.000055 / dpr
              : safeZoom >= 12
                  ? 0.000090 / dpr
                  : 0.000140 / dpr;

  final int subdivisions = safeZoom >= 17
      ? 8
      : safeZoom >= 15
          ? 6
          : safeZoom >= 13
              ? 4
              : 2;

  return optimizePolylineForMap(
    points,
    epsilon: epsilon,
    tension: 0.5,
    subdivisions: subdivisions,
    maxOutputPoints: maxOutputPoints,
    duplicateTolerance: duplicateTolerance,
    preserveClosedLoop: preserveClosedLoop,
  );
}

/// Fast helper tuned for live GPS rendering.
///
/// It removes impossible jumps, simplifies the path, and smooths the route
/// without generating too many points for Flutter/Mapbox render layers.
List<LatLng> optimizeLiveRoutePolyline(
  List<LatLng> points, {
  double maxJumpMeters = 160.0,
  int maxOutputPoints = _kDefaultMaxOutputPoints,
  bool preserveClosedLoop = false,
}) {
  final List<LatLng> filtered = removeGpsJumps(
    points,
    maxJumpMeters: maxJumpMeters,
  );

  return optimizePolylineAdaptive(
    filtered,
    maxOutputPoints: maxOutputPoints.clamp(2, 5000).toInt(),
    preserveClosedLoop: preserveClosedLoop,
  );
}

/// Removes isolated GPS jumps.
///
/// This uses distance-only filtering because this utility does not receive
/// timestamps. It is intentionally conservative: it keeps the first point and
/// only drops a point when the jump from the previous kept point is too large.
///
/// Complexity: O(N), with haversine cost per accepted candidate.
List<LatLng> removeGpsJumps(
  List<LatLng> points, {
  double maxJumpMeters = 160.0,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
}) {
  final List<LatLng> cleaned = _cleanPoints(
    points,
    duplicateTolerance: duplicateTolerance,
  );

  final int cleanedLength = cleaned.length;
  if (cleanedLength <= 2) return List<LatLng>.unmodifiable(cleaned);

  final double safeMaxJump =
      maxJumpMeters.isFinite && maxJumpMeters > 0.0 ? maxJumpMeters : 160.0;

  final List<LatLng> result = <LatLng>[cleaned.first];

  for (int i = 1; i < cleanedLength; i++) {
    final LatLng previous = result.last;
    final LatLng current = cleaned[i];
    final double distance = calculateDistanceMeters(previous, current);

    if (distance <= safeMaxJump || i == cleanedLength - 1) {
      result.add(current);
    }
  }

  return List<LatLng>.unmodifiable(result);
}

/// Resamples a route into roughly equal-distance points.
///
/// Useful for replay markers, animated route previews, and progress tracking.
///
/// Complexity: O(N * targetCount) because each interpolation scans from start.
/// Keep [maxPoints] bounded for large routes.
List<LatLng> resamplePolylineByDistance(
  List<LatLng> points, {
  double spacingMeters = 10.0,
  int maxPoints = 2500,
}) {
  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.length < 2) return List<LatLng>.unmodifiable(cleaned);

  final double safeSpacing =
      spacingMeters.isFinite && spacingMeters > 0.1 ? spacingMeters : 10.0;
  final int safeMax = maxPoints.clamp(2, 10000).toInt();

  final double total = calculatePolylineDistanceMeters(cleaned);
  if (total <= 0.0) return List<LatLng>.unmodifiable(cleaned);

  final int targetCount =
      math.min((total / safeSpacing).ceil() + 1, safeMax).toInt();
  final List<LatLng> result = <LatLng>[];

  for (int i = 0; i < targetCount; i++) {
    final double distance = i == targetCount - 1
        ? total
        : (i * safeSpacing).clamp(0.0, total).toDouble();

    final LatLng? point = interpolatePointAtDistance(cleaned, distance);
    if (point != null) {
      _addIfDifferent(result, point, _kDefaultDuplicateTolerance);
    }
  }

  if (result.isEmpty || !_nearlySame(result.last, cleaned.last, 0.0)) {
    _addIfDifferent(result, cleaned.last, _kDefaultDuplicateTolerance);
  }

  return List<LatLng>.unmodifiable(result);
}

/// Returns route bearing at a cumulative distance.
///
/// Useful for replay vehicle heading or navigation puck orientation.
double? bearingAtDistance(
  List<LatLng> points,
  double distanceMeters, {
  double lookAheadMeters = 8.0,
}) {
  if (!distanceMeters.isFinite || distanceMeters < 0.0) return null;

  final List<LatLng> cleaned = _cleanPoints(points);
  if (cleaned.length < 2) return null;

  final double safeLookAhead =
      lookAheadMeters.isFinite && lookAheadMeters > 0.0 ? lookAheadMeters : 8.0;

  final LatLng? a = interpolatePointAtDistance(cleaned, distanceMeters);
  final LatLng? b = interpolatePointAtDistance(
    cleaned,
    distanceMeters + safeLookAhead,
  );

  if (a == null || b == null) return null;
  return calculateBearingDegrees(a, b);
}

/// Returns cumulative distance at the nearest point on a route.
///
/// This is useful for progress bars or snapping a live GPS point to a route.
double? cumulativeDistanceAtClosestPoint(
  List<LatLng> polyline,
  LatLng query,
) {
  final List<LatLng> cleaned = _cleanPoints(polyline, removeDuplicates: false);
  final ClosestPointResult? closest = closestPointOnPolyline(cleaned, query);

  if (closest == null) return null;

  double total = 0.0;

  for (int i = 1; i <= closest.segmentIndex; i++) {
    total += calculateDistanceMeters(cleaned[i - 1], cleaned[i]);
  }

  if (closest.segmentIndex < cleaned.length - 1) {
    total += calculateDistanceMeters(
      cleaned[closest.segmentIndex],
      closest.point,
    );
  }

  return total.isFinite ? total : null;
}

// ---------------------------------------------------------------------------
// Downsampling
// ---------------------------------------------------------------------------

/// Downsamples points by keeping first, last, and evenly-spaced middle points.
///
/// Good for charts, previews, thumbnails, or mini maps.
///
/// Complexity: O(N) for cleaning + O(maxPoints) for sampling.
List<LatLng> downsamplePolyline(
  List<LatLng> points, {
  int maxPoints = 300,
}) {
  final List<LatLng> cleaned = _cleanPoints(points);
  final int cleanedLength = cleaned.length;
  final int safeMax = math.max(2, maxPoints);

  if (cleanedLength <= safeMax) {
    return List<LatLng>.unmodifiable(cleaned);
  }

  final int lastIndex = cleanedLength - 1;
  final double step = lastIndex / (safeMax - 1);

  // Single fixed-size allocation. No result.toList() or extra growable copy.
  final List<LatLng> result =
      List<LatLng>.filled(safeMax, cleaned.first, growable: false);

  for (int i = 0; i < safeMax; i++) {
    final int index = (i * step).round().clamp(0, lastIndex).toInt();
    result[i] = cleaned[index];
  }

  // Force exact final point without appending or cloning.
  result[safeMax - 1] = cleaned[lastIndex];

  return List<LatLng>.unmodifiable(result);
}

/// Downsamples numeric values for charts.
///
/// This performs at most one output allocation and does not create an
/// intermediate `where(...).toList()` cleaned copy.
///
/// Complexity: O(N + maxPoints).
List<double> downsampleValues(
  List<double> values, {
  int maxPoints = 120,
}) {
  final int valueLength = values.length;
  final int safeMax = math.max(2, maxPoints);

  int finiteCount = 0;
  for (int i = 0; i < valueLength; i++) {
    if (values[i].isFinite) finiteCount++;
  }

  if (finiteCount == 0) return const <double>[];

  if (finiteCount <= safeMax) {
    final List<double> result =
        List<double>.filled(finiteCount, 0.0, growable: false);

    int out = 0;
    for (int i = 0; i < valueLength; i++) {
      final double value = values[i];
      if (value.isFinite) result[out++] = value;
    }

    return List<double>.unmodifiable(result);
  }

  final List<double> result =
      List<double>.filled(safeMax, 0.0, growable: false);
  final int lastFiniteOrdinal = finiteCount - 1;
  final double step = lastFiniteOrdinal / (safeMax - 1);

  int sourceIndex = 0;
  int finiteOrdinal = -1;

  for (int out = 0; out < safeMax; out++) {
    final int targetOrdinal =
        (out * step).round().clamp(0, lastFiniteOrdinal).toInt();

    while (sourceIndex < valueLength && finiteOrdinal < targetOrdinal) {
      final double value = values[sourceIndex++];
      if (value.isFinite) {
        finiteOrdinal++;
        if (finiteOrdinal == targetOrdinal) {
          result[out] = value;
          break;
        }
      }
    }
  }

  // Guarantee the exact last finite value is present.
  for (int i = valueLength - 1; i >= 0; i--) {
    final double value = values[i];
    if (value.isFinite) {
      result[safeMax - 1] = value;
      break;
    }
  }

  return List<double>.unmodifiable(result);
}

// ---------------------------------------------------------------------------
// Bounds
// ---------------------------------------------------------------------------

/// Calculates approximate route bounds.
///
/// Returns `null` if no valid points exist.
///
/// Complexity: O(N).
LatLngBoundsLite? calculatePolylineBounds(List<LatLng> points) {
  final List<LatLng> cleaned = _cleanPoints(points, removeDuplicates: false);

  if (cleaned.isEmpty) return null;

  double minLat = cleaned.first.latitude;
  double maxLat = cleaned.first.latitude;
  double minLng = cleaned.first.longitude;
  double maxLng = cleaned.first.longitude;

  for (int i = 1; i < cleaned.length; i++) {
    final LatLng point = cleaned[i];

    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
    if (point.longitude < minLng) minLng = point.longitude;
    if (point.longitude > maxLng) maxLng = point.longitude;
  }

  return LatLngBoundsLite(
    southWest: LatLng(minLat, minLng),
    northEast: LatLng(maxLat, maxLng),
  );
}

// ---------------------------------------------------------------------------
// Distance & geometry
// ---------------------------------------------------------------------------

/// Calculates approximate total route length in meters using haversine.
///
/// Performance: skips haversine for identical consecutive points.
///
/// Complexity: O(N), with trig operations per non-identical segment.
double calculatePolylineDistanceMeters(List<LatLng> points) {
  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.length < 2) return 0.0;

  double total = 0.0;

  for (int i = 1; i < cleaned.length; i++) {
    final LatLng a = cleaned[i - 1];
    final LatLng b = cleaned[i];

    if (a.latitude == b.latitude && a.longitude == b.longitude) continue;

    total += calculateDistanceMeters(a, b);
  }

  return total.isFinite ? total : 0.0;
}

/// Calculates approximate distance between two points in meters (haversine).
double calculateDistanceMeters(LatLng a, LatLng b) {
  if (!_isValidLatLng(a) || !_isValidLatLng(b)) return 0.0;

  final double lat1 = _degToRad(a.latitude);
  final double lat2 = _degToRad(b.latitude);
  final double dLat = _degToRad(b.latitude - a.latitude);
  final double dLng = _degToRad(b.longitude - a.longitude);

  final double sinLat = math.sin(dLat * 0.5);
  final double sinLng = math.sin(dLng * 0.5);

  final double h =
      sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;

  final double safeH = h.clamp(0.0, 1.0).toDouble();
  final double c = 2.0 * math.atan2(math.sqrt(safeH), math.sqrt(1.0 - safeH));

  final double meters = _kEarthRadiusMeters * c;
  return meters.isFinite ? meters : 0.0;
}

/// Calculates heading/bearing from [from] to [to] in degrees (0–360).
///
/// Returns `null` when the two points are identical or input is invalid,
/// rather than the ambiguous `0.0`.
double? calculateBearingDegrees(LatLng from, LatLng to) {
  if (!_isValidLatLng(from) || !_isValidLatLng(to)) return null;

  if (_nearlySame(from, to, 0.0)) return null;

  final double lat1 = _degToRad(from.latitude);
  final double lat2 = _degToRad(to.latitude);
  final double dLng = _degToRad(to.longitude - from.longitude);

  final double y = math.sin(dLng) * math.cos(lat2);
  final double x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

  return normalizeDegrees(_radToDeg(math.atan2(y, x)));
}

/// Normalises degrees to [0, 360).
double normalizeDegrees(double degrees) {
  if (!degrees.isFinite) return 0.0;

  final double normalized = degrees % 360.0;
  return normalized < 0.0 ? normalized + 360.0 : normalized;
}

// ---------------------------------------------------------------------------
// Point queries
// ---------------------------------------------------------------------------

/// Gets the last valid point in a list.
///
/// Complexity: O(N) worst case.
LatLng? lastValidPoint(List<LatLng> points) {
  for (int i = points.length - 1; i >= 0; i--) {
    if (_isValidLatLng(points[i])) return points[i];
  }
  return null;
}

/// Gets the first valid point in a list.
///
/// Complexity: O(N) worst case.
LatLng? firstValidPoint(List<LatLng> points) {
  for (int i = 0; i < points.length; i++) {
    final LatLng point = points[i];
    if (_isValidLatLng(point)) return point;
  }
  return null;
}

/// Finds the closest point on [polyline] to [query].
///
/// Returns a [ClosestPointResult] with the projected point, the segment index
/// (0-based), and the distance in meters. Returns `null` for empty polylines.
///
/// Complexity: O(N).
ClosestPointResult? closestPointOnPolyline(
  List<LatLng> polyline,
  LatLng query,
) {
  final List<LatLng> cleaned = _cleanPoints(polyline, removeDuplicates: false);

  if (cleaned.isEmpty || !_isValidLatLng(query)) return null;

  if (cleaned.length == 1) {
    return ClosestPointResult(
      point: cleaned.first,
      segmentIndex: 0,
      distanceMeters: calculateDistanceMeters(cleaned.first, query),
    );
  }

  double bestDistSq = double.infinity;
  LatLng bestPoint = cleaned.first;
  int bestSegment = 0;

  for (int i = 0; i < cleaned.length - 1; i++) {
    final LatLng start = cleaned[i];
    final LatLng end = cleaned[i + 1];

    final double distSq = _getSqSegDist(query, start, end);

    if (distSq < bestDistSq) {
      bestDistSq = distSq;
      bestPoint = _projectPointOnSegment(query, start, end);
      bestSegment = i;
    }
  }

  return ClosestPointResult(
    point: bestPoint,
    segmentIndex: bestSegment,
    distanceMeters: calculateDistanceMeters(bestPoint, query),
  );
}

/// Fast test: returns `true` if [query] is within [thresholdMeters] of any
/// segment in [polyline].
///
/// Uses a squared-distance approximation in degree-space for a cheap first
/// pass.
///
/// Complexity: O(N).
bool isPointNearPolyline(
  List<LatLng> polyline,
  LatLng query, {
  double thresholdMeters = 50.0,
}) {
  final List<LatLng> cleaned = _cleanPoints(polyline, removeDuplicates: false);

  if (cleaned.isEmpty || !_isValidLatLng(query)) return false;

  final double safeThreshold = thresholdMeters.isFinite && thresholdMeters > 0.0
      ? thresholdMeters
      : 50.0;

  // Rough degree-space threshold (1 deg ≈ 111 km).
  final double thresholdDeg = safeThreshold / 111000.0;
  final double thresholdSq = thresholdDeg * thresholdDeg;

  if (cleaned.length == 1) {
    final double dx = query.longitude - cleaned.first.longitude;
    final double dy = query.latitude - cleaned.first.latitude;
    return (dx * dx + dy * dy) <= thresholdSq;
  }

  for (int i = 0; i < cleaned.length - 1; i++) {
    final double distSq = _getSqSegDist(query, cleaned[i], cleaned[i + 1]);
    if (distSq <= thresholdSq) return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Splitting / subsectioning
// ---------------------------------------------------------------------------

/// Splits [points] at [distanceMeters] cumulative from the start.
///
/// Returns a [SplitPolylineResult] with the before/after halves. The split
/// point is included at the end of [before] and the start of [after].
///
/// Returns `null` if [points] has fewer than 2 valid points or
/// [distanceMeters] is outside the route's total length.
///
/// Complexity: O(N).
SplitPolylineResult? splitPolylineAtDistance(
  List<LatLng> points,
  double distanceMeters,
) {
  if (!distanceMeters.isFinite || distanceMeters < 0.0) return null;

  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.length < 2) return null;

  double cumulative = 0.0;

  for (int i = 1; i < cleaned.length; i++) {
    final LatLng previous = cleaned[i - 1];
    final LatLng current = cleaned[i];
    final double segLen = calculateDistanceMeters(previous, current);
    final double next = cumulative + segLen;

    if (next >= distanceMeters) {
      final double t =
          segLen > 0.0 ? (distanceMeters - cumulative) / segLen : 0.0;
      final LatLng split = _lerpLatLng(
        previous,
        current,
        t.clamp(0.0, 1.0).toDouble(),
      );

      final List<LatLng> before = <LatLng>[];
      for (int j = 0; j < i; j++) {
        before.add(cleaned[j]);
      }
      _addIfDifferent(before, split, 0.0);

      final List<LatLng> after = <LatLng>[split];
      for (int j = i; j < cleaned.length; j++) {
        _addIfDifferent(after, cleaned[j], 0.0);
      }

      return SplitPolylineResult(
        before: List<LatLng>.unmodifiable(before),
        after: List<LatLng>.unmodifiable(after),
        splitPoint: split,
        splitSegmentIndex: i - 1,
      );
    }

    cumulative = next;
  }

  return null;
}

/// Extracts a sub-section of [points] between [startMeters] and [endMeters]
/// cumulative distances from the route start.
///
/// Returns an empty list if the range is invalid or outside the route.
///
/// Complexity: O(N), single-pass after cleaning.
List<LatLng> polylineSubsection(
  List<LatLng> points, {
  required double startMeters,
  required double endMeters,
}) {
  if (!startMeters.isFinite ||
      !endMeters.isFinite ||
      startMeters >= endMeters ||
      startMeters < 0.0) {
    return const <LatLng>[];
  }

  final List<LatLng> cleaned = _cleanPoints(points);
  if (cleaned.length < 2) return const <LatLng>[];

  final List<LatLng> result = <LatLng>[];
  double cumulative = 0.0;
  bool started = false;

  for (int i = 1; i < cleaned.length; i++) {
    final LatLng a = cleaned[i - 1];
    final LatLng b = cleaned[i];
    final double segLen = calculateDistanceMeters(a, b);
    final double next = cumulative + segLen;

    if (next < startMeters) {
      cumulative = next;
      continue;
    }

    if (cumulative > endMeters) break;

    if (!started) {
      final double tStart =
          segLen > 0.0 ? (startMeters - cumulative) / segLen : 0.0;
      final LatLng startPoint = _lerpLatLng(
        a,
        b,
        tStart.clamp(0.0, 1.0).toDouble(),
      );
      result.add(startPoint);
      started = true;
    }

    if (next >= endMeters) {
      final double tEnd =
          segLen > 0.0 ? (endMeters - cumulative) / segLen : 0.0;
      final LatLng endPoint = _lerpLatLng(
        a,
        b,
        tEnd.clamp(0.0, 1.0).toDouble(),
      );
      _addIfDifferent(result, endPoint, 0.0);
      return List<LatLng>.unmodifiable(result);
    }

    _addIfDifferent(result, b, 0.0);
    cumulative = next;
  }

  return result.isEmpty ? const <LatLng>[] : List<LatLng>.unmodifiable(result);
}

/// Interpolates an exact [LatLng] at [distanceMeters] along [points].
///
/// Returns `null` if the distance is out of range or the route is too short.
///
/// Complexity: O(N).
LatLng? interpolatePointAtDistance(
  List<LatLng> points,
  double distanceMeters,
) {
  if (!distanceMeters.isFinite || distanceMeters < 0.0) return null;

  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.isEmpty) return null;
  if (cleaned.length == 1) return cleaned.first;
  if (distanceMeters == 0.0) return cleaned.first;

  double cumulative = 0.0;

  for (int i = 1; i < cleaned.length; i++) {
    final double segLen = calculateDistanceMeters(cleaned[i - 1], cleaned[i]);
    final double next = cumulative + segLen;

    if (next >= distanceMeters) {
      final double t =
          segLen > 0.0 ? (distanceMeters - cumulative) / segLen : 0.0;
      return _lerpLatLng(
        cleaned[i - 1],
        cleaned[i],
        t.clamp(0.0, 1.0).toDouble(),
      );
    }

    cumulative = next;
  }

  return cleaned.last;
}

// ---------------------------------------------------------------------------
// Private geometry helpers
// ---------------------------------------------------------------------------

/// Squared perpendicular distance from [point] to segment [start]–[end].
///
/// Uses a cheap local equirectangular projection instead of raw degree-space.
/// This keeps simplification more consistent at different latitudes while still
/// avoiding expensive haversine calls inside Douglas-Peucker.
double _getSqSegDist(LatLng point, LatLng start, LatLng end) {
  final double meanLat = _degToRad(
    (point.latitude + start.latitude + end.latitude) / 3.0,
  );
  final double lngScale = math.cos(meanLat).abs().clamp(0.01, 1.0).toDouble();

  double x = start.longitude * lngScale;
  double y = start.latitude;

  final double endX = end.longitude * lngScale;
  final double endY = end.latitude;
  final double pointX = point.longitude * lngScale;
  final double pointY = point.latitude;

  final double dx = endX - x;
  final double dy = endY - y;

  if (dx.abs() < _kGeometryEpsilon && dy.abs() < _kGeometryEpsilon) {
    final double ex = pointX - x;
    final double ey = pointY - y;
    return ex * ex + ey * ey;
  }

  final double denominator = dx * dx + dy * dy;
  if (denominator <= _kGeometryEpsilon * _kGeometryEpsilon) {
    final double ex = pointX - x;
    final double ey = pointY - y;
    return ex * ex + ey * ey;
  }

  final double t = ((pointX - x) * dx + (pointY - y) * dy) / denominator;

  if (t >= 1.0) {
    x = endX;
    y = endY;
  } else if (t > 0.0) {
    x += dx * t;
    y += dy * t;
  }

  final double ex = pointX - x;
  final double ey = pointY - y;

  return ex * ex + ey * ey;
}

/// Projects [query] onto segment [start]–[end] and returns the nearest point.
LatLng _projectPointOnSegment(LatLng query, LatLng start, LatLng end) {
  final double meanLat = _degToRad(
    (query.latitude + start.latitude + end.latitude) / 3.0,
  );
  final double lngScale = math.cos(meanLat).abs().clamp(0.01, 1.0).toDouble();

  final double startX = start.longitude * lngScale;
  final double startY = start.latitude;
  final double endX = end.longitude * lngScale;
  final double endY = end.latitude;
  final double queryX = query.longitude * lngScale;
  final double queryY = query.latitude;

  final double dx = endX - startX;
  final double dy = endY - startY;

  if (dx.abs() < _kGeometryEpsilon && dy.abs() < _kGeometryEpsilon) {
    return start;
  }

  final double denominator = dx * dx + dy * dy;
  if (denominator <= _kGeometryEpsilon * _kGeometryEpsilon) return start;

  final double t =
      ((queryX - startX) * dx + (queryY - startY) * dy) / denominator;
  final double clamped = t.clamp(0.0, 1.0).toDouble();

  return LatLng(
    start.latitude + (end.latitude - start.latitude) * clamped,
    start.longitude + (end.longitude - start.longitude) * clamped,
  );
}

/// Catmull-Rom interpolation between [p1] and [p2].
///
/// The four basis values b0..b3 sum to 1 for all clamped `t`, eliminating
/// coordinate drift from the interpolation itself.
LatLng _catmullRom(
  LatLng p0,
  LatLng p1,
  LatLng p2,
  LatLng p3,
  double t,
  double tension,
) {
  final double safeT = t.isFinite ? t.clamp(0.0, 1.0).toDouble() : 0.0;
  final double safeTension =
      tension.isFinite ? tension.clamp(0.0, 1.0).toDouble() : 0.5;

  final double t2 = safeT * safeT;
  final double t3 = t2 * safeT;

  final double b0 =
      -safeTension * t3 + 2.0 * safeTension * t2 - safeTension * safeT;
  final double b1 = (2.0 - safeTension) * t3 + (safeTension - 3.0) * t2 + 1.0;
  final double b2 = (safeTension - 2.0) * t3 +
      (3.0 - 2.0 * safeTension) * t2 +
      safeTension * safeT;
  final double b3 = safeTension * t3 - safeTension * t2;

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
  final int count =
      math.min(subdivisions.clamp(1, 24).toInt() + 1, maxOutputPoints).toInt();

  if (count <= 2) return <LatLng>[a, b];

  final List<LatLng> result = List<LatLng>.filled(count, a, growable: false);

  for (int i = 0; i < count; i++) {
    final double t = i / (count - 1);
    result[i] = _lerpLatLng(a, b, t);
  }

  return result;
}

/// Linear interpolation between two [LatLng] points.
LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
  final double safeT = t.isFinite ? t.clamp(0.0, 1.0).toDouble() : 0.0;

  return LatLng(
    a.latitude + (b.latitude - a.latitude) * safeT,
    a.longitude + (b.longitude - a.longitude) * safeT,
  );
}

LatLng _controlPointBefore(
  List<LatLng> points,
  int index,
  int sourceLength,
  bool isClosedLoop,
) {
  if (index > 0) return points[index - 1];

  if (isClosedLoop && sourceLength > 2) {
    return points[sourceLength - 2];
  }

  return _reflectPoint(points[1], points[0]);
}

LatLng _controlPointAfter(
  List<LatLng> points,
  int index,
  int sourceLength,
  bool isClosedLoop,
) {
  final int nextIndex = index + 1;

  if (nextIndex < sourceLength) return points[nextIndex];

  if (isClosedLoop && sourceLength > 2) {
    return points[1];
  }

  return _reflectPoint(points[sourceLength - 2], points[sourceLength - 1]);
}

LatLng _reflectPoint(LatLng anchor, LatLng pivot) {
  return LatLng(
    2.0 * pivot.latitude - anchor.latitude,
    2.0 * pivot.longitude - anchor.longitude,
  );
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

/// Cleans a point list by removing invalid and (optionally) near-duplicate
/// entries.
///
/// Complexity: O(N). This is intentionally a single linear pass.
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

  for (int i = 0; i < points.length; i++) {
    final LatLng point = points[i];

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

/// Returns `true` if [a] and [b] are within [tolerance] degrees of each other.
///
/// Positive tolerances are clamped to at least [_kGeometryEpsilon], then
/// compared with real Euclidean distance instead of squared tolerance. This is
/// slightly more expensive than squared-distance but safer for tiny tolerances.
bool _nearlySame(LatLng a, LatLng b, double tolerance) {
  final double dLat = a.latitude - b.latitude;
  final double dLng = a.longitude - b.longitude;

  if (tolerance <= 0.0) {
    return dLat == 0.0 && dLng == 0.0;
  }

  final double safeTolerance = math.max(tolerance, _kGeometryEpsilon);
  return math.sqrt(dLat * dLat + dLng * dLng) <= safeTolerance;
}

bool _isClosedLoop(List<LatLng> points) {
  if (points.length < 3) return false;
  return _nearlySame(points.first, points.last, _kDefaultDuplicateTolerance);
}

double _degToRad(double degrees) => degrees * (math.pi / 180.0);
double _radToDeg(double radians) => radians * (180.0 / math.pi);

// ---------------------------------------------------------------------------
// Value objects
// ---------------------------------------------------------------------------

class _SegmentRange {
  const _SegmentRange(this.first, this.last);
  final int first;
  final int last;
}

/// Result of [closestPointOnPolyline].
class ClosestPointResult {
  const ClosestPointResult({
    required this.point,
    required this.segmentIndex,
    required this.distanceMeters,
  });

  /// The projected point on the polyline.
  final LatLng point;

  /// Zero-based index of the segment `[segmentIndex, segmentIndex+1]`.
  final int segmentIndex;

  /// Haversine distance from [point] to the query point, in meters.
  final double distanceMeters;

  @override
  String toString() => 'ClosestPointResult(point: $point, '
      'segmentIndex: $segmentIndex, distanceMeters: $distanceMeters)';
}

/// Result of [splitPolylineAtDistance].
class SplitPolylineResult {
  const SplitPolylineResult({
    required this.before,
    required this.after,
    required this.splitPoint,
    required this.splitSegmentIndex,
  });

  /// Points from the start up to and including [splitPoint].
  final List<LatLng> before;

  /// Points from [splitPoint] to the end.
  final List<LatLng> after;

  /// The interpolated point at the exact split distance.
  final LatLng splitPoint;

  /// Zero-based segment index where the split occurs.
  final int splitSegmentIndex;

  @override
  String toString() => 'SplitPolylineResult(splitPoint: $splitPoint, '
      'splitSegmentIndex: $splitSegmentIndex, '
      'before: ${before.length} pts, after: ${after.length} pts)';
}

// ---------------------------------------------------------------------------
// LatLngBoundsLite
// ---------------------------------------------------------------------------

/// Lightweight geographic bounds — no flutter_map dependency.
class LatLngBoundsLite {
  const LatLngBoundsLite({
    required this.southWest,
    required this.northEast,
  });

  final LatLng southWest;
  final LatLng northEast;

  LatLng get center => LatLng(
        (southWest.latitude + northEast.latitude) * 0.5,
        (southWest.longitude + northEast.longitude) * 0.5,
      );

  double get widthDegrees => (northEast.longitude - southWest.longitude).abs();

  double get heightDegrees => (northEast.latitude - southWest.latitude).abs();

  bool get isPoint =>
      southWest.latitude == northEast.latitude &&
      southWest.longitude == northEast.longitude;

  bool contains(LatLng point) {
    if (!_isValidLatLng(point)) return false;

    return point.latitude >= southWest.latitude &&
        point.latitude <= northEast.latitude &&
        point.longitude >= southWest.longitude &&
        point.longitude <= northEast.longitude;
  }

  /// Returns `true` if [other] is fully contained within this bounds.
  bool containsBounds(LatLngBoundsLite other) {
    return other.southWest.latitude >= southWest.latitude &&
        other.northEast.latitude <= northEast.latitude &&
        other.southWest.longitude >= southWest.longitude &&
        other.northEast.longitude <= northEast.longitude;
  }

  /// Returns `true` if this bounds overlaps [other].
  bool intersects(LatLngBoundsLite other) {
    return !(other.northEast.latitude < southWest.latitude ||
        other.southWest.latitude > northEast.latitude ||
        other.northEast.longitude < southWest.longitude ||
        other.southWest.longitude > northEast.longitude);
  }

  /// Returns a new bounds that contains both this and [other].
  LatLngBoundsLite expand(LatLngBoundsLite other) {
    return LatLngBoundsLite(
      southWest: LatLng(
        math.min(southWest.latitude, other.southWest.latitude),
        math.min(southWest.longitude, other.southWest.longitude),
      ),
      northEast: LatLng(
        math.max(northEast.latitude, other.northEast.latitude),
        math.max(northEast.longitude, other.northEast.longitude),
      ),
    );
  }

  /// Returns a padded copy of this bounds.
  ///
  /// Non-positive padding values are silently ignored.
  LatLngBoundsLite pad({
    double latitudePadding = 0.0005,
    double longitudePadding = 0.0005,
  }) {
    final double safeLatPad = latitudePadding.isFinite && latitudePadding > 0.0
        ? latitudePadding
        : 0.0;

    final double safeLngPad =
        longitudePadding.isFinite && longitudePadding > 0.0
            ? longitudePadding
            : 0.0;

    return LatLngBoundsLite(
      southWest: LatLng(
        (southWest.latitude - safeLatPad)
            .clamp(_kMinLatitude, _kMaxLatitude)
            .toDouble(),
        (southWest.longitude - safeLngPad)
            .clamp(_kMinLongitude, _kMaxLongitude)
            .toDouble(),
      ),
      northEast: LatLng(
        (northEast.latitude + safeLatPad)
            .clamp(_kMinLatitude, _kMaxLatitude)
            .toDouble(),
        (northEast.longitude + safeLngPad)
            .clamp(_kMinLongitude, _kMaxLongitude)
            .toDouble(),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LatLngBoundsLite &&
        other.southWest == southWest &&
        other.northEast == northEast;
  }

  @override
  int get hashCode => Object.hash(southWest, northEast);

  @override
  String toString() =>
      'LatLngBoundsLite(southWest: $southWest, northEast: $northEast)';
}
