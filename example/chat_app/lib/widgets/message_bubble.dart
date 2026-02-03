import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';

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

    final isUser = message.isUser;
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
                                p is! LlamaToolResultContent,
                          )
                          .map((p) => _buildMediaPart(context, p)),
                    if (message.isToolCall)
                      _buildToolCallView(context)
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: color,
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
                          data: message.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            code: TextStyle(
                              color: isUser
                                  ? textColor.withValues(alpha: 0.9)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              backgroundColor: isUser
                                  ? Colors.black.withValues(alpha: 0.1)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: isUser
                                  ? Colors.black.withValues(alpha: 0.1)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
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
        ],
      ),
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
      if (part.path != null) {
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
    final toolCall = message.parts
        ?.whereType<LlamaToolCallContent>()
        .firstOrNull;
    final title = toolCall != null
        ? 'Tool: ${toolCall.name}'
        : 'Executing Tool';
    final content = toolCall != null
        ? jsonEncode(toolCall.arguments)
        : message.text;

    final toolResult = message.parts
        ?.whereType<LlamaToolResultContent>()
        .firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (toolResult != null || isNextSame)
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                )
              else
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (toolResult != null) ...[
                  const Divider(height: 12, thickness: 0.5),
                  Text(
                    'Result: ${toolResult.result is String ? toolResult.result : jsonEncode(toolResult.result)}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
