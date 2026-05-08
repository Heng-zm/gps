import 'package:latlong2/latlong.dart';

/// Douglas-Peucker simplification — reduces point count before smoothing.
///
/// Performance: Uses index-based recursion to avoid memory-heavy
/// list slicing and squared distances to avoid math.sqrt.
///
/// [epsilon] is in degrees; ~0.00005° ≈ 5.5 metres.
List<LatLng> simplifyPolyline(List<LatLng> points, {double epsilon = 0.00005}) {
  if (points.length <= 2) return points.isEmpty ? [] : List.from(points);

  final List<bool> keep = List.filled(points.length, false);
  final double epsilonSq = epsilon * epsilon;

  // Mark first and last points
  keep[0] = true;
  keep[points.length - 1] = true;

  // Recursive worker
  _simplifyStep(points, 0, points.length - 1, epsilonSq, keep);

  // Collect marked points
  final List<LatLng> result = [];
  for (int i = 0; i < points.length; i++) {
    if (keep[i]) result.add(points[i]);
  }
  return result;
}

void _simplifyStep(
  List<LatLng> points,
  int first,
  int last,
  double epsilonSq,
  List<bool> keep,
) {
  double maxDistSq = 0;
  int index = first;

  for (int i = first + 1; i < last; i++) {
    final double dSq = _getSqSegDist(points[i], points[first], points[last]);
    if (dSq > maxDistSq) {
      maxDistSq = dSq;
      index = i;
    }
  }

  if (maxDistSq > epsilonSq) {
    keep[index] = true;
    _simplifyStep(points, first, index, epsilonSq, keep);
    _simplifyStep(points, index, last, epsilonSq, keep);
  }
}

/// Squared perpendicular distance from point to segment p1-p2.
/// Performance: Avoids math.sqrt.
double _getSqSegDist(LatLng p, LatLng p1, LatLng p2) {
  double x = p1.longitude;
  double y = p1.latitude;
  double dx = p2.longitude - x;
  double dy = p2.latitude - y;

  if (dx != 0 || dy != 0) {
    double t =
        ((p.longitude - x) * dx + (p.latitude - y) * dy) / (dx * dx + dy * dy);

    if (t > 1) {
      x = p2.longitude;
      y = p2.latitude;
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }

  dx = p.longitude - x;
  dy = p.latitude - y;

  return dx * dx + dy * dy;
}

/// Smooths a list of [LatLng] points using a Catmull-Rom spline.
///
/// [tension] controls curve tightness (0.5 is default).
/// [subdivisions] is number of points to insert between segments.
List<LatLng> smoothPolyline(
  List<LatLng> points, {
  double tension = 0.5,
  int subdivisions = 10,
}) {
  final int len = points.length;
  if (len < 2) return points.isEmpty ? [] : List.from(points);

  if (len == 2) {
    return _linearSubdivide(points[0], points[1], subdivisions);
  }

  final List<LatLng> result = [];

  // Synthetic control points for start and end
  final pStart = _reflectPoint(points[1], points[0]);
  final pEnd = _reflectPoint(points[len - 2], points.last);

  for (int i = 0; i < len - 1; i++) {
    final LatLng a = (i == 0) ? pStart : points[i - 1];
    final LatLng b = points[i];
    final LatLng c = points[i + 1];
    final LatLng d = (i + 2 >= len) ? pEnd : points[i + 2];

    result.add(b);

    for (int s = 1; s < subdivisions; s++) {
      final double t = s / subdivisions;
      result.add(_catmullRom(a, b, c, d, t, tension));
    }
  }

  result.add(points.last);
  return result;
}

/// Catmull-Rom interpolation between [p1] and [p2].
LatLng _catmullRom(
    LatLng p0, LatLng p1, LatLng p2, LatLng p3, double t, double tension) {
  final double t2 = t * t;
  final double t3 = t2 * t;

  final double b0 = -tension * t3 + 2 * tension * t2 - tension * t;
  final double b1 = (2 - tension) * t3 + (tension - 3) * t2 + 1;
  final double b2 = (tension - 2) * t3 + (3 - 2 * tension) * t2 + tension * t;
  final double b3 = tension * t3 - tension * t2;

  return LatLng(
    b0 * p0.latitude + b1 * p1.latitude + b2 * p2.latitude + b3 * p3.latitude,
    b0 * p0.longitude +
        b1 * p1.longitude +
        b2 * p2.longitude +
        b3 * p3.longitude,
  );
}

/// Helper: Linear interpolation for 2-point polylines.
List<LatLng> _linearSubdivide(LatLng a, LatLng b, int subdivisions) {
  final List<LatLng> result = [];
  for (int i = 0; i <= subdivisions; i++) {
    final double t = i / subdivisions;
    result.add(LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    ));
  }
  return result;
}

/// Helper: Point reflection for spline control points.
LatLng _reflectPoint(LatLng anchor, LatLng pivot) {
  return LatLng(
    2 * pivot.latitude - anchor.latitude,
    2 * pivot.longitude - anchor.longitude,
  );
}
