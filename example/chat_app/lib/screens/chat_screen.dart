import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';
import '../widgets/pruning_indicator.dart';
import '../widgets/runtime_status_panel.dart';
import '../widgets/welcome_view.dart';
import 'manage_models_screen.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? onOpenModelSelection;

  const ChatScreen({super.key, this.onOpenModelSelection});

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

    final diff = _distanceFromBottom();
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
    final shouldAutoFollowAfterGeneration = _distanceFromBottom() < 1200;

    if (provider.isGenerating) {
      _scrollToBottom();
    }

    if (_wasGenerating && !provider.isGenerating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        if (shouldAutoFollowAfterGeneration) {
          _scrollToBottom(force: true);
        }
        if (provider.isReady) {
          _focusNode.requestFocus();
        }
      });
    }
    _wasGenerating = provider.isGenerating;
  }

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    final diff = _distanceFromBottom();

    if (force || diff < 50) {
      _scrollController.jumpTo(pos.maxScrollExtent);
    } else if (diff < 500) {
      _scrollController.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    if (_showScrollToBottom) {
      setState(() {
        _showScrollToBottom = false;
      });
    }
  }

  double _distanceFromBottom() {
    if (!_scrollController.hasClients) {
      return 0;
    }

    final pos = _scrollController.position;
    final distance = pos.maxScrollExtent - pos.pixels;
    return distance < 0 ? 0 : distance;
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    final provider = context.read<ChatProvider>();
    if (text.isEmpty && provider.stagedParts.isEmpty) return;

    provider.sendMessage(text);
    _controller.value = TextEditingValue.empty;
    _focusNode.requestFocus();
  }

  void _openModelSelection() {
    final callback = widget.onOpenModelSelection;
    if (callback != null) {
      callback();
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ManageModelsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surfaceContainerLowest.withValues(alpha: 0.94),
            colorScheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -64,
            child: IgnorePointer(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: 0.07),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -130,
            left: -90,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.tertiary.withValues(alpha: 0.06),
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

                    final topPadding = provider.isReady ? 88.0 : 28.0;

                    return ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 24),
                      itemCount: provider.messages.length,
                      itemBuilder: (context, index) {
                        final message = provider.messages[index];
                        var isNextSame = false;
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
          const Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: RuntimeStatusPanel(),
          ),
          if (_showScrollToBottom)
            Positioned(
              right: 20,
              bottom: 100,
              child: FloatingActionButton.small(
                heroTag: 'scroll-to-bottom',
                onPressed: _scrollToBottom,
                tooltip: 'Jump to latest',
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
