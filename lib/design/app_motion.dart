import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'app_tokens.dart';

bool _reduceMotion(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

class AppFadeSlide extends StatelessWidget {
  const AppFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.05),
    this.duration = AppDurations.normal,
    this.curve = AppCurves.standard,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;
  final Curve curve;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = _reduceMotion(context);

    if (!enabled || reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: delay + duration,
      curve: Curves.linear,
      builder: (BuildContext context, double value, Widget? animatedChild) {
        final double delayMs = delay.inMilliseconds.toDouble();
        final double durationMs = duration.inMilliseconds.toDouble();
        final double totalMs = delayMs + durationMs;

        final double rawT = totalMs <= 0 || durationMs <= 0
            ? 1.0
            : ((value * totalMs - delayMs) / durationMs).clamp(0.0, 1.0);

        final double t = curve.transform(rawT);

        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(
              offset.dx * (1 - t) * 80,
              offset.dy * (1 - t) * 80,
            ),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class AppFadeScale extends StatelessWidget {
  const AppFadeScale({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppDurations.normal,
    this.beginScale = 0.96,
    this.curve = AppCurves.standard,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double beginScale;
  final Curve curve;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = _reduceMotion(context);

    if (!enabled || reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: delay + duration,
      curve: Curves.linear,
      builder: (BuildContext context, double value, Widget? animatedChild) {
        final double delayMs = delay.inMilliseconds.toDouble();
        final double durationMs = duration.inMilliseconds.toDouble();
        final double totalMs = delayMs + durationMs;

        final double rawT = totalMs <= 0 || durationMs <= 0
            ? 1.0
            : ((value * totalMs - delayMs) / durationMs).clamp(0.0, 1.0);

        final double t = curve.transform(rawT);
        final double safeBeginScale = beginScale.clamp(0.0, 1.0);
        final double scale = safeBeginScale + ((1 - safeBeginScale) * t);

        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: scale,
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class AppStaggeredFadeSlide extends StatelessWidget {
  const AppStaggeredFadeSlide({
    super.key,
    required this.children,
    this.delayStep = const Duration(milliseconds: 55),
    this.offset = const Offset(0, 0.04),
    this.duration = AppDurations.normal,
    this.separator,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final Duration delayStep;
  final Offset offset;
  final Duration duration;
  final Widget? separator;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final List<Widget> animatedChildren = <Widget>[];

    for (int i = 0; i < children.length; i++) {
      if (i > 0 && separator != null) {
        animatedChildren.add(separator!);
      }

      animatedChildren.add(
        AppFadeSlide(
          delay: delayStep * i,
          offset: offset,
          duration: duration,
          child: children[i],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: animatedChildren,
    );
  }
}

class AppPressableScale extends StatefulWidget {
  const AppPressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.enabled = true,
    this.enableHaptic = true,
    this.behavior = HitTestBehavior.opaque,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool enabled;
  final bool enableHaptic;
  final HitTestBehavior behavior;
  final String? semanticLabel;

  @override
  State<AppPressableScale> createState() => _AppPressableScaleState();
}

class _AppPressableScaleState extends State<AppPressableScale> {
  bool _pressed = false;
  bool _tapLocked = false;
  Timer? _unlockTimer;

  bool get _enabled {
    return widget.enabled &&
        (widget.onTap != null || widget.onLongPress != null);
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (!_enabled || _tapLocked) return;

    _tapLocked = true;
    _unlockTimer?.cancel();
    _unlockTimer = Timer(AppDurations.fast, () {
      _tapLocked = false;
    });

    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }

    widget.onTap?.call();
  }

  void _handleLongPress() {
    if (!_enabled) return;

    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }

    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = _reduceMotion(context);
    final double safeScale = widget.scale.clamp(0.85, 1.0);

    Widget current = GestureDetector(
      behavior: widget.behavior,
      onTap: _enabled ? _handleTap : null,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : AppDurations.fast,
        curve: AppCurves.standard,
        scale: _pressed ? safeScale : 1,
        child: AnimatedOpacity(
          duration: reduceMotion ? Duration.zero : AppDurations.fast,
          curve: AppCurves.standard,
          opacity: _enabled ? 1 : 0.45,
          child: widget.child,
        ),
      ),
    );

    if (widget.semanticLabel != null &&
        widget.semanticLabel!.trim().isNotEmpty) {
      current = Semantics(
        button: true,
        enabled: _enabled,
        label: widget.semanticLabel,
        child: current,
      );
    }

    return current;
  }
}

class AppAnimatedSwitcher extends StatelessWidget {
  const AppAnimatedSwitcher({
    super.key,
    required this.child,
    this.duration = AppDurations.normal,
    this.reverseDuration = AppDurations.fast,
  });

  final Widget child;
  final Duration duration;
  final Duration reverseDuration;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = _reduceMotion(context);

    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      reverseDuration: reduceMotion ? Duration.zero : reverseDuration,
      switchInCurve: AppCurves.standard,
      switchOutCurve: AppCurves.emphasized,
      transitionBuilder: (Widget child, Animation<double> animation) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: AppCurves.standard,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.98,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class AppRouteTransitions {
  const AppRouteTransitions._();

  static PageRoute<T> cupertino<T>(Widget page) {
    return CupertinoPageRoute<T>(
      builder: (_) => page,
    );
  }

  static PageRoute<T> fadeSlide<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: AppDurations.normal,
      reverseTransitionDuration: AppDurations.fast,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final bool reduceMotion = _reduceMotion(context);

        if (reduceMotion) return child;

        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: AppCurves.standard,
          reverseCurve: AppCurves.emphasized,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static PageRoute<T> fadeScale<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: AppDurations.normal,
      reverseTransitionDuration: AppDurations.fast,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final bool reduceMotion = _reduceMotion(context);

        if (reduceMotion) return child;

        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: AppCurves.standard,
          reverseCurve: AppCurves.emphasized,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.985,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

extension AppDurationMultiplier on Duration {
  Duration operator *(int factor) {
    return Duration(milliseconds: inMilliseconds * factor);
  }
}
