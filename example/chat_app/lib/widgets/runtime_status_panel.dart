import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class RuntimeStatusPanel extends StatelessWidget {
  const RuntimeStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      ChatProvider,
      (bool, String, String, bool, int?, int?, int?, int?, String?)
    >(
      selector: (_, provider) => (
        provider.isReady,
        provider.activeBackend,
        provider.runtimeBackendRaw,
        provider.runtimeGpuActive,
        provider.runtimeGpuLayers,
        provider.runtimeThreads,
        provider.lastFirstTokenLatencyMs,
        provider.lastGenerationLatencyMs,
        provider.runtimeModelArchitecture,
      ),
      builder: (context, data, _) {
        final (
          isReady,
          activeBackend,
          runtimeBackendRaw,
          runtimeGpuActive,
          runtimeGpuLayers,
          runtimeThreads,
          firstTokenLatencyMs,
          generationLatencyMs,
          modelArchitecture,
        ) = data;

        if (!isReady) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(context, icon: Icons.memory_rounded, text: activeBackend),
                _chip(
                  context,
                  icon: runtimeGpuActive
                      ? Icons.rocket_launch_rounded
                      : Icons.electric_bolt_outlined,
                  text: runtimeGpuActive ? 'GPU active' : 'GPU inactive',
                  color: runtimeGpuActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
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
                if (modelArchitecture != null && modelArchitecture.isNotEmpty)
                  _chip(
                    context,
                    icon: Icons.category_outlined,
                    text: modelArchitecture,
                  ),
                if (runtimeBackendRaw.isNotEmpty)
                  Tooltip(
                    message: runtimeBackendRaw,
                    child: _chip(
                      context,
                      icon: Icons.info_outline_rounded,
                      text: 'details',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedColor = color ?? colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: resolvedColor),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w600,
              color: resolvedColor,
            ),
          ),
        ],
      ),
    );
  }
}
