# GPS Tracking

A Flutter GPS tracking app created with FlutLab.

## Overview

GPS Tracking is a Flutter application for recording, viewing, and replaying trips. The project includes tracking screens, history/replay UI, map controls, AR camera guidance, and AI-assisted tracking features.

## Main Features

- Real-time GPS tracking
- Speed, distance, and route monitoring
- Trip history and replay
- Map view and map style controls
- AR camera tracking UI
- Street AR and markerless scan guidance
- AI object tracking support
- Road condition and motion stability feedback
- Battery, GPS accuracy, and status HUD indicators
- Flutter Web-safe fallback support for unsupported native features

## Project Structure

```text
lib/
  screens/
    tracking/
      tracking_screen.dart
      tracking_ar_camera_screen.dart
      tracking_top_hud.dart
      tracking_bottom_dock.dart
      tracking_map_layer.dart
      tracking_models.dart
  services/
    ai_object_tracking_service.dart
    ai_road_condition_service.dart
    ai_scene_understanding_service.dart
    ai_tracking_brain_service.dart
    ai_tflite_object_detection_service.dart
  models/
  theme/
assets/
  models/
```

## Requirements

- Flutter SDK
- Dart SDK
- FlutLab or another Flutter IDE
- Android/iOS device or emulator for camera and GPS features
- Mapbox token if your map features use Mapbox
- TFLite model file if object detection is enabled

## Recommended Pubspec Assets

If using AI object detection, add your model assets:

```yaml
flutter:
  assets:
    - assets/models/coco_ssd_mobilenet.tflite
    - assets/models/coco_labels.txt
```

If using TFLite, add:

```yaml
dependencies:
  tflite_flutter: ^0.12.1
```

## Getting Started

Clone or open the project in FlutLab, then run:

```bash
flutter pub get
flutter analyze
flutter run
```

For a clean rebuild:

```bash
flutter clean
flutter pub get
flutter run
```

## FlutLab

This project was created with FlutLab.

Helpful links:

- FlutLab: https://flutlab.io
- FlutLab Docs: https://flutlab.io/docs
- Flutter Documentation: https://flutter.dev/docs
- Flutter Cookbook: https://flutter.dev/docs/cookbook

## Notes

Some features require real device hardware:

- GPS tracking
- Camera preview
- AR camera overlay
- Motion sensor / accelerometer
- Torch / flashlight
- TFLite object detection

Flutter Web may use fallback behavior for camera, TensorFlow Lite, and platform-specific features.

## License

Add your project license here.
