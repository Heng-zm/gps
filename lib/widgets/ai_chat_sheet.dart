import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/trip_data.dart';
import '../services/ai_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PALETTE
// ─────────────────────────────────────────────────────────────────────────────

class _Gold {
  static const Color bright = Color(0xFFEDD068);
  static const Color mid = Color(0xFFD4A843);
  static const Color dark = Color(0xFF8B6914);
  static const Color ink = Color(0xFF1A1500);
  static const Color surface = Color(0xFF0D0C07);
  static const Color sheet = Color(0xFF0F0E09);
  static const Color bubble = Color(0xFF1C1A0F);
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;

  bool get isUser => role == 'user';
}

class AiChatSheet extends StatefulWidget {
  const AiChatSheet({
    super.key,
    required this.summary,
  });

  final TripSummary summary;

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();

  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final List<Map<String, String>> _history = <Map<String, String>>[];

  bool _isTyping = false;
  String _thinkingStatus = 'Thinking…';
  Timer? _statusTimer;

  static const int _maxHistoryItems = 20;
  static const int _maxVisibleMessages = 80;

  static const List<String> _statuses = <String>[
    'Thinking…',
    'Analysing trip…',
    'Reviewing safety…',
    'Checking efficiency…',
    'Finalising…',
  ];

  static const List<String> _smartChips = <String>[
    'Was my speed safe?',
    'Estimated fuel usage?',
    'How to improve efficiency?',
    'Analyse my stops',
  ];

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _startThinkingAnimation() {
    _statusTimer?.cancel();

    int index = 0;

    _safeSetState(() {
      _thinkingStatus = _statuses.first;
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) {
      if (!mounted || !_isTyping) {
        timer.cancel();
        return;
      }

      index = (index + 1) % _statuses.length;

      _safeSetState(() {
        _thinkingStatus = _statuses[index];
      });
    });
  }

  void _stopThinkingAnimation() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;

      final double target = _scrollCtrl.position.maxScrollExtent;

      if (!animated) {
        _scrollCtrl.jumpTo(target);
        return;
      }

      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _trimBuffers() {
    if (_messages.length > _maxVisibleMessages) {
      final int removeCount = _messages.length - _maxVisibleMessages;
      _messages.removeRange(0, removeCount);
    }

    if (_history.length > _maxHistoryItems) {
      final int removeCount = _history.length - _maxHistoryItems;
      _history.removeRange(0, removeCount);
    }
  }

  Future<void> _sendMessage([String? text]) async {
    if (_isTyping) return;

    final String query = (text ?? _controller.text).trim();
    if (query.isEmpty) return;

    HapticFeedback.lightImpact();
    _controller.clear();
    _focusNode.unfocus();

    _safeSetState(() {
      _messages.add(_ChatMessage(role: 'user', text: query));
      _isTyping = true;
      _trimBuffers();
    });

    _startThinkingAnimation();
    _scrollToBottom();

    String response;

    try {
      response = await AiService.instance.chatWithAi(
        widget.summary,
        query,
        List<Map<String, String>>.unmodifiable(_history),
      );

      if (response.trim().isEmpty) {
        response = 'I could not generate a useful answer for this trip yet.';
      }
    } catch (e, st) {
      debugPrint('AiChatSheet send failed: $e\n$st');
      response =
          'Sorry, I could not reach the AI coach right now. Please check your connection and try again.';
    }

    if (!mounted) return;

    _stopThinkingAnimation();

    _safeSetState(() {
      _isTyping = false;

      _messages.add(_ChatMessage(role: 'ai', text: response));

      _history
        ..add(<String, String>{'role': 'user', 'content': query})
        ..add(<String, String>{'role': 'assistant', 'content': response});

      _trimBuffers();
    });

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double bottomInset = media.viewInsets.bottom;
    final double height = media.size.height * 0.86;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFF17120A),
                  _Gold.sheet,
                  Color(0xFF070604),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border.all(
                color: _Gold.dark.withValues(alpha: 0.32),
                width: 1,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                const _SheetHandle(),
                _SheetTitle(summary: widget.summary),
                const _GoldDivider(),
                Expanded(
                  child: _messages.isEmpty && !_isTyping
                      ? _EmptyCoachState(
                          onPromptTap: _sendMessage,
                        )
                      : _MessageList(
                          messages: _messages,
                          isTyping: _isTyping,
                          thinkingStatus: _thinkingStatus,
                          scrollCtrl: _scrollCtrl,
                        ),
                ),
                _SmartChips(
                  chips: _smartChips,
                  isTyping: _isTyping,
                  onChipTap: _sendMessage,
                ),
                _InputBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  isTyping: _isTyping,
                  onSend: _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      width: 44,
      height: 4,
      decoration: BoxDecoration(
        color: _Gold.dark.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({
    required this.summary,
  });

  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final String distance = summary.distanceMiles.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: <Color>[_Gold.bright, _Gold.mid, _Gold.dark],
                stops: <double>[0.2, 0.62, 1.0],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _Gold.mid.withValues(alpha: 0.28),
                  blurRadius: 14,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: _Gold.ink,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'AI COACH',
                  style: TextStyle(
                    color: _Gold.bright,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 2.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Trip insights and safety feedback',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white38,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _Gold.dark.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: _Gold.dark.withValues(alpha: 0.25)),
            ),
            child: Text(
              '$distance mi',
              style: const TextStyle(
                color: _Gold.bright,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldDivider extends StatelessWidget {
  const _GoldDivider();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          colors: <Color>[
            Colors.transparent,
            _Gold.dark,
            _Gold.mid,
            _Gold.dark,
            Colors.transparent,
          ],
          stops: <double>[0.0, 0.2, 0.5, 0.8, 1.0],
        ).createShader(bounds);
      },
      child: Container(height: 1, color: Colors.white),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyCoachState extends StatelessWidget {
  const _EmptyCoachState({
    required this.onPromptTap,
  });

  final void Function(String) onPromptTap;

  @override
  Widget build(BuildContext context) {
    const List<String> prompts = <String>[
      'Give me a quick trip summary',
      'Was my driving efficient?',
      'What should I improve next time?',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _Gold.dark.withValues(alpha: 0.22)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _Gold.dark.withValues(alpha: 0.16),
                  border: Border.all(color: _Gold.dark.withValues(alpha: 0.28)),
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  color: _Gold.bright,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ask your AI coach',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Get trip feedback, safety notes, stop analysis, and efficiency tips based on your current trip summary.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.54),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final String prompt in prompts) ...<Widget>[
          _PromptTile(
            text: prompt,
            onTap: () => onPromptTap(prompt),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _PromptTile extends StatelessWidget {
  const _PromptTile({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Gold.bubble.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _Gold.dark.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                CupertinoIcons.sparkles,
                color: _Gold.mid,
                size: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                color: Colors.white30,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MESSAGE LIST
// ─────────────────────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.isTyping,
    required this.thinkingStatus,
    required this.scrollCtrl,
  });

  final List<_ChatMessage> messages;
  final bool isTyping;
  final String thinkingStatus;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: messages.length + (isTyping ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == messages.length) {
          return _ThinkingBubble(status: thinkingStatus);
        }

        final _ChatMessage message = messages[index];

        return _ChatBubble(
          key: ValueKey<String>(
              '${message.role}_${index}_${message.text.hashCode}'),
          text: message.text,
          isUser: message.isUser,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT BUBBLE
// ─────────────────────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final double maxWidth = MediaQuery.of(context).size.width * 0.78;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: BoxDecoration(
            gradient: isUser
                ? const LinearGradient(
                    colors: <Color>[_Gold.dark, _Gold.mid],
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
                : Border.all(color: _Gold.dark.withValues(alpha: 0.22)),
            boxShadow: isUser
                ? <BoxShadow>[
                    BoxShadow(
                      color: _Gold.mid.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: isUser ? _UserText(text: text) : _AiMarkdown(text: text),
        ),
      ),
    );
  }
}

class _UserText extends StatelessWidget {
  const _UserText({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      style: const TextStyle(
        color: _Gold.ink,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AiMarkdown extends StatelessWidget {
  const _AiMarkdown({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
        strong: const TextStyle(
          color: _Gold.bright,
          fontWeight: FontWeight.w900,
        ),
        em: TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.white.withValues(alpha: 0.64),
        ),
        h1: const TextStyle(
          color: _Gold.bright,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        h2: const TextStyle(
          color: _Gold.bright,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
        h3: const TextStyle(
          color: _Gold.bright,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
        listBullet: const TextStyle(
          color: _Gold.mid,
          fontSize: 14,
        ),
        blockquote: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 14,
          height: 1.45,
        ),
        blockquoteDecoration: BoxDecoration(
          color: _Gold.dark.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: _Gold.mid.withValues(alpha: 0.7),
              width: 3,
            ),
          ),
        ),
        code: TextStyle(
          color: _Gold.bright,
          backgroundColor: _Gold.dark.withValues(alpha: 0.2),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        codeblockDecoration: BoxDecoration(
          color: _Gold.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _Gold.dark.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THINKING BUBBLE
// ─────────────────────────────────────────────────────────────────────────────

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _Gold.bubble,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomLeft: Radius.zero,
          ),
          border: Border.all(color: _Gold.dark.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CupertinoActivityIndicator(
              color: _Gold.mid,
              radius: 8,
            ),
            const SizedBox(width: 10),
            Text(
              status,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
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

// ─────────────────────────────────────────────────────────────────────────────
// SMART CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _SmartChips extends StatelessWidget {
  const _SmartChips({
    required this.chips,
    required this.isTyping,
    required this.onChipTap,
  });

  final List<String> chips;
  final bool isTyping;
  final void Function(String) onChipTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (BuildContext context, int index) {
            final String chip = chips[index];

            return _SmartChip(
              text: chip,
              enabled: !isTyping,
              onTap: () => onChipTap(chip),
            );
          },
        ),
      ),
    );
  }
}

class _SmartChip extends StatelessWidget {
  const _SmartChip({
    required this.text,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: _Gold.dark.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: enabled ? onTap : null,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: _Gold.dark.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: _Gold.mid,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INPUT BAR
// ─────────────────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.isTyping,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isTyping;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !isTyping,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                placeholder: isTyping ? 'Thinking…' : 'Ask your coach…',
                placeholderStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.24),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
                cursorColor: _Gold.bright,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: _Gold.bubble,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _Gold.dark.withValues(alpha: 0.32),
                  ),
                ),
                onSubmitted: (_) {
                  if (!isTyping) onSend();
                },
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              enabled: !isTyping,
              onTap: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1.0 : 0.4,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: <Color>[_Gold.dark, _Gold.mid],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _Gold.mid.withValues(alpha: enabled ? 0.3 : 0.0),
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
    );
  }
}
