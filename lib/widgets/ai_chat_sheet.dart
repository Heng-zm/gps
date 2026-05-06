import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/trip_data.dart';
import '../services/ai_service.dart';

// ─── Shared Palette (mirrors ai_analysis_card.dart) ──────────────────────────

class _Gold {
  static const bright = Color(0xFFEDD068);
  static const mid = Color(0xFFD4A843);
  static const dark = Color(0xFF8B6914);
  static const ink = Color(0xFF1A1500);
  static const surface = Color(0xFF0D0C07);
  static const sheet = Color(0xFF0F0E09);
  static const bubble = Color(0xFF1C1A0F);
}

// ─── AiChatSheet ─────────────────────────────────────────────────────────────

class AiChatSheet extends StatefulWidget {
  final TripSummary summary;
  const AiChatSheet({super.key, required this.summary});

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];
  final List<Map<String, String>> _history = [];

  bool _isTyping = false;
  String _thinkingStatus = 'Thinking…';
  Timer? _statusTimer;

  static const _statuses = [
    'Thinking…',
    'Analysing trip…',
    'Reviewing safety…',
    'Finalising…',
  ];

  static const _smartChips = [
    'Was my speed safe?',
    'Estimated fuel usage?',
    'How to improve efficiency?',
    'Analyse my stops',
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _startThinkingAnimation() {
    _statusTimer?.cancel();
    int i = 0;
    setState(() => _thinkingStatus = _statuses[0]);
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || !_isTyping) {
        timer.cancel();
        return;
      }
      setState(() => _thinkingStatus = _statuses[++i % _statuses.length]);
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  Future<void> _sendMessage([String? text]) async {
    final query = (text ?? _controller.text).trim();
    if (query.isEmpty) return;

    HapticFeedback.lightImpact();
    _controller.clear();

    setState(() {
      _messages.add({'role': 'user', 'text': query});
      _isTyping = true;
    });

    _startThinkingAnimation();
    _scrollToBottom();

    final response =
        await AiService.instance.chatWithAi(widget.summary, query, _history);

    if (mounted) {
      _statusTimer?.cancel();
      setState(() {
        _isTyping = false;
        _messages.add({'role': 'ai', 'text': response});
        _history
          ..add({'role': 'user', 'content': query})
          ..add({'role': 'assistant', 'content': response});
      });
      _scrollToBottom();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: _Gold.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _Gold.dark.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          _SheetHandle(),
          _SheetTitle(),
          _GoldDivider(),
          Expanded(
              child: _MessageList(
            messages: _messages,
            isTyping: _isTyping,
            thinkingStatus: _thinkingStatus,
            scrollCtrl: _scrollCtrl,
          )),
          if (_messages.isEmpty && !_isTyping)
            _SmartChips(chips: _smartChips, onChipTap: _sendMessage),
          _InputBar(
            controller: _controller,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ─── Handle ───────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: _Gold.dark.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ─── Title ────────────────────────────────────────────────────────────────────

class _SheetTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [_Gold.bright, _Gold.dark],
                stops: [0.3, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: _Gold.mid.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: _Gold.ink, size: 10),
          ),
          const SizedBox(width: 8),
          const Text(
            'AI COACH',
            style: TextStyle(
              color: _Gold.bright,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Divider ──────────────────────────────────────────────────────────────────

class _GoldDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
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
    );
  }
}

// ─── Message list ─────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final List<Map<String, String>> messages;
  final bool isTyping;
  final String thinkingStatus;
  final ScrollController scrollCtrl;

  const _MessageList({
    required this.messages,
    required this.isTyping,
    required this.thinkingStatus,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: messages.length + (isTyping ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return _ThinkingBubble(status: thinkingStatus);
        }
        final msg = messages[i];
        final isUser = msg['role'] == 'user';
        return _ChatBubble(text: msg['text']!, isUser: isUser);
      },
    );
  }
}

// ─── Chat bubble ─────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [_Gold.dark, _Gold.mid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isUser ? null : _Gold.bubble,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? Radius.zero : const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
          ),
          border: isUser
              ? null
              : Border.all(color: _Gold.dark.withValues(alpha: 0.2)),
          boxShadow: isUser
              ? [
                  BoxShadow(
                    color: _Gold.mid.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: isUser
            ? Text(
                text,
                style: const TextStyle(
                  color: _Gold.ink,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              )
            : MarkdownBody(
                data: text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.5,
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
                    backgroundColor: _Gold.dark.withValues(alpha: 0.2),
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
                ),
              ),
      ),
    );
  }
}

// ─── Thinking bubble ─────────────────────────────────────────────────────────

class _ThinkingBubble extends StatelessWidget {
  final String status;
  const _ThinkingBubble({required this.status});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _Gold.bubble,
          borderRadius:
              BorderRadius.circular(18).copyWith(bottomLeft: Radius.zero),
          border: Border.all(color: _Gold.dark.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(
              color: _Gold.mid,
              radius: 8,
            ),
            const SizedBox(width: 10),
            Text(
              status,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Smart chips ──────────────────────────────────────────────────────────────

class _SmartChips extends StatelessWidget {
  final List<String> chips;
  final void Function(String) onChipTap;

  const _SmartChips({required this.chips, required this.onChipTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => onChipTap(chips[i]),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _Gold.dark.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _Gold.dark.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              chips[i],
              style: const TextStyle(
                color: _Gold.mid,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                placeholder: 'Ask your coach…',
                placeholderStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
                style: const TextStyle(color: Colors.white),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: _Gold.bubble,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _Gold.dark.withValues(alpha: 0.3),
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onSend,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_Gold.dark, _Gold.mid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _Gold.mid.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.arrow_up,
                  color: _Gold.ink,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
