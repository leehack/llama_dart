import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamadart/llamadart.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class SettingsSheet extends StatelessWidget {
  final VoidCallback onOpenModelSelection;

  const SettingsSheet({super.key, required this.onOpenModelSelection});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final contextSizeOptions = _buildContextSizeOptions(
          provider.contextSize,
        );
        final availableBackends = _getAvailableBackends(provider);
        final selectedBackend =
            availableBackends.contains(provider.preferredBackend)
            ? provider.preferredBackend
            : GpuBackend.auto;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Runtime, generation, and tool behavior',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(
                        context,
                        icon: Icons.memory_rounded,
                        label: 'Active: ${provider.activeBackend}',
                      ),
                      _buildInfoChip(
                        context,
                        icon: Icons.tune_rounded,
                        label:
                            'Ctx ${provider.contextSize == 0 ? 'Auto' : provider.contextSize}',
                      ),
                      _buildInfoChip(
                        context,
                        icon: Icons.auto_awesome_rounded,
                        label: 'Tools ${provider.toolsEnabled ? 'On' : 'Off'}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(
                  context,
                  title: 'Model & Files',
                  icon: Icons.folder_copy_rounded,
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Model',
                  icon: Icons.description_outlined,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onOpenModelSelection();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              provider.modelPath?.split('/').last ?? 'None',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Multimodal Projector (mmproj)',
                  icon: Icons.extension_outlined,
                  child: InkWell(
                    onTap: () {
                      provider.selectMmprojFile();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.extension_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              provider.settings.mmprojPath?.split('/').last ??
                                  'None',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (provider.settings.mmprojPath != null)
                            IconButton(
                              onPressed: () => provider.updateMmprojPath(''),
                              icon: const Icon(Icons.clear, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          else
                            Icon(
                              Icons.file_upload_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader(
                  context,
                  title: 'Runtime',
                  icon: Icons.speed_rounded,
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Preferred Backend',
                  subtitle: 'Forces a specific driver if available',
                  icon: Icons.developer_board_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<GpuBackend>(
                            value: selectedBackend,
                            isExpanded: true,
                            items: availableBackends.map((backend) {
                              return DropdownMenuItem(
                                value: backend,
                                child: Text(backend.name.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                provider.updatePreferredBackend(value);
                              }
                            },
                          ),
                        ),
                      ),
                      if (provider.availableDevices.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Active: ${provider.activeBackend}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Context Size',
                  subtitle: provider.contextSize == 0
                      ? 'Auto'
                      : provider.contextSize.toString(),
                  icon: Icons.data_object_rounded,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: provider.contextSize,
                        isExpanded: true,
                        items: contextSizeOptions.map((size) {
                          return DropdownMenuItem(
                            value: size,
                            child: Text(size == 0 ? 'Auto (Native)' : '$size'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            provider.updateContextSize(value);
                          }
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader(
                  context,
                  title: 'Generation',
                  icon: Icons.auto_awesome_rounded,
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Temperature',
                  subtitle: provider.temperature.toStringAsFixed(2),
                  icon: Icons.thermostat_rounded,
                  child: Slider(
                    value: provider.temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    onChanged: (value) => provider.updateTemperature(value),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSettingItem(
                        context,
                        title: 'Top-K',
                        subtitle: provider.topK.toString(),
                        icon: Icons.filter_alt_rounded,
                        child: Slider(
                          value: provider.topK.toDouble(),
                          min: 1,
                          max: 100,
                          divisions: 100,
                          onChanged: (value) =>
                              provider.updateTopK(value.toInt()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSettingItem(
                        context,
                        title: 'Top-P',
                        subtitle: provider.topP.toStringAsFixed(2),
                        icon: Icons.percent_rounded,
                        child: Slider(
                          value: provider.topP,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          onChanged: (value) => provider.updateTopP(value),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Max Output Tokens',
                  subtitle: provider.maxGenerationTokens.toString(),
                  icon: Icons.text_fields_rounded,
                  child: Slider(
                    value: provider.maxGenerationTokens.toDouble(),
                    min: 512.0,
                    max: 32768.0,
                    divisions: (32768 - 512) ~/ 512,
                    onChanged: (value) =>
                        provider.updateMaxTokens(value.toInt()),
                  ),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader(
                  context,
                  title: 'Tools',
                  icon: Icons.handyman_rounded,
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Tool Calling',
                  icon: Icons.handyman_rounded,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Enable Tools'),
                        subtitle: const Text(
                          'Allow model to use external tools',
                        ),
                        value: provider.toolsEnabled,
                        onChanged: (value) =>
                            provider.updateToolsEnabled(value),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text('Force Tool Call'),
                        subtitle: const Text('Enforce JSON output via grammar'),
                        value: provider.forceToolCall,
                        onChanged: provider.toolsEnabled
                            ? (value) => provider.updateForceToolCall(value)
                            : null,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader(
                  context,
                  title: 'Diagnostics',
                  icon: Icons.bug_report_outlined,
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Dart Log Level',
                  subtitle: 'Controls llamadart logger verbosity',
                  icon: Icons.article_outlined,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<LlamaLogLevel>(
                        value: provider.settings.logLevel,
                        isExpanded: true,
                        items: LlamaLogLevel.values.map((level) {
                          return DropdownMenuItem(
                            value: level,
                            child: Text(level.name.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            provider.updateLogLevel(value);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  context,
                  title: 'Native Log Level',
                  subtitle: 'Controls llama.cpp backend verbosity',
                  icon: Icons.settings_input_component_outlined,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<LlamaLogLevel>(
                        value: provider.settings.nativeLogLevel,
                        isExpanded: true,
                        items: LlamaLogLevel.values.map((level) {
                          return DropdownMenuItem(
                            value: level,
                            child: Text(level.name.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            provider.updateNativeLogLevel(value);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData? icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(icon, size: 16, color: colorScheme.primary),
                ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (subtitle != null)
                Flexible(
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: colorScheme.secondary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<GpuBackend> _getAvailableBackends(ChatProvider provider) {
    final Set<GpuBackend> backends = {GpuBackend.auto};

    for (final device in provider.availableDevices) {
      final d = device.toLowerCase();
      if (d.contains('metal') || d.contains('mtl')) {
        backends.add(GpuBackend.metal);
      }
      if (d.contains('vulkan')) backends.add(GpuBackend.vulkan);
      if (d.contains('cuda')) backends.add(GpuBackend.cuda);
      if (d.contains('blas')) backends.add(GpuBackend.blas);
      if (d.contains('cpu') || d.contains('llvm')) backends.add(GpuBackend.cpu);
    }

    final active = provider.activeBackend.toLowerCase();
    if (active.contains('metal') || active.contains('mtl')) {
      backends.add(GpuBackend.metal);
    }
    if (active.contains('vulkan')) backends.add(GpuBackend.vulkan);
    if (active.contains('cuda')) backends.add(GpuBackend.cuda);
    if (active.contains('blas')) backends.add(GpuBackend.blas);
    if (active.contains('cpu') || active.contains('llvm')) {
      backends.add(GpuBackend.cpu);
    }

    if (backends.length == 1) {
      backends.add(GpuBackend.cpu);
    }

    final ordered = backends.toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
    return ordered;
  }

  List<int> _buildContextSizeOptions(int currentValue) {
    final options = <int>{
      0,
      2048,
      4096,
      8192,
      16384,
      32768,
      currentValue,
    }.toList()..sort();
    return options;
  }
}
