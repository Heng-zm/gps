import 'package:flutter/cupertino.dart';

import 'app_tokens.dart';

class AppFadeSlide extends StatelessWidget {
  const AppFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.05),
    this.duration = AppDurations.normal,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: delay + duration,
      curve: AppCurves.standard,
      builder: (BuildContext context, double value, Widget? child) {
        final double t = delay == Duration.zero
            ? value
            : ((value - 0.25).clamp(0.0, 1.0));

        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(offset.dx * (1 - t) * 80, offset.dy * (1 - t) * 80),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class AppPressableScale extends StatefulWidget {
  const AppPressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<AppPressableScale> createState() => _AppPressableScaleState();
}

class _AppPressableScaleState extends State<AppPressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      child: AnimatedScale(
        duration: AppDurations.fast,
        curve: AppCurves.standard,
        scale: _pressed ? widget.scale : 1,
        child: widget.child,
      ),
    );
  }
}

class AppRouteTransitions {
  const AppRouteTransitions._();

  static PageRoute<T> cupertino<T>(Widget page) {
    return CupertinoPageRoute<T>(builder: (_) => page);
  }

  static PageRoute<T> fadeSlide<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: AppDurations.normal,
      reverseTransitionDuration: AppDurations.fast,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, Animation<double> animation, __, Widget child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: AppCurves.standard,
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
}
