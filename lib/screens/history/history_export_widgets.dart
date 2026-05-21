part of 'history_screen.dart';

class _TripExportSheet extends StatelessWidget {
  const _TripExportSheet({
    required this.trip,
    required this.settings,
    required this.onSelected,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final ValueChanged<TripExportFormat> onSelected;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.viewPaddingOf(context);
    final Size size = MediaQuery.sizeOf(context);
    final double bottomPad = math.max(safe.bottom, 14.0);
    final double maxHeight = size.height * 0.86;
    final double distance = settings.toDisplayDistance(trip.distanceMiles);

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight,
                minWidth: double.infinity,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _kSurface.withValues(alpha: 0.96),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.52),
                      blurRadius: 30,
                      offset: const Offset(0, -12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Center(
                            child: Container(
                              width: 46,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: <Widget>[
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: <Color>[_kGoldSoft, _kGold],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: _kGoldSoft.withValues(alpha: 0.22),
                                      blurRadius: 22,
                                      offset: const Offset(0, 9),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  CupertinoIcons.square_arrow_up_fill,
                                  color: Color(0xFF15130D),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const _SafeText(
                                      'Export Trip',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _SafeText(
                                      '${distance.toStringAsFixed(distance >= 100 ? 0 : 1)} ${settings.distanceUnit} · ${trip.route.length} GPS points',
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(18, 0, 18, bottomPad + 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            ...TripExportFormat.values.map(
                              (TripExportFormat format) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: _TripExportFormatTile(
                                    format: format,
                                    onTap: () => onSelected(format),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 2),
                            const _SafeText(
                              'Export opens your device share sheet as a real file. Clipboard fallback is used if sharing is unavailable. GPX/KML need at least 2 GPS points.',
                              maxLines: 3,
                              softWrap: true,
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripExportFormatTile extends StatefulWidget {
  const _TripExportFormatTile({
    required this.format,
    required this.onTap,
  });

  final TripExportFormat format;
  final VoidCallback onTap;

  @override
  State<_TripExportFormatTile> createState() => _TripExportFormatTileState();
}

class _TripExportFormatTileState extends State<_TripExportFormatTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final TripExportFormat format = widget.format;

    return Semantics(
      button: true,
      label: 'Export ${format.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.985 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _pressed ? 0.075 : 0.045),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: Colors.white.withValues(alpha: _pressed ? 0.13 : 0.075),
              ),
            ),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: _pressed ? 0.20 : 0.13),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBlue.withValues(alpha: 0.18)),
                  ),
                  child: Icon(format.icon, color: _kBlue, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SafeText(
                        format.label,
                        maxLines: 1,
                        style: const TextStyle(
                          decoration: TextDecoration.none,
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _SafeText(
                        format.description,
                        maxLines: 1,
                        style: const TextStyle(
                          decoration: TextDecoration.none,
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: _pressed ? 0.03 : 0.0,
                  child: const Icon(
                    CupertinoIcons.chevron_right_circle_fill,
                    color: _kGoldSoft,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> _shareTripExportFile({
  required BuildContext context,
  required String filename,
  required String content,
  required TripExportFormat format,
}) {
  return TripExportService.shareRawFile(
    context: context,
    filename: filename,
    content: content,
    mimeType: _TripExportBuilder.mimeType(format),
    subject: filename,
    text: 'Trip export from GPS Tracker: $filename',
  );
}

class _TripExportBuilder {
  const _TripExportBuilder._();

  static String fileName(SavedTrip trip, TripExportFormat format) {
    final String date = DateFormat('yyyyMMdd_HHmm').format(trip.date);
    final String safeId = trip.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'trip_${date}_$safeId.${format.extensionName}';
  }

  static String mimeType(TripExportFormat format) {
    return switch (format) {
      TripExportFormat.gpx => 'application/gpx+xml',
      TripExportFormat.kml => 'application/vnd.google-earth.kml+xml',
      TripExportFormat.csv => 'text/csv',
      TripExportFormat.json => 'application/json',
      TripExportFormat.txt => 'text/plain',
    };
  }

  static String build({
    required SavedTrip trip,
    required SettingsService settings,
    required TripExportFormat format,
  }) {
    return switch (format) {
      TripExportFormat.gpx => _gpx(trip),
      TripExportFormat.kml => _kml(trip),
      TripExportFormat.csv => _csv(trip),
      TripExportFormat.json => _json(trip),
      TripExportFormat.txt => _txt(trip, settings),
    };
  }

  static String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _gpx(SavedTrip trip) {
    final String name = _xmlEscape('Trip ${trip.formattedDate}');
    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<gpx version="1.1" creator="TrackPro AI" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <metadata><name>$name</name></metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>$name</name>')
      ..writeln('    <trkseg>');

    for (final SavedRoutePoint point in trip.route) {
      buffer.writeln(
        '      <trkpt lat="${point.lat.toStringAsFixed(7)}" lon="${point.lng.toStringAsFixed(7)}"><extensions><speed_mph>${point.speedMph.toStringAsFixed(2)}</speed_mph></extensions></trkpt>',
      );
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  static String _kml(SavedTrip trip) {
    final String name = _xmlEscape('Trip ${trip.formattedDate}');
    final String coordinates = trip.route
        .map((SavedRoutePoint p) =>
            '${p.lng.toStringAsFixed(7)},${p.lat.toStringAsFixed(7)},0')
        .join(' ');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$name</name>
    <Placemark>
      <name>$name</name>
      <Style>
        <LineStyle><color>ff4fd5ff</color><width>5</width></LineStyle>
      </Style>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>$coordinates</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
''';
  }

  static String _csv(SavedTrip trip) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('index,latitude,longitude,speed_mph');

    for (int i = 0; i < trip.route.length; i++) {
      final SavedRoutePoint point = trip.route[i];
      buffer.writeln(
        '$i,${point.lat.toStringAsFixed(7)},${point.lng.toStringAsFixed(7)},${point.speedMph.toStringAsFixed(2)}',
      );
    }

    return buffer.toString();
  }

  static String _json(SavedTrip trip) {
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(trip.toJson());
  }

  static String _txt(SavedTrip trip, SettingsService settings) {
    final double distance = settings.toDisplayDistance(trip.distanceMiles);
    final double maxSpeed = settings.toDisplaySpeed(trip.maxSpeedMph);
    final double avgSpeed = settings.toDisplaySpeed(trip.avgSpeedMph);

    return '''Trip Summary
Date: ${trip.formattedDate}
Distance: ${distance.toStringAsFixed(distance >= 100 ? 0 : 1)} ${settings.distanceUnit}
Max Speed: ${maxSpeed.round()} ${settings.speedUnit}
Average Speed: ${avgSpeed.round()} ${settings.speedUnit}
Duration: ${trip.formattedDuration}
Altitude Gain: ${trip.altitudeGainFt.toStringAsFixed(0)} ft
GPS Points: ${trip.route.length}
Trip ID: ${trip.id}
''';
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _PressableButton extends StatefulWidget {
  const _PressableButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 180),
    value: 1.0,
    lowerBound: 0.88,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _ctrl.reverse().then((_) => _ctrl.forward());
        widget.onTap();
      },
      onTapDown: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.forward(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, Widget? child) =>
            Transform.scale(scale: _ctrl.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
    this.overflow = TextOverflow.ellipsis,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
      style: style.copyWith(decoration: TextDecoration.none),
    );
  }
}

// ── LatLng tween for animated camera moves ────────────────────────────────────

class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}
