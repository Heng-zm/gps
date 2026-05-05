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

  void _getAiInsights() async {
    setState(() => _loading = true);
    try {
      final result = await AiService.instance.analyzeTrip(widget.summary);
      if (mounted) {
        setState(() {
          _analysis = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysis = "Analysis failed. Please try again.";
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFA855F7).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: Color(0xFFA855F7), size: 20),
              const SizedBox(width: 10),
              const Text(
                'GEMINI AI ANALYSIS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (_analysis != null && !_loading)
                GestureDetector(
                  onTap: _getAiInsights,
                  child: const Icon(Icons.refresh,
                      color: Colors.white24, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // FIX: Removed curly braces { } around these logic blocks
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CupertinoActivityIndicator(color: Color(0xFFA855F7)),
              ),
            )
          else if (_analysis == null)
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: const Color(0xFFA855F7).withValues(alpha: 0.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                borderRadius: BorderRadius.circular(12),
                onPressed: _getAiInsights,
                child: const Text(
                  'Analyze Trip Performance',
                  style: TextStyle(
                    color: Color(0xFFA855F7),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            Text(
              _analysis!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
