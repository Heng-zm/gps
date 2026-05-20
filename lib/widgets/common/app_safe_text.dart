import 'package:flutter/widgets.dart';

/// Safe text used across dense overlays and web builds.
///
/// Text is wrapped with [IgnorePointer] so it never steals taps from nearby
/// buttons. This also reduces Flutter Web text-fragment hit-test noise.
class AppSafeText extends StatelessWidget {
  const AppSafeText(
    this.data, {
    super.key,
    required this.style,
    this.maxLines = 1,
    this.textAlign,
    this.softWrap = false,
    this.overflow = TextOverflow.ellipsis,
    this.semanticsLabel,
    this.excludeSemantics = false,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextOverflow overflow;
  final String? semanticsLabel;
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final Widget text = IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        textAlign: textAlign,
        softWrap: softWrap,
        overflow: overflow,
        style: style,
      ),
    );

    if (excludeSemantics) return ExcludeSemantics(child: text);
    if (semanticsLabel == null) return text;

    return Semantics(
      label: semanticsLabel,
      child: text,
    );
  }
}
