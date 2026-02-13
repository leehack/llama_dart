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
    final color = isUser
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondaryContainer;
    final textColor = isUser
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSecondaryContainer;

    const borderRadius = 20.0;
    final border = BorderRadius.only(
      topLeft: const Radius.circular(borderRadius),
      topRight: const Radius.circular(borderRadius),
      bottomLeft: Radius.circular(isUser ? borderRadius : 4),
      bottomRight: Radius.circular(isUser ? 4 : borderRadius),
    );

    final thinkingText = message.thinkingText;

    return Padding(
      padding: EdgeInsets.only(bottom: isNextSame ? 4 : 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                _buildAvatar(context, isUser),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: align,
                  children: [
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
                        bubbleColor: color,
                        textColor: textColor,
                        border: border,
                        isUser: isUser,
                      ),
                  ],
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                _buildAvatar(context, isUser),
              ],
            ],
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 40),
              child: Text(
                _formatTimestamp(context),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 40),
              child: Text(
                _formatTimestamp(context),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: textColor, fontSize: 15, height: 1.4),
          code: TextStyle(
            color: isUser
                ? textColor.withValues(alpha: 0.9)
                : colorScheme.onSurfaceVariant,
            backgroundColor: isUser
                ? Colors.black.withValues(alpha: 0.1)
                : colorScheme.surfaceContainerHighest,
            fontFamily: 'monospace',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
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
      margin: const EdgeInsets.only(bottom: 4),
      constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

  Widget _buildAvatar(BuildContext context, bool isUser) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isUser
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          isUser ? Icons.person_rounded : Icons.auto_awesome,
          size: 16,
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
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
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide.none,
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
              "Thought Process",
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
            ),
            child: Text(
              thinkingText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary,
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
