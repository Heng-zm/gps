import 'dart:async';

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
  bool _checkingPermission = false;
  LocationPermissionResult? _location;
  String _mapboxStatus = 'Checking...';
  MapboxRuntimeMode _runtimeMode = MapboxRuntimeMode.auto;
  DateTime? _lastCheckedAt;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _mapboxStatus = 'Checking...';
    });

    try {
      final LocationPermissionResult location =
          await _permissionService.check();

      final bool hasToken = MapboxConfig.accessToken.trim().isNotEmpty;

      if (!mounted) return;

      setState(() {
        _location = location;
        _mapboxStatus = hasToken ? 'Configured' : 'Missing token';
        _runtimeMode =
            kIsWeb ? MapboxRuntimeMode.webFallback : MapboxRuntimeMode.auto;
        _lastCheckedAt = DateTime.now();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _mapboxStatus = MapboxConfig.accessToken.trim().isNotEmpty
            ? 'Configured'
            : 'Missing token';
        _runtimeMode =
            kIsWeb ? MapboxRuntimeMode.webFallback : MapboxRuntimeMode.auto;
        _lastCheckedAt = DateTime.now();
        _loading = false;
      });

      _showSnackBar('Diagnostics check failed: $error', isError: true);
    }
  }

  Future<void> _requestLocation() async {
    if (_checkingPermission) return;

    setState(() => _checkingPermission = true);

    try {
      final LocationPermissionResult result =
          await _permissionService.ensureReady();

      if (!mounted) return;

      setState(() {
        _location = result;
        _lastCheckedAt = DateTime.now();
      });

      _showSnackBar(
        result.isReady
            ? 'Location permission is ready.'
            : result.message,
        isError: !result.isReady,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Permission check failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  void _openLocationSettings() {
    _permissionService.openLocationSettings();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppColors.red : AppColors.card,
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocationPermissionResult? location = _location;
    final bool locationReady = location?.isReady == true;
    final bool serviceEnabled = location?.serviceEnabled == true;
    final bool tokenReady = _mapboxStatus == 'Configured';
    final int readyCount = <bool>[
      locationReady,
      serviceEnabled,
      tokenReady,
      true,
    ].where((bool value) => value).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh diagnostics',
            onPressed: _loading ? null : _refresh,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _loading
                  ? const CupertinoActivityIndicator(
                      key: ValueKey<String>('loading'),
                      radius: 9,
                    )
                  : const Icon(
                      CupertinoIcons.refresh,
                      key: ValueKey<String>('refresh'),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.blue,
          backgroundColor: AppColors.card,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loading && location == null
                ? const _DiagnosticsLoadingView(
                    key: ValueKey<String>('loading-view'),
                  )
                : ListView(
                    key: const ValueKey<String>('content-view'),
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: <Widget>[
                      _DiagnosticsHero(
                        readyCount: readyCount,
                        totalCount: 4,
                        lastCheckedAt: _lastCheckedAt,
                      ),
                      const SizedBox(height: 14),
                      _DiagnosticsCard(
                        title: 'Location',
                        subtitle: locationReady
                            ? 'GPS permission and service are ready'
                            : 'Location needs attention',
                        icon: CupertinoIcons.location_fill,
                        statusColor:
                            locationReady ? AppColors.green : AppColors.red,
                        children: <Widget>[
                          _DiagnosticRow(
                            label: 'Service',
                            value: serviceEnabled ? 'Enabled' : 'Disabled',
                            good: serviceEnabled,
                          ),
                          _DiagnosticRow(
                            label: 'Permission',
                            value: _formatPermissionName(
                              location?.permission.name,
                            ),
                            good: locationReady,
                          ),
                          _DiagnosticRow(
                            label: 'Status',
                            value: location?.message ?? 'Unknown',
                            good: locationReady,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          _ActionButton(
                            label: _checkingPermission
                                ? 'Checking Permission...'
                                : 'Request / Check Permission',
                            icon: CupertinoIcons.checkmark_shield_fill,
                            loading: _checkingPermission,
                            onTap: _requestLocation,
                          ),
                          const SizedBox(height: 8),
                          _ActionButton(
                            label: 'Open Location Settings',
                            icon: CupertinoIcons.gear_alt_fill,
                            onTap: _openLocationSettings,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _DiagnosticsCard(
                        title: 'Mapbox',
                        subtitle: tokenReady
                            ? 'Map renderer is configured'
                            : 'Access token is missing',
                        icon: CupertinoIcons.map_fill,
                        statusColor: tokenReady ? AppColors.green : AppColors.red,
                        children: <Widget>[
                          _DiagnosticRow(
                            label: 'Token',
                            value: _mapboxStatus,
                            good: tokenReady,
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
                        subtitle: 'Runtime and build information',
                        icon: CupertinoIcons.device_phone_portrait,
                        statusColor: AppColors.blueSoft,
                        children: <Widget>[
                          _DiagnosticRow(
                            label: 'Build mode',
                            value: _buildModeLabel,
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
        ),
      ),
    );
  }

  String get _buildModeLabel {
    if (kReleaseMode) return 'Release';
    if (kProfileMode) return 'Profile';
    return 'Debug';
  }

  String _formatPermissionName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Unknown';

    final String spaced = value
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (Match match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .trim();

    if (spaced.isEmpty) return 'Unknown';

    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class _DiagnosticsLoadingView extends StatelessWidget {
  const _DiagnosticsLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: const <Widget>[
        _SkeletonBlock(height: 92, radius: 28),
        SizedBox(height: 14),
        _SkeletonBlock(height: 210, radius: 24),
        SizedBox(height: 14),
        _SkeletonBlock(height: 132, radius: 24),
        SizedBox(height: 14),
        _SkeletonBlock(height: 116, radius: 24),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    required this.radius,
  });

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.35, end: 0.75),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(opacity: value, child: child);
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.07)),
        ),
      ),
    );
  }
}

class _DiagnosticsHero extends StatelessWidget {
  const _DiagnosticsHero({
    required this.readyCount,
    required this.totalCount,
    required this.lastCheckedAt,
  });

  final int readyCount;
  final int totalCount;
  final DateTime? lastCheckedAt;

  @override
  Widget build(BuildContext context) {
    final double progress =
        totalCount <= 0 ? 0 : (readyCount / totalCount).clamp(0.0, 1.0);
    final bool healthy = readyCount >= totalCount - 1;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.blue.withValues(alpha: 0.22),
            AppColors.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.blueSoft.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double value, Widget? child) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 5,
                      color: healthy ? AppColors.green : AppColors.blueSoft,
                      backgroundColor: AppColors.white.withValues(alpha: 0.10),
                    );
                  },
                ),
                Icon(
                  healthy
                      ? CupertinoIcons.checkmark_shield_fill
                      : CupertinoIcons.exclamationmark_triangle_fill,
                  color: healthy ? AppColors.green : AppColors.blueSoft,
                  size: 23,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  healthy ? 'System looks ready' : 'Diagnostics need review',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$readyCount of $totalCount checks are healthy'
                  '${lastCheckedAt == null ? '' : ' • ${_timeLabel(lastCheckedAt!)}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white70,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    final TimeOfDay value = TimeOfDay.fromDateTime(time);
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return 'checked $hour:$minute';
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.statusColor,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color statusColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(icon, color: statusColor, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.value,
    required this.good,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final bool good;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final Color color = good ? AppColors.green : AppColors.red;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.055)),
      ),
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
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
              child: Text(value),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.loading ? null : widget.onTap,
      onTapDown: widget.loading ? null : (_) => _setPressed(true),
      onTapCancel: widget.loading ? null : () => _setPressed(false),
      onTapUp: widget.loading ? null : (_) => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: widget.loading ? 0.08 : 0.14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.blue.withValues(alpha: widget.loading ? 0.14 : 0.26),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: widget.loading
                    ? const CupertinoActivityIndicator(
                        key: ValueKey<String>('button-loading'),
                        radius: 8,
                      )
                    : Icon(
                        widget.icon,
                        key: const ValueKey<String>('button-icon'),
                        color: AppColors.blueSoft,
                        size: 16,
                      ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
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
      ),
    );
  }
}
