import 'package:flutter/cupertino.dart';

import '../../theme/app_theme.dart';

class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      placeholder: hintText,
      placeholderStyle: const TextStyle(
        color: AppColors.white38,
        fontWeight: FontWeight.w700,
      ),
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      prefix: const Padding(
        padding: EdgeInsets.only(left: 13, right: 7),
        child: Icon(
          CupertinoIcons.search,
          color: AppColors.white54,
          size: 17,
        ),
      ),
      suffix: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, TextEditingValue value, __) {
          if (value.text.isEmpty) return const SizedBox.shrink();

          return CupertinoButton(
            padding: const EdgeInsets.only(right: 10),
            minSize: 0,
            onPressed: () {
              controller.clear();
              onClear?.call();
            },
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: AppColors.white38,
              size: 18,
            ),
          );
        },
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
      ),
    );
  }
}
