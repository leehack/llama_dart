import '../grammar/tool_grammar_generator.dart' as grammar;
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/content_part.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import 'chat_format.dart';
import 'chat_parse_result.dart';
import 'chat_template_handler.dart';
import 'handlers/command_r7b_handler.dart';
import 'handlers/deepseek_r1_handler.dart';
import 'handlers/deepseek_v3_handler.dart';
import 'handlers/apertus_handler.dart';
import 'handlers/apriel15_handler.dart';
import 'handlers/exaone_moe_handler.dart';
import 'handlers/firefunction_v2_handler.dart';
import 'handlers/function_gemma_handler.dart';
import 'handlers/functionary_v31_llama31_handler.dart';
import 'handlers/functionary_v32_handler.dart';
import 'handlers/gemma_handler.dart';
import 'handlers/generic_handler.dart';
import 'handlers/glm45_handler.dart';
import 'handlers/gpt_oss_handler.dart';
import 'handlers/granite_handler.dart';
import 'handlers/hermes_handler.dart';
import 'handlers/kimi_k2_handler.dart';
import 'handlers/lfm2_handler.dart';
import 'handlers/llama3_handler.dart';
import 'handlers/magistral_handler.dart';
import 'handlers/minimax_m2_handler.dart';
import 'handlers/mistral_handler.dart';
import 'handlers/nemotron_v2_handler.dart';
import 'handlers/qwen3_coder_xml_handler.dart';
import 'handlers/seed_oss_handler.dart';
import 'handlers/solar_open_handler.dart';
import 'handlers/translate_gemma_handler.dart';
import 'handlers/xiaomi_mimo_handler.dart';
import 'template_caps.dart';
import 'template_workarounds.dart';

/// Predicate used to match a custom template handler or template override.
typedef ChatTemplateMatcher = bool Function(ChatTemplateRoutingContext context);

/// Context passed to custom handler/template matchers.
class ChatTemplateRoutingContext {
  /// The current template source selected from metadata.
  final String? templateSource;

  /// The model metadata for this render request.
  final Map<String, String> metadata;

  /// The messages that will be rendered.
  final List<LlamaChatMessage> messages;

  /// Whether this request includes tools.
  final bool hasTools;

  /// Creates a new routing context.
  const ChatTemplateRoutingContext({
    required this.templateSource,
    required this.metadata,
    required this.messages,
    required this.hasTools,
  });
}

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

  static const Set<ChatFormat> _schemaDisabledFormats = {
    ChatFormat.deepseekV3,
    ChatFormat.deepseekR1,
    ChatFormat.commandR7B,
    ChatFormat.glm45,
    ChatFormat.hermes,
  };

  static const Set<ChatFormat> _requiredKeepsLazyFormats = {
    ChatFormat.apertus,
    ChatFormat.nemotronV2,
    ChatFormat.lfm2,
  };

  /// Custom handlers registered by user code.
  static final Map<String, _RegisteredHandler> _customHandlers = {};

  /// Custom template overrides registered by user code.
  static final Map<String, _RegisteredTemplateOverride> _templateOverrides = {};

  /// IDs of currently registered custom handlers.
  static List<String> get customHandlerIds => _customHandlers.keys.toList();

  /// IDs of currently registered template overrides.
  static List<String> get templateOverrideIds =>
      _templateOverrides.keys.toList();

  /// Registers a custom chat template [handler].
  ///
  /// If [matcher] is provided, this handler can be selected automatically
  /// during [render] when the matcher returns true.
  ///
  /// If a handler with the same [id] already exists, it is replaced.
  static void registerHandler({
    required String id,
    required ChatTemplateHandler handler,
    ChatTemplateMatcher? matcher,
  }) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Handler id must not be empty.');
    }

    _customHandlers[normalizedId] = _RegisteredHandler(
      id: normalizedId,
      handler: handler,
      matcher: matcher,
    );
  }

  /// Unregisters a custom handler by [id].
  ///
  /// Returns true if a handler was removed.
  static bool unregisterHandler(String id) {
    return _customHandlers.remove(id) != null;
  }

  /// Clears all registered custom handlers.
  static void clearCustomHandlers() {
    _customHandlers.clear();
  }

  /// Registers a custom template override.
  ///
  /// The [matcher] decides when this override applies. If omitted, the
  /// override applies to all requests (unless a per-call custom template is
  /// provided).
  ///
  /// If an override with the same [id] already exists, it is replaced.
  static void registerTemplateOverride({
    required String id,
    required String templateSource,
    ChatTemplateMatcher? matcher,
  }) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Override id must not be empty.');
    }

    if (templateSource.trim().isEmpty) {
      throw ArgumentError.value(
        templateSource,
        'templateSource',
        'Template source must not be empty.',
      );
    }

    _templateOverrides[normalizedId] = _RegisteredTemplateOverride(
      id: normalizedId,
      templateSource: templateSource,
      matcher: matcher ?? (_) => true,
    );
  }

  /// Unregisters a template override by [id].
  ///
  /// Returns true if an override was removed.
  static bool unregisterTemplateOverride(String id) {
    return _templateOverrides.remove(id) != null;
  }

  /// Clears all registered template overrides.
  static void clearTemplateOverrides() {
    _templateOverrides.clear();
  }

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
    String? customTemplate,
    String? customHandlerId,
  }) {
    // 1. Select template source (default vs tool_use variant)
    final hasTools = tools != null && tools.isNotEmpty;
    var metadataTemplate = templateSource;

    if (hasTools && metadata.containsKey('tokenizer.chat_template.tool_use')) {
      metadataTemplate = metadata['tokenizer.chat_template.tool_use'];
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using tool_use template variant',
      );
    }

    final metadataContext = ChatTemplateRoutingContext(
      templateSource: metadataTemplate,
      metadata: metadata,
      messages: messages,
      hasTools: hasTools,
    );

    var effectiveTemplate = customTemplate;
    if (effectiveTemplate != null) {
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using per-call custom template override',
      );
    } else {
      final override = _resolveTemplateOverride(metadataContext);
      if (override != null) {
        effectiveTemplate = override.templateSource;
        LlamaLogger.instance.debug(
          'ChatTemplateEngine: Applied template override id=${override.id}',
        );
      } else {
        effectiveTemplate = metadataTemplate;
      }
    }

    final routingContext = ChatTemplateRoutingContext(
      templateSource: effectiveTemplate,
      metadata: metadata,
      messages: messages,
      hasTools: hasTools,
    );

    final customHandler = _resolveCustomHandler(
      routingContext,
      explicitHandlerId: customHandlerId,
    );

    final selectedHandlerId = customHandler?.id;
    final selectedHandler = customHandler?.handler;
    final hasSchemaResponseFormat = _hasSchemaResponseFormat(responseFormat);

    ChatFormat effectiveFormat;
    if (selectedHandler != null) {
      effectiveFormat = selectedHandler.format;
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Selected custom handler id=$selectedHandlerId '
        'format=$effectiveFormat',
      );
    } else {
      final format = detectFormat(effectiveTemplate);
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Detected format=$format from template',
      );

      // Match llama.cpp schema-aware routing: tools + schema falls back to
      // generic routing, and some format handlers are disabled with schema.
      if (hasTools && hasSchemaResponseFormat) {
        effectiveFormat = ChatFormat.generic;
      } else if (hasSchemaResponseFormat &&
          _schemaDisabledFormats.contains(format)) {
        effectiveFormat = hasTools
            ? ChatFormat.generic
            : ChatFormat.contentOnly;
      } else {
        effectiveFormat = format;
      }

      // Use generic handler fallback only when there is no template at all.
      if (effectiveFormat == ChatFormat.contentOnly &&
          effectiveTemplate == null) {
        effectiveFormat = ChatFormat.generic;
      }
    }

    final handler = selectedHandler ?? handlerFor(effectiveFormat);

    // 3. Apply workarounds matching llama.cpp
    final caps = TemplateCaps.detect(effectiveTemplate ?? '');
    var effectiveMessages = messages;

    if (hasTools && caps.supportsToolCalls && !caps.supportsTools) {
      LlamaLogger.instance.warning(
        'ChatTemplateEngine: Template appears to support tool-call output but '
        'does not advertise tool definitions. Results may be unreliable; '
        'consider overriding the chat template.',
      );
    }

    // Workarounds mirror llama.cpp preprocessing chain.
    // Apply only to built-in routing; custom handlers are expected to own
    // their message preprocessing semantics.
    if (selectedHandler == null) {
      if (!caps.supportsSystemRole) {
        effectiveMessages = TemplateWorkarounds.applySystemMessageWorkaround(
          effectiveMessages,
          caps,
        );
      }

      try {
        effectiveMessages = TemplateWorkarounds.applyFormatWorkarounds(
          effectiveMessages,
          effectiveFormat,
        );
      } catch (e) {
        LlamaLogger.instance.warning(
          'ChatTemplateEngine: Format workarounds failed for '
          '$effectiveFormat: $e. Continuing without them.',
        );
      }
    }

    try {
      // Proactively detect templates that access content as a list
      // (e.g. SmolVLM's `message['content'][0]['type']`)
      final hasMediaParts = effectiveMessages.any(
        (message) => message.parts.any(
          (part) => part is LlamaImageContent || part is LlamaAudioContent,
        ),
      );
      final needsTypedContent = caps.supportsTypedContent && hasMediaParts;

      if (needsTypedContent) {
        LlamaLogger.instance.debug(
          'ChatTemplateEngine: Using multimodal content format '
          'for template that accesses content as list',
        );
        var rendered = _withHandlerId(
          handler.renderWithMultimodalContent(
            templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
            messages: effectiveMessages,
            metadata: metadata,
            addAssistant: addAssistant,
            tools: tools,
            enableThinking: enableThinking,
          ),
          selectedHandlerId,
        );
        if (effectiveFormat == ChatFormat.contentOnly) {
          rendered = _withFormat(rendered, ChatFormat.contentOnly.index);
        }

        final withGrammar = _applyGrammar(
          rendered,
          tools,
          toolChoice,
          responseFormat,
        );
        return _normalizeGrammarLazyForToolChoice(withGrammar, toolChoice);
      }

      var baseResult = _withHandlerId(
        handler.render(
          templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
          messages: effectiveMessages,
          metadata: metadata,
          addAssistant: addAssistant,
          tools: tools,
          enableThinking: enableThinking,
        ),
        selectedHandlerId,
      );

      if (effectiveFormat == ChatFormat.contentOnly) {
        baseResult = _withFormat(baseResult, ChatFormat.contentOnly.index);
      }

      // Apply grammar constraints for tool calls or response format
      final withGrammar = _applyGrammar(
        baseResult,
        tools,
        toolChoice,
        responseFormat,
      );
      return _normalizeGrammarLazyForToolChoice(withGrammar, toolChoice);
    } catch (e) {
      LlamaLogger.instance.warning(
        'ChatTemplateEngine: Handler $effectiveFormat failed: $e, '
        'falling back to generic handler',
      );

      // Fall back to generic handler with ChatML template
      final fallback = handlerFor(ChatFormat.generic);
      try {
        final fallbackResult = _applyGrammar(
          _withHandlerId(
            fallback.render(
              templateSource: GenericHandler.chatMlTemplate,
              messages: effectiveMessages,
              metadata: metadata,
              addAssistant: addAssistant,
              tools: tools,
              enableThinking: enableThinking,
            ),
            null,
          ),
          tools,
          toolChoice,
          responseFormat,
        );
        return _normalizeGrammarLazyForToolChoice(fallbackResult, toolChoice);
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
          final grammarText = grammar.ToolGrammarGenerator.generateForSchema(
            schema,
          );
          return LlamaChatTemplateResult(
            prompt: result.prompt,
            format: result.format,
            grammar: grammarText,
            grammarLazy: result.grammarLazy,
            additionalStops: result.additionalStops,
            preservedTokens: result.preservedTokens,
            grammarTriggers: result.grammarTriggers,
            thinkingForcedOpen: result.thinkingForcedOpen,
            parser: result.parser,
            tokenCount: result.tokenCount,
            handlerId: result.handlerId,
          );
        }
      } else if (type == 'json_object') {
        final grammarText = grammar.ToolGrammarGenerator.generateForSchema({
          'type': 'object',
        });
        return LlamaChatTemplateResult(
          prompt: result.prompt,
          format: result.format,
          grammar: grammarText,
          grammarLazy: result.grammarLazy,
          additionalStops: result.additionalStops,
          preservedTokens: result.preservedTokens,
          grammarTriggers: result.grammarTriggers,
          thinkingForcedOpen: result.thinkingForcedOpen,
          parser: result.parser,
          tokenCount: result.tokenCount,
          handlerId: result.handlerId,
        );
      }
    }

    // If tools are provided and grammar wasn't set by handler, generate it
    // only for generic/content-only routing. Format-specific handlers should
    // provide their own grammar semantics (or leave unconstrained), matching
    // llama.cpp behavior more closely.
    final resultFormat = result.format < ChatFormat.values.length
        ? ChatFormat.values[result.format]
        : ChatFormat.generic;
    final allowGenericToolGrammar =
        resultFormat == ChatFormat.generic ||
        resultFormat == ChatFormat.contentOnly;

    if (tools != null &&
        tools.isNotEmpty &&
        toolChoice != ToolChoice.none &&
        result.grammar == null &&
        allowGenericToolGrammar) {
      final grammarResult = grammar.ToolGrammarGenerator.generate(
        tools,
        toolChoice: _toGrammarToolChoice(toolChoice),
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
          parser: result.parser,
          tokenCount: result.tokenCount,
          handlerId: result.handlerId,
        );
      }
    }

    return result;
  }

  static LlamaChatTemplateResult _normalizeGrammarLazyForToolChoice(
    LlamaChatTemplateResult result,
    ToolChoice toolChoice,
  ) {
    if (toolChoice != ToolChoice.required || !result.grammarLazy) {
      return result;
    }
    if (result.grammar == null || result.grammar!.isEmpty) {
      return result;
    }

    final resultFormat = result.format < ChatFormat.values.length
        ? ChatFormat.values[result.format]
        : ChatFormat.generic;
    if (_requiredKeepsLazyFormats.contains(resultFormat)) {
      return result;
    }

    return LlamaChatTemplateResult(
      prompt: result.prompt,
      format: result.format,
      grammar: result.grammar,
      grammarLazy: false,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: result.grammarTriggers,
      thinkingForcedOpen: result.thinkingForcedOpen,
      parser: result.parser,
      tokenCount: result.tokenCount,
      handlerId: result.handlerId,
    );
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
    String? handlerId,
  }) {
    final resolved = _resolveHandlerForParse(
      formatIndex: formatIndex,
      handlerId: handlerId,
    );
    final handler = resolved.handler;
    final format = resolved.format;

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

  /// Returns the thinking tags used by the selected parser handler.
  static ({String startTag, String endTag}) thinkingTagsFor(
    int formatIndex, {
    String? handlerId,
  }) {
    final resolved = _resolveHandlerForParse(
      formatIndex: formatIndex,
      handlerId: handlerId,
    );
    return (
      startTag: resolved.handler.thinkingStartTag,
      endTag: resolved.handler.thinkingEndTag,
    );
  }

  /// Creates a handler instance for the given format.
  static ChatTemplateHandler _createHandler(ChatFormat format) {
    switch (format) {
      case ChatFormat.hermes:
        return HermesHandler();
      case ChatFormat.llama3:
      case ChatFormat.llama3BuiltinTools:
        return Llama3Handler();
      case ChatFormat.firefunctionV2:
        return FirefunctionV2Handler();
      case ChatFormat.functionaryV32:
        return FunctionaryV32Handler();
      case ChatFormat.functionaryV31Llama31:
        return FunctionaryV31Llama31Handler();
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
      case ChatFormat.gptOss:
        return GptOssHandler();
      case ChatFormat.seedOss:
        return SeedOssHandler();
      case ChatFormat.nemotronV2:
        return NemotronV2Handler();
      case ChatFormat.apertus:
        return ApertusHandler();
      case ChatFormat.xiaomiMimo:
        return XiaomiMimoHandler();
      case ChatFormat.apriel15:
        return Apriel15Handler();
      case ChatFormat.solarOpen:
        return SolarOpenHandler();
      case ChatFormat.exaoneMoe:
        return ExaoneMoeHandler();
      case ChatFormat.translateGemma:
        return TranslateGemmaHandler();
      case ChatFormat.pegSimple:
      case ChatFormat.pegNative:
      case ChatFormat.pegConstructed:
        return GenericHandler();
      case ChatFormat.generic:
      case ChatFormat.contentOnly:
        return GenericHandler();
    }
  }

  static bool _hasSchemaResponseFormat(Map<String, dynamic>? responseFormat) {
    if (responseFormat == null) {
      return false;
    }

    final type = responseFormat['type'] as String?;
    return type == 'json_schema' || type == 'json_object';
  }

  static LlamaChatTemplateResult _withHandlerId(
    LlamaChatTemplateResult result,
    String? handlerId,
  ) {
    if (result.handlerId == handlerId) {
      return result;
    }

    return LlamaChatTemplateResult(
      prompt: result.prompt,
      format: result.format,
      grammar: result.grammar,
      grammarLazy: result.grammarLazy,
      thinkingForcedOpen: result.thinkingForcedOpen,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: result.grammarTriggers,
      parser: result.parser,
      tokenCount: result.tokenCount,
      handlerId: handlerId,
    );
  }

  static LlamaChatTemplateResult _withFormat(
    LlamaChatTemplateResult result,
    int format,
  ) {
    if (result.format == format) {
      return result;
    }

    return LlamaChatTemplateResult(
      prompt: result.prompt,
      format: format,
      grammar: result.grammar,
      grammarLazy: result.grammarLazy,
      thinkingForcedOpen: result.thinkingForcedOpen,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: result.grammarTriggers,
      parser: result.parser,
      tokenCount: result.tokenCount,
      handlerId: result.handlerId,
    );
  }

  static _RegisteredTemplateOverride? _resolveTemplateOverride(
    ChatTemplateRoutingContext context,
  ) {
    for (final entry in _templateOverrides.values.toList().reversed) {
      if (entry.matcher(context)) {
        return entry;
      }
    }

    return null;
  }

  static _RegisteredHandler? _resolveCustomHandler(
    ChatTemplateRoutingContext context, {
    String? explicitHandlerId,
  }) {
    if (explicitHandlerId != null) {
      final explicit = _customHandlers[explicitHandlerId];
      if (explicit == null) {
        throw ArgumentError.value(
          explicitHandlerId,
          'customHandlerId',
          'No custom handler is registered with this id.',
        );
      }

      return explicit;
    }

    for (final entry in _customHandlers.values.toList().reversed) {
      final matcher = entry.matcher;
      if (matcher != null && matcher(context)) {
        return entry;
      }
    }

    return null;
  }

  static ({ChatTemplateHandler handler, ChatFormat format})
  _resolveHandlerForParse({required int formatIndex, String? handlerId}) {
    if (handlerId != null) {
      final custom = _customHandlers[handlerId];
      if (custom != null) {
        return (handler: custom.handler, format: custom.handler.format);
      }

      LlamaLogger.instance.warning(
        'ChatTemplateEngine: Unknown custom handler id=$handlerId. '
        'Falling back to format index parsing.',
      );
    }

    final format = formatIndex < ChatFormat.values.length
        ? ChatFormat.values[formatIndex]
        : ChatFormat.generic;
    return (handler: handlerFor(format), format: format);
  }

  static grammar.ToolChoice _toGrammarToolChoice(ToolChoice toolChoice) {
    switch (toolChoice) {
      case ToolChoice.none:
        return grammar.ToolChoice.none;
      case ToolChoice.required:
        return grammar.ToolChoice.required;
      case ToolChoice.auto:
        return grammar.ToolChoice.auto;
    }
  }
}

class _RegisteredHandler {
  final String id;
  final ChatTemplateHandler handler;
  final ChatTemplateMatcher? matcher;

  const _RegisteredHandler({
    required this.id,
    required this.handler,
    required this.matcher,
  });
}

class _RegisteredTemplateOverride {
  final String id;
  final String templateSource;
  final ChatTemplateMatcher matcher;

  const _RegisteredTemplateOverride({
    required this.id,
    required this.templateSource,
    required this.matcher,
  });
}
