import '../grammar/tool_grammar_generator.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_template_result.dart';
import '../models/tools/tool_definition.dart';
import 'chat_format.dart';
import 'chat_parse_result.dart';
import 'chat_template_handler.dart';
import 'handlers/command_r7b_handler.dart';
import 'handlers/deepseek_r1_handler.dart';
import 'handlers/deepseek_v3_handler.dart';
import 'handlers/function_gemma_handler.dart';
import 'handlers/gemma_handler.dart';
import 'handlers/generic_handler.dart';
import 'handlers/glm45_handler.dart';
import 'handlers/granite_handler.dart';
import 'handlers/hermes_handler.dart';
import 'handlers/kimi_k2_handler.dart';
import 'handlers/lfm2_handler.dart';
import 'handlers/llama3_handler.dart';
import 'handlers/magistral_handler.dart';
import 'handlers/minimax_m2_handler.dart';
import 'handlers/mistral_handler.dart';
import 'handlers/qwen3_coder_xml_handler.dart';
import 'template_caps.dart';
import 'template_workarounds.dart';

/// Orchestrates chat template detection, rendering, and output parsing.
///
/// This is the main entry point for the template module. It:
/// 1. Detects the chat format from the Jinja template source
/// 2. Delegates to the appropriate per-format handler for rendering
/// 3. Provides output parsing via the detected format's handler
///
/// Usage:
/// ```dart
/// final engine = ChatTemplateEngine();
/// final result = engine.render(
///   templateSource: metadata['tokenizer.chat_template'],
///   messages: messages,
///   metadata: metadata,
///   tools: tools,
///   enableThinking: true,
/// );
/// // Later, parse the output:
/// final parsed = engine.parse(result.format, rawOutput);
/// ```
class ChatTemplateEngine {
  /// Singleton handler instances, lazily initialized.
  static final Map<ChatFormat, ChatTemplateHandler> _handlers = {};

  /// Returns the handler for the given [format].
  static ChatTemplateHandler handlerFor(ChatFormat format) {
    return _handlers.putIfAbsent(format, () => _createHandler(format));
  }

  /// Detects the [ChatFormat] from a template source string.
  static ChatFormat detectFormat(String? templateSource) {
    return detectChatFormat(templateSource);
  }

  /// Full rendering pipeline: detect format → get handler → render.
  ///
  /// If the template source is null/empty, uses the ChatML fallback.
  /// If rendering fails, falls back to basic prompt concatenation.
  static LlamaChatTemplateResult render({
    required String? templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
  }) {
    // 1. Select template source (default vs tool_use variant)
    final hasTools = tools != null && tools.isNotEmpty;
    var effectiveTemplate = templateSource;

    if (hasTools && metadata.containsKey('tokenizer.chat_template.tool_use')) {
      effectiveTemplate = metadata['tokenizer.chat_template.tool_use'];
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using tool_use template variant',
      );
    }

    // 2. Detect format
    final format = detectFormat(effectiveTemplate);
    LlamaLogger.instance.debug(
      'ChatTemplateEngine: Detected format=$format from template',
    );

    // Use the generic handler with ChatML fallback for contentOnly
    // or when no template is available
    final effectiveFormat =
        (format == ChatFormat.contentOnly && effectiveTemplate == null)
        ? ChatFormat.generic
        : format;

    final handler = handlerFor(effectiveFormat);

    // 3. Apply workarounds matching llama.cpp
    final caps = TemplateCaps.detect(effectiveTemplate ?? '');
    var effectiveMessages = messages;

    // Workaround: System message not supported -> merge into first user msg
    if (!caps.supportsSystemRole) {
      effectiveMessages = TemplateWorkarounds.applySystemMessageWorkaround(
        messages,
        caps,
      );
    }

    try {
      // Proactively detect templates that access content as a list
      // (e.g. SmolVLM's `message['content'][0]['type']`)
      final needsTypedContent = caps.supportsTypedContent;

      if (needsTypedContent) {
        LlamaLogger.instance.debug(
          'ChatTemplateEngine: Using multimodal content format '
          'for template that accesses content as list',
        );
        return _applyGrammar(
          handler.renderWithMultimodalContent(
            templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
            messages: effectiveMessages,
            metadata: metadata,
            addAssistant: addAssistant,
            tools: tools,
            enableThinking: enableThinking,
          ),
          tools,
          toolChoice,
          responseFormat,
        );
      }

      final baseResult = handler.render(
        templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
        messages: effectiveMessages,
        metadata: metadata,
        addAssistant: addAssistant,
        tools: tools,
        enableThinking: enableThinking,
      );

      // Apply grammar constraints for tool calls or response format
      return _applyGrammar(baseResult, tools, toolChoice, responseFormat);
    } catch (e) {
      LlamaLogger.instance.warning(
        'ChatTemplateEngine: Handler $effectiveFormat failed: $e, '
        'falling back to generic handler',
      );

      // Fall back to generic handler with ChatML template
      final fallback = handlerFor(ChatFormat.generic);
      try {
        return fallback.render(
          templateSource: GenericHandler.chatMlTemplate,
          messages: effectiveMessages,
          metadata: metadata,
          addAssistant: addAssistant,
          tools: tools,
          enableThinking: enableThinking,
        );
      } catch (e2) {
        LlamaLogger.instance.warning(
          'ChatTemplateEngine: Generic fallback also failed: $e2, '
          'using simple concatenation',
        );

        // Ultimate fallback: simple concatenation
        var prompt = effectiveMessages.map((m) => m.content).join('\n');
        if (addAssistant) {
          prompt += '\nAssistant:';
        }
        return LlamaChatTemplateResult(
          prompt: prompt,
          format: ChatFormat.contentOnly.index,
        );
      }
    }
  }

  /// Apply grammar constraints based on tool definitions and response format.
  static LlamaChatTemplateResult _applyGrammar(
    LlamaChatTemplateResult result,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice,
    Map<String, dynamic>? responseFormat,
  ) {
    // If response_format is json_object/json_schema, generate grammar for it
    if (responseFormat != null) {
      final type = responseFormat['type'] as String?;
      if (type == 'json_schema') {
        final schema =
            responseFormat['json_schema']?['schema'] as Map<String, dynamic>?;
        if (schema != null) {
          final grammar = ToolGrammarGenerator.generateForSchema(schema);
          return LlamaChatTemplateResult(
            prompt: result.prompt,
            format: result.format,
            grammar: grammar,
            additionalStops: result.additionalStops,
            preservedTokens: result.preservedTokens,
            thinkingForcedOpen: result.thinkingForcedOpen,
          );
        }
      } else if (type == 'json_object') {
        final grammar = ToolGrammarGenerator.generateForSchema({
          'type': 'object',
        });
        return LlamaChatTemplateResult(
          prompt: result.prompt,
          format: result.format,
          grammar: grammar,
          additionalStops: result.additionalStops,
          preservedTokens: result.preservedTokens,
          thinkingForcedOpen: result.thinkingForcedOpen,
        );
      }
    }

    // If tools are provided and grammar wasn't set by handler, generate it
    if (tools != null &&
        tools.isNotEmpty &&
        toolChoice != ToolChoice.none &&
        result.grammar == null) {
      final grammarResult = ToolGrammarGenerator.generate(
        tools,
        toolChoice: toolChoice,
      );
      if (grammarResult != null) {
        return LlamaChatTemplateResult(
          prompt: result.prompt,
          format: result.format,
          grammar: grammarResult.grammar,
          grammarLazy: grammarResult.grammarLazy,
          additionalStops: result.additionalStops,
          preservedTokens: result.preservedTokens,
          grammarTriggers: grammarResult.grammarTriggers
              .map((t) => GrammarTrigger(type: 0, value: t))
              .toList(),
          thinkingForcedOpen: result.thinkingForcedOpen,
        );
      }
    }

    return result;
  }

  /// Parses raw LLM output using the format's handler.
  ///
  /// The [formatIndex] should come from [LlamaChatTemplateResult.format].
  static ChatParseResult parse(
    int formatIndex,
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final format = formatIndex < ChatFormat.values.length
        ? ChatFormat.values[formatIndex]
        : ChatFormat.generic;

    final handler = handlerFor(format);
    try {
      return handler.parse(
        output,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
      );
    } catch (e) {
      // If parsing fails during streaming (partial), rethrow so caller handles it.
      // If final parse fails, fall back to content-only parse.
      if (isPartial) rethrow;

      LlamaLogger.instance.warning(
        'ChatTemplateEngine: Parse failed for $format: $e. '
        'Falling back to content-only.',
      );
      return ChatParseResult(content: output.trim());
    }
  }

  /// Creates a handler instance for the given format.
  static ChatTemplateHandler _createHandler(ChatFormat format) {
    switch (format) {
      case ChatFormat.hermes:
        return HermesHandler();
      case ChatFormat.llama3:
        return Llama3Handler();
      case ChatFormat.mistralNemo:
        return MistralHandler();
      case ChatFormat.magistral:
        return MagistralHandler();
      case ChatFormat.lfm2:
        return Lfm2Handler();
      case ChatFormat.deepseekR1:
        return DeepseekR1Handler();
      case ChatFormat.deepseekV3:
        return DeepseekV3Handler();
      case ChatFormat.functionGemma:
        return FunctionGemmaHandler();
      case ChatFormat.gemma:
        return GemmaHandler();
      case ChatFormat.commandR7B:
        return CommandR7BHandler();
      case ChatFormat.granite:
        return GraniteHandler();
      case ChatFormat.glm45:
        return Glm45Handler();
      case ChatFormat.kimiK2:
        return KimiK2Handler();
      case ChatFormat.qwen3CoderXml:
        return Qwen3CoderXmlHandler();
      case ChatFormat.minimaxM2:
        return MinimaxM2Handler();
      case ChatFormat.generic:
      case ChatFormat.contentOnly:
        return GenericHandler();
    }
  }
}
