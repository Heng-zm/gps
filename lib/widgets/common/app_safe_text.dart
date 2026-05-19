import 'package:flutter/widgets.dart';

/// Safe one-line text used across the app.
///
/// Uses [IgnorePointer] so text fragments do not participate in hit testing.
/// This helps avoid Flutter Web text-fragment hit-test issues in dense overlays.
class AppSafeText extends StatelessWidget {
  const AppSafeText(
    this.data, {
    super.key,
    required this.style,
    this.maxLines = 1,
    this.textAlign,
    this.softWrap = false,
    this.overflow = TextOverflow.clip,
    this.semanticsLabel,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextOverflow overflow;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: IgnorePointer(
        child: Text(
          data,
          maxLines: maxLines,
          textAlign: textAlign,
          softWrap: softWrap,
          overflow: overflow,
          style: style,
        ),
      ),
    );
  }
}
