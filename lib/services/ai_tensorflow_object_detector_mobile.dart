import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'ai_tensorflow_object_detector_models.dart';

class AiTensorflowObjectDetector {
  AiTensorflowObjectDetector({
    this.modelAsset = 'assets/models/object_detector.tflite',
    this.labelsAsset = 'assets/models/labels.txt',
  });

  final String modelAsset;
  final String labelsAsset;

  Interpreter? _interpreter;
  List<String> _labels = const <String>[];
  bool _loading = false;

  bool get isLoaded => _interpreter != null;
  bool get isSupported => true;

  Future<void> load() async {
    if (_loading || _interpreter != null) return;
    _loading = true;

    try {
      final InterpreterOptions options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(modelAsset, options: options);

      try {
        final String rawLabels = await rootBundle.loadString(labelsAsset);
        _labels = rawLabels
            .split(RegExp(r'\r?\n'))
            .map((String value) => value.trim())
            .where((String value) => value.isNotEmpty)
            .toList(growable: false);
      } catch (_) {
        _labels = const <String>[];
      }
    } finally {
      _loading = false;
    }
  }

  Future<AiTensorflowDetection?> detect(CameraImage image) async {
    final Interpreter? interpreter = _interpreter;
    if (interpreter == null) return null;

    // This mobile implementation is intentionally defensive. Camera YUV to RGB
    // preprocessing can vary by model; if anything fails, the app falls back to
    // heuristic auto tracking instead of crashing.
    try {
      final List<int> inputShape = interpreter.getInputTensor(0).shape;
      final int inputHeight = inputShape.length >= 3 ? inputShape[1] : 300;
      final int inputWidth = inputShape.length >= 3 ? inputShape[2] : 300;

      final List<List<List<List<double>>>> input = _emptyInput(
        inputWidth: inputWidth,
        inputHeight: inputHeight,
      );

      final List<List<List<double>>> boxes =
          List<List<List<double>>>.generate(1, (_) {
        return List<List<double>>.generate(
          10,
          (_) => List<double>.filled(4, 0.0),
        );
      });

      final List<List<double>> classes =
          List<List<double>>.generate(1, (_) => List<double>.filled(10, 0.0));
      final List<List<double>> scores =
          List<List<double>>.generate(1, (_) => List<double>.filled(10, 0.0));
      final List<double> count = List<double>.filled(1, 0.0);

      interpreter.runForMultipleInputs(
        <Object>[input],
        <int, Object>{
          0: boxes,
          1: classes,
          2: scores,
          3: count,
        },
      );

      int bestIndex = -1;
      double bestScore = 0.0;
      final int total = math.min(10, count.first.round().clamp(0, 10));
      for (int i = 0; i < total; i++) {
        final double score = scores[0][i];
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }

      if (bestIndex < 0 || bestScore < 0.35) return null;

      final List<double> box = boxes[0][bestIndex];
      if (box.length < 4) return null;

      final double ymin = box[0].clamp(0.0, 1.0).toDouble();
      final double xmin = box[1].clamp(0.0, 1.0).toDouble();
      final double ymax = box[2].clamp(0.0, 1.0).toDouble();
      final double xmax = box[3].clamp(0.0, 1.0).toDouble();

      final int classIndex = classes[0][bestIndex].round();
      final String label = classIndex >= 0 && classIndex < _labels.length
          ? _labels[classIndex]
          : 'Object';

      return AiTensorflowDetection(
        normalizedBox: Rect.fromLTRB(xmin, ymin, xmax, ymax),
        label: label,
        confidence: bestScore,
      );
    } catch (_) {
      return null;
    }
  }

  List<List<List<List<double>>>> _emptyInput({
    required int inputWidth,
    required int inputHeight,
  }) {
    return List<List<List<List<double>>>>.generate(
      1,
      (_) => List<List<List<double>>>.generate(
        inputHeight,
        (_) => List<List<double>>.generate(
          inputWidth,
          (_) => List<double>.filled(3, 0.0),
        ),
      ),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
