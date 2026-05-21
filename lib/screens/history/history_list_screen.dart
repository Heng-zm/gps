part of 'history_screen.dart';

// SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SettingsService _settings = SettingsService.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<SavedTrip> _trips = const <SavedTrip>[];
  bool _loading = true;
  bool _refreshing = false;

  String? _loadError;

  String _query = '';
  _HistoryFilter _filter = _HistoryFilter.all;
  _HistorySortMode _sortMode = _HistorySortMode.newest;

  double _totalMiles = 0.0;
  double _allTimeTopSpeedMph = 0.0;
  int _totalMinutes = 0;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_loadTrips());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final String next = _searchCtrl.text.trim().toLowerCase();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  List<SavedTrip> get _visibleTrips {
    final DateTime now = DateTime.now();
    final List<SavedTrip> visible = _trips.where((SavedTrip trip) {
      final bool matchesFilter = switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.week => now.difference(trip.date).inDays <= 7,
        _HistoryFilter.month => now.difference(trip.date).inDays <= 31,
        _HistoryFilter.longTrips => trip.distanceMiles >= 10.0,
        _HistoryFilter.fastTrips => trip.maxSpeedMph >= 55.0,
      };

      if (!matchesFilter) return false;
      if (_query.isEmpty) return true;

      final String haystack = <String>[
        trip.formattedDate,
        trip.formattedDateShort,
        trip.distanceMiles.toStringAsFixed(1),
        trip.maxSpeedMph.toStringAsFixed(0),
        trip.avgSpeedMph.toStringAsFixed(0),
      ].join(' ').toLowerCase();

      return haystack.contains(_query);
    }).toList(growable: false);

    return _sortVisibleTrips(visible);
  }

  List<SavedTrip> _sortVisibleTrips(List<SavedTrip> trips) {
    if (trips.length < 2) return trips;

    final List<SavedTrip> sorted = List<SavedTrip>.from(trips);
    sorted.sort((SavedTrip a, SavedTrip b) {
      return switch (_sortMode) {
        _HistorySortMode.newest => b.date.compareTo(a.date),
        _HistorySortMode.longest =>
          b.totalTime.inSeconds.compareTo(a.totalTime.inSeconds),
        _HistorySortMode.fastest =>
          b.maxSpeedMph.compareTo(a.maxSpeedMph),
        _HistorySortMode.distance =>
          b.distanceMiles.compareTo(a.distanceMiles),
      };
    });

    return List<SavedTrip>.unmodifiable(sorted);
  }

  void _calculateLifetimeStats() {
    double totalMiles = 0.0;
    double topSpeed = 0.0;
    int totalMinutes = 0;

    for (final SavedTrip trip in _trips) {
      totalMiles += trip.distanceMiles.isFinite ? trip.distanceMiles : 0.0;
      if (trip.maxSpeedMph.isFinite && trip.maxSpeedMph > topSpeed) {
        topSpeed = trip.maxSpeedMph;
      }
      totalMinutes += math.max(0, trip.totalTime.inMinutes);
    }

    _totalMiles = totalMiles;
    _allTimeTopSpeedMph = topSpeed;
    _totalMinutes = totalMinutes;
  }

  Future<void> _loadTrips() async {
    if (!mounted || _refreshing) return;

    setState(() {
      _loading = _trips.isEmpty;
      _refreshing = true;
      _loadError = null;
    });

    try {
      final result = await SavedTrip.loadAllTrips();

      if (!mounted) return;

      setState(() {
        _trips = result.trips;
        _loadError = result.error;
        _calculateLifetimeStats();
        _loading = false;
        _refreshing = false;
      });
    } catch (e, st) {
      debugPrint('_loadTrips unexpected: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = 'Something went wrong. Tap to retry.';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _executeDelete(SavedTrip trip) async {
    HapticFeedback.mediumImpact();

    final bool exists = _trips.any((SavedTrip t) => t.id == trip.id);
    if (!exists) return;

    setState(() {
      final List<SavedTrip> next = List<SavedTrip>.from(_trips)
        ..removeWhere((SavedTrip t) => t.id == trip.id);
      _trips = List<SavedTrip>.unmodifiable(next);
      _calculateLifetimeStats();
    });

    final bool success = await SavedTrip.deleteTrip(trip.id);

    if (!success && mounted) {
      setState(() {
        final List<SavedTrip> rollback = List<SavedTrip>.from(_trips)
          ..removeWhere((SavedTrip t) => t.id == trip.id)
          ..add(trip)
          ..sort((SavedTrip a, SavedTrip b) => b.date.compareTo(a.date));
        _trips = List<SavedTrip>.unmodifiable(rollback);
        _calculateLifetimeStats();
      });

      _showSnack('Failed to delete. Connection error.', _kRed);
    }
  }

  Future<bool> _confirmDelete(SavedTrip trip) async {
    final bool? result = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Delete Trip'),
          content: const Text('Permanently remove this trip from the cloud?'),
          actions: <Widget>[
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (result == true) await _executeDelete(trip);
    return false;
  }

  Future<void> _openExportSheet(SavedTrip trip) async {
    HapticFeedback.mediumImpact();

    await showCupertinoModalPopup<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext sheetContext) {
        return _TripExportSheet(
          trip: trip,
          settings: _settings,
          onSelected: (TripExportFormat format) async {
            Navigator.of(sheetContext).pop();
            await _copyTripExport(trip, format);
          },
        );
      },
    );
  }

  Future<void> _copyTripExport(
    SavedTrip trip,
    TripExportFormat format,
  ) async {
    final bool routeFormat =
        format == TripExportFormat.gpx || format == TripExportFormat.kml;
    if (routeFormat && trip.route.length < 2) {
      _showSnack(
          'This trip has no route points to export as ${format.label}.', _kRed);
      return;
    }

    final String content = _TripExportBuilder.build(
      trip: trip,
      settings: _settings,
      format: format,
    );
    final String filename = _TripExportBuilder.fileName(trip, format);

    final bool shared = await _shareTripExportFile(
      context: context,
      filename: filename,
      content: content,
      format: format,
    );
    if (!mounted) return;

    if (shared) {
      _showSnack('$filename ready to share.', _kGreen);
      return;
    }

    final bool copied = await _safeCopyToClipboard(content);
    if (!mounted) return;

    if (copied) {
      _showSnack(
        'Share unavailable. $filename copied to clipboard.',
        _kGoldSoft,
      );
      return;
    }

    _showSnack(
      'Share and clipboard are unavailable. Export text opened instead.',
      _kGoldSoft,
    );

    await _showTripExportPreviewPopup(
      context: context,
      filename: filename,
      extensionName: format.extensionName,
      content: content,
    );
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  void _openTripDetails(SavedTrip trip) {
    HapticFeedback.lightImpact();

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation) {
          return TripDetailScreen(
            trip: trip,
            settings: _settings,
            onExport: _openExportSheet,
          );
        },
        transitionsBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation, Widget child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.05),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<SavedTrip> visibleTrips = _visibleTrips;
    final bool showSummary = !_loading && _trips.isNotEmpty;
    final double topSafe = MediaQuery.viewPaddingOf(context).top;
    final double bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: _kBg,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: _HistoryBackground()),
              CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: <Widget>[
                  CupertinoSliverRefreshControl(onRefresh: _loadTrips),
                  SliverPadding(
                    padding: EdgeInsets.only(top: topSafe + 8),
                    sliver: SliverToBoxAdapter(
                      child: _HistoryHeader(
                        loading: _loading,
                        refreshing: _refreshing,
                        tripCount: _trips.length,
                      ),
                    ),
                  ),
                  if (showSummary)
                    SliverToBoxAdapter(
                      child: _LifetimeSummary(
                        settings: _settings,
                        totalMiles: _totalMiles,
                        allTimeTopSpeedMph: _allTimeTopSpeedMph,
                        totalMinutes: _totalMinutes,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _HistoryToolbar(
                      controller: _searchCtrl,
                      selectedFilter: _filter,
                      onFilterChanged: (_HistoryFilter filter) {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = filter);
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _HistorySortStrip(
                      selected: _sortMode,
                      onChanged: (_HistorySortMode mode) {
                        HapticFeedback.selectionClick();
                        setState(() => _sortMode = mode);
                      },
                    ),
                  ),
                  if (_loading)
                    const SliverToBoxAdapter(child: _LoadingState())
                  else if (_loadError != null)
                    SliverToBoxAdapter(
                      child: _ErrorState(
                        message: _loadError!,
                        onRetry: _loadTrips,
                      ),
                    )
                  else if (_trips.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyState())
                  else if (visibleTrips.isEmpty)
                    const SliverToBoxAdapter(child: _NoResultsState())
                  else
                    SliverSafeArea(
                      top: false,
                      minimum: EdgeInsets.only(
                        bottom: math.max(24.0, bottomSafe + 24.0),
                      ),
                      sliver: SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                        sliver: SliverList.builder(
                          itemCount: visibleTrips.length,
                          itemBuilder: (BuildContext context, int index) {
                            final SavedTrip trip = visibleTrips[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Dismissible(
                                key: ValueKey<String>('trip-${trip.id}'),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) => _confirmDelete(trip),
                                background: const _DeleteBackground(),
                                child: _Pressable(
                                  onTap: () => _openTripDetails(trip),
                                  child: _TripCard(
                                    trip: trip,
                                    settings: _settings,
                                    onOpen: () => _openTripDetails(trip),
                                    onDelete: () => _confirmDelete(trip),
                                    onExport: () => _openExportSheet(trip),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HistoryFilter { all, week, month, longTrips, fastTrips }

enum _HistorySortMode { newest, longest, fastest, distance }

extension _HistorySortModeX on _HistorySortMode {
  String get label {
    return switch (this) {
      _HistorySortMode.newest => 'Newest',
      _HistorySortMode.longest => 'Longest',
      _HistorySortMode.fastest => 'Fastest',
      _HistorySortMode.distance => 'Distance',
    };
  }

  IconData get icon {
    return switch (this) {
      _HistorySortMode.newest => CupertinoIcons.clock_fill,
      _HistorySortMode.longest => CupertinoIcons.timer_fill,
      _HistorySortMode.fastest => CupertinoIcons.speedometer,
      _HistorySortMode.distance => CupertinoIcons.map_fill,
    };
  }
}


extension _HistoryFilterX on _HistoryFilter {
  String get label {
    return switch (this) {
      _HistoryFilter.all => 'All',
      _HistoryFilter.week => 'Week',
      _HistoryFilter.month => 'Month',
      _HistoryFilter.longTrips => 'Long',
      _HistoryFilter.fastTrips => 'Fast',
    };
  }

  IconData get icon {
    return switch (this) {
      _HistoryFilter.all => CupertinoIcons.square_grid_2x2_fill,
      _HistoryFilter.week => CupertinoIcons.calendar,
      _HistoryFilter.month => CupertinoIcons.calendar_today,
      _HistoryFilter.longTrips => CupertinoIcons.map_fill,
      _HistoryFilter.fastTrips => CupertinoIcons.speedometer,
    };
  }
}


class _HistorySortStrip extends StatelessWidget {
  const _HistorySortStrip({
    required this.selected,
    required this.onChanged,
  });

  final _HistorySortMode selected;
  final ValueChanged<_HistorySortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _HistorySortMode.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (BuildContext context, int index) {
            final _HistorySortMode mode = _HistorySortMode.values[index];
            final bool active = mode == selected;

            return _Pressable(
              onTap: () => onChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active
                      ? _kGoldSoft.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? _kGoldSoft.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      mode.icon,
                      size: 14,
                      color: active ? _kGoldSoft : Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    _SafeText(
                      mode.label.toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(
                        decoration: TextDecoration.none,
                        color: active ? _kGoldSoft : Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.55,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
