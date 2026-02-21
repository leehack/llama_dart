import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:llamadart/llamadart.dart';

import '../models/chat_message.dart';
import 'tool_execution_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isNextSame;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isNextSame,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: _buildBubble(context));
  }

  Widget _buildBubble(BuildContext context) {
    if (message.role == LlamaChatRole.tool) {
      return const SizedBox.shrink();
    }

    if (message.isInfo) {
      return _buildInfoMessage(context);
    }

    final isUser = message.isUser;
    final isTypingPlaceholder =
        !isUser &&
        message.text.trim() == '...' &&
        (message.parts == null || message.parts!.isEmpty);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final colorScheme = Theme.of(context).colorScheme;

    final bubbleColor = isUser
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.22),
            colorScheme.surfaceContainerHighest,
          )
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.72);
    final textColor = colorScheme.onSurface;

    const borderRadius = 24.0;
    final border = BorderRadius.only(
      topLeft: const Radius.circular(borderRadius),
      topRight: const Radius.circular(borderRadius),
      bottomLeft: Radius.circular(isUser ? borderRadius : 8),
      bottomRight: Radius.circular(isUser ? 8 : borderRadius),
    );

    final thinkingText = message.thinkingText;

    return Padding(
      padding: EdgeInsets.only(bottom: isNextSame ? 8 : 18),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _maxBubbleWidth(context)),
          child: Column(
            crossAxisAlignment: align,
            children: [
              if (!isTypingPlaceholder)
                _buildRoleAndTimeLabel(context, isUser: isUser),
              if (message.parts != null)
                ...message.parts!
                    .where(
                      (p) =>
                          p is! LlamaTextContent &&
                          p is! LlamaToolCallContent &&
                          p is! LlamaToolResultContent &&
                          p is! LlamaThinkingContent,
                    )
                    .map((p) => _buildMediaPart(context, p)),
              if (thinkingText != null && thinkingText.trim().isNotEmpty)
                _buildThinkingView(context, thinkingText),
              if (message.isToolCall)
                _buildToolCallView(context)
              else if (isTypingPlaceholder)
                _buildTypingBubble(context)
              else if (message.text.isNotEmpty)
                _buildMarkdownBubble(
                  context,
                  message.text,
                  bubbleColor: bubbleColor,
                  textColor: textColor,
                  border: border,
                  isUser: isUser,
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _maxBubbleWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) return 860;
    if (width >= 1000) return width * 0.64;
    if (width >= 720) return width * 0.72;
    return width * 0.86;
  }

  Widget _buildRoleAndTimeLabel(BuildContext context, {required bool isUser}) {
    final colorScheme = Theme.of(context).colorScheme;
    final roleLabel = isUser ? 'User' : 'Model';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$roleLabel  •  ${_formatTimestamp(context)}',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
        ),
      ),
    );
  }

  Widget _buildInfoMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownBubble(
    BuildContext context,
    String text, {
    required Color bubbleColor,
    required Color textColor,
    required BorderRadius border,
    required bool isUser,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: border,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: isUser ? 0.2 : 0.35,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            color: textColor.withValues(alpha: isUser ? 0.98 : 0.95),
            fontSize: 16,
            height: 1.45,
          ),
          h1: TextStyle(
            color: textColor,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          h2: TextStyle(
            color: textColor,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          code: TextStyle(
            color: isUser
                ? textColor.withValues(alpha: 0.9)
                : colorScheme.onSurfaceVariant,
            backgroundColor: isUser
                ? Colors.black.withValues(alpha: 0.1)
                : colorScheme.surfaceContainerHighest,
            fontFamily: 'monospace',
          ),
          blockquote: TextStyle(
            color: textColor.withValues(alpha: 0.85),
            fontSize: 14,
            height: 1.45,
          ),
          blockquoteDecoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.65),
                width: 3,
              ),
            ),
          ),
          codeblockDecoration: BoxDecoration(
            color: isUser
                ? Colors.black.withValues(alpha: 0.1)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingBubble(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: const _TypingDots(),
    );
  }

  String _formatTimestamp(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final mediaQuery = MediaQuery.maybeOf(context);
    final time = TimeOfDay.fromDateTime(message.timestamp);

    return localizations.formatTimeOfDay(
      time,
      alwaysUse24HourFormat: mediaQuery?.alwaysUse24HourFormat ?? false,
    );
  }

  Widget _buildMediaPart(BuildContext context, LlamaContentPart part) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildPartContent(part),
    );
  }

  Widget _buildPartContent(LlamaContentPart part) {
    if (part is LlamaImageContent) {
      if (!kIsWeb && part.path != null) {
        return Image.file(File(part.path!), fit: BoxFit.cover);
      } else if (part.bytes != null) {
        return Image.memory(part.bytes!, fit: BoxFit.cover);
      }
    } else if (part is LlamaAudioContent) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.black12,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audiotrack),
            SizedBox(width: 8),
            Text('Audio message'),
          ],
        ),
      );
    }
    return const Icon(Icons.description);
  }

  Widget _buildToolCallView(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final toolCalls = message.parts?.whereType<LlamaToolCallContent>().toList();
    final toolResults = message.parts
        ?.whereType<LlamaToolResultContent>()
        .toList();

    if (toolCalls == null || toolCalls.isEmpty) {
      return _buildMarkdownBubble(
        context,
        message.text,
        bubbleColor: colorScheme.surfaceContainerHighest,
        textColor: colorScheme.onSurface,
        border: BorderRadius.circular(12),
        isUser: false,
      );
    }

    return ToolExecutionCard(
      toolCalls: toolCalls,
      toolResults: toolResults ?? const [],
    );
  }

  Widget _buildThinkingView(BuildContext context, String thinkingText) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      width: double.infinity,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.psychology,
              size: 16,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Thought process',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              thinkingText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSecondaryContainer;

    return SizedBox(
      width: 38,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (index) {
              final phase = (progress + (index * 0.2)) % 1.0;
              final alpha =
                  ((0.3 + (0.7 * (1.0 - (phase - 0.5).abs() * 2.0))).clamp(
                            0.25,
                            1.0,
                          )
                          as num)
                      .toDouble();

              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: alpha),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
