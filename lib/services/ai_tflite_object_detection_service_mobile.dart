import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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

  Interpreter? _interpreter;
  List<String> _labels = const <String>[];
  bool _loading = false;
  bool _busy = false;

  bool get isLoaded => _interpreter != null;
  bool get isSupported => true;

  Future<void> load() async {
    if (_loading || _interpreter != null) return;
    _loading = true;

    try {
      final ByteData rawAsset = await rootBundle.load(modelAsset);
      if (rawAsset.lengthInBytes < 1024) {
        debugPrint(
          '[AiTfliteObjectDetectionService] Model asset $modelAsset is empty or placeholder '
          '(${rawAsset.lengthInBytes} bytes). Using vision heuristic engine.',
        );
        _interpreter = null;
        resultN.value = AiDetectionResult.empty(modelReady: false);
        return;
      }

      final InterpreterOptions options = InterpreterOptions()..threads = 2;
      _interpreter = Interpreter.fromBuffer(
        rawAsset.buffer.asUint8List(rawAsset.offsetInBytes, rawAsset.lengthInBytes),
        options: options,
      );

      try {
        final String rawLabels = await rootBundle.loadString(labelsAsset);
        _labels = rawLabels
            .split(RegExp(r'\r?\n'))
            .map((String value) => value.trim())
            .where((String value) => value.isNotEmpty)
            .toList(growable: false);
      } catch (_) {
        _labels = _defaultCocoLabels;
      }

      resultN.value = AiDetectionResult.empty(modelReady: true);
    } catch (error) {
      debugPrint('[AiTfliteObjectDetectionService] Model init deferred: $error');
      _interpreter = null;
      resultN.value = AiDetectionResult.empty(modelReady: false);
    } finally {
      _loading = false;
    }
  }

  Uint8List? _reusableUint8Buffer;
  Float32List? _reusableFloat32Buffer;

  final List<List<List<double>>> _boxesOutput =
      List<List<List<double>>>.generate(1, (_) {
    return List<List<double>>.generate(
      10,
      (_) => List<double>.filled(4, 0.0),
    );
  });
  final List<List<double>> _classesOutput =
      List<List<double>>.generate(1, (_) => List<double>.filled(10, 0.0));
  final List<List<double>> _scoresOutput =
      List<List<double>>.generate(1, (_) => List<double>.filled(10, 0.0));
  final List<double> _countOutput = List<double>.filled(1, 0.0);

  Future<AiDetectionResult> detect(CameraImage image) async {
    final Interpreter? interpreter = _interpreter;
    if (interpreter == null || _busy) return resultN.value;

    _busy = true;
    try {
      final Tensor inputTensor = interpreter.getInputTensor(0);
      final List<int> inputShape = inputTensor.shape;
      final TensorType inputType = inputTensor.type;
      final int inputHeight = inputShape.length >= 3 ? inputShape[1] : 300;
      final int inputWidth = inputShape.length >= 3 ? inputShape[2] : 300;

      final Object input = _buildCameraTensorInput(
        image: image,
        targetWidth: inputWidth,
        targetHeight: inputHeight,
        tensorType: inputType,
      );

      for (int i = 0; i < 10; i++) {
        _boxesOutput[0][i].fillRange(0, 4, 0.0);
        _classesOutput[0][i] = 0.0;
        _scoresOutput[0][i] = 0.0;
      }
      _countOutput[0] = 0.0;

      interpreter.runForMultipleInputs(
        <Object>[input],
        <int, Object>{
          0: _boxesOutput,
          1: _classesOutput,
          2: _scoresOutput,
          3: _countOutput,
        },
      );

      final List<AiDetection> detections = _parseSsdOutputs(
        boxes: _boxesOutput,
        classes: _classesOutput,
        scores: _scoresOutput,
        count: _countOutput,
      );

      final AiDetectionResult result = AiDetectionResult(
        detections: detections,
        timestamp: DateTime.now(),
        modelReady: true,
      );

      resultN.value = result;
      return result;
    } catch (_) {
      return resultN.value;
    } finally {
      _busy = false;
    }
  }

  List<AiDetection> _parseSsdOutputs({
    required List<List<List<double>>> boxes,
    required List<List<double>> classes,
    required List<List<double>> scores,
    required List<double> count,
  }) {
    final int total = math.min(10, count.first.round().clamp(0, 10));
    final List<AiDetection> detections = <AiDetection>[];

    for (int i = 0; i < total; i++) {
      final double score = scores[0][i];
      if (!score.isFinite || score < minConfidence) continue;

      final int classIndex = classes[0][i].round();
      final String label = _labelForIndex(classIndex);
      final AiDetectedType type = aiDetectedTypeFromCocoLabel(label);

      // Keep only the requested COCO-first classes plus surface aliases.
      if (!_isAllowedType(type)) continue;

      final List<double> box = boxes[0][i];
      if (box.length < 4) continue;

      final double ymin = box[0].clamp(0.0, 1.0).toDouble();
      final double xmin = box[1].clamp(0.0, 1.0).toDouble();
      final double ymax = box[2].clamp(0.0, 1.0).toDouble();
      final double xmax = box[3].clamp(0.0, 1.0).toDouble();

      final Rect rect = Rect.fromLTRB(xmin, ymin, xmax, ymax);
      final AiDetection detection = AiDetection(
        type: type,
        label: type == AiDetectedType.unknown ? label : type.label,
        confidence: score,
        box: rect,
      );

      if (detection.isUsable) detections.add(detection);
    }

    detections.sort((AiDetection a, AiDetection b) {
      final double aScore = a.confidence + (a.isObstacle ? 0.18 : 0.0);
      final double bScore = b.confidence + (b.isObstacle ? 0.18 : 0.0);
      return bScore.compareTo(aScore);
    });

    return detections.take(maxDetections).toList(growable: false);
  }

  bool _isAllowedType(AiDetectedType type) {
    switch (type) {
      case AiDetectedType.person:
      case AiDetectedType.car:
      case AiDetectedType.motorcycle:
      case AiDetectedType.bicycle:
      case AiDetectedType.bus:
      case AiDetectedType.truck:
      case AiDetectedType.trafficLight:
      case AiDetectedType.stopSign:
      case AiDetectedType.chair:
      case AiDetectedType.obstacle:
      case AiDetectedType.floor:
      case AiDetectedType.road:
      case AiDetectedType.wall:
        return true;
      case AiDetectedType.unknown:
        return false;
    }
  }

  String _labelForIndex(int classIndex) {
    if (_labels.isEmpty) return 'Object';

    // Some COCO SSD models output 1-based class ids, others 0-based.
    if (classIndex >= 0 && classIndex < _labels.length) {
      return _labels[classIndex];
    }
    final int zeroBased = classIndex - 1;
    if (zeroBased >= 0 && zeroBased < _labels.length) {
      return _labels[zeroBased];
    }

    return 'Object';
  }

  Object _buildCameraTensorInput({
    required CameraImage image,
    required int targetWidth,
    required int targetHeight,
    required TensorType tensorType,
  }) {
    final int totalPixels = targetWidth * targetHeight;
    final int totalValues = totalPixels * 3;
    final bool isFloat = tensorType == TensorType.float32;

    Uint8List? u8Buf;
    Float32List? f32Buf;

    if (isFloat) {
      if (_reusableFloat32Buffer == null ||
          _reusableFloat32Buffer!.length != totalValues) {
        _reusableFloat32Buffer = Float32List(totalValues);
      }
      f32Buf = _reusableFloat32Buffer;
    } else {
      if (_reusableUint8Buffer == null ||
          _reusableUint8Buffer!.length != totalValues) {
        _reusableUint8Buffer = Uint8List(totalValues);
      }
      u8Buf = _reusableUint8Buffer;
    }

    final int srcWidth = image.width;
    final int srcHeight = image.height;
    final bool isBgra =
        image.planes.length == 1 && image.planes[0].bytesPerPixel == 4;
    final bool isYuv = image.planes.length >= 3;

    int destIdx = 0;

    if (isBgra) {
      final Plane plane = image.planes[0];
      final Uint8List bytes = plane.bytes;
      final int rowStride = plane.bytesPerRow;

      for (int y = 0; y < targetHeight; y++) {
        final int srcY = (y * srcHeight) ~/ targetHeight;
        final int rowOffset = srcY * rowStride;

        for (int x = 0; x < targetWidth; x++) {
          final int srcX = (x * srcWidth) ~/ targetWidth;
          final int pixelOffset = rowOffset + (srcX * 4);

          if (pixelOffset + 2 < bytes.length) {
            final int b = bytes[pixelOffset];
            final int g = bytes[pixelOffset + 1];
            final int r = bytes[pixelOffset + 2];

            if (isFloat) {
              f32Buf![destIdx++] = r / 255.0;
              f32Buf[destIdx++] = g / 255.0;
              f32Buf[destIdx++] = b / 255.0;
            } else {
              u8Buf![destIdx++] = r;
              u8Buf[destIdx++] = g;
              u8Buf[destIdx++] = b;
            }
          } else {
            if (isFloat) {
              f32Buf![destIdx++] = 0.0;
              f32Buf[destIdx++] = 0.0;
              f32Buf[destIdx++] = 0.0;
            } else {
              u8Buf![destIdx++] = 0;
              u8Buf[destIdx++] = 0;
              u8Buf[destIdx++] = 0;
            }
          }
        }
      }
    } else if (isYuv) {
      final Plane yPlane = image.planes[0];
      final Plane uPlane = image.planes[1];
      final Plane vPlane = image.planes[2];

      final Uint8List yBytes = yPlane.bytes;
      final Uint8List uBytes = uPlane.bytes;
      final Uint8List vBytes = vPlane.bytes;

      final int yRowStride = yPlane.bytesPerRow;
      final int uvRowStride = uPlane.bytesPerRow;
      final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int y = 0; y < targetHeight; y++) {
        final int srcY = (y * srcHeight) ~/ targetHeight;
        final int yRowOffset = srcY * yRowStride;
        final int uvRowOffset = (srcY >> 1) * uvRowStride;

        for (int x = 0; x < targetWidth; x++) {
          final int srcX = (x * srcWidth) ~/ targetWidth;
          final int yOffset = yRowOffset + srcX;
          final int uvOffset = uvRowOffset + ((srcX >> 1) * uvPixelStride);

          if (yOffset < yBytes.length &&
              uvOffset < uBytes.length &&
              uvOffset < vBytes.length) {
            final int yVal = yBytes[yOffset];
            final int uVal = uBytes[uvOffset] - 128;
            final int vVal = vBytes[uvOffset] - 128;

            final int r = (yVal + (1.402 * vVal)).round().clamp(0, 255);
            final int g =
                (yVal - (0.344136 * uVal) - (0.714136 * vVal)).round().clamp(0, 255);
            final int b = (yVal + (1.772 * uVal)).round().clamp(0, 255);

            if (isFloat) {
              f32Buf![destIdx++] = r / 255.0;
              f32Buf[destIdx++] = g / 255.0;
              f32Buf[destIdx++] = b / 255.0;
            } else {
              u8Buf![destIdx++] = r;
              u8Buf[destIdx++] = g;
              u8Buf[destIdx++] = b;
            }
          } else {
            if (isFloat) {
              f32Buf![destIdx++] = 0.0;
              f32Buf[destIdx++] = 0.0;
              f32Buf[destIdx++] = 0.0;
            } else {
              u8Buf![destIdx++] = 0;
              u8Buf[destIdx++] = 0;
              u8Buf[destIdx++] = 0;
            }
          }
        }
      }
    } else {
      final Plane plane = image.planes[0];
      final Uint8List bytes = plane.bytes;
      final int rowStride = plane.bytesPerRow;

      for (int y = 0; y < targetHeight; y++) {
        final int srcY = (y * srcHeight) ~/ targetHeight;
        final int rowOffset = srcY * rowStride;

        for (int x = 0; x < targetWidth; x++) {
          final int srcX = (x * srcWidth) ~/ targetWidth;
          final int pixelOffset = rowOffset + srcX;

          final int val = pixelOffset < bytes.length ? bytes[pixelOffset] : 0;
          if (isFloat) {
            final double normalized = val / 255.0;
            f32Buf![destIdx++] = normalized;
            f32Buf[destIdx++] = normalized;
            f32Buf[destIdx++] = normalized;
          } else {
            u8Buf![destIdx++] = val;
            u8Buf[destIdx++] = val;
            u8Buf[destIdx++] = val;
          }
        }
      }
    }

    return isFloat ? f32Buf!.buffer : u8Buf!;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _reusableUint8Buffer = null;
    _reusableFloat32Buffer = null;
    resultN.dispose();
  }
}

const List<String> _defaultCocoLabels = <String>[
  'person',
  'bicycle',
  'car',
  'motorcycle',
  'airplane',
  'bus',
  'train',
  'truck',
  'boat',
  'traffic light',
  'fire hydrant',
  'stop sign',
  'parking meter',
  'bench',
  'bird',
  'cat',
  'dog',
  'horse',
  'sheep',
  'cow',
  'elephant',
  'bear',
  'zebra',
  'giraffe',
  'backpack',
  'umbrella',
  'handbag',
  'tie',
  'suitcase',
  'frisbee',
  'skis',
  'snowboard',
  'sports ball',
  'kite',
  'baseball bat',
  'baseball glove',
  'skateboard',
  'surfboard',
  'tennis racket',
  'bottle',
  'wine glass',
  'cup',
  'fork',
  'knife',
  'spoon',
  'bowl',
  'banana',
  'apple',
  'sandwich',
  'orange',
  'broccoli',
  'carrot',
  'hot dog',
  'pizza',
  'donut',
  'cake',
  'chair',
];
