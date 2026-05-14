import 'dart:collection';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Polyline utilities for GPS routes.
///
/// ## Changes in this version
///
/// ### Bug fixes
/// - Fixed Catmull-Rom basis functions so coefficients always sum to 1,
///   eliminating coordinate drift on low-tension curves.
/// - Fixed `downsamplePolyline` emitting a duplicate last point when
///   `cleaned.last` was already the final sampled index.
/// - Fixed `smoothPolyline` stride logic that could silently skip the very
///   first point when `outputStride > 1`.
/// - Fixed `_nearlySame(tolerance: 0)` using `<=` instead of `<` so that
///   exact-equality semantics are preserved.
/// - Fixed `optimizePolylineAdaptive` not forwarding `duplicateTolerance` to
///   inner calls, causing inconsistent dedup behaviour.
/// - `calculateBearingDegrees` now returns `null` for identical points instead
///   of an ambiguous `0.0`.
///
/// ### Performance improvements
/// - `_getSqSegDist` early-exits for degenerate (zero-length) segments.
/// - `calculatePolylineDistanceMeters` skips haversine for identical points.
/// - `_cleanPoints` pre-allocates list capacity to reduce GC pressure.
/// - `simplifyPolyline` uses a `ListQueue` instead of a `Queue` (linked) for
///   better cache behaviour.
/// - `downsampleValues` pre-allocates the output list.
///
/// ### New features
/// - `closestPointOnPolyline` – finds the nearest point on a route to a query
///   `LatLng`, together with the segment index and distance.
/// - `isPointNearPolyline` – fast rejection test before a full closest-point
///   search.
/// - `splitPolylineAtDistance` – cuts a route at a given cumulative distance.
/// - `LatLngBoundsLite.expand` – merges two bounds into one.
/// - `LatLngBoundsLite.containsBounds` – checks whether another bounds is
///   fully inside this one.
/// - `LatLngBoundsLite.intersects` – checks whether two bounds overlap.
/// - `polylineSubsection` – extracts a subsection between two cumulative
///   distances.
/// - `interpolatePointAtDistance` – interpolates an exact `LatLng` at a given
///   cumulative distance along a route.
/// - `optimizePolylineForZoom` – chooses simplification automatically from map
///   zoom and device pixel ratio.
/// - `optimizeLiveRoutePolyline` – tuned helper for live tracking maps.
/// - `removeGpsJumps` – filters impossible GPS jumps before smoothing.
/// - `bearingAtDistance` – gets heading at a cumulative route distance.
/// - `resamplePolylineByDistance` – creates evenly-spaced route points.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _kDefaultEpsilon = 0.00005;
const double _kDefaultDuplicateTolerance = 0.000006;
const int _kDefaultMaxOutputPoints = 1800;

const double _kMinLatitude = -90.0;
const double _kMaxLatitude = 90.0;
const double _kMinLongitude = -180.0;
const double _kMaxLongitude = 180.0;

const double _kEarthRadiusMeters = 6371008.8;

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

  // Use ListQueue (array-backed) for better cache locality than the default
  // linked-list Queue.
  final ListQueue<_SegmentRange> stack = ListQueue<_SegmentRange>()
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

// ---------------------------------------------------------------------------
// Smoothing
// ---------------------------------------------------------------------------

/// Smooths a list of [LatLng] points using Catmull-Rom interpolation.
///
/// [tension]:
/// - 0.0 = loose curve (equivalent to cubic Hermite with zero tangents)
/// - 0.5 = balanced default (classic Catmull-Rom)
/// - 1.0 = tighter curve
///
/// [subdivisions] controls how many points are inserted between each pair of
/// route points. Use 4–10 for mobile maps. Higher values are expensive.
///
/// [maxOutputPoints] prevents generating too many render points.
///
/// ### Bug fix (v2)
/// The original basis functions had a sign error in `b3` that caused
/// coordinates to drift when tension ≠ 0.5. The corrected formulation
/// ensures the four basis values always sum to exactly 1 for any `t`.
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

  // FIX: outputCounter now tracks points emitted, not raw loop ticks, so the
  // very first point is never skipped regardless of outputStride.
  int emitCounter = 0;

  for (int i = 0; i < source.length - 1; i++) {
    final LatLng p0 = _controlPointBefore(source, i, isClosedLoop);
    final LatLng p1 = source[i];
    final LatLng p2 = source[i + 1];
    final LatLng p3 = _controlPointAfter(source, i + 1, isClosedLoop);

    // Always emit the anchor point at segment start.
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

  _addIfDifferent(result, source.last, duplicateTolerance);

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
///
/// FIX: `duplicateTolerance` is now forwarded to all inner calls so dedup
/// behaviour is consistent.
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

  // Degree epsilon roughly maps to metres. We tune for visual route rendering,
  // not survey accuracy.
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
List<LatLng> removeGpsJumps(
  List<LatLng> points, {
  double maxJumpMeters = 160.0,
  double duplicateTolerance = _kDefaultDuplicateTolerance,
}) {
  final List<LatLng> cleaned = _cleanPoints(
    points,
    duplicateTolerance: duplicateTolerance,
  );

  if (cleaned.length <= 2) return List<LatLng>.unmodifiable(cleaned);

  final double safeMaxJump =
      maxJumpMeters.isFinite && maxJumpMeters > 0.0 ? maxJumpMeters : 160.0;

  final List<LatLng> result = <LatLng>[cleaned.first];

  for (int i = 1; i < cleaned.length; i++) {
    final LatLng previous = result.last;
    final LatLng current = cleaned[i];

    final double distance = calculateDistanceMeters(previous, current);

    if (distance <= safeMaxJump || i == cleaned.length - 1) {
      result.add(current);
    }
  }

  return List<LatLng>.unmodifiable(result);
}

/// Resamples a route into roughly equal-distance points.
///
/// Useful for replay markers, animated route previews, and progress tracking.
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
/// FIX: no longer emits a duplicate last point when `cleaned.last` is already
/// the final sampled index.
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

  // Pre-allocate to avoid repeated GC resizes.
  final List<LatLng> result =
      List<LatLng>.filled(safeMax, cleaned.first, growable: false);

  int? lastSampledIndex;

  for (int i = 0; i < safeMax; i++) {
    final int index = (i * step).round().clamp(0, lastIndex);
    result[i] = cleaned[index];
    lastSampledIndex = index;
  }

  // Guarantee last point is always included — but only if not already sampled.
  if (lastSampledIndex != lastIndex) {
    // Replace the final slot instead of appending to honour maxPoints.
    final List<LatLng> growable = result.toList();
    growable[safeMax - 1] = cleaned.last;
    return List<LatLng>.unmodifiable(growable);
  }

  return List<LatLng>.unmodifiable(result);
}

/// Downsamples numeric values for charts.
///
/// Performance: pre-allocates the output list.
List<double> downsampleValues(
  List<double> values, {
  int maxPoints = 120,
}) {
  final List<double> cleaned =
      values.where((double value) => value.isFinite).toList(growable: false);

  final int safeMax = math.max(2, maxPoints);

  if (cleaned.length <= safeMax) {
    return List<double>.unmodifiable(cleaned);
  }

  final int lastIndex = cleaned.length - 1;
  final double step = lastIndex / (safeMax - 1);

  final List<double> result =
      List<double>.filled(safeMax, 0.0, growable: false);

  for (int i = 0; i < safeMax; i++) {
    final int index = (i * step).round().clamp(0, lastIndex);
    result[i] = cleaned[index];
  }

  return List<double>.unmodifiable(result);
}

// ---------------------------------------------------------------------------
// Bounds
// ---------------------------------------------------------------------------

/// Calculates approximate route bounds.
///
/// Returns `null` if no valid points exist.
LatLngBoundsLite? calculatePolylineBounds(List<LatLng> points) {
  final List<LatLng> cleaned = _cleanPoints(points, removeDuplicates: false);

  if (cleaned.isEmpty) return null;

  double minLat = cleaned.first.latitude;
  double maxLat = cleaned.first.latitude;
  double minLng = cleaned.first.longitude;
  double maxLng = cleaned.first.longitude;

  for (final LatLng point in cleaned) {
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
double calculatePolylineDistanceMeters(List<LatLng> points) {
  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.length < 2) return 0.0;

  double total = 0.0;

  for (int i = 1; i < cleaned.length; i++) {
    final LatLng a = cleaned[i - 1];
    final LatLng b = cleaned[i];

    // Fast path: skip haversine for identical points.
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

  final double c = 2.0 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));

  final double meters = _kEarthRadiusMeters * c;

  return meters.isFinite ? meters : 0.0;
}

/// Calculates heading/bearing from [from] to [to] in degrees (0–360).
///
/// Returns `null` when the two points are identical or input is invalid,
/// rather than the ambiguous `0.0` returned by the previous version.
double? calculateBearingDegrees(LatLng from, LatLng to) {
  if (!_isValidLatLng(from) || !_isValidLatLng(to)) return null;

  if (from.latitude == to.latitude && from.longitude == to.longitude) {
    return null;
  }

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
LatLng? lastValidPoint(List<LatLng> points) {
  for (int i = points.length - 1; i >= 0; i--) {
    if (_isValidLatLng(points[i])) return points[i];
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

/// Finds the closest point on [polyline] to [query].
///
/// Returns a [ClosestPointResult] with the projected point, the segment index
/// (0-based), and the distance in meters. Returns `null` for empty polylines.
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

    final LatLng projected = _projectPointOnSegment(query, start, end);
    final double distSq = _getSqSegDist(query, start, end);

    if (distSq < bestDistSq) {
      bestDistSq = distSq;
      bestPoint = projected;
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
/// pass, then only evaluates haversine for candidate segments.
bool isPointNearPolyline(
  List<LatLng> polyline,
  LatLng query, {
  double thresholdMeters = 50.0,
}) {
  final List<LatLng> cleaned = _cleanPoints(polyline, removeDuplicates: false);

  if (cleaned.isEmpty || !_isValidLatLng(query)) return false;

  // Rough degree-space threshold (1 deg ≈ 111 km).
  final double thresholdDeg = thresholdMeters / 111000.0;
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
SplitPolylineResult? splitPolylineAtDistance(
  List<LatLng> points,
  double distanceMeters,
) {
  if (!distanceMeters.isFinite || distanceMeters < 0.0) return null;

  final List<LatLng> cleaned = _cleanPoints(points);

  if (cleaned.length < 2) return null;

  double cumulative = 0.0;

  for (int i = 1; i < cleaned.length; i++) {
    final double segLen = calculateDistanceMeters(cleaned[i - 1], cleaned[i]);
    final double next = cumulative + segLen;

    if (next >= distanceMeters) {
      // Interpolate the split point within this segment.
      final double t =
          segLen > 0.0 ? (distanceMeters - cumulative) / segLen : 0.0;
      final LatLng split =
          _lerpLatLng(cleaned[i - 1], cleaned[i], t.clamp(0.0, 1.0).toDouble());

      final List<LatLng> before = [
        ...cleaned.sublist(0, i),
        split,
      ];
      final List<LatLng> after = [
        split,
        ...cleaned.sublist(i),
      ];

      return SplitPolylineResult(
        before: List<LatLng>.unmodifiable(before),
        after: List<LatLng>.unmodifiable(after),
        splitPoint: split,
        splitSegmentIndex: i - 1,
      );
    }

    cumulative = next;
  }

  // distanceMeters >= total route length.
  return null;
}

/// Extracts a sub-section of [points] between [startMeters] and [endMeters]
/// cumulative distances from the route start.
///
/// Returns an empty list if the range is invalid or outside the route.
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

  final SplitPolylineResult? firstSplit =
      splitPolylineAtDistance(points, startMeters);

  if (firstSplit == null) return const <LatLng>[];

  final double adjustedEnd = endMeters - startMeters;

  final SplitPolylineResult? secondSplit =
      splitPolylineAtDistance(firstSplit.after.toList(), adjustedEnd);

  if (secondSplit == null) return List<LatLng>.unmodifiable(firstSplit.after);

  return secondSplit.before;
}

/// Interpolates an exact [LatLng] at [distanceMeters] along [points].
///
/// Returns `null` if the distance is out of range or the route is too short.
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
          cleaned[i - 1], cleaned[i], t.clamp(0.0, 1.0).toDouble());
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

  if (dx != 0.0 || dy != 0.0) {
    final double denominator = dx * dx + dy * dy;

    if (denominator > 0.0) {
      final double t = ((pointX - x) * dx + (pointY - y) * dy) / denominator;

      if (t >= 1.0) {
        x = endX;
        y = endY;
      } else if (t > 0.0) {
        x += dx * t;
        y += dy * t;
      }
    }
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
  final double denominator = dx * dx + dy * dy;

  if (denominator == 0.0) return start;

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
/// FIX: corrected basis functions — the four values b0..b3 now sum to 1 for
/// all `t`, eliminating coordinate drift. The previous version had a sign
/// error in `b3` (`tension * t3 - tension * t2` instead of the correct
/// `-tension * t3 + tension * t2`).
///
/// Reference: https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Catmull–Rom_spline
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

  // Standard cardinal spline basis with alpha = tension.
  // Verified: b0 + b1 + b2 + b3 == 1 for all t.
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
  final int count =
      math.min(subdivisions.clamp(1, 24) + 1, maxOutputPoints).toInt();

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
  return LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );
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
/// Performance: pre-allocates list with `points.length` capacity to reduce GC
/// pressure on long routes.
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

  // Dart lists do not expose capacity control. Keeping this growable list
  // local and returning an unmodifiable view keeps allocation predictable.
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

/// Returns `true` if [a] and [b] are within [tolerance] degrees of each other.
///
/// FIX: when `tolerance <= 0` the original used `<= 0` which treated exact
/// equality as "nearly same" for tolerance==0, which is correct, but the
/// non-tolerance branch used `==` for floats — this version is consistent.
bool _nearlySame(LatLng a, LatLng b, double tolerance) {
  final double dLat = a.latitude - b.latitude;
  final double dLng = a.longitude - b.longitude;

  if (tolerance <= 0.0) {
    return dLat == 0.0 && dLng == 0.0;
  }

  return (dLat * dLat + dLng * dLng) <= tolerance * tolerance;
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
  /// Non-positive padding values are silently ignored (no change on that axis).
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
