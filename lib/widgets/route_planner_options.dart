import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/mapbox_route_models.dart';
import 'route_planner_sheet.dart';

class RoutePlannerOptions {
  const RoutePlannerOptions._();

  static const List<RoutePlannerOption<DirectionsProfile>> profileOptions =
      <RoutePlannerOption<DirectionsProfile>>[
    RoutePlannerOption<DirectionsProfile>(
      value: DirectionsProfile.drivingTraffic,
      label: 'DRIVE+TRAFFIC',
      shortLabel: 'Drive+Traffic',
      icon: CupertinoIcons.car_detailed,
      description: 'Driving with live traffic where available',
    ),
    RoutePlannerOption<DirectionsProfile>(
      value: DirectionsProfile.driving,
      label: 'DRIVING',
      shortLabel: 'Driving',
      icon: CupertinoIcons.car_detailed,
      description: 'Standard driving route',
    ),
    RoutePlannerOption<DirectionsProfile>(
      value: DirectionsProfile.walking,
      label: 'WALKING',
      shortLabel: 'Walking',
      icon: CupertinoIcons.person_fill,
      description: 'Walking route',
    ),
    RoutePlannerOption<DirectionsProfile>(
      value: DirectionsProfile.cycling,
      label: 'CYCLING',
      shortLabel: 'Cycling',
      icon: Icons.directions_bike_rounded,
      description: 'Cycling route',
    ),
  ];

  static const List<RoutePlannerOption<MapboxStandardPreset>> presetOptions =
      <RoutePlannerOption<MapboxStandardPreset>>[
    RoutePlannerOption<MapboxStandardPreset>(
      value: MapboxStandardPreset.day,
      label: 'DAY',
      icon: CupertinoIcons.sun_max_fill,
      description: 'Bright standard map',
    ),
    RoutePlannerOption<MapboxStandardPreset>(
      value: MapboxStandardPreset.dusk,
      label: 'DUSK',
      icon: CupertinoIcons.sunset_fill,
      description: 'Soft evening style',
    ),
    RoutePlannerOption<MapboxStandardPreset>(
      value: MapboxStandardPreset.dawn,
      label: 'DAWN',
      icon: CupertinoIcons.sunrise_fill,
      description: 'Morning style',
    ),
    RoutePlannerOption<MapboxStandardPreset>(
      value: MapboxStandardPreset.night,
      label: 'NIGHT',
      icon: CupertinoIcons.moon_stars_fill,
      description: 'Dark night style',
    ),
  ];

  static const List<RoutePlannerOption<MapboxRuntimeMode>> runtimeOptions =
      <RoutePlannerOption<MapboxRuntimeMode>>[
    RoutePlannerOption<MapboxRuntimeMode>(
      value: MapboxRuntimeMode.auto,
      label: 'AUTO',
      icon: CupertinoIcons.sparkles,
      description: 'Best renderer for this platform',
    ),
    RoutePlannerOption<MapboxRuntimeMode>(
      value: MapboxRuntimeMode.native,
      label: 'NATIVE',
      icon: CupertinoIcons.device_phone_portrait,
      description: 'Native Mapbox renderer',
    ),
    RoutePlannerOption<MapboxRuntimeMode>(
      value: MapboxRuntimeMode.webFallback,
      label: 'WEB',
      icon: CupertinoIcons.globe,
      description: 'Flutter map fallback',
    ),
  ];
}
