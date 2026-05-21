import 'package:camera/camera.dart';

import 'ai_tensorflow_object_detector_models.dart';

class AiTensorflowObjectDetector {
  AiTensorflowObjectDetector({
    this.modelAsset = 'assets/models/object_detector.tflite',
    this.labelsAsset = 'assets/models/labels.txt',
  });

  final String modelAsset;
  final String labelsAsset;

  bool get isLoaded => false;
  bool get isSupported => false;

  Future<void> load() async {
    // TensorFlow Lite through tflite_flutter uses dart:ffi and is not available
    // on Flutter Web. This stub keeps web builds working and lets AR fallback
    // auto tracking continue.
  }

  Future<AiTensorflowDetection?> detect(CameraImage image) async {
    return null;
  }

  void dispose() {}
}
