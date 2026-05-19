import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum MapboxVisualStyle {
  standard,
  standardSatellite,
  streets,
  outdoors,
  light,
  dark,
  satellite,
  satelliteStreets,
  navigationDay,
  navigationNight,
}

extension MapboxVisualStyleX on MapboxVisualStyle {
  String get label {
    switch (this) {
      case MapboxVisualStyle.standard:
        return 'Mapbox Standard';
      case MapboxVisualStyle.standardSatellite:
        return 'Standard Satellite';
      case MapboxVisualStyle.streets:
        return 'Streets';
      case MapboxVisualStyle.outdoors:
        return 'Outdoors';
      case MapboxVisualStyle.light:
        return 'Light';
      case MapboxVisualStyle.dark:
        return 'Dark';
      case MapboxVisualStyle.satellite:
        return 'Satellite';
      case MapboxVisualStyle.satelliteStreets:
        return 'Satellite Streets';
      case MapboxVisualStyle.navigationDay:
        return 'Navigation Day';
      case MapboxVisualStyle.navigationNight:
        return 'Navigation Night';
    }
  }

  String get shortLabel {
    switch (this) {
      case MapboxVisualStyle.standard:
        return 'Standard';
      case MapboxVisualStyle.standardSatellite:
        return 'Std Sat';
      case MapboxVisualStyle.streets:
        return 'Streets';
      case MapboxVisualStyle.outdoors:
        return 'Outdoor';
      case MapboxVisualStyle.light:
        return 'Light';
      case MapboxVisualStyle.dark:
        return 'Dark';
      case MapboxVisualStyle.satellite:
        return 'Satellite';
      case MapboxVisualStyle.satelliteStreets:
        return 'Sat+Road';
      case MapboxVisualStyle.navigationDay:
        return 'Nav Day';
      case MapboxVisualStyle.navigationNight:
        return 'Nav Night';
    }
  }

  String get description {
    switch (this) {
      case MapboxVisualStyle.standard:
        return 'Default configurable basemap with modern 3D elements.';
      case MapboxVisualStyle.standardSatellite:
        return 'Satellite imagery blended with Mapbox Standard 3D layers.';
      case MapboxVisualStyle.streets:
        return 'Comprehensive general-purpose road map.';
      case MapboxVisualStyle.outdoors:
        return 'Optimized for hiking, biking and fitness tracking.';
      case MapboxVisualStyle.light:
        return 'Subtle low-contrast grayscale map.';
      case MapboxVisualStyle.dark:
        return 'Dark map for night use and dark UI.';
      case MapboxVisualStyle.satellite:
        return 'Pure aerial photography without roads or labels.';
      case MapboxVisualStyle.satelliteStreets:
        return 'Satellite imagery with major roads and labels.';
      case MapboxVisualStyle.navigationDay:
        return 'High-contrast style optimized for daytime driving.';
      case MapboxVisualStyle.navigationNight:
        return 'Dark navigation style for dashboard use.';
    }
  }

  String get styleUri {
    switch (this) {
      case MapboxVisualStyle.standard:
        return 'mapbox://styles/mapbox/standard';
      case MapboxVisualStyle.standardSatellite:
        return 'mapbox://styles/mapbox/standard-satellite';
      case MapboxVisualStyle.streets:
        return 'mapbox://styles/mapbox/streets-v12';
      case MapboxVisualStyle.outdoors:
        return 'mapbox://styles/mapbox/outdoors-v12';
      case MapboxVisualStyle.light:
        return 'mapbox://styles/mapbox/light-v11';
      case MapboxVisualStyle.dark:
        return 'mapbox://styles/mapbox/dark-v11';
      case MapboxVisualStyle.satellite:
        return 'mapbox://styles/mapbox/satellite-v9';
      case MapboxVisualStyle.satelliteStreets:
        return 'mapbox://styles/mapbox/satellite-streets-v12';
      case MapboxVisualStyle.navigationDay:
        return 'mapbox://styles/mapbox/navigation-day-v1';
      case MapboxVisualStyle.navigationNight:
        return 'mapbox://styles/mapbox/navigation-night-v1';
    }
  }

  IconData get icon {
    switch (this) {
      case MapboxVisualStyle.standard:
        return CupertinoIcons.cube_box_fill;
      case MapboxVisualStyle.standardSatellite:
        return CupertinoIcons.globe;
      case MapboxVisualStyle.streets:
        return CupertinoIcons.map_fill;
      case MapboxVisualStyle.outdoors:
        return CupertinoIcons.tree;
      case MapboxVisualStyle.light:
        return CupertinoIcons.sun_max_fill;
      case MapboxVisualStyle.dark:
        return CupertinoIcons.moon_stars_fill;
      case MapboxVisualStyle.satellite:
        return CupertinoIcons.photo_fill;
      case MapboxVisualStyle.satelliteStreets:
        return CupertinoIcons.map_pin_ellipse;
      case MapboxVisualStyle.navigationDay:
      case MapboxVisualStyle.navigationNight:
        return CupertinoIcons.car_detailed;
    }
  }

  Color get accentColor {
    switch (this) {
      case MapboxVisualStyle.standard:
        return const Color(0xFF3B82F6);
      case MapboxVisualStyle.standardSatellite:
        return const Color(0xFF22C55E);
      case MapboxVisualStyle.streets:
        return const Color(0xFF38BDF8);
      case MapboxVisualStyle.outdoors:
        return const Color(0xFF16A34A);
      case MapboxVisualStyle.light:
        return const Color(0xFFE5E7EB);
      case MapboxVisualStyle.dark:
        return const Color(0xFF60A5FA);
      case MapboxVisualStyle.satellite:
        return const Color(0xFFA3E635);
      case MapboxVisualStyle.satelliteStreets:
        return const Color(0xFFF59E0B);
      case MapboxVisualStyle.navigationDay:
        return const Color(0xFF2563EB);
      case MapboxVisualStyle.navigationNight:
        return const Color(0xFF818CF8);
    }
  }

  bool get isStandardFamily {
    switch (this) {
      case MapboxVisualStyle.standard:
      case MapboxVisualStyle.standardSatellite:
        return true;
      default:
        return false;
    }
  }

  bool get isSatelliteFamily {
    switch (this) {
      case MapboxVisualStyle.standardSatellite:
      case MapboxVisualStyle.satellite:
      case MapboxVisualStyle.satelliteStreets:
        return true;
      default:
        return false;
    }
  }

  bool get isNavigationFamily {
    switch (this) {
      case MapboxVisualStyle.navigationDay:
      case MapboxVisualStyle.navigationNight:
        return true;
      default:
        return false;
    }
  }

  bool get isDark {
    switch (this) {
      case MapboxVisualStyle.dark:
      case MapboxVisualStyle.navigationNight:
        return true;
      default:
        return false;
    }
  }

  String rasterTilesUrl(String accessToken, {int tileSize = 512}) {
    final String token = Uri.encodeComponent(accessToken.trim());
    final String stylePath = styleUri.replaceFirst('mapbox://styles/', '');
    final int safeTileSize = tileSize == 256 ? 256 : 512;
    return 'https://api.mapbox.com/styles/v1/$stylePath/tiles/'
        '$safeTileSize/{z}/{x}/{y}@2x?access_token=$token';
  }

  String get storageKey => name;

  static MapboxVisualStyle fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();

    for (final MapboxVisualStyle style in MapboxVisualStyle.values) {
      if (style.storageKey.toLowerCase() == normalized ||
          style.label.toLowerCase() == normalized ||
          style.shortLabel.toLowerCase() == normalized) {
        return style;
      }
    }

    switch (normalized) {
      case 'standard-satellite':
      case 'stdsat':
      case 'std_sat':
        return MapboxVisualStyle.standardSatellite;
      case 'sat':
        return MapboxVisualStyle.satellite;
      case 'sat-road':
      case 'sat+road':
      case 'satellite-streets':
        return MapboxVisualStyle.satelliteStreets;
      case 'navday':
      case 'navigation-day':
        return MapboxVisualStyle.navigationDay;
      case 'navnight':
      case 'navigation-night':
        return MapboxVisualStyle.navigationNight;
      default:
        return MapboxVisualStyle.standard;
    }
  }
}

class MapboxStyleCatalog {
  const MapboxStyleCatalog._();

  static const List<MapboxVisualStyle> standard = <MapboxVisualStyle>[
    MapboxVisualStyle.standard,
    MapboxVisualStyle.standardSatellite,
  ];

  static const List<MapboxVisualStyle> classic = <MapboxVisualStyle>[
    MapboxVisualStyle.streets,
    MapboxVisualStyle.outdoors,
    MapboxVisualStyle.light,
    MapboxVisualStyle.dark,
  ];

  static const List<MapboxVisualStyle> satellite = <MapboxVisualStyle>[
    MapboxVisualStyle.satellite,
    MapboxVisualStyle.satelliteStreets,
  ];

  static const List<MapboxVisualStyle> navigation = <MapboxVisualStyle>[
    MapboxVisualStyle.navigationDay,
    MapboxVisualStyle.navigationNight,
  ];

  static const List<MapboxVisualStyle> all = <MapboxVisualStyle>[
    ...standard,
    ...classic,
    ...satellite,
    ...navigation,
  ];
}
