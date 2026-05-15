// ignore_for_file: unused_element

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/trip_data.dart';
import '../services/ai_service.dart';
import 'common/app_status_pill.dart';
import 'common/app_glass_card.dart';
import 'common/app_filter_chip.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLACK / WHITE / BLUE APP PALETTE
// ─────────────────────────────────────────────────────────────────────────────

class _AppColors {
  static const Color bright = Color(0xFFFFFFFF);
  static const Color mid = Color(0xFF3B82F6);
  static const Color dark = Color(0xFF1E40AF);
  static const Color surface = Color(0xFF05070B);
  static const Color sheet = Color(0xFF070A12);
  static const Color bubble = Color(0xFF101522);
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

  bool get _canSend => !_isTyping && _controller.text.trim().isNotEmpty;

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
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.removeListener(_onInputChanged);
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
    final double height = (media.size.height * 0.90).clamp(540.0, 780.0);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 660,
            maxHeight: media.size.height * 0.95,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0xFF0B1220),
                      _AppColors.sheet,
                      Color(0xFF000000),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(34),
                  ),
                  border: Border.all(
                    color: _AppColors.mid.withValues(alpha: 0.24),
                    width: 1,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.52),
                      blurRadius: 34,
                      offset: const Offset(0, -14),
                    ),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    const _SheetHandle(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        children: <Widget>[
                          _AiCoachHero(summary: widget.summary),
                          const SizedBox(height: 10),
                          _TripContextStrip(summary: widget.summary),
                        ],
                      ),
                    ),
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
                      canSend: _canSend,
                      onSend: _sendMessage,
                    ),
                  ],
                ),
              ),
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
        color: _AppColors.dark.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _AiCoachHero extends StatelessWidget {
  const _AiCoachHero({
    required this.summary,
  });

  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 26,
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.blueButtonGradient,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.34),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.sparkles,
              color: AppColors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'AI Trip Coach',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ask about safety, speed, route quality, or improvements.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.56),
                    fontSize: 12,
                    height: 1.20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppStatusPill(
                      label: '${summary.distanceMiles.toStringAsFixed(1)} MI',
                      color: AppColors.blueSoft,
                      icon: CupertinoIcons.location_fill,
                    ),
                    AppStatusPill(
                      label: '${summary.avgSpeedMph.round()} MPH AVG',
                      color: AppColors.green,
                      icon: CupertinoIcons.speedometer,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripContextStrip extends StatelessWidget {
  const _TripContextStrip({
    required this.summary,
  });

  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final List<_TripContextItem> items = <_TripContextItem>[
      _TripContextItem(
        label: 'Distance',
        value: summary.distanceMiles.toStringAsFixed(1),
        unit: 'mi',
        icon: CupertinoIcons.map_fill,
      ),
      _TripContextItem(
        label: 'Avg speed',
        value: summary.avgSpeedMph.round().toString(),
        unit: 'mph',
        icon: CupertinoIcons.speedometer,
      ),
      _TripContextItem(
        label: 'Max speed',
        value: summary.maxSpeedMph.round().toString(),
        unit: 'mph',
        icon: CupertinoIcons.arrow_up_right,
      ),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: item == items.last ? 0 : 8,
            ),
            child: _TripContextMiniCard(item: item),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _TripContextItem {
  const _TripContextItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
}

class _TripContextMiniCard extends StatelessWidget {
  const _TripContextMiniCard({
    required this.item,
  });

  final _TripContextItem item;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(11),
      borderRadius: 18,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(item.icon, color: AppColors.blueSoft, size: 15),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Flexible(
                child: Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  item.unit,
                  style: const TextStyle(
                    color: AppColors.blueSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            item.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.white54,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.55,
            ),
          ),
        ],
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: <Color>[
                  _AppColors.bright,
                  _AppColors.mid,
                  _AppColors.dark
                ],
                stops: <double>[0.2, 0.62, 1.0],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _AppColors.mid.withValues(alpha: 0.30),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'AI COACH',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 2.0,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Trip insights, safety, and efficiency',
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
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(maxWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _AppColors.dark.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
              border:
                  Border.all(color: _AppColors.dark.withValues(alpha: 0.25)),
            ),
            child: Text(
              '$distance mi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _AppColors.bright,
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
            _AppColors.dark,
            _AppColors.mid,
            _AppColors.dark,
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
      'Summarize this trip',
      'How was my speed?',
      'Was this route efficient?',
      'How can I save battery?',
      'What should I improve?',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _AppColors.dark.withValues(alpha: 0.22)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _AppColors.dark.withValues(alpha: 0.16),
                  border: Border.all(
                      color: _AppColors.dark.withValues(alpha: 0.28)),
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  color: _AppColors.bright,
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
      color: _AppColors.bubble.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AppColors.dark.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                CupertinoIcons.sparkles,
                color: _AppColors.mid,
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
      cacheExtent: 600,
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
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double maxWidth =
        screenWidth < 420 ? screenWidth * 0.84 : screenWidth * 0.72;

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
                    colors: <Color>[Color(0xFF1D4ED8), _AppColors.mid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isUser ? null : _AppColors.bubble,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: isUser ? Radius.zero : const Radius.circular(18),
              bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
            ),
            border: isUser
                ? null
                : Border.all(color: _AppColors.dark.withValues(alpha: 0.22)),
            boxShadow: isUser
                ? <BoxShadow>[
                    BoxShadow(
                      color: _AppColors.mid.withValues(alpha: 0.22),
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
        color: Colors.white,
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
          color: _AppColors.bright,
          fontWeight: FontWeight.w900,
        ),
        em: TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.white.withValues(alpha: 0.64),
        ),
        h1: const TextStyle(
          color: _AppColors.bright,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        h2: const TextStyle(
          color: _AppColors.bright,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
        h3: const TextStyle(
          color: _AppColors.bright,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
        listBullet: const TextStyle(
          color: _AppColors.mid,
          fontSize: 14,
        ),
        blockquote: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 14,
          height: 1.45,
        ),
        blockquoteDecoration: BoxDecoration(
          color: _AppColors.dark.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: _AppColors.mid.withValues(alpha: 0.7),
              width: 3,
            ),
          ),
        ),
        code: TextStyle(
          color: _AppColors.bright,
          backgroundColor: _AppColors.dark.withValues(alpha: 0.2),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        codeblockDecoration: BoxDecoration(
          color: _AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _AppColors.dark.withValues(alpha: 0.3),
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
          color: _AppColors.bubble,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomLeft: Radius.zero,
          ),
          border: Border.all(color: _AppColors.dark.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CupertinoActivityIndicator(
              color: _AppColors.mid,
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
      child: isTyping
          ? const SizedBox.shrink()
          : RepaintBoundary(
              child: SizedBox(
                height: 50,
                child: ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: chips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final String chip = chips[index];

                    return _SmartChip(
                      text: chip,
                      onTap: () => onChipTap(chip),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _SmartChip extends StatelessWidget {
  const _SmartChip({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFilterChip(
      label: text,
      selected: false,
      icon: CupertinoIcons.sparkles,
      onTap: onTap,
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
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isTyping;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          border: Border(
            top: BorderSide(color: _AppColors.dark.withValues(alpha: 0.16)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  focusNode: focusNode,
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
                  cursorColor: _AppColors.bright,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  suffix: controller.text.isEmpty || isTyping
                      ? null
                      : CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 28,
                          onPressed: controller.clear,
                          child: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Colors.white30,
                            size: 17,
                          ),
                        ),
                  decoration: BoxDecoration(
                    color: _AppColors.bubble,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: focusNode.hasFocus
                          ? _AppColors.mid.withValues(alpha: 0.42)
                          : _AppColors.dark.withValues(alpha: 0.32),
                    ),
                    boxShadow: focusNode.hasFocus
                        ? <BoxShadow>[
                            BoxShadow(
                              color: _AppColors.mid.withValues(alpha: 0.10),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  onSubmitted: (_) {
                    if (canSend) onSend();
                  },
                ),
              ),
              const SizedBox(width: 10),
              _SendButton(
                enabled: canSend,
                isTyping: isTyping,
                onTap: onSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.isTyping,
    required this.onTap,
  });

  final bool enabled;
  final bool isTyping;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send message',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1.0 : 0.42,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: enabled
                  ? const LinearGradient(
                      colors: <Color>[Color(0xFF1D4ED8), _AppColors.mid],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: enabled ? null : _AppColors.bubble,
              border: Border.all(
                color: enabled
                    ? Colors.transparent
                    : _AppColors.dark.withValues(alpha: 0.28),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _AppColors.mid.withValues(alpha: enabled ? 0.30 : 0.0),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: isTyping
                  ? const CupertinoActivityIndicator(
                      color: _AppColors.mid,
                      radius: 8,
                    )
                  : Icon(
                      CupertinoIcons.arrow_up,
                      color: enabled ? Colors.white : Colors.white30,
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
