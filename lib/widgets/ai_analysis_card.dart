import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/trip_data.dart';
import '../services/ai_service.dart';

// ─── Shared Palette ───────────────────────────────────────────────────────────

class _Gold {
  static const bright = Color(0xFFEDD068);
  static const mid = Color(0xFFD4A843);
  static const dark = Color(0xFF8B6914);
  static const ink = Color(0xFF1A1500);
  static const cardBg = Color(0xFF181710);
  static const surface = Color(0xFF111108);
  static const red = Color(0xFFE8412A);
}

// ─── AiAnalysisCard ───────────────────────────────────────────────────────────

class AiAnalysisCard extends StatefulWidget {
  final TripSummary summary;
  const AiAnalysisCard({super.key, required this.summary});

  @override
  State<AiAnalysisCard> createState() => _AiAnalysisCardState();
}

class _AiAnalysisCardState extends State<AiAnalysisCard>
    with SingleTickerProviderStateMixin {
  String? _analysis;
  bool _loading = false;
  String? _errorMessage;
  String _thinkingStatus = 'Analysing trip data…';
  double _pulseTarget = 1.2;
  Timer? _statusTimer;

  late final AnimationController _shimmerCtrl;

  static const _statuses = [
    'Consulting AI…',
    'Evaluating safety…',
    'Calculating efficiency…',
    'Finalising report…',
  ];

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _startThinkingAnimation() {
    _statusTimer?.cancel();
    int i = 0;
    setState(() => _thinkingStatus = _statuses[0]);
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || !_loading) {
        timer.cancel();
        return;
      }
      setState(() => _thinkingStatus = _statuses[++i % _statuses.length]);
    });
  }

  Future<void> _getAiInsights() async {
    if (_loading) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _loading = true;
      _errorMessage = null;
      _pulseTarget = 1.2;
    });

    _shimmerCtrl.repeat();
    _startThinkingAnimation();

    try {
      final result =
          await AiService.instance.analyzeTrip(widget.summary, weather: null);
      if (mounted) {
        _statusTimer?.cancel();
        _shimmerCtrl.stop();
        setState(() {
          _analysis = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _statusTimer?.cancel();
        _shimmerCtrl.stop();
        setState(() {
          _errorMessage = 'AI connection failed. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: _Gold.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _Gold.dark.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: _Gold.mid.withValues(alpha: 0.07),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              hasAnalysis: _analysis != null,
              isLoading: _loading,
              onRefresh: _getAiInsights,
            ),
            const _GoldDivider(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Padding(
                key: ValueKey('$_loading/$_errorMessage/${_analysis == null}'),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _LoadingBody(
        thinkingStatus: _thinkingStatus,
        pulseTarget: _pulseTarget,
        shimmerCtrl: _shimmerCtrl,
        onPulseEnd: () =>
            setState(() => _pulseTarget = _pulseTarget == 1.2 ? 0.8 : 1.2),
      );
    }
    if (_errorMessage != null) {
      return _ErrorBody(message: _errorMessage!, onRetry: _getAiInsights);
    }
    if (_analysis == null) {
      return _IdleBody(onAnalyze: _getAiInsights);
    }
    return _ResultBody(text: _analysis!);
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final bool hasAnalysis;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _CardHeader({
    required this.hasAnalysis,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [_Gold.bright, _Gold.dark],
                stops: [0.3, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: _Gold.mid.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: _Gold.ink, size: 14),
          ),
          const SizedBox(width: 10),
          const Text(
            'AI ANALYSIS',
            style: TextStyle(
              color: _Gold.bright,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              color: _Gold.dark,
              shape: BoxShape.circle,
            ),
          ),
          const Spacer(),
          if (hasAnalysis && !isLoading)
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _Gold.dark.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _Gold.dark.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: _Gold.dark,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Divider ──────────────────────────────────────────────────────────────────

class _GoldDivider extends StatelessWidget {
  const _GoldDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Colors.transparent,
            _Gold.dark,
            _Gold.mid,
            _Gold.dark,
            Colors.transparent,
          ],
          stops: [0.0, 0.2, 0.5, 0.8, 1.0],
        ).createShader(bounds),
        child: Container(height: 1, color: Colors.white),
      ),
    );
  }
}

// ─── Loading Body ─────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  final String thinkingStatus;
  final double pulseTarget;
  final AnimationController shimmerCtrl;
  final VoidCallback onPulseEnd;

  const _LoadingBody({
    required this.thinkingStatus,
    required this.pulseTarget,
    required this.shimmerCtrl,
    required this.onPulseEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: pulseTarget),
              duration: const Duration(seconds: 1),
              curve: Curves.easeInOut,
              onEnd: onPulseEnd,
              builder: (_, value, __) => Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _Gold.mid.withValues(alpha: 0.15 * value),
                      blurRadius: 20 * value,
                      spreadRadius: 4 * value,
                    ),
                  ],
                ),
                child: const CupertinoActivityIndicator(
                  color: _Gold.mid,
                  radius: 9,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              thinkingStatus,
              style: TextStyle(
                color: _Gold.dark.withValues(alpha: 0.9),
                fontSize: 12,
                letterSpacing: 0.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...[0.92, 0.78, 0.86, 0.55].map(
          (w) => _ShimmerLine(controller: shimmerCtrl, widthFactor: w),
        ),
      ],
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final AnimationController controller;
  final double widthFactor;
  const _ShimmerLine({required this.controller, required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final v = controller.value;
          return FractionallySizedBox(
            widthFactor: widthFactor,
            alignment: Alignment.centerLeft,
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: const [
                  Color(0xFF1E1C10),
                  Color(0xFF3A3418),
                  Color(0xFF1E1C10),
                ],
                stops: [
                  (v - 0.4).clamp(0.0, 1.0),
                  v.clamp(0.0, 1.0),
                  (v + 0.4).clamp(0.0, 1.0),
                ],
              ).createShader(bounds),
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Error Body ───────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: double.infinity),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _Gold.red.withValues(alpha: 0.1),
            border: Border.all(color: _Gold.red.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.wifi_off_rounded, color: _Gold.red, size: 20),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(color: _Gold.red, fontSize: 13, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: _Gold.dark.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Gold.dark.withValues(alpha: 0.5)),
            ),
            child: const Text(
              'TRY AGAIN',
              style: TextStyle(
                color: _Gold.mid,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Idle Body ────────────────────────────────────────────────────────────────

class _IdleBody extends StatelessWidget {
  final VoidCallback onAnalyze;
  const _IdleBody({required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _Gold.dark.withValues(alpha: 0.1),
            border: Border.all(color: _Gold.dark.withValues(alpha: 0.25)),
          ),
          child:
              const Icon(Icons.insights_rounded, color: _Gold.dark, size: 22),
        ),
        Text(
          'Unlock your trip intelligence',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onAnalyze,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_Gold.dark, _Gold.mid, _Gold.dark],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _Gold.mid.withValues(alpha: 0.22),
                  blurRadius: 16,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, color: _Gold.ink, size: 14),
                SizedBox(width: 8),
                Text(
                  'ANALYSE TRIP PERFORMANCE',
                  style: TextStyle(
                    color: _Gold.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Result Body ──────────────────────────────────────────────────────────────

class _ResultBody extends StatelessWidget {
  final String text;
  const _ResultBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Vertical gold accent bar
              Container(
                width: 2,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_Gold.bright, _Gold.dark],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              Expanded(
                child: MarkdownBody(
                  data: text,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      height: 1.65,
                      letterSpacing: 0.2,
                    ),
                    strong: const TextStyle(
                      color: _Gold.bright,
                      fontWeight: FontWeight.w800,
                    ),
                    em: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    listBullet: const TextStyle(color: _Gold.mid),
                    code: TextStyle(
                      color: _Gold.bright,
                      backgroundColor: _Gold.dark.withValues(alpha: 0.15),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: _Gold.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _Gold.dark.withValues(alpha: 0.3),
                      ),
                    ),
                    blockquote: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 16,
              height: 1,
              color: _Gold.dark.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              'AI GENERATED',
              style: TextStyle(
                color: _Gold.dark.withValues(alpha: 0.6),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
