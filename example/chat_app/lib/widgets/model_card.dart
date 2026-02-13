import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/downloadable_model.dart';

class ModelCard extends StatelessWidget {
  final DownloadableModel model;
  final bool isDownloaded;
  final bool isDownloading;
  final double progress;
  final bool isWeb;
  final bool isSelected;
  final int gpuLayers;
  final int contextSize;
  final ValueChanged<int> onGpuLayersChanged;
  final ValueChanged<int> onContextSizeChanged;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback? onCancel;

  const ModelCard({
    super.key,
    required this.model,
    required this.isDownloaded,
    required this.isDownloading,
    required this.progress,
    required this.isWeb,
    required this.isSelected,
    required this.gpuLayers,
    required this.contextSize,
    required this.onGpuLayersChanged,
    required this.onContextSizeChanged,
    required this.onSelect,
    required this.onDownload,
    required this.onDelete,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaChip(
                          context,
                          icon: Icons.sd_storage_outlined,
                          label: '${model.sizeMb} MB',
                        ),
                        _buildMetaChip(
                          context,
                          icon: Icons.memory_rounded,
                          label: '${model.minRamGb} GB RAM',
                        ),
                        if (isSelected)
                          _buildMetaChip(
                            context,
                            icon: Icons.check_circle_outline_rounded,
                            label: 'Selected',
                            emphasize: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCapabilityChip(
                          context,
                          icon: Icons.build_circle_outlined,
                          label: 'Tools',
                          supported: model.supportsToolCalling,
                        ),
                        _buildCapabilityChip(
                          context,
                          icon: Icons.psychology_alt_outlined,
                          label: 'Thinking',
                          supported: model.supportsThinking,
                        ),
                        _buildCapabilityChip(
                          context,
                          icon: Icons.visibility_outlined,
                          label: 'Vision',
                          supported: model.supportsVision,
                        ),
                        _buildCapabilityChip(
                          context,
                          icon: Icons.mic_none_rounded,
                          label: 'Audio',
                          supported: model.supportsAudio,
                        ),
                        _buildCapabilityChip(
                          context,
                          icon: Icons.videocam_outlined,
                          label: 'Video',
                          supported: model.supportsVideo,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isWeb && (isDownloaded || (progress > 0 && !isDownloaded)))
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: colorScheme.error,
                  ),
                  onPressed: onDelete,
                  tooltip: progress > 0 && !isDownloaded
                      ? 'Cancel & Discard'
                      : 'Delete Model',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            model.description,
            style: GoogleFonts.outfit(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildParamChip(
                context,
                label: 'T ${model.preset.temperature.toStringAsFixed(2)}',
              ),
              _buildParamChip(context, label: 'K ${model.preset.topK}'),
              _buildParamChip(
                context,
                label: 'P ${model.preset.topP.toStringAsFixed(2)}',
              ),
              _buildParamChip(
                context,
                label: 'Ctx ${model.preset.contextSize}',
              ),
              _buildParamChip(context, label: 'Gen ${model.preset.maxTokens}'),
            ],
          ),
          const SizedBox(height: 16),
          if (isDownloading || (progress > 0 && !isDownloaded)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isDownloading ? 'Downloading...' : 'Paused',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDownloading ? colorScheme.primary : Colors.orange,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDownloading
                            ? colorScheme.primary
                            : Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        icon: Icon(
                          isDownloading
                              ? Icons.pause_circle_outline_rounded
                              : Icons.play_circle_outline_rounded,
                          color: isDownloading
                              ? colorScheme.primary
                              : Colors.orange,
                        ),
                        onPressed: isDownloading ? onCancel : onDownload,
                        tooltip: isDownloading
                            ? 'Pause Download'
                            : 'Resume Download',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
          if (!isDownloading) ...[
            if (isDownloaded && !isWeb && isSelected) ...[
              const SizedBox(height: 16),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerTheme: const DividerThemeData(thickness: 0.5),
                ),
                child: ExpansionTile(
                  title: Text(
                    'Advanced Settings (Selected)',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 16),
                  shape: const RoundedRectangleBorder(),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'GPU Offloading (Layers)',
                              style: GoogleFonts.outfit(fontSize: 13),
                            ),
                            Text(
                              gpuLayers.toString(),
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: gpuLayers.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: gpuLayers.toString(),
                          onChanged: (v) => onGpuLayersChanged(v.round()),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Context Size (Tokens)',
                              style: GoogleFonts.outfit(fontSize: 13),
                            ),
                            Text(
                              contextSize.toString(),
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: contextSize.clamp(512, 32768).toDouble(),
                          min: 512,
                          max: 32768,
                          divisions: 63, // 512 steps
                          label: contextSize.toString(),
                          onChanged: (v) => onContextSizeChanged(v.round()),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Note: Higher values use more VRAM/RAM and may cause crashes if exceeding system limits.',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: isDownloaded || isWeb
                  ? FilledButton.icon(
                      onPressed: onSelect,
                      icon: Icon(
                        isSelected
                            ? Icons.check_circle_outline_rounded
                            : Icons.auto_awesome_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isWeb
                            ? 'Load Web Model'
                            : (isSelected
                                  ? 'Reload Selected Model'
                                  : 'Use this model'),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: onDownload,
                      icon: Icon(
                        progress > 0
                            ? Icons.play_arrow_rounded
                            : Icons.download_rounded,
                        size: 18,
                      ),
                      label: Text(
                        progress > 0 ? 'Resume Download' : 'Download to Device',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool emphasize = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = emphasize
        ? colorScheme.primaryContainer.withValues(alpha: 0.75)
        : colorScheme.secondaryContainer.withValues(alpha: 0.5);
    final foreground = emphasize
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool supported,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = supported
        ? colorScheme.primaryContainer.withValues(alpha: 0.65)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final foreground = supported
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: supported
            ? null
            : Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            supported ? Icons.check_rounded : Icons.close_rounded,
            size: 12,
            color: foreground,
          ),
        ],
      ),
    );
  }

  Widget _buildParamChip(BuildContext context, {required String label}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
