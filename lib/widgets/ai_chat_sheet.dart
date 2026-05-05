import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/trip_data.dart';
import '../services/ai_service.dart';

class AiChatSheet extends StatefulWidget {
  final TripSummary summary;
  const AiChatSheet({super.key, required this.summary});

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  final List<Content> _history = [];
  bool _isTyping = false;

  final List<String> _smartChips = [
    "Was my speed safe?",
    "Estimated fuel usage?",
    "How to improve efficiency?",
    "Analyze my stops"
  ];

  void _sendMessage([String? text]) async {
    final query = text ?? _controller.text.trim();
    if (query.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add({"role": "user", "text": query});
      _isTyping = true;
    });

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollController.animateTo(_scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });

    final response =
        await AiService.instance.chatWithAi(widget.summary, query, _history);

    if (mounted) {
      setState(() {
        _messages.add({"role": "ai", "text": response});
        _history.add(Content.text(query));
        _history.add(Content.model([TextPart(response)]));
        _isTyping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white10, borderRadius: BorderRadius.circular(2)),
          ),
          const Text('TRACKPRO AI COACH',
              style: TextStyle(
                  color: Color(0xFFA855F7),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2)),
          const SizedBox(height: 10),

          // ── Chat Area ─────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final isUser = _messages[i]["role"] == "user";
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFFA855F7)
                          : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomRight: isUser
                            ? const Radius.circular(0)
                            : const Radius.circular(18),
                        bottomLeft: isUser
                            ? const Radius.circular(18)
                            : const Radius.circular(0),
                      ),
                    ),
                    child: Text(_messages[i]["text"]!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, height: 1.4)),
                  ),
                );
              },
            ),
          ),

          if (_isTyping)
            const Padding(
                padding: EdgeInsets.all(10),
                child: CupertinoActivityIndicator(color: Color(0xFFA855F7))),

          // ── Smart Chips ──────────────────────────────────────────────────
          if (_messages.isEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _smartChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ActionChip(
                  backgroundColor: const Color(0xFF1A1A1A),
                  side: BorderSide(
                      color: const Color(0xFFA855F7).withValues(alpha: 0.3)),
                  label: Text(_smartChips[i],
                      style: const TextStyle(
                          color: Color(0xFFA855F7), fontSize: 11)),
                  onPressed: () => _sendMessage(_smartChips[i]),
                ),
              ),
            ),

          // ── Input ────────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _controller,
                      placeholder: 'Ask your coach...',
                      placeholderStyle: const TextStyle(color: Colors.white24),
                      style: const TextStyle(color: Colors.white),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16)),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _sendMessage(),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                          color: Color(0xFFA855F7), shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.arrow_up,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
