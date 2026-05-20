part of 'summary_screen.dart';

const Color _kCard = Color(0xFF111111);
const Color _kBorder = Color(0x14FFFFFF);
const Color _kTeal = Color(0xFF4ECDC4);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kPurple = Color(0xFFA855F7);
const Color _kRed = Color(0xFFE74C3C);
const Color _kGreen = Color(0xFF27AE60);

const int _kMaxLocalHistoryItems = 100;
const int _kJsonComputeThreshold = 30;
const double _kCoordinateTolerance = 0.00001;

bool _sameCoordinate(double a, double b) {
  return (a - b).abs() < _kCoordinateTolerance;
}

bool _tripHistoryContainsIdSync(List<String> items, String id) {
  if (id.isEmpty) return false;

  for (final String item in items) {
    try {
      final Object? decoded = jsonDecode(item);
      if (decoded is Map && decoded['id']?.toString() == id) {
        return true;
      }
    } catch (_) {
      // Ignore legacy/corrupted entries.
    }
  }

  return false;
}

bool _tripHistoryContainsIdWorker(Map<String, Object?> args) {
  final Object? rawItems = args['items'];
  final Object? rawId = args['id'];

  if (rawItems is! List || rawId is! String) return false;

  return _tripHistoryContainsIdSync(rawItems.cast<String>(), rawId);
}

List<String> _buildLocalMirrorHistorySync({
  required List<String> existing,
  required Map<String, dynamic> payload,
  required int limit,
}) {
  final String id = payload['id']?.toString() ?? '';
  final String encodedPayload = jsonEncode(payload);
  final List<String> next = <String>[encodedPayload];

  for (final String item in existing) {
    if (next.length >= limit) break;

    try {
      final Object? decoded = jsonDecode(item);
      if (decoded is Map && decoded['id']?.toString() == id) {
        continue;
      }
    } catch (_) {
      // Keep legacy/corrupted entries at the end so the app never destroys
      // user history during a cache update.
    }

    next.add(item);
  }

  return next;
}

List<String> _buildLocalMirrorHistoryWorker(Map<String, Object?> args) {
  final Object? rawExisting = args['existing'];
  final Object? rawPayload = args['payload'];
  final Object? rawLimit = args['limit'];

  if (rawExisting is! List || rawPayload is! Map || rawLimit is! int) {
    return const <String>[];
  }

  return _buildLocalMirrorHistorySync(
    existing: rawExisting.cast<String>(),
    payload: Map<String, dynamic>.from(rawPayload),
    limit: rawLimit,
  );
}

class _RouteQualitySnapshot {
  const _RouteQualitySnapshot({
    required this.score,
    required this.label,
    required this.accuracyLabel,
    required this.color,
  });

  final int score;
  final String label;
  final String accuracyLabel;
  final Color color;

  static _RouteQualitySnapshot fromPoints(List<TripPoint> points) {
    if (points.length < 3) {
      return const _RouteQualitySnapshot(
        score: 45,
        label: 'Limited',
        accuracyLabel: '--',
        color: _kGold,
      );
    }

    double accuracySum = 0.0;
    int accuracyCount = 0;
    int weakAccuracy = 0;
    int duplicateLike = 0;
    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double accuracy = point.accuracyMeters;
      if (accuracy.isFinite && accuracy > 0.0) {
        accuracySum += accuracy;
        accuracyCount++;
        if (accuracy > 35.0) weakAccuracy++;
      }

      final double lat = point.position.latitude;
      final double lng = point.position.longitude;

      if (lastLat != null &&
          lastLng != null &&
          _sameCoordinate(lastLat, lat) &&
          _sameCoordinate(lastLng, lng)) {
        duplicateLike++;
      }

      lastLat = lat;
      lastLng = lng;
    }

    final double avgAccuracy =
        accuracyCount == 0 ? 25.0 : accuracySum / accuracyCount;

    int score = 100;
    if (points.length < 10) score -= 18;
    if (points.length < 5) score -= 20;
    score -= (weakAccuracy * 4).clamp(0, 28).toInt();
    score -= (duplicateLike * 3).clamp(0, 18).toInt();

    if (avgAccuracy > 10) score -= 6;
    if (avgAccuracy > 20) score -= 10;
    if (avgAccuracy > 35) score -= 14;

    score = score.clamp(0, 100).toInt();

    final String label;
    final Color color;
    if (score >= 88) {
      label = 'Excellent';
      color = _kGreen;
    } else if (score >= 72) {
      label = 'Good';
      color = _kTeal;
    } else if (score >= 50) {
      label = 'Fair';
      color = _kGold;
    } else {
      label = 'Weak';
      color = _kRed;
    }

    final String accuracyLabel =
        accuracyCount == 0 ? '--' : '±${avgAccuracy.clamp(0.0, 99.0).round()}m';

    return _RouteQualitySnapshot(
      score: score,
      label: label,
      accuracyLabel: accuracyLabel,
      color: color,
    );
  }
}

class _SaveTripResult {
  const _SaveTripResult({
    required this.savedLocally,
    required this.syncedToCloud,
  });

  final bool savedLocally;
  final bool syncedToCloud;
}
