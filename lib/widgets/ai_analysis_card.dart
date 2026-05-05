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

class _AiAnalysisCardState extends State<AiAnalysisCard> {
  String? _analysis;
  bool _loading = false;
  String? _errorMessage;

  /// Triggers the Gemini AI to process the trip summary
  // Inside AiAnalysisCardState...
  Future<void> _getAiInsights() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // SMART UPGRADE: Passing weather if available
      final result = await AiService.instance.analyzeTrip(widget.summary,
          weather: null // You can pass your stored weather model here
          );

      if (mounted)
        setState(() {
          _analysis = result;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _errorMessage = "AI connection failed.";
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    const purpleAccent = Color(0xFFA855F7);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151515), // Matches the new OLED black theme
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: purpleAccent.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: purpleAccent, size: 18),
              const SizedBox(width: 10),
              const Text(
                'GEMINI ANALYSIS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (_analysis != null && !_loading)
                GestureDetector(
                  onTap: _getAiInsights,
                  child: Icon(
                    CupertinoIcons.refresh,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 14,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Content Area with Smooth Animation
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildBody(purpleAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Color accent) {
    // 1. Loading State
    if (_loading) {
      return Center(
        key: const ValueKey('loading'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              const CupertinoActivityIndicator(color: Color(0xFFA855F7)),
              const SizedBox(height: 8),
              Text(
                'Consulting Gemini...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Error State
    if (_errorMessage != null) {
      return Column(
        key: const ValueKey('error'),
        children: [
          Text(
            _errorMessage!,
            style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _getAiInsights,
            child: const Text('Try Again', style: TextStyle(fontSize: 14)),
          ),
        ],
      );
    }

    // 3. Initial State (Button)
    if (_analysis == null) {
      return SizedBox(
        key: const ValueKey('button'),
        width: double.infinity,
        child: CupertinoButton(
          color: accent.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(vertical: 14),
          borderRadius: BorderRadius.circular(14),
          onPressed: _getAiInsights,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Generate Smart Insights',
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.sparkles, color: accent, size: 16),
            ],
          ),
        ),
      );
    }

    // 4. Result State (The Analysis Text)
    return Container(
      key: const ValueKey('result'),
      width: double.infinity,
      child: Text(
        _analysis!,
        style: const TextStyle(
          color: Color(0xFFEEEEEE),
          fontSize: 14,
          height: 1.6,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
