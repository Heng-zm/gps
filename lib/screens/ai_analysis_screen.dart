import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/trip_data.dart';
import '../services/ai_service.dart';

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
  late final AnimationController _shimmerController;

  // ── Gold palette (matches SpeedometerWidget) ──────────────────────────────
  static const Color _goldMid = Color(0xFFD4A843);
  static const Color _goldDark = Color(0xFF8B6914);
  static const Color _cardBg = Color(0xFF181710);

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _getAiInsights() async {
    setState(() => _loading = true);
    try {
      final result = await AiService.instance.analyzeTrip(widget.summary);
      if (mounted) {
        setState(() {
          _analysis = result;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _analysis = 'Analysis unavailable. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _goldDark.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: _goldMid.withValues(alpha: 0.06),
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
            _Header(
              hasAnalysis: _analysis != null,
              isLoading: _loading,
              onRefresh: _getAiInsights,
            ),
            _Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: _Body(
                loading: _loading,
                analysis: _analysis,
                shimmerController: _shimmerController,
                onAnalyze: _getAiInsights,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool hasAnalysis;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _Header({
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
          // Gold AI icon badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFEDD068), Color(0xFF8B6914)],
                stops: [0.3, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A843).withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF1A1500),
              size: 14,
            ),
          ),
          const SizedBox(width: 10),

          // Title
          const Text(
            'AI ANALYSIS',
            style: TextStyle(
              color: Color(0xFFEDD068),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 3,
            ),
          ),

          // Decorative dot
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF8B6914),
              shape: BoxShape.circle,
            ),
          ),

          const Spacer(),

          // Refresh button
          if (hasAnalysis && !isLoading)
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B6914).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF8B6914).withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF8B6914),
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Gold hairline divider ────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Colors.transparent,
            Color(0xFF8B6914),
            Color(0xFFD4A843),
            Color(0xFF8B6914),
            Colors.transparent,
          ],
          stops: [0.0, 0.2, 0.5, 0.8, 1.0],
        ).createShader(bounds),
        child: Container(height: 1, color: Colors.white),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final bool loading;
  final String? analysis;
  final AnimationController shimmerController;
  final VoidCallback onAnalyze;

  const _Body({
    required this.loading,
    required this.analysis,
    required this.shimmerController,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return _LoadingState(controller: shimmerController);
    if (analysis == null) return _IdleState(onAnalyze: onAnalyze);
    return _ResultState(text: analysis!);
  }
}

// ─── Loading state — animated shimmer lines ───────────────────────────────────

class _LoadingState extends StatelessWidget {
  final AnimationController controller;
  const _LoadingState({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CupertinoActivityIndicator(
              color: Color(0xFFD4A843),
              radius: 8,
            ),
            const SizedBox(width: 10),
            Text(
              'Analysing trip data…',
              style: TextStyle(
                color: const Color(0xFF8B6914).withValues(alpha: 0.8),
                fontSize: 12,
                letterSpacing: 1,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...[0.9, 0.75, 0.85, 0.55].map(
          (w) => _ShimmerLine(controller: controller, widthFactor: w),
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
                  (controller.value - 0.4).clamp(0.0, 1.0),
                  controller.value.clamp(0.0, 1.0),
                  (controller.value + 0.4).clamp(0.0, 1.0),
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

// ─── Idle state — CTA button ──────────────────────────────────────────────────

class _IdleState extends StatelessWidget {
  final VoidCallback onAnalyze;
  const _IdleState({required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Decorative icon
        Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF8B6914).withValues(alpha: 0.1),
            border: Border.all(
              color: const Color(0xFF8B6914).withValues(alpha: 0.25),
            ),
          ),
          child: const Icon(
            Icons.insights_rounded,
            color: Color(0xFF8B6914),
            size: 22,
          ),
        ),

        Text(
          'Unlock your trip intelligence',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 16),

        // Gold CTA button
        GestureDetector(
          onTap: onAnalyze,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF8B6914),
                  Color(0xFFD4A843),
                  Color(0xFF8B6914)
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A843).withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFF1A1500), size: 14),
                SizedBox(width: 8),
                Text(
                  'ANALYSE TRIP PERFORMANCE',
                  style: TextStyle(
                    color: Color(0xFF1A1500),
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

// ─── Result state — analysis text ─────────────────────────────────────────────

class _ResultState extends StatelessWidget {
  final String text;
  const _ResultState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left gold bar + quote
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 2,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFEDD068), Color(0xFF8B6914)],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13.5,
                    height: 1.65,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Footer tag
        Row(
          children: [
            Container(
              width: 16,
              height: 1,
              color: const Color(0xFF8B6914).withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              'AI GENERATED',
              style: TextStyle(
                color: const Color(0xFF8B6914).withValues(alpha: 0.6),
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
