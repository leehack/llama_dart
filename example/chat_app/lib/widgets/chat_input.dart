import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llamadart/llamadart.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class ChatInput extends StatefulWidget {
  final VoidCallback onSend;
  final TextEditingController controller;
  final FocusNode focusNode;

  const ChatInput({
    super.key,
    required this.onSend,
    required this.controller,
    required this.focusNode,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final isGenerating = provider.isGenerating;
        final enabled = !isGenerating && provider.isReady;

        return Container(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.stagedParts.isNotEmpty)
                Container(
                  height: 80,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: provider.stagedParts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final part = provider.stagedParts[index];
                      return Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _buildPartPreview(part),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => provider.removeStagedPart(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              Row(
                children: [
                  if (provider.supportsVision || provider.supportsAudio)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onSelected: (value) {
                        if (value == 'image') {
                          provider.pickImage();
                        } else if (value == 'audio') {
                          provider.pickAudio();
                        }
                      },
                      itemBuilder: (context) => [
                        if (provider.supportsVision)
                          const PopupMenuItem(
                            value: 'image',
                            child: Row(
                              children: [
                                Icon(Icons.image_outlined),
                                SizedBox(width: 12),
                                Text('Attach Image'),
                              ],
                            ),
                          ),
                        if (provider.supportsAudio)
                          const PopupMenuItem(
                            value: 'audio',
                            child: Row(
                              children: [
                                Icon(Icons.audiotrack_outlined),
                                SizedBox(width: 12),
                                Text('Attach Audio'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            includeRepeats: false,
                          ): widget.onSend,
                        },
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          enabled: enabled,
                          maxLines: 6,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (enabled) {
                              widget.onSend();
                            }
                          },
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: enabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: isGenerating
                          ? () => provider.stopGeneration()
                          : (enabled ? widget.onSend : null),
                      icon: isGenerating
                          ? Icon(
                              Icons.stop_rounded,
                              color: Theme.of(context).colorScheme.error,
                            )
                          : Icon(
                              Icons.arrow_upward_rounded,
                              color: enabled
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPartPreview(LlamaContentPart part) {
    if (part is LlamaImageContent) {
      if (part.path != null) {
        return Image.file(File(part.path!), fit: BoxFit.cover);
      } else if (part.bytes != null) {
        return Image.memory(part.bytes!, fit: BoxFit.cover);
      }
    } else if (part is LlamaAudioContent) {
      return const Center(child: Icon(Icons.audiotrack, size: 32));
    }
    return const Center(child: Icon(Icons.description, size: 32));
  }
}
