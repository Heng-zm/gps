import 'package:flutter/widgets.dart';

class AppSafeText extends StatelessWidget {
  const AppSafeText(
    this.data, {
    super.key,
    required this.style,
    this.maxLines = 1,
    this.textAlign,
    this.softWrap = false,
    this.overflow = TextOverflow.ellipsis,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      maxLines: maxLines,
      textAlign: textAlign,
      softWrap: softWrap,
      overflow: overflow,
      style: style,
    );
  }
}
