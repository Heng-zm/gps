part of 'history_screen.dart';

// HISTORY UI
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryBackground extends StatelessWidget {
  const _HistoryBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF120F07),
                Color(0xFF050506),
                Color(0xFF000000),
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -90,
          child: _BlurOrb(
            size: 280,
            color: _kGoldSoft.withValues(alpha: 0.18),
          ),
        ),
        Positioned(
          top: 120,
          right: -110,
          child: _BlurOrb(
            size: 260,
            color: _kBlue.withValues(alpha: 0.15),
          ),
        ),
        Positioned(
          bottom: -150,
          left: 30,
          child: _BlurOrb(
            size: 320,
            color: _kPurple.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.loading,
    required this.refreshing,
    required this.tripCount,
  });

  final bool loading;
  final bool refreshing;
  final int tripCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: _GlassCard(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    _kGoldSoft.withValues(alpha: 0.95),
                    _kGold.withValues(alpha: 0.72),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _kGoldSoft.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.map_fill,
                color: Color(0xFF15130D),
                size: 25,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SafeText(
                    'Trip Timeline',
                    maxLines: 1,
                    style: TextStyle(decoration: TextDecoration.none,

                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _SafeText(
                    loading
                        ? 'Syncing your saved rides…'
                        : '$tripCount saved ${tripCount == 1 ? 'trip' : 'trips'} · swipe left to delete',
                    maxLines: 1,
                    style: const TextStyle(decoration: TextDecoration.none,

                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: refreshing
                  ? const CupertinoActivityIndicator(
                      key: ValueKey<String>('history-syncing'),
                      color: _kGoldSoft,
                      radius: 10,
                    )
                  : const _HeaderBadge(key: ValueKey<String>('history-ready')),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: const Icon(
        CupertinoIcons.clock_fill,
        color: _kGoldSoft,
        size: 20,
      ),
    );
  }
}

class _LifetimeSummary extends StatelessWidget {
  const _LifetimeSummary({
    required this.settings,
    required this.totalMiles,
    required this.allTimeTopSpeedMph,
    required this.totalMinutes,
  });

  final SettingsService settings;
  final double totalMiles;
  final double allTimeTopSpeedMph;
  final int totalMinutes;

  @override
  Widget build(BuildContext context) {
    final double displayDistance = settings.toDisplayDistance(totalMiles);
    final double displayTopSpeed = settings.toDisplaySpeed(allTimeTopSpeedMph);
    final double hours = totalMinutes / 60.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: _GlassCard(
        radius: 30,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: _SafeText(
                    'Lifetime Dashboard',
                    maxLines: 1,
                    style: TextStyle(decoration: TextDecoration.none,

                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _kGreen.withValues(alpha: 0.18)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(CupertinoIcons.check_mark_circled_solid,
                          color: _kGreen, size: 13),
                      SizedBox(width: 5),
                      _SafeText(
                        'SYNCED',
                        maxLines: 1,
                        style: TextStyle(decoration: TextDecoration.none,

                          color: _kGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      _kGoldSoft,
                      _kCyan.withValues(alpha: 0.92),
                      _kPurple.withValues(alpha: 0.90),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SummaryMetric(
                    label: 'Distance',
                    value: displayDistance
                        .toStringAsFixed(displayDistance >= 100 ? 0 : 1),
                    unit: settings.distanceUnit,
                    icon: CupertinoIcons.map_fill,
                    color: _kGoldSoft,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Top Speed',
                    value: displayTopSpeed.round().toString(),
                    unit: settings.speedUnit,
                    icon: CupertinoIcons.speedometer,
                    color: _kCyan,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Time',
                    value: hours >= 10
                        ? hours.round().toString()
                        : hours.toStringAsFixed(1),
                    unit: 'hr',
                    icon: CupertinoIcons.timer_fill,
                    color: _kGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 16),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _SafeText(
                  value,
                  maxLines: 1,
                  style: TextStyle(decoration: TextDecoration.none,

                    color: color,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SafeText(
                    unit,
                    maxLines: 1,
                    style: const TextStyle(decoration: TextDecoration.none,

                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          _SafeText(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(decoration: TextDecoration.none,

              color: Colors.white38,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  const _HistoryToolbar({
    required this.controller,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _HistoryFilter selectedFilter;
  final ValueChanged<_HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: _GlassCard(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: <Widget>[
            CupertinoTextField(
              controller: controller,
              placeholder: 'Search date, distance, speed…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(CupertinoIcons.search,
                    color: Colors.white38, size: 18),
              ),
              suffix: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, TextEditingValue value, __) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return CupertinoButton(
                    padding: const EdgeInsets.only(right: 8),
                    minSize: 0,
                    onPressed: controller.clear,
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Colors.white38,
                      size: 18,
                    ),
                  );
                },
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              cursorColor: _kGoldSoft,
              style: const TextStyle(decoration: TextDecoration.none,

                  color: Colors.white, fontWeight: FontWeight.w800),
              placeholderStyle: const TextStyle(decoration: TextDecoration.none,

                  color: Colors.white38, fontWeight: FontWeight.w700),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            const SizedBox(height: 11),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _HistoryFilter.values.map((_HistoryFilter filter) {
                  final bool selected = selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: filter.label,
                      icon: filter.icon,
                      selected: selected,
                      onTap: () => onFilterChanged(filter),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? const Color(0xFF15130D) : Colors.white60;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: <Color>[_kGoldSoft, _kGold])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _kGoldSoft.withValues(alpha: 0.56)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: _kGoldSoft.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            _SafeText(
              label.toUpperCase(),
              maxLines: 1,
              style: TextStyle(decoration: TextDecoration.none,

                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.settings,
    required this.onOpen,
    required this.onDelete,
    required this.onExport,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final double distance = settings.toDisplayDistance(trip.distanceMiles);
    final double maxSpeed = settings.toDisplaySpeed(trip.maxSpeedMph);
    final double avgSpeed = settings.toDisplaySpeed(trip.avgSpeedMph);

    return _GlassCard(
      radius: 28,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -42,
              top: -44,
              child: _BlurOrb(
                size: 130,
                color: trip.hasRoute
                    ? _kGoldSoft.withValues(alpha: 0.11)
                    : _kRed.withValues(alpha: 0.10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _RouteMiniMap(
                        route: trip.route,
                        accent: trip.hasRoute ? _kGoldSoft : Colors.white24,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _SafeText(
                                    trip.formattedDateShort,
                                    maxLines: 1,
                                    style: const TextStyle(decoration: TextDecoration.none,

                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                _TripStatusPill(hasRoute: trip.hasRoute),
                              ],
                            ),
                            const SizedBox(height: 5),
                            _SafeText(
                              trip.formattedDate,
                              maxLines: 1,
                              style: const TextStyle(decoration: TextDecoration.none,

                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Icon(
                                  trip.hasRoute
                                      ? CupertinoIcons.play_circle_fill
                                      : CupertinoIcons.location_slash,
                                  color:
                                      trip.hasRoute ? _kGreen : Colors.white30,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SafeText(
                                    trip.hasRoute
                                        ? '${trip.route.length} GPS points · cinematic replay'
                                        : 'No GPS route saved',
                                    maxLines: 1,
                                    style: const TextStyle(decoration: TextDecoration.none,

                                      color: Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 34,
                        onPressed: onDelete,
                        child: const Icon(CupertinoIcons.trash,
                            color: _kRed, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Distance',
                          value:
                              distance.toStringAsFixed(distance >= 100 ? 0 : 1),
                          unit: settings.distanceUnit,
                          color: _kGoldSoft,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Max',
                          value: maxSpeed.round().toString(),
                          unit: settings.speedUnit,
                          color: _kCyan,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Avg',
                          value: avgSpeed.round().toString(),
                          unit: settings.speedUnit,
                          color: _kGreen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Time',
                          value: trip.formattedDuration,
                          unit: '',
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _TripCardActionButton(
                          label: 'OPEN REPLAY',
                          icon: CupertinoIcons.chevron_right_circle_fill,
                          color: trip.hasRoute ? _kGoldSoft : Colors.white24,
                          onTap: onOpen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TripCardActionButton(
                        label: 'EXPORT',
                        icon: CupertinoIcons.square_arrow_up_fill,
                        color: _kBlue,
                        compact: true,
                        onTap: onExport,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCardActionButton extends StatelessWidget {
  const _TripCardActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 11 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: <Widget>[
            _SafeText(
              label,
              maxLines: 1,
              style: const TextStyle(decoration: TextDecoration.none,

                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            SizedBox(width: compact ? 8 : 0),
            if (!compact) const Spacer(),
            Icon(icon, color: color, size: 19),
          ],
        ),
      ),
    );
  }
}

class _TripStatusPill extends StatelessWidget {
  const _TripStatusPill({required this.hasRoute});

  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    final Color color = hasRoute ? _kGreen : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: _SafeText(
        hasRoute ? 'ROUTE' : 'DATA',
        maxLines: 1,
        style: TextStyle(decoration: TextDecoration.none,

          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _RouteMiniMap extends StatelessWidget {
  const _RouteMiniMap({
    required this.route,
    required this.accent,
  });

  final List<SavedRoutePoint> route;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: CustomPaint(
        painter: _RouteMiniPainter(route: route, accent: accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RouteMiniPainter extends CustomPainter {
  const _RouteMiniPainter({
    required this.route,
    required this.accent,
  });

  final List<SavedRoutePoint> route;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    for (int i = 1; i <= 2; i++) {
      final double offset = size.width * i / 3;
      canvas.drawLine(
          Offset(offset, 0), Offset(offset, size.height), gridPaint);
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), gridPaint);
    }

    if (route.length < 2) {
      final Paint dot = Paint()..color = accent.withValues(alpha: 0.7);
      canvas.drawCircle(size.center(Offset.zero), 5, dot);
      return;
    }

    double minLat = route.first.lat;
    double maxLat = route.first.lat;
    double minLng = route.first.lng;
    double maxLng = route.first.lng;

    for (final SavedRoutePoint point in route) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLng = math.min(minLng, point.lng);
      maxLng = math.max(maxLng, point.lng);
    }

    final double latRange = math.max(0.000001, maxLat - minLat);
    final double lngRange = math.max(0.000001, maxLng - minLng);
    const double pad = 12;
    final ui.Path path = ui.Path();

    for (int i = 0; i < route.length; i++) {
      final SavedRoutePoint point = route[i];
      final double x =
          pad + ((point.lng - minLng) / lngRange) * (size.width - pad * 2);
      final double y = pad +
          (1 - ((point.lat - minLat) / latRange)) * (size.height - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final Paint glow = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 8;
    final Paint line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;

    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);

    // Draw start and end dots
    final double startX =
        pad + ((route.first.lng - minLng) / lngRange) * (size.width - pad * 2);
    final double startY = pad +
        (1 - ((route.first.lat - minLat) / latRange)) * (size.height - pad * 2);
    final double endX =
        pad + ((route.last.lng - minLng) / lngRange) * (size.width - pad * 2);
    final double endY = pad +
        (1 - ((route.last.lat - minLat) / latRange)) * (size.height - pad * 2);

    final Paint startPaint = Paint()..color = const Color(0xFF32D74B);
    final Paint endPaint = Paint()..color = const Color(0xFFFF3B30);
    final Paint dotBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(startX, startY), 3.5, startPaint);
    canvas.drawCircle(Offset(startX, startY), 3.5, dotBorder);

    canvas.drawCircle(Offset(endX, endY), 3.5, endPaint);
    canvas.drawCircle(Offset(endX, endY), 3.5, dotBorder);
  }

  @override
  bool shouldRepaint(covariant _RouteMiniPainter oldDelegate) {
    if (oldDelegate.accent != accent) return true;
    if (oldDelegate.route.length != route.length) return true;
    if (route.isEmpty) return false;
    final bool firstSame = oldDelegate.route.first.lat == route.first.lat &&
        oldDelegate.route.first.lng == route.first.lng;
    final bool lastSame = oldDelegate.route.last.lat == route.last.lat &&
        oldDelegate.route.last.lng == route.last.lng;
    return !firstSame || !lastSame;
  }
}

class _TripMiniStat extends StatelessWidget {
  const _TripMiniStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _SafeText(
                value,
                maxLines: 1,
                style: TextStyle(decoration: TextDecoration.none,

                    color: color, fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
            if (unit.isNotEmpty)
              _SafeText(
                unit,
                maxLines: 1,
                style: const TextStyle(decoration: TextDecoration.none,

                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w900),
              ),
            const SizedBox(height: 5),
            _SafeText(
              label.toUpperCase(),
              maxLines: 1,
              style: const TextStyle(decoration: TextDecoration.none,

                color: Colors.white30,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(CupertinoIcons.trash_fill, color: _kRed),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: CupertinoActivityIndicator(color: _kGoldSoft, radius: 14),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 90, 26, 26),
      child: Column(
        children: <Widget>[
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              _BlurOrb(size: 110, color: _kRed.withValues(alpha: 0.15)),
              const Icon(CupertinoIcons.wifi_exclamationmark,
                  color: _kRed, size: 44),
            ],
          ),
          const SizedBox(height: 16),
          const _SafeText(
            'Connection Error',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(decoration: TextDecoration.none,

                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          _SafeText(
            message,
            maxLines: 3,
            softWrap: true,
            textAlign: TextAlign.center,
            style: const TextStyle(decoration: TextDecoration.none,

                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          CupertinoButton(
            color: _kGoldSoft,
            borderRadius: BorderRadius.circular(14),
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(decoration: TextDecoration.none,

                  color: Color(0xFF15130D), fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: CupertinoIcons.map,
      title: 'No trips yet',
      subtitle: 'Saved recordings will appear here after tracking.',
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: CupertinoIcons.search,
      title: 'No matching trips',
      subtitle: 'Try another search or filter.',
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 90, 26, 26),
      child: Column(
        children: <Widget>[
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              _BlurOrb(size: 110, color: _kGoldSoft.withValues(alpha: 0.1)),
              Icon(icon, color: _kGoldSoft, size: 44),
            ],
          ),
          const SizedBox(height: 16),
          _SafeText(
            title,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(decoration: TextDecoration.none,

                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          _SafeText(
            subtitle,
            maxLines: 2,
            softWrap: true,
            textAlign: TextAlign.center,
            style: const TextStyle(decoration: TextDecoration.none,

                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
