import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SPEEDOMETER WIDGET — Micro Number HUD Edition
//
// UX/UI + performance update:
// - Smaller default compact size for bottom-right corner HUD.
// - Stateless and painter-free.
// - Smooth number animation.
// - Safer speed clamping.
// - Lower visual weight so it does not cover the map.
// - Keeps constructor compatibility with existing tracking_screen.dart.
// ═══════════════════════════════════════════════════════════════════════════════

class SpeedometerWidget extends StatelessWidget {
  const SpeedometerWidget({
    super.key,
    required this.speedMph,
    this.isOverLimit = false,
    this.compact = true,
    this.showUnit = true,
    this.showOverLimitBadge = true,
  });

  final double speedMph;
  final bool isOverLimit;
  final bool compact;
  final bool showUnit;
  final bool showOverLimitBadge;

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;

    final double displaySpeed = settings
        .toDisplaySpeed(_safeSpeed(speedMph))
        .clamp(0.0, 999.0)
        .toDouble();

    final String unitLabel = settings.speedUnit.toUpperCase();
    final int semanticSpeed = displaySpeed.round();
    final _SpeedometerSize size = _SpeedometerSize.from(compact: compact);

    return Semantics(
      label: 'Speed $semanticSpeed $unitLabel',
      value: semanticSpeed.toString(),
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: displaySpeed),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (_, double animatedSpeed, __) {
            return _SpeedReadout(
              speed: animatedSpeed,
              unitLabel: unitLabel,
              isOverLimit: isOverLimit,
              showUnit: showUnit,
              showOverLimitBadge: showOverLimitBadge,
              size: size,
            );
          },
        ),
      ),
    );
  }

  static double _safeSpeed(double value) {
    if (!value.isFinite || value <= 0.0) return 0.0;
    return value;
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({
    required this.speed,
    required this.unitLabel,
    required this.isOverLimit,
    required this.showUnit,
    required this.showOverLimitBadge,
    required this.size,
  });

  final double speed;
  final String unitLabel;
  final bool isOverLimit;
  final bool showUnit;
  final bool showOverLimitBadge;
  final _SpeedometerSize size;

  @override
  Widget build(BuildContext context) {
    final int roundedSpeed = speed.round().clamp(0, 999).toInt();
    final Color numberColor =
        isOverLimit ? const Color(0xFFFF453A) : Colors.white;
    final Color unitColor = isOverLimit
        ? const Color(0xFFFFA197)
        : Colors.white.withValues(alpha: 0.62);

    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: size.minWidth,
            maxWidth: size.maxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                roundedSpeed.toString(),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: numberColor,
                  fontSize: size.numberFontSize,
                  fontWeight: FontWeight.w800,
                  height: 0.84,
                  letterSpacing: size.numberLetterSpacing,
                  shadows: <Shadow>[
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.34),
                      blurRadius: 9,
                      offset: const Offset(0, 3),
                    ),
                    if (isOverLimit)
                      Shadow(
                        color: const Color(0xFFFF453A).withValues(alpha: 0.38),
                        blurRadius: 14,
                      ),
                  ],
                  fontFeatures: const <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (showUnit) ...<Widget>[
                SizedBox(height: size.unitGap),
                Text(
                  unitLabel,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: unitColor,
                    fontSize: size.unitFontSize,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: size.unitLetterSpacing,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
              if (isOverLimit && showOverLimitBadge) ...<Widget>[
                SizedBox(height: size.badgeGap),
                const _OverLimitBadge(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverLimitBadge extends StatelessWidget {
  const _OverLimitBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFF453A).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFF453A).withValues(alpha: 0.26),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          'OVER',
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            color: Color(0xFFFFA197),
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _SpeedometerSize {
  const _SpeedometerSize({
    required this.numberFontSize,
    required this.numberLetterSpacing,
    required this.unitFontSize,
    required this.unitLetterSpacing,
    required this.unitGap,
    required this.badgeGap,
    required this.minWidth,
    required this.maxWidth,
  });

  final double numberFontSize;
  final double numberLetterSpacing;
  final double unitFontSize;
  final double unitLetterSpacing;
  final double unitGap;
  final double badgeGap;
  final double minWidth;
  final double maxWidth;

  factory _SpeedometerSize.from({
    required bool compact,
  }) {
    if (compact) {
      return const _SpeedometerSize(
        numberFontSize: 42.0,
        numberLetterSpacing: -1.35,
        unitFontSize: 8.0,
        unitLetterSpacing: 1.7,
        unitGap: 3.0,
        badgeGap: 5.0,
        minWidth: 50.0,
        maxWidth: 88.0,
      );
    }

    return const _SpeedometerSize(
      numberFontSize: 58.0,
      numberLetterSpacing: -2.0,
      unitFontSize: 9.5,
      unitLetterSpacing: 2.1,
      unitGap: 4.0,
      badgeGap: 6.0,
      minWidth: 68.0,
      maxWidth: 118.0,
    );
  }
}
