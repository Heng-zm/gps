import 'package:geolocator/geolocator.dart';

enum LocationPermissionStatus {
  ready,
  serviceDisabled,
  denied,
  deniedForever,
}

class LocationPermissionResult {
  const LocationPermissionResult({
    required this.status,
    required this.serviceEnabled,
    required this.permission,
  });

  final LocationPermissionStatus status;
  final bool serviceEnabled;
  final LocationPermission permission;

  bool get isReady => status == LocationPermissionStatus.ready;

  String get message {
    switch (status) {
      case LocationPermissionStatus.ready:
        return 'Location is ready.';
      case LocationPermissionStatus.serviceDisabled:
        return 'Location service is disabled.';
      case LocationPermissionStatus.denied:
        return 'Location permission was denied.';
      case LocationPermissionStatus.deniedForever:
        return 'Location permission is permanently denied.';
    }
  }
}

class LocationPermissionService {
  const LocationPermissionService();

  Future<LocationPermissionResult> check() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final LocationPermission permission = await Geolocator.checkPermission();

    if (!serviceEnabled) {
      return LocationPermissionResult(
        status: LocationPermissionStatus.serviceDisabled,
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult(
        status: LocationPermissionStatus.deniedForever,
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionResult(
        status: LocationPermissionStatus.denied,
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
    }

    return LocationPermissionResult(
      status: LocationPermissionStatus.ready,
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
  }

  Future<LocationPermissionResult> ensureReady() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return const LocationPermissionResult(
        status: LocationPermissionStatus.serviceDisabled,
        serviceEnabled: false,
        permission: LocationPermission.denied,
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult(
        status: LocationPermissionStatus.deniedForever,
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionResult(
        status: LocationPermissionStatus.denied,
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
    }

    return LocationPermissionResult(
      status: LocationPermissionStatus.ready,
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
