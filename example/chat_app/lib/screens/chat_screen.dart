import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import 'model_selection_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/welcome_view.dart';
import '../widgets/chat_app_bar_title.dart';
import '../widgets/pruning_indicator.dart';
import '../widgets/clear_chat_button.dart';
import '../widgets/settings_icon.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _wasGenerating = false;
  bool _showScrollToBottom = false;
  ChatProvider? _providerForListener;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ChatProvider>();
      _providerForListener = provider;
      if (provider.modelPath == null) {
        _openModelSelection();
      }
      provider.addListener(_onProviderUpdate);
    });
  }

  @override
  void dispose() {
    _providerForListener?.removeListener(_onProviderUpdate);
    _scrollController.removeListener(_onScrollChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;

    final diff =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final shouldShow = diff > 220;

    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() {
        _showScrollToBottom = shouldShow;
      });
    }
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    if (provider.isGenerating) {
      _scrollToBottom();
    }

    if (_wasGenerating && !provider.isGenerating && provider.isReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
    _wasGenerating = provider.isGenerating;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      final diff = pos.maxScrollExtent - pos.pixels;

      if (diff < 50) {
        _scrollController.jumpTo(pos.maxScrollExtent);
      } else if (diff < 500) {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }

      if (_showScrollToBottom) {
        setState(() {
          _showScrollToBottom = false;
        });
      }
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    final provider = context.read<ChatProvider>();
    if (text.isEmpty && provider.stagedParts.isEmpty) return;

    provider.sendMessage(text);

    // Reset the controller completely to clear any composing state from the IME.
    // Using TextEditingValue.empty is more robust than .clear() for some IMEs.
    _controller.value = TextEditingValue.empty;

    _focusNode.requestFocus();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _openModelSelection() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ModelSelectionScreen()),
    );
  }

  void _showModelSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) =>
          SettingsSheet(onOpenModelSelection: _openModelSelection),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
              colorScheme.surface,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -160,
              left: -100,
              child: IgnorePointer(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.secondary.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                const PruningIndicator(),
                Expanded(
                  child: Consumer<ChatProvider>(
                    builder: (context, provider, _) {
                      if (provider.messages.isEmpty) {
                        return WelcomeView(
                          isInitializing: provider.isInitializing,
                          error: provider.error,
                          modelPath: provider.modelPath,
                          isLoaded: provider.isLoaded,
                          loadingProgress: provider.loadingProgress,
                          onRetry: () => provider.loadModel(),
                          onSelectModel: _openModelSelection,
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 120, 16, 24),
                        itemCount: provider.messages.length,
                        itemBuilder: (context, index) {
                          final message = provider.messages[index];
                          bool isNextSame = false;
                          if (index + 1 < provider.messages.length) {
                            isNextSame =
                                provider.messages[index + 1].isUser ==
                                message.isUser;
                          }
                          return MessageBubble(
                            message: message,
                            isNextSame: isNextSame,
                          );
                        },
                      );
                    },
                  ),
                ),
                ChatInput(
                  onSend: _sendMessage,
                  controller: _controller,
                  focusNode: _focusNode,
                ),
              ],
            ),
            if (_showScrollToBottom)
              Positioned(
                right: 20,
                bottom: 96,
                child: FloatingActionButton.small(
                  heroTag: 'scroll-to-bottom',
                  onPressed: _scrollToBottom,
                  tooltip: 'Jump to latest',
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.8),
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: const ChatAppBarTitle(),
      actions: [
        const ClearChatButton(),
        IconButton(
          onPressed: _showModelSettings,
          icon: const SettingsIcon(),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
