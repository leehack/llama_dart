import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class RuntimeStatusPanel extends StatelessWidget {
  const RuntimeStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      ChatProvider,
      (bool, String, String, int, int, double?, int?, int?, int?, int?)
    >(
      selector: (_, provider) => (
        provider.isReady,
        provider.activeBackend,
        provider.activeModelName,
        provider.currentTokens,
        provider.contextLimit,
        provider.lastTokensPerSecond,
        provider.lastFirstTokenLatencyMs,
        provider.lastGenerationLatencyMs,
        provider.runtimeGpuLayers,
        provider.runtimeThreads,
      ),
      builder: (context, data, _) {
        final (
          isReady,
          activeBackend,
          activeModelName,
          currentTokens,
          contextLimit,
          tokensPerSecond,
          firstTokenLatencyMs,
          generationLatencyMs,
          runtimeGpuLayers,
          runtimeThreads,
        ) = data;

        if (!isReady) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, icon: Icons.memory_rounded, text: activeBackend),
              _chip(
                context,
                icon: Icons.model_training_outlined,
                text: activeModelName,
              ),
              _chip(
                context,
                icon: Icons.data_usage_rounded,
                text: '$currentTokens/$contextLimit tok',
              ),
              if (tokensPerSecond != null)
                _chip(
                  context,
                  icon: Icons.speed_rounded,
                  text: '${tokensPerSecond.toStringAsFixed(1)} tok/s',
                ),
              if (firstTokenLatencyMs != null)
                _chip(
                  context,
                  icon: Icons.bolt_rounded,
                  text: 'first ${firstTokenLatencyMs}ms',
                ),
              if (generationLatencyMs != null)
                _chip(
                  context,
                  icon: Icons.timer_outlined,
                  text: 'total ${generationLatencyMs}ms',
                ),
              if (runtimeGpuLayers != null)
                _chip(
                  context,
                  icon: Icons.layers_rounded,
                  text: 'layers $runtimeGpuLayers',
                ),
              if (runtimeThreads != null)
                _chip(
                  context,
                  icon: Icons.alt_route_rounded,
                  text: 'threads $runtimeThreads',
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
