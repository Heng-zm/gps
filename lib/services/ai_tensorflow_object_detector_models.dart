import 'dart:ui';

class AiTensorflowDetection {
  const AiTensorflowDetection({
    required this.normalizedBox,
    required this.label,
    required this.confidence,
  });

  final Rect normalizedBox;
  final String label;
  final double confidence;

  bool get isUsable {
    return confidence.isFinite &&
        confidence >= 0.35 &&
        normalizedBox.width > 0.02 &&
        normalizedBox.height > 0.02;
  }
}
