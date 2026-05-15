// ignore_for_file: prefer_const_constructors

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/mapbox_config.dart';
import '../../models/mapbox_route_models.dart';
import '../../services/location_permission_service.dart';
import '../../theme/app_theme.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final LocationPermissionService _permissionService =
      const LocationPermissionService();

  bool _loading = true;
  LocationPermissionResult? _location;
  String _mapboxStatus = 'Checking...';
  MapboxRuntimeMode _runtimeMode = MapboxRuntimeMode.auto;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final LocationPermissionResult location =
        await _permissionService.check();

    final bool hasToken = MapboxConfig.accessToken.trim().isNotEmpty;

    if (!mounted) return;

    setState(() {
      _location = location;
      _mapboxStatus = hasToken ? 'Configured' : 'Missing token';
      _runtimeMode = kIsWeb ? MapboxRuntimeMode.webFallback : MapboxRuntimeMode.auto;
      _loading = false;
    });
  }

  Future<void> _requestLocation() async {
    final LocationPermissionResult result =
        await _permissionService.ensureReady();

    if (!mounted) return;

    setState(() => _location = result);
  }

  @override
  Widget build(BuildContext context) {
    final LocationPermissionResult? location = _location;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: <Widget>[
          IconButton(
            onPressed: _refresh,
            icon: const Icon(CupertinoIcons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator(radius: 13))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _DiagnosticsCard(
                    title: 'Location',
                    icon: CupertinoIcons.location_fill,
                    children: <Widget>[
                      _DiagnosticRow(
                        label: 'Service',
                        value: location?.serviceEnabled == true
                            ? 'Enabled'
                            : 'Disabled',
                        good: location?.serviceEnabled == true,
                      ),
                      _DiagnosticRow(
                        label: 'Permission',
                        value: location?.permission.name ?? 'Unknown',
                        good: location?.isReady == true,
                      ),
                      _DiagnosticRow(
                        label: 'Status',
                        value: location?.message ?? 'Unknown',
                        good: location?.isReady == true,
                      ),
                      const SizedBox(height: 10),
                      _ActionButton(
                        label: 'Request / Check Permission',
                        icon: CupertinoIcons.checkmark_shield_fill,
                        onTap: _requestLocation,
                      ),
                      const SizedBox(height: 8),
                      _ActionButton(
                        label: 'Open Location Settings',
                        icon: CupertinoIcons.gear_alt_fill,
                        onTap: _permissionService.openLocationSettings,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DiagnosticsCard(
                    title: 'Mapbox',
                    icon: CupertinoIcons.map_fill,
                    children: <Widget>[
                      _DiagnosticRow(
                        label: 'Token',
                        value: _mapboxStatus,
                        good: _mapboxStatus == 'Configured',
                      ),
                      _DiagnosticRow(
                        label: 'Default renderer',
                        value: _runtimeMode.label,
                        good: true,
                      ),
                      _DiagnosticRow(
                        label: 'Platform',
                        value: kIsWeb ? 'Web' : defaultTargetPlatform.name,
                        good: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DiagnosticsCard(
                    title: 'App',
                    icon: CupertinoIcons.device_phone_portrait,
                    children: <Widget>[
                      _DiagnosticRow(
                        label: 'Build mode',
                        value: kReleaseMode
                            ? 'Release'
                            : kProfileMode
                                ? 'Profile'
                                : 'Debug',
                        good: true,
                      ),
                      _DiagnosticRow(
                        label: 'Flutter web',
                        value: kIsWeb ? 'Yes' : 'No',
                        good: true,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.blueSoft, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.value,
    required this.good,
  });

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final Color color = good ? AppColors.green : AppColors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: AppColors.blueSoft, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
