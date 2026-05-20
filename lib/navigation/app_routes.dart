/// Centralized app route names.
class AppRoutes {
  const AppRoutes._();

  static const String root = '/';
  static const String tracking = '/tracking';
  static const String map = '/map';
  static const String history = '/history';
  static const String settings = '/settings';
  static const String summary = '/summary';
  static const String diagnostics = '/diagnostics';
  static const String arCamera = '/tracking/ar';

  static const List<String> ordered = <String>[
    root,
    tracking,
    map,
    history,
    settings,
    summary,
    diagnostics,
    arCamera,
  ];

  static const Set<String> all = <String>{
    root,
    tracking,
    map,
    history,
    settings,
    summary,
    diagnostics,
    arCamera,
  };

  static String? normalize(String? route) {
    final String value = (route ?? '').trim();
    if (value.isEmpty) return null;
    if (value == '/') return root;
    return value.startsWith('/') ? value : '/$value';
  }

  static bool isKnown(String? route) {
    final String? normalized = normalize(route);
    return normalized != null && all.contains(normalized);
  }

  static String safeRoute(String? route, {String fallback = tracking}) {
    final String? normalized = normalize(route);
    if (normalized != null && all.contains(normalized)) return normalized;
    return all.contains(fallback) ? fallback : tracking;
  }

  static bool isTrackingRoute(String? route) {
    final String? normalized = normalize(route);
    return normalized == tracking || normalized == arCamera;
  }

  static String labelOf(String? route) {
    switch (safeRoute(route, fallback: root)) {
      case root:
        return 'Home';
      case tracking:
        return 'Tracking';
      case map:
        return 'Map';
      case history:
        return 'History';
      case settings:
        return 'Settings';
      case summary:
        return 'Summary';
      case diagnostics:
        return 'Diagnostics';
      case arCamera:
        return 'AR Camera';
      default:
        return 'Unknown';
    }
  }
}
