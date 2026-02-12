import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';

class ToolExecutionCard extends StatelessWidget {
  final List<LlamaToolCallContent> toolCalls;
  final List<LlamaToolResultContent> toolResults;

  const ToolExecutionCard({
    super.key,
    required this.toolCalls,
    required this.toolResults,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pendingCount = toolCalls
        .where((call) => _matchToolResultForCall(toolResults, call) == null)
        .length;
    final allCompleted = pendingCount == 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.24),
              colorScheme.surfaceContainerHigh.withValues(alpha: 0.82),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.16),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Tool execution',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                _ToolStatusChip(
                  allCompleted: allCompleted,
                  pendingCount: pendingCount,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...toolCalls.asMap().entries.map((entry) {
              final index = entry.key;
              final call = entry.value;
              final result = _matchToolResultForCall(toolResults, call);
              final isLast = index == toolCalls.length - 1;
              return _ToolCallItem(
                toolCall: call,
                toolResult: result,
                isLast: isLast,
              );
            }),
          ],
        ),
      ),
    );
  }

  LlamaToolResultContent? _matchToolResultForCall(
    List<LlamaToolResultContent> results,
    LlamaToolCallContent call,
  ) {
    for (final result in results) {
      if (call.id != null && result.id != null && call.id == result.id) {
        return result;
      }
    }

    for (final result in results) {
      if (result.name == call.name) {
        return result;
      }
    }

    return null;
  }
}

class _ToolStatusChip extends StatelessWidget {
  final bool allCompleted;
  final int pendingCount;

  const _ToolStatusChip({
    required this.allCompleted,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = allCompleted
        ? colorScheme.primary.withValues(alpha: 0.14)
        : colorScheme.surfaceContainerHighest;
    final fg = allCompleted
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allCompleted ? Icons.check_rounded : Icons.more_horiz_rounded,
            size: 12,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            allCompleted ? 'Completed' : '$pendingCount pending',
            style: TextStyle(
              fontSize: 10,
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCallItem extends StatelessWidget {
  final LlamaToolCallContent toolCall;
  final LlamaToolResultContent? toolResult;
  final bool isLast;

  const _ToolCallItem({
    required this.toolCall,
    required this.toolResult,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.code_rounded,
                  size: 14,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  toolCall.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Text(
                toolResult == null ? 'Running' : 'Completed',
                style: TextStyle(
                  fontSize: 11,
                  color: toolResult == null
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (toolResult == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          const SizedBox(height: 6),
          _ToolBlock(
            label: 'Arguments',
            value: _formatArguments(toolCall.arguments),
          ),
          if (toolResult != null) ...[
            const SizedBox(height: 8),
            _ToolBlock(
              label: 'Result',
              value: _prettyJson(toolResult!.result),
              emphasize: true,
            ),
          ],
        ],
      ),
    );
  }

  String _formatArguments(Map<String, dynamic> args) {
    if (args.isEmpty) {
      return 'No arguments';
    }
    return _prettyJson(args);
  }

  String _prettyJson(Object? value) {
    if (value == null) {
      return 'null';
    }

    if (value is String) {
      return value;
    }

    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}

class _ToolBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _ToolBlock({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            maxLines: 8,
            minLines: 1,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: emphasize ? colorScheme.primary : colorScheme.onSurface,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
