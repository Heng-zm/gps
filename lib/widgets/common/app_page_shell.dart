import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppPageShell extends StatelessWidget {
  const AppPageShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 24),
    this.showBackButton = false,
    this.onBack,
    this.resizeToAvoidBottomInset = true,
    this.scrollable = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showBackButton;
  final VoidCallback? onBack;
  final bool resizeToAvoidBottomInset;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);

    Widget bodyChild = Padding(
      padding: padding,
      child: child,
    );

    if (scrollable) {
      bodyChild = SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: media.padding.bottom + 8),
        child: bodyChild,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: _AppPageBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _AppPageHeader(
                  title: title,
                  subtitle: subtitle,
                  leading: leading,
                  trailing: trailing,
                  showBackButton: showBackButton,
                  onBack: onBack ?? () => Navigator.of(context).maybePop(),
                ),
                Expanded(child: bodyChild),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppPageBackground extends StatelessWidget {
  const _AppPageBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.72, -0.92),
          radius: 1.25,
          colors: <Color>[
            AppColors.blue.withValues(alpha: 0.18),
            AppColors.surface,
            AppColors.black,
          ],
          stops: const <double>[0.0, 0.44, 1.0],
        ),
      ),
    );
  }
}

class _AppPageHeader extends StatelessWidget {
  const _AppPageHeader({
    required this.title,
    required this.showBackButton,
    required this.onBack,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool showBackButton;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final Widget? resolvedLeading = leading ??
        (showBackButton
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 44,
                pressedOpacity: 0.78,
                onPressed: onBack,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.chevron_back,
                    color: AppColors.white,
                    size: 18,
                  ),
                ),
              )
            : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (resolvedLeading != null) ...<Widget>[
                    resolvedLeading,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 12),
                    Flexible(
                      flex: 0,
                      child: trailing!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
