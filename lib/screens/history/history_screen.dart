import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/mapbox_config.dart';
import '../../models/location_puck_style.dart';
import '../../models/mapbox_styles.dart';
import '../../services/settings_service.dart';
import '../../services/trip_export_service.dart';
import '../../services/trip_export_service.dart';
import '../../widgets/location_puck_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY SCREEN — Premium glass timeline + cinematic trip replay
// Clean, clear UI with an Apple-Music-style replay controller, unified
// map action buttons, and flawless text decoration safety.

part 'history_models.dart';
part 'history_list_screen.dart';
part 'history_list_widgets.dart';
part 'history_detail_screen.dart';
part 'history_export_widgets.dart';
