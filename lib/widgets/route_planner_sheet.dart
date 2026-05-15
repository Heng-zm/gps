// ignore_for_file: unused_element, prefer_const_constructors

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/mapbox_route_models.dart';
import '../services/mapbox_geocoding_service.dart';
import '../theme/app_theme.dart';
import 'common/app_status_pill.dart';
import 'common/app_section_card.dart';
import 'common/app_search_bar.dart';
import 'common/app_glass_card.dart';
import 'common/app_filter_chip.dart';
import 'common/app_action_button.dart';

class RoutePlannerOption<T> {
  const RoutePlannerOption({
    required this.value,
    required this.label,
    required this.icon,
    this.shortLabel,
    this.description,
  });

  final T value;
  final String label;
  final String? shortLabel;
  final IconData icon;
  final String? description;

  String get displayLabel => shortLabel ?? label;
}

class RoutePlannerSheet<TProfile, TPreset, TRuntime> extends StatefulWidget {
  const RoutePlannerSheet({
    super.key,
    required this.mapboxAccessToken,
    required this.profileOptions,
    required this.initialProfile,
    required this.presetOptions,
    required this.initialPreset,
    required this.runtimeOptions,
    required this.initialRuntime,
    required this.directionsLoading,
    required this.onPlanRoute,
    required this.onPresetChanged,
    required this.onRuntimeChanged,
    required this.onClearRoute,
    this.plannedRoute,
    this.currentPositionProvider,
    this.title = 'ROUTE PLANNER',
    this.subtitle = 'Search and plan your next route',
  });

  final String mapboxAccessToken;
  final List<RoutePlannerOption<TProfile>> profileOptions;
  final TProfile initialProfile;
  final List<RoutePlannerOption<TPreset>> presetOptions;
  final TPreset initialPreset;
  final List<RoutePlannerOption<TRuntime>> runtimeOptions;
  final TRuntime initialRuntime;
  final bool directionsLoading;
  final PlannedRouteSummary? plannedRoute;
  final LatLng? Function()? currentPositionProvider;
  final String title;
  final String subtitle;

  final Future<void> Function({
    required double destinationLat,
    required double destinationLng,
    required TProfile profile,
  }) onPlanRoute;

  final ValueChanged<TPreset> onPresetChanged;
  final ValueChanged<TRuntime> onRuntimeChanged;
  final VoidCallback onClearRoute;

  @override
  State<RoutePlannerSheet<TProfile, TPreset, TRuntime>> createState() =>
      _RoutePlannerSheetState<TProfile, TPreset, TRuntime>();
}

class _RoutePlannerSheetState<TProfile, TPreset, TRuntime>
    extends State<RoutePlannerSheet<TProfile, TPreset, TRuntime>> {
  static const Color _goldSoft = Color(0xFFFFD86B);
  static const Color _blue = AppColors.blue;
  static const Color _green = AppColors.green;
  static const Color _muted = Colors.white54;
  static const Color _surface = Color(0xFF14141A);
  static const Color _textPrimary = Colors.white;
  static const Color _textMuted = Colors.white54;
  static const Duration _animFast = Duration(milliseconds: 180);
  static const Duration _animMed = Duration(milliseconds: 260);

  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  Timer? _searchDebounce;

  late TProfile _profile;
  late TPreset _preset;
  late TRuntime _runtime;

  MapboxPlaceResult? _selectedPlace;
  List<MapboxPlaceResult> _results = const <MapboxPlaceResult>[];
  String _lastQuery = '';
  bool _searching = false;
  int _searchToken = 0;

  RoutePlannerOption<TProfile> get _selectedProfileOption =>
      _findOption(widget.profileOptions, _profile);

  RoutePlannerOption<TPreset> get _selectedPresetOption =>
      _findOption(widget.presetOptions, _preset);

  RoutePlannerOption<TRuntime> get _selectedRuntimeOption =>
      _findOption(widget.runtimeOptions, _runtime);

  RoutePlannerOption<T> _findOption<T>(List<RoutePlannerOption<T>> items, T value) {
    for (final RoutePlannerOption<T> item in items) {
      if (item.value == value) return item;
    }
    return items.first;
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _preset = widget.initialPreset;
    _runtime = widget.initialRuntime;
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchToken++;
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final String query = _searchCtrl.text.trim();

    if (query == _lastQuery) return;

    _searchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _lastQuery = '';
        _results = const <MapboxPlaceResult>[];
        _selectedPlace = null;
      });
      return;
    }

    if (_trySelectCoordinate(query, silent: true)) return;

    if (query.length < 3) {
      setState(() {
        _lastQuery = query;
        _results = const <MapboxPlaceResult>[];
        _selectedPlace = null;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 650), () {
      if (mounted) unawaited(_searchPlaces(silentShortQuery: true));
    });
  }

  void _clearSearch() {
    HapticFeedback.selectionClick();
    _searchDebounce?.cancel();
    setState(() {
      _searchCtrl.clear();
      _lastQuery = '';
      _selectedPlace = null;
      _results = const <MapboxPlaceResult>[];
      _searching = false;
    });
  }

  bool _trySelectCoordinate(String input, {bool silent = false}) {
    final RegExpMatch? match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(input);

    if (match == null) return false;

    final double? lat = double.tryParse(match.group(1)!);
    final double? lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return false;

    final LatLng position = LatLng(lat, lng);
    if (!isValidLatLng(position)) {
      if (!silent) _showSheetSnack('Coordinate is invalid.');
      return true;
    }

    final MapboxPlaceResult place = MapboxPlaceResult(
      name: 'Pinned coordinate',
      address: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      position: position,
    );

    setState(() {
      _lastQuery = input.trim();
      _selectedPlace = place;
      _results = <MapboxPlaceResult>[place];
      _searching = false;
    });

    return true;
  }

  Future<void> _searchPlaces({bool silentShortQuery = false}) async {
    final String query = _searchCtrl.text.trim();

    if (_trySelectCoordinate(query)) return;

    if (query.length < 2) {
      if (!silentShortQuery) _showSheetSnack('Type a place name first.');
      return;
    }

    if (_searching && query == _lastQuery) return;
    _lastQuery = query;

    _searchFocus.unfocus();

    final int token = ++_searchToken;
    setState(() {
      _searching = true;
      _results = const <MapboxPlaceResult>[];
      _selectedPlace = null;
    });

    try {
      final MapboxGeocodingService service = MapboxGeocodingService(
        accessToken: widget.mapboxAccessToken,
      );

      final List<MapboxPlaceResult> nextResults = await service.searchPlaces(
        query: query,
        proximity: widget.currentPositionProvider?.call(),
        limit: 8,
      );

      if (!mounted || token != _searchToken) return;

      setState(() {
        _results = List<MapboxPlaceResult>.unmodifiable(nextResults);
        if (nextResults.length == 1) _selectedPlace = nextResults.first;
      });

      if (nextResults.isEmpty) _showSheetSnack('No matching location found.');
    } on MapboxGeocodingException catch (error) {
      if (mounted && token == _searchToken) {
        _showSheetSnack(error.message);
      }
    } catch (error, stackTrace) {
      debugPrint('Mapbox geocoding search error: $error\n$stackTrace');
      if (mounted && token == _searchToken) {
        _showSheetSnack('Location search failed.');
      }
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => _searching = false);
      }
    }
  }


  Future<void> _submit() async {
    final MapboxPlaceResult? place = _selectedPlace;

    if (place == null) {
      _showSheetSnack(
        _results.isNotEmpty
            ? 'Tap a search result first.'
            : 'Search and select a destination first.',
      );
      return;
    }

    await widget.onPlanRoute(
      destinationLat: place.position.latitude,
      destinationLng: place.position.longitude,
      profile: _profile,
    );
  }

  void _quickSearch(String query) {
    HapticFeedback.selectionClick();
    _searchCtrl.text = query;
    _searchCtrl.selection = TextSelection.collapsed(offset: query.length);
    unawaited(_searchPlaces());
  }

  void _showSheetSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _cyclePreset() {
    final int index =
        widget.presetOptions.indexWhere((item) => item.value == _preset);
    final RoutePlannerOption<TPreset> next =
        widget.presetOptions[(index + 1) % widget.presetOptions.length];
    HapticFeedback.selectionClick();
    setState(() => _preset = next.value);
    widget.onPresetChanged(next.value);
  }

  void _cycleRuntime() {
    final int index =
        widget.runtimeOptions.indexWhere((item) => item.value == _runtime);
    final RoutePlannerOption<TRuntime> next =
        widget.runtimeOptions[(index + 1) % widget.runtimeOptions.length];
    HapticFeedback.selectionClick();
    setState(() => _runtime = next.value);
    widget.onRuntimeChanged(next.value);
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double bottomInset = media.viewInsets.bottom;
    final double maxHeight = media.size.height * 0.94;

    return AnimatedPadding(
      duration: _animMed,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxHeight,
            maxWidth: 640,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _surface.withValues(alpha: 0.97),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.60),
                      blurRadius: 34,
                      offset: const Offset(0, -16),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 46,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        _RoutePlannerHeroHeader(
                          title: widget.title,
                          subtitle: widget.subtitle,
                          selectedPlace: _selectedPlace,
                          profileLabel: _selectedProfileOption.displayLabel,
                          onClear:
                              _selectedPlace == null ? null : _clearSearch,
                        ),
                        const SizedBox(height: 14),
                        AppGlassCard(
                          padding: const EdgeInsets.all(14),
                          borderRadius: 24,
                          child: Column(
                            children: <Widget>[
                              AppSearchBar(
                                controller: _searchCtrl,
                                focusNode: _searchFocus,
                                hintText: 'Search destination or paste lat,lng',
                                onSubmitted: (_) => unawaited(_searchPlaces()),
                                onClear: _clearSearch,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: AppActionButton(
                                      label: _searching
                                          ? 'Searching...'
                                          : 'Search',
                                      icon: CupertinoIcons.search,
                                      primary: true,
                                      enabled: !_searching,
                                      onTap: () => unawaited(_searchPlaces()),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  AppStatusPill(
                                    label: _selectedPlace == null
                                        ? 'NO DEST'
                                        : 'SELECTED',
                                    color: _selectedPlace == null
                                        ? _muted
                                        : _green,
                                    icon: _selectedPlace == null
                                        ? CupertinoIcons.location
                                        : CupertinoIcons.checkmark_alt,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _RoutePlannerQuickChips(
                                onQuickSearch: _quickSearch,
                              ),
                              if (_selectedPlace != null) ...<Widget>[
                                const SizedBox(height: 12),
                                _SelectedDestinationCard(
                                  place: _selectedPlace!,
                                  onClear: _clearSearch,
                                ),
                              ],
                              if (_results.isNotEmpty &&
                                  _selectedPlace == null) ...<Widget>[
                                const SizedBox(height: 12),
                                _RoutePlannerResultsList(
                                  results: _results,
                                  onSelect: (place) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedPlace = place);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppSectionCard(
                          title: 'Travel mode',
                          subtitle: 'Choose the route profile',
                          icon: CupertinoIcons.car_detailed,
                          children: <Widget>[
                            _RoutePlannerModeCard<TProfile>(
                              options: widget.profileOptions,
                              selected: _profile,
                              onChanged: (profile) {
                                HapticFeedback.selectionClick();
                                setState(() => _profile = profile);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _RoutePlannerSelectCard(
                                title: 'Map style',
                                subtitle: 'Standard preset',
                                icon: CupertinoIcons.map_fill,
                                color: _goldSoft,
                                child: _RoutePlannerSelectButton(
                                  label: _selectedPresetOption.label,
                                  icon: _selectedPresetOption.icon,
                                  color: _goldSoft,
                                  onTap: _cyclePreset,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _RoutePlannerSelectCard(
                                title: 'Runtime',
                                subtitle: 'Best map engine',
                                icon: CupertinoIcons.speedometer,
                                color: _green,
                                child: _RoutePlannerSelectButton(
                                  label: _selectedRuntimeOption.label,
                                  icon: _selectedRuntimeOption.icon,
                                  color: _green,
                                  onTap: _cycleRuntime,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _PlannedRouteSummaryCard<TProfile>(
                          route: widget.plannedRoute,
                          selectedPlace: _selectedPlace,
                          profile: _selectedProfileOption,
                          onClearRoute: widget.plannedRoute == null
                              ? null
                              : widget.onClearRoute,
                        ),
                        const SizedBox(height: 14),
                        AppActionButton(
                          label: widget.directionsLoading
                              ? 'Planning route...'
                              : 'Plan Route',
                          icon: CupertinoIcons.location_north_line_fill,
                          primary: true,
                          enabled: _selectedPlace != null &&
                              !widget.directionsLoading,
                          onTap: _selectedPlace != null &&
                                  !widget.directionsLoading
                              ? _submit
                              : () => _showSheetSnack(
                                    'Search and select a destination first.',
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _RoutePlannerHeader extends StatelessWidget {
  const _RoutePlannerHeader({
    required this.title,
    required this.subtitle,
    required this.selectedPlace,
    required this.onClear,
  });

  final String title;
  final String subtitle;
  final MapboxPlaceResult? selectedPlace;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _RoutePlannerSheetState._blue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _RoutePlannerSheetState._blue.withValues(alpha: 0.24),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _RoutePlannerSheetState._blue.withValues(alpha: 0.18),
                blurRadius: 24,
              ),
            ],
          ),
          child: const Icon(
            Icons.navigation_rounded,
            color: _RoutePlannerSheetState._blue,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  color: _RoutePlannerSheetState._textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                selectedPlace == null ? subtitle : 'Destination selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _RoutePlannerSheetState._textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (onClear != null)
          _RoutePlannerTinyButton(
            icon: CupertinoIcons.xmark,
            color: _RoutePlannerSheetState._textMuted,
            onTap: onClear!,
          ),
      ],
    );
  }
}


class _RoutePlannerHeroHeader extends StatelessWidget {
  const _RoutePlannerHeroHeader({
    required this.title,
    required this.subtitle,
    required this.selectedPlace,
    required this.profileLabel,
    required this.onClear,
  });

  final String title;
  final String subtitle;
  final MapboxPlaceResult? selectedPlace;
  final String profileLabel;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 26,
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.blueButtonGradient,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.30),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.location_north_line_fill,
              color: AppColors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedPlace?.name ?? subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppStatusPill(
                      label: profileLabel,
                      color: AppColors.blueSoft,
                      icon: CupertinoIcons.car_detailed,
                    ),
                    AppStatusPill(
                      label: selectedPlace == null ? 'SEARCH' : 'READY',
                      color: selectedPlace == null ? AppColors.white54 : AppColors.green,
                      icon: selectedPlace == null
                          ? CupertinoIcons.search
                          : CupertinoIcons.checkmark_alt,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onClear != null) ...<Widget>[
            const SizedBox(width: 10),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: onClear,
              child: const Icon(
                CupertinoIcons.xmark_circle_fill,
                color: Colors.white38,
                size: 24,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlannerSectionTitle extends StatelessWidget {
  const _PlannerSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          CupertinoIcons.slider_horizontal_3,
          color: AppColors.blueSoft,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
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
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoutePlannerQuickChips extends StatelessWidget {
  const _RoutePlannerQuickChips({
    required this.onQuickSearch,
  });

  final ValueChanged<String> onQuickSearch;

  @override
  Widget build(BuildContext context) {
    const List<String> quick = <String>[
      'Phnom Penh',
      'Airport',
      'Home',
      'Work',
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: quick.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String label = quick[index];

          return AppFilterChip(
            label: label,
            selected: false,
            icon: CupertinoIcons.location_fill,
            onTap: () => onQuickSearch(label),
          );
        },
      ),
    );
  }
}

class _RoutePlannerResultsList extends StatelessWidget {
  const _RoutePlannerResultsList({
    required this.results,
    required this.onSelect,
  });

  final List<MapboxPlaceResult> results;
  final ValueChanged<MapboxPlaceResult> onSelect;

  @override
  Widget build(BuildContext context) {
    final int count = results.length > 5 ? 5 : results.length;

    return Column(
      children: List<Widget>.generate(count, (int index) {
        final MapboxPlaceResult place = results[index];

        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => onSelect(place),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.075),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    CupertinoIcons.location_fill,
                    color: AppColors.blueSoft,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          place.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    color: Colors.white30,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _RoutePlannerSearchCard extends StatelessWidget {
  const _RoutePlannerSearchCard({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.selectedPlace,
    required this.results,
    required this.onSearch,
    required this.onClear,
    required this.onSelect,
    required this.onQuickSearch,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final MapboxPlaceResult? selectedPlace;
  final List<MapboxPlaceResult> results;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final ValueChanged<MapboxPlaceResult> onSelect;
  final ValueChanged<String> onQuickSearch;

  @override
  Widget build(BuildContext context) {
    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _RoutePlannerEndpointDot(
                icon: CupertinoIcons.location_fill,
                color: _RoutePlannerSheetState._blue,
              ),
              const SizedBox(width: 8),
              const Text(
                'From',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: _RoutePlannerSheetState._textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color:
                        _RoutePlannerSheetState._blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: _RoutePlannerSheetState._blue
                          .withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Text(
                    'My Location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _RoutePlannerSheetState._blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (selectedPlace != null) ...<Widget>[
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: _RoutePlannerSheetState._green,
                  size: 17,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: selectedPlace == null
                    ? Colors.white.withValues(alpha: 0.08)
                    : _RoutePlannerSheetState._green.withValues(alpha: 0.26),
              ),
              boxShadow: selectedPlace == null
                  ? null
                  : <BoxShadow>[
                      BoxShadow(
                        color: _RoutePlannerSheetState._green
                            .withValues(alpha: 0.10),
                        blurRadius: 16,
                      ),
                    ],
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 14),
                Icon(
                  selectedPlace == null
                      ? CupertinoIcons.search
                      : CupertinoIcons.location_solid,
                  color: selectedPlace == null
                      ? _RoutePlannerSheetState._textMuted
                      : _RoutePlannerSheetState._green,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: CupertinoTextField.borderless(
                    controller: controller,
                    focusNode: focusNode,
                    placeholder: 'Search destination or paste lat,lng...',
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => onSearch(),
                    style: const TextStyle(
                      color: _RoutePlannerSheetState._textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    placeholderStyle: const TextStyle(
                      color: _RoutePlannerSheetState._textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty) ...<Widget>[
                  _RoutePlannerTinyButton(
                    icon: CupertinoIcons.xmark,
                    color: _RoutePlannerSheetState._textMuted,
                    onTap: onClear,
                  ),
                  const SizedBox(width: 5),
                ],
                SizedBox(
                  width: 92,
                  height: 44,
                  child: _RoutePlannerGradientButton(
                    label: searching ? '...' : 'GO',
                    icon: searching
                        ? CupertinoIcons.hourglass
                        : CupertinoIcons.search,
                    color: _RoutePlannerSheetState._blue,
                    onTap: searching ? () {} : onSearch,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
          if (searching) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                color: _RoutePlannerSheetState._blue,
              ),
            ),
          ],
          if (selectedPlace != null) ...<Widget>[
            const SizedBox(height: 10),
            _SelectedDestinationCard(
              place: selectedPlace!,
              onClear: onClear,
            ),
          ],
          if (results.isEmpty && selectedPlace == null && !searching) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Recent & popular',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: _RoutePlannerSheetState._textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const _RoutePlannerHintChip(label: 'lat,lng supported'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _RoutePlannerShortcutChip(
                    icon: CupertinoIcons.house_fill,
                    title: 'Home',
                    subtitle: 'Nearby',
                    onTap: () => onQuickSearch('home'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RoutePlannerShortcutChip(
                    icon: CupertinoIcons.briefcase_fill,
                    title: 'Work',
                    subtitle: 'Office',
                    onTap: () => onQuickSearch('work'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RoutePlannerShortcutChip(
                    icon: CupertinoIcons.building_2_fill,
                    title: 'Market',
                    subtitle: 'Popular',
                    onTap: () => onQuickSearch('Central Market Phnom Penh'),
                  ),
                ),
              ],
            ),
          ],
          if (results.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Search results',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: _RoutePlannerSheetState._textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _RoutePlannerHintChip(label: '${results.length} found'),
              ],
            ),
            const SizedBox(height: 8),
            ...results.map(
              (place) => _RoutePlannerPlaceTile(
                place: place,
                selected: identical(place, selectedPlace),
                onTap: () => onSelect(place),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutePlannerEndpointDot extends StatelessWidget {
  const _RoutePlannerEndpointDot({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: color, size: 14),
    );
  }
}

class _RoutePlannerHintChip extends StatelessWidget {
  const _RoutePlannerHintChip({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          color: _RoutePlannerSheetState._textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SelectedDestinationCard extends StatelessWidget {
  const _SelectedDestinationCard({
    required this.place,
    required this.onClear,
  });

  final MapboxPlaceResult place;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _RoutePlannerSheetState._animFast,
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _RoutePlannerSheetState._green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: _RoutePlannerSheetState._green.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: _RoutePlannerSheetState._green,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _RoutePlannerSheetState._textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  place.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _RoutePlannerSheetState._textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RoutePlannerTinyButton(
            icon: CupertinoIcons.xmark,
            color: _RoutePlannerSheetState._textMuted,
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}

class _RoutePlannerShortcutChip extends StatelessWidget {
  const _RoutePlannerShortcutChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableTap(
      onTap: onTap,
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: _RoutePlannerSheetState._blue, size: 17),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _RoutePlannerSheetState._textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerModeCard<T> extends StatelessWidget {
  const _RoutePlannerModeCard({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<RoutePlannerOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Travel mode',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: _RoutePlannerSheetState._textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 11),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: options.map((option) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _RoutePlannerModeChip<T>(
                    option: option,
                    selected: option.value == selected,
                    onTap: () => onChanged(option.value),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePlannerModeChip<T> extends StatelessWidget {
  const _RoutePlannerModeChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final RoutePlannerOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        selected ? _RoutePlannerSheetState._blue : Colors.white54;

    return _PressableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _RoutePlannerSheetState._animFast,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? _RoutePlannerSheetState._blue.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? _RoutePlannerSheetState._blue.withValues(alpha: 0.46)
                : Colors.white.withValues(alpha: 0.09),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(option.icon, color: color, size: 16),
            const SizedBox(width: 7),
            Text(
              option.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerSelectCard extends StatelessWidget {
  const _RoutePlannerSelectCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _RoutePlannerSheetState._textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RoutePlannerSelectButton extends StatelessWidget {
  const _RoutePlannerSelectButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableTap(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(CupertinoIcons.chevron_down, color: color, size: 12),
          ],
        ),
      ),
    );
  }
}

class _PlannedRouteSummaryCard<T> extends StatelessWidget {
  const _PlannedRouteSummaryCard({
    required this.route,
    required this.selectedPlace,
    required this.profile,
    required this.onClearRoute,
  });

  final PlannedRouteSummary? route;
  final MapboxPlaceResult? selectedPlace;
  final RoutePlannerOption<T> profile;
  final VoidCallback? onClearRoute;

  @override
  Widget build(BuildContext context) {
    final bool hasRoute = route != null;

    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Route summary',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: _RoutePlannerSheetState._textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _RoutePlannerSheetState._green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color:
                        _RoutePlannerSheetState._green.withValues(alpha: 0.18),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      CupertinoIcons.circle_fill,
                      color: _RoutePlannerSheetState._green,
                      size: 7,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Live traffic',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: _RoutePlannerSheetState._textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _RoutePlannerSheetState._blue
                            .withValues(alpha: 0.18),
                        border: Border.all(
                          color: _RoutePlannerSheetState._blue
                              .withValues(alpha: 0.32),
                        ),
                      ),
                      child: Icon(
                        profile.icon,
                        color: _RoutePlannerSheetState._blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: hasRoute
                          ? Row(
                              children: <Widget>[
                                Expanded(
                                  child: _RouteMetric(
                                    value: route!.distanceLabel,
                                    label: 'Distance',
                                  ),
                                ),
                                const _MetricDivider(),
                                Expanded(
                                  child: _RouteMetric(
                                    value: route!.durationLabel,
                                    label: 'Est. time',
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              selectedPlace == null
                                  ? 'Select a destination to preview route.'
                                  : 'Ready to calculate route to ${selectedPlace!.name}.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _RoutePlannerSheetState._textMuted,
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    if (hasRoute) ...<Widget>[
                      const _MetricDivider(),
                      Expanded(
                        child: _RouteMetric(
                          value: route!.profileLabel,
                          label: 'Mode',
                          color: _RoutePlannerSheetState._blue,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RoutePreviewPainter(
                      active: hasRoute,
                      color: hasRoute
                          ? _RoutePlannerSheetState._blue
                          : Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasRoute && onClearRoute != null) ...<Widget>[
            const SizedBox(height: 10),
            _RoutePlannerSecondaryButton(
              label: 'CLEAR ROUTE',
              icon: CupertinoIcons.trash,
              onTap: onClearRoute!,
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({
    required this.value,
    required this.label,
    this.color = _RoutePlannerSheetState._textPrimary,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          ' ',
          style: TextStyle(fontSize: 0),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 9),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _RoutePlannerPlanButton extends StatelessWidget {
  const _RoutePlannerPlanButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color disabledColor = Colors.white38;

    return _PressableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _RoutePlannerSheetState._animFast,
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  colors: <Color>[
                    _RoutePlannerSheetState._green.withValues(alpha: 0.86),
                    _RoutePlannerSheetState._green.withValues(alpha: 0.56),
                  ],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled
                ? _RoutePlannerSheetState._green.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color:
                        _RoutePlannerSheetState._green.withValues(alpha: 0.24),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (loading)
              const CupertinoActivityIndicator(color: Colors.white, radius: 10)
            else
              Icon(
                CupertinoIcons.location_fill,
                color: enabled ? Colors.white : disabledColor,
                size: 19,
              ),
            const SizedBox(width: 10),
            Text(
              loading ? 'PLANNING ROUTE...' : 'PLAN ROUTE',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: enabled ? Colors.white : disabledColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerSecondaryButton extends StatelessWidget {
  const _RoutePlannerSecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableTap(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white54, size: 15),
            const SizedBox(width: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
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

class _RoutePlannerGlassCard extends StatelessWidget {
  const _RoutePlannerGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RoutePlannerGradientButton extends StatelessWidget {
  const _RoutePlannerGradientButton({
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
    return _PressableTap(
      onTap: onTap,
      child: Container(
        height: compact ? 44 : 48,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              color.withValues(alpha: 0.85),
              color.withValues(alpha: 0.42),
            ],
          ),
          borderRadius: BorderRadius.circular(compact ? 17 : 18),
          border: Border.all(color: color.withValues(alpha: 0.36)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: compact ? 13 : 15),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerTinyButton extends StatelessWidget {
  const _RoutePlannerTinyButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableTap(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _RoutePlannerPlaceTile extends StatelessWidget {
  const _RoutePlannerPlaceTile({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final MapboxPlaceResult place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        selected ? _RoutePlannerSheetState._green : _RoutePlannerSheetState._blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: _PressableTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: _RoutePlannerSheetState._animFast,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: selected ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 0.34 : 0.16),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.location_solid,
                color: accent,
                size: 17,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _RoutePlannerSheetState._textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      place.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _RoutePlannerSheetState._textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter({
    required this.active,
    required this.color,
  });

  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1.0;

    for (double x = 0; x < size.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x + 22, size.height), gridPaint);
    }

    final ui.Path path = ui.Path()
      ..moveTo(12, size.height * 0.62)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.10,
        size.width * 0.38,
        size.height * 0.92,
        size.width * 0.58,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.78,
        -4,
        size.width * 0.82,
        size.height * 0.88,
        size.width - 14,
        size.height * 0.32,
      );

    final Paint routePaint = Paint()
      ..color = color.withValues(alpha: active ? 0.82 : 0.28)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, routePaint);

    final Paint dotPaint = Paint()
      ..color = color.withValues(alpha: active ? 1.0 : 0.45);
    canvas.drawCircle(Offset(12, size.height * 0.62), 5, dotPaint);
    canvas.drawCircle(Offset(size.width - 14, size.height * 0.32), 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.active != active || oldDelegate.color != color;
  }
}

class _PressableTap extends StatelessWidget {
  const _PressableTap({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: child,
    );
  }
}
