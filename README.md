# GPS Tracker

A modern Flutter GPS tracking app with Mapbox maps, route planning, trip replay, AI trip insights, export tools, diagnostics, weather, and premium black / white / blue UI.

## Features

### Live GPS Tracking

- Live speed tracking
- Distance, duration, average speed, max speed
- Auto-pause support
- GPS signal and accuracy indicators
- Battery-friendly tracking modes
- Weather card
- Heading / compass support
- Route quality indicators

### Mapbox Maps

Supported Mapbox styles:

| Style | URI |
|---|---|
| Mapbox Standard | `mapbox://styles/mapbox/standard` |
| Standard Satellite | `mapbox://styles/mapbox/standard-satellite` |
| Streets | `mapbox://styles/mapbox/streets-v12` |
| Outdoors | `mapbox://styles/mapbox/outdoors-v12` |
| Light | `mapbox://styles/mapbox/light-v11` |
| Dark | `mapbox://styles/mapbox/dark-v11` |
| Satellite | `mapbox://styles/mapbox/satellite-v9` |
| Satellite Streets | `mapbox://styles/mapbox/satellite-streets-v12` |
| Navigation Day | `mapbox://styles/mapbox/navigation-day-v1` |
| Navigation Night | `mapbox://styles/mapbox/navigation-night-v1` |

### 3D Map

3D map modes:

- Flat
- Soft 3D
- Full 3D
- Navigation 3D

The app supports camera pitch, bearing, and zoom changes for a 3D navigation feel.

### Route Planning

- Search destination with Mapbox Geocoding
- Plan route with Mapbox Directions
- Travel modes
- Route preview
- Route summary
- Map style picker
- Runtime mode controls

### Trip History

- Saved trip list
- Search trips
- Filter by:
  - All
  - Week
  - Month
  - Long trips
  - Fast trips
- Lifetime stats
- Trip detail and replay
- Swipe to delete

### Trip Replay

- Video-style replay controller
- Play / pause
- Timeline scrubber
- Speed selector:
  - 0.5x
  - 1x
  - 2x
  - 4x
- Replay route on map

### Summary

- Trip score / route quality
- Distance and duration hero card
- Avg speed / max speed
- Moving time / stopped time
- Route preview
- Speed chart
- Elevation stats
- AI trip insight
- Export actions

### AI Chat

- AI Trip Coach
- Suggested prompts
- Trip context cards
- Markdown answers
- Sticky input bar

### Export Center

Export formats:

- GPX
- KML
- CSV
- JSON
- Summary Image

### Diagnostics

Checks:

- GPS service
- Location permission
- Mapbox token
- Mapbox Geocoding
- Mapbox Directions
- Internet status
- Renderer status
- App build mode

## Project Structure

```text
lib/
├── design/
│   ├── app_motion.dart
│   └── app_tokens.dart
├── models/
│   ├── mapbox_3d_config.dart
│   ├── mapbox_route_models.dart
│   ├── mapbox_styles.dart
│   └── tracking_accuracy_mode.dart
├── navigation/
│   └── app_routes.dart
├── screens/
│   ├── diagnostics/
│   ├── export/
│   ├── map/
│   ├── onboarding/
│   ├── tracking/
│   ├── history_screen.dart
│   ├── settings_screen.dart
│   └── summary_screen.dart
├── services/
│   ├── location_permission_service.dart
│   ├── mapbox_3d_service.dart
│   ├── mapbox_directions_service.dart
│   ├── mapbox_geocoding_service.dart
│   └── settings_service.dart
├── utils/
│   ├── app_haptics.dart
│   └── app_logger.dart
└── widgets/
    ├── common/
    │   ├── app_action_button.dart
    │   ├── app_draggable_sheet.dart
    │   ├── app_empty_state.dart
    │   ├── app_filter_chip.dart
    │   ├── app_glass_card.dart
    │   ├── app_icon_button.dart
    │   ├── app_metric_card.dart
    │   ├── app_page_shell.dart
    │   ├── app_route_preview.dart
    │   ├── app_search_bar.dart
    │   ├── app_section_card.dart
    │   ├── app_speed_chart.dart
    │   ├── app_status_pill.dart
    │   ├── app_switch_tile.dart
    │   ├── app_timeline_slider.dart
    │   └── app_ui.dart
    ├── ai_chat_sheet.dart
    ├── mapbox_3d_mode_selector.dart
    ├── mapbox_style_options.dart
    └── route_planner_sheet.dart
```

## Requirements

- Flutter stable
- Dart SDK
- Android Studio or VS Code
- Xcode for iOS builds
- Visual Studio 2022 for Windows builds
- Mapbox access token

## Setup

### 1. Clone project

```bash
git clone <your-repo-url>
cd gps_tracker
```

### 2. Install packages

```bash
flutter pub get
```

### 3. Add Mapbox token

Create or update your Mapbox config file, for example:

```dart
class MapboxConfig {
  static const String accessToken = 'YOUR_MAPBOX_ACCESS_TOKEN';
}
```

Never commit a private production token to a public repository.

### 4. Clean and analyze

```bash
flutter clean
flutter pub get
flutter analyze
```

## Run App

### Android

```bash
flutter run
```

### Windows

```bash
flutter run -d windows
```

### iOS

```bash
flutter run -d ios
```

## Build

### Android APK

```bash
flutter build apk --release
```

### Android App Bundle

```bash
flutter build appbundle --release
```

### Windows

```bash
flutter build windows --release
```

Output:

```text
build/windows/x64/runner/Release/
```

Keep all `.dll` files together with the `.exe`.

### iOS config-only without codesign

```bash
flutter build ios --release --config-only --no-codesign
```

## Mapbox Style Usage

Native Mapbox:

```dart
await mapboxMap.style.setStyleURI(
  MapStyle.satelliteStreets.styleUri,
);
```

Flutter Map fallback:

```dart
TileLayer(
  urlTemplate: MapStyle.satelliteStreets.tileUrlTemplate,
)
```

## 3D Map Usage

```dart
await Mapbox3DService.apply3D(
  mapboxMap: mapboxMap,
  mode: Mapbox3DMode.full3D,
  latitude: current.latitude,
  longitude: current.longitude,
  bearing: heading,
);
```

## App UI System

Use one shared import:

```dart
import '../widgets/common/app_ui.dart';
```

or from nested folders:

```dart
import '../../widgets/common/app_ui.dart';
```

The UI system includes:

- Glass cards
- Action buttons
- Status pills
- Search bar
- Filter chips
- Metric cards
- Section cards
- Timeline slider
- Route preview
- Speed chart
- Empty states

## Troubleshooting

### Mapbox style not changing

Check:

- Mapbox token is valid
- `styleUri` is passed to native Mapbox
- fallback `tileUrlTemplate` uses the token
- app was fully restarted after code changes

### Missing AppGlassCard / AppActionButton in `part of` files

If a file uses:

```dart
part of 'map_screen.dart';
```

then imports must be added to the parent file:

```text
map_screen.dart
```

not the part file.

### CocoaPods multiple post_install hooks

iOS `Podfile` only supports one `post_install` block. Merge all `post_install` code into a single block.

### Windows build missing plugin folder

Run:

```bash
flutter clean
flutter pub get
flutter build windows --release
```

If still failing, delete:

```text
build/
.windows/
```

then run again.

### Weather widget optional parameter warning

If analyzer shows:

```text
A value for optional parameter 'textAlign' isn't ever given
A value for optional parameter 'softWrap' isn't ever given
A value for optional parameter 'overflow' isn't ever given
```

Add at the top of `lib/widgets/weather_widget.dart`:

```dart
// ignore_for_file: unused_element_parameter
```

or remove the unused optional parameters from the private helper widget.

## Recommended Next Updates

- Favorite trips
- Trip comparison
- Route deviation alert
- Offline map/cache screen
- Dashboard screen
- Premium bottom navigation
- Export service integration
- Onboarding persistence
- App settings search improvements

## License

Private project. Add your license here if you plan to publish.
