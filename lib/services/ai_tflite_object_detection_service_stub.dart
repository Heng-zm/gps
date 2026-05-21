import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_detection_models.dart';

class AiTfliteObjectDetectionService {
  AiTfliteObjectDetectionService({
    this.modelAsset = 'assets/models/coco_ssd_mobilenet.tflite',
    this.labelsAsset = 'assets/models/coco_labels.txt',
    this.minConfidence = 0.35,
    this.maxDetections = 3,
  });

  final String modelAsset;
  final String labelsAsset;
  final double minConfidence;
  final int maxDetections;

  final ValueNotifier<AiDetectionResult> resultN =
      ValueNotifier<AiDetectionResult>(AiDetectionResult.empty());

  bool get isLoaded => false;
  bool get isSupported => false;

  Future<void> load() async {
    resultN.value = AiDetectionResult.empty(modelReady: false);
  }

  Future<AiDetectionResult> detect(CameraImage image) async {
    return resultN.value;
  }

  void dispose() {
    resultN.dispose();
  }
}
