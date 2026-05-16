part of 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAP BOTTOM PANEL
// ─────────────────────────────────────────────────────────────────────────────

extension _MapScreenBottomPanel on _MapScreenState {
  // ───────────────────────────────────────────────────────────────────────────
  // BOTTOM PANEL
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBottomPanel(BuildContext context) {
    if (_route.isEmpty) return const SizedBox.shrink();

    return MeasureSize(
      onChange: (Size size) => _bottomPanelHeight.value = size.height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).padding.bottom + 10,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    _kSurface.withValues(alpha: 0.92),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Drag handle
                  GestureDetector(
                    onTap: _togglePanel,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _panelExpanded ? 36 : 48,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    child: _panelExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (widget.isLive &&
                                    _showChart &&
                                    _route.speedSamples.isNotEmpty)
                                  _buildMiniChart(),
                                if (widget.isLive && _showSpeedGradient) ...<Widget>[
                                  const SizedBox(height: 10),
                                  _buildSpeedLegend(),
                                  const SizedBox(height: 12),
                                  Divider(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    height: 1,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                _buildCompactRouteSummaryCard(),
                                if (_plannedRoute != null) ...<Widget>[
                                  const SizedBox(height: 10),
                                  _buildPlannedRouteSummaryCard(),
                                ],
                                if (!widget.isLive &&
                                    _route.validPoints.length > 1) ...<Widget>[
                                  const SizedBox(height: 10),
                                  _buildReplayControls(),
                                ],
                                const SizedBox(height: 10),
                                _buildActionRow(),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactRouteSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SummaryMiniStat(
              label: 'DISTANCE',
              value: _formatDistance(_route.distanceKm),
              color: _kBlueSoft,
            ),
          ),
          const _ThinDivider(),
          Expanded(
            child: _SummaryMiniStat(
              label: 'MAX SPEED',
              value: '${_route.maxSpeedKmh.toStringAsFixed(0)} km/h',
              color: _kBlueSoft,
            ),
          ),
          const _ThinDivider(),
          Expanded(
            child: _SummaryMiniStat(
              label: 'AVG SPEED',
              value: '${_route.avgSpeedKmh.toStringAsFixed(0)} km/h',
              color: _kGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannedRouteSummaryCard() {
    final PlannedRoute? route = _plannedRoute;
    if (route == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.location_north_line_fill,
            color: _kBlue,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${route.distanceLabelMetric} · ${route.durationLabel()} · ${route.profile.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PressableButton(
            onTap: () => _setMapState(() => _plannedRoute = null),
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Colors.white54,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _PressableButton(
            onTap: _fitRoute,
            child: const _ActionTile(
              icon: CupertinoIcons.arrow_down_right_arrow_up_left,
              label: 'FIT ROUTE',
              isActive: false,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PressableButton(
            onTap: _toggleFollow,
            child: _ActionTile(
              icon: _followMode
                  ? CupertinoIcons.location_fill
                  : CupertinoIcons.location,
              label: _followMode ? 'FOLLOWING' : 'FOLLOW',
              isActive: _followMode,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PressableButton(
            onTap: _openMapboxControls,
            child: _ActionTile(
              icon: CupertinoIcons.location_north_line_fill,
              label: _plannedRoute == null ? 'ROUTE' : 'PLANNED',
              isActive: _plannedRoute != null,
            ),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildStatsGrid() {
    final bool hasAltitude = _route.maxAltitudeM > 0.0;

    return Row(
      children: <Widget>[
        _StatTile(
          label: 'DISTANCE',
          value: _route.distanceKm >= 1
              ? _route.distanceKm.toStringAsFixed(2)
              : (_route.distanceKm * 1000).toStringAsFixed(0),
          unit: _route.distanceKm >= 1 ? 'KM' : 'M',
          color: _kBlueSoft,
          icon: CupertinoIcons.map,
        ),
        _StatTile(
          label: 'MAX SPD',
          value: _route.maxSpeedKmh.toStringAsFixed(0),
          unit: 'KM/H',
          color: _kBlueSoft,
          icon: CupertinoIcons.bolt_fill,
        ),
        _StatTile(
          label: 'AVG SPD',
          value: _route.avgSpeedKmh.toStringAsFixed(0),
          unit: 'KM/H',
          color: _kGreen,
          icon: CupertinoIcons.speedometer,
        ),
        _StatTile(
          label: hasAltitude ? 'MAX ALT' : 'POINTS',
          value: hasAltitude
              ? _route.maxAltitudeM.toStringAsFixed(0)
              : '${_route.validPoints.length}',
          unit: hasAltitude ? 'M' : 'PTS',
          color: _kRed,
          icon: hasAltitude
              ? CupertinoIcons.arrow_up
              : CupertinoIcons.circle_grid_hex,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MINI CHART with touch scrubbing
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildMiniChart() {
    final bool hasAltitude = _route.altSamples.any((double v) => v > 0.0);
    final List<double> samples = _chartMode == _ChartMode.speed
        ? _route.speedSamples
        : _route.altSamples;
    final Color chartColor =
        _chartMode == _ChartMode.speed ? _kBlueSoft : _kBlue;
    final String unit = _chartMode == _ChartMode.speed ? 'km/h' : 'm';

    return AnimatedBuilder(
      animation: _chartRevealController,
      builder: (_, __) => Opacity(
        opacity: _chartRevealController.value,
        child: SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _chartRevealController,
            curve: Curves.easeOutCubic,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 6),
              // Tabs
              Row(
                children: <Widget>[
                  _ChartTab(
                    label: 'SPEED',
                    active: _chartMode == _ChartMode.speed,
                    color: _kBlueSoft,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _setMapState(() => _chartMode = _ChartMode.speed);
                    },
                  ),
                  const SizedBox(width: 7),
                  if (hasAltitude)
                    _ChartTab(
                      label: 'ALTITUDE',
                      active: _chartMode == _ChartMode.altitude,
                      color: _kBlue,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _setMapState(() => _chartMode = _ChartMode.altitude);
                      },
                    ),
                  const Spacer(),
                  // Scrub value display
                  ValueListenableBuilder<int>(
                    valueListenable: _chartScrubIndex,
                    builder: (_, int idx, __) {
                      final String label = idx >= 0 && idx < samples.length
                          ? '${samples[idx].toStringAsFixed(1)} $unit'
                          : '';
                      return AnimatedOpacity(
                        opacity: label.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: chartColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Chart with scrub gesture
              SizedBox(
                height: 76,
                child: ValueListenableBuilder<int>(
                  valueListenable: _chartScrubIndex,
                  builder: (_, int scrubIdx, __) {
                    return GestureDetector(
                      onHorizontalDragUpdate: (DragUpdateDetails details) {
                        final RenderBox? box =
                            context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final double localX =
                            details.localPosition.dx.clamp(0.0, box.size.width);
                        final int idx =
                            ((localX / box.size.width) * (samples.length - 1))
                                .round()
                                .clamp(0, samples.length - 1);
                        _chartScrubIndex.value = idx;
                      },
                      onHorizontalDragEnd: (_) {
                        Future<void>.delayed(
                          const Duration(milliseconds: 1500),
                          () {
                            if (mounted) _chartScrubIndex.value = -1;
                          },
                        );
                      },
                      child: CustomPaint(
                        size: const Size(double.infinity, 76),
                        painter: _MiniChartPainter(
                          samples: samples,
                          color: chartColor,
                          useSpeedColors: _chartMode == _ChartMode.speed,
                          scrubIndex: scrubIdx,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                color: Colors.white.withValues(alpha: 0.06),
                height: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedLegend() {
    const List<({Color color, String label})> items =
        <({Color color, String label})>[
      (color: _kBlueSoft, label: '<15'),
      (color: _kGreen, label: '15–40'),
      (color: _kBlue, label: '40–70'),
      (color: _kBlueSoft, label: '70–100'),
      (color: _kRed, label: '100+'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((item) {
          return Column(
            children: <Widget>[
              Container(
                width: 26,
                height: 4,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Column(
      children: <Widget>[
        _PressableButton(
          onTap: () => _doZoom(1),
          child: const _ZoomBox(icon: CupertinoIcons.plus),
        ),
        const SizedBox(height: 8),
        _PressableButton(
          onTap: () => _doZoom(-1),
          child: const _ZoomBox(icon: CupertinoIcons.minus),
        ),
      ],
    );
  }}

// ─────────────────────────────────────────────────────────────────────────────
// MINI CHART PAINTER
// ─────────────────────────────────────────────────────────────────────────────

// FIX: Cache the ParagraphStyle at class level — allocating it on every paint
// call was unnecessary garbage.
final ui.ParagraphStyle _kLabelParaStyle = ui.ParagraphStyle(
  textDirection: ui.TextDirection.ltr,
);

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.samples,
    required this.color,
    this.useSpeedColors = false,
    this.scrubIndex = -1,
  });

  final List<double> samples;
  final Color color;
  final bool useSpeedColors;
  final int scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final double maxVal = samples.reduce(math.max).clamp(1.0, double.infinity);
    final double w = size.width;
    final double h = size.height - 4;
    final int len = samples.length;
    final double denom = math.max(1, len - 1).toDouble();

    final List<Offset> pts = List<Offset>.generate(len, (int i) {
      return Offset((i / denom) * w, h - (samples[i] / maxVal) * h);
    });

    // Fill path
    final ui.Path fillPath = ui.Path()
      ..moveTo(pts.first.dx, h + 4)
      ..lineTo(pts.first.dx, pts.first.dy);

    // Line path
    final ui.Path linePath = ui.Path()..moveTo(pts.first.dx, pts.first.dy);

    for (int i = 0; i < len - 1; i++) {
      final Offset p0 = i > 0 ? pts[i - 1] : pts[i];
      final Offset p1 = pts[i];
      final Offset p2 = pts[i + 1];
      final Offset p3 = i + 2 < len ? pts[i + 2] : p2;

      final double cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final double cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final double cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final double cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      linePath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    fillPath
      ..lineTo(pts.last.dx, h + 4)
      ..close();

    // Draw fill
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h + 4)),
    );

    // Grid lines
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.5;

    for (int tick = 0; tick <= 2; tick++) {
      final double value = maxVal * tick / 2;
      final double y = h - (value / maxVal) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);

      final ui.ParagraphBuilder builder = ui.ParagraphBuilder(_kLabelParaStyle)
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
          ),
        )
        ..addText(value.toStringAsFixed(0));

      final ui.Paragraph para = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 40));
      canvas.drawParagraph(para, Offset(2, y - 9));
    }

    // Line
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Speed dots
    if (useSpeedColors && len > 4) {
      final int step = (len / 12).ceil().clamp(1, len);
      final Paint dotPaint = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < pts.length; i += step) {
        dotPaint.color = _speedColor(samples[i]);
        canvas.drawCircle(pts[i], 2.5, dotPaint);
      }
    }

    // Scrub crosshair
    if (scrubIndex >= 0 && scrubIndex < pts.length) {
      final Offset scrubPt = pts[scrubIndex];

      // Vertical line
      canvas.drawLine(
        Offset(scrubPt.dx, 0),
        Offset(scrubPt.dx, h + 4),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );

      // Dot
      canvas.drawCircle(
        scrubPt,
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        scrubPt,
        5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    // FIX: List identity check is correct for immutable lists from utils.
    // Also check scrubIndex for crosshair updates.
    return !identical(oldDelegate.samples, samples) ||
        oldDelegate.color != color ||
        oldDelegate.useSpeedColors != useSpeedColors ||
        oldDelegate.scrubIndex != scrubIndex;
  }
}

