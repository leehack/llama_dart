/// Identifies the chat format detected from a model's template source.
///
/// Each format corresponds to a specific model family's tool calling
/// convention, with dedicated rendering and parsing logic.
///
/// See llama.cpp's `common_chat_format` enum for the reference implementation.
enum ChatFormat {
  /// No tool call support — plain text-only models.
  contentOnly,

  /// ChatML-based generic handler (JSON tool call wrapping).
  /// Fallback for models using `<|im_start|>/<|im_end|>` without
  /// a more specific tool call format.
  generic,

  /// Hermes 2 Pro / Qwen 2.5 / Qwen 3 — `<tool_call>` XML tags.
  hermes,

  /// Llama 3.x — ipython role with `<|python_tag|>`.
  llama3,

  /// Mistral Nemo — `[TOOL_CALLS]` prefix with JSON array.
  mistralNemo,

  /// Magistral — `[THINK]`/`[/THINK]` thinking + `[TOOL_CALLS]` prefix.
  magistral,

  /// LFM2 — `<|tool_call_start|>/<|tool_call_end|>` special tokens.
  lfm2,

  /// DeepSeek R1 — fullwidth unicode delimiters.
  deepseekR1,

  /// DeepSeek V3.1 — prefix-based thinking with `<tool_call>` tags.
  deepseekV3,

  /// FunctionGemma — `<start_function_call>call:name{args}<end_function_call>`.
  functionGemma,

  /// Gemma 3 / Gemma 3n — `<start_of_turn>/<end_of_turn>` with
  /// prompt-engineered tool calling and multimodal support.
  gemma,

  /// Command R7B — `<|START_ACTION|>/<|END_ACTION|>` with thinking.
  commandR7B,

  /// Granite — `<|tool_call|>` + JSON array with `<think>` support.
  granite,

  /// GLM 4.5 — `<|observation|>` with XML-style arg_key/arg_value.
  glm45,

  /// Kimi K2 — `<|tool_call_begin|>` with special tokens.
  kimiK2,

  /// Qwen3 Coder XML — `<function=name><parameter=key>` format.
  qwen3CoderXml,

  /// MiniMax M2 — `<minimax:tool_call>` with `<invoke>` tags.
  minimaxM2,
}

/// Detects the [ChatFormat] by scanning a Jinja template source string
/// for signature tokens, following llama.cpp's priority order.
///
/// Returns [ChatFormat.contentOnly] if `templateSource` is null or empty.
/// Falls back to [ChatFormat.generic] if no specific pattern is matched
/// but ChatML tokens are present.
ChatFormat detectChatFormat(String? templateSource) {
  if (templateSource == null || templateSource.isEmpty) {
    return ChatFormat.contentOnly;
  }

  // DeepSeek R1 — fullwidth unicode delimiters (highest priority)
  if (templateSource.contains('<｜tool▁calls▁begin｜>')) {
    return ChatFormat.deepseekR1;
  }

  // DeepSeek V3.1 — prefix-based thinking
  if (templateSource.contains("message['prefix'] is defined") &&
      templateSource.contains('thinking')) {
    return ChatFormat.deepseekV3;
  }

  // Command R7B — START_ACTION/END_ACTION pattern
  if (templateSource.contains('<|START_ACTION|>')) {
    return ChatFormat.commandR7B;
  }

  // Kimi K2 — tool_calls_section tokens
  if (templateSource.contains('<|tool_calls_section_begin|>')) {
    return ChatFormat.kimiK2;
  }

  // GLM 4.5 — observation tag with arg_key/arg_value XML
  if (templateSource.contains('<|observation|>')) {
    return ChatFormat.glm45;
  }

  // Granite — tool_call with endoftext pattern
  if (templateSource.contains('<|tool_call|>')) {
    return ChatFormat.granite;
  }

  // MiniMax M2 — minimax:tool_call tags
  if (templateSource.contains('<minimax:tool_call>')) {
    return ChatFormat.minimaxM2;
  }

  // Qwen3 Coder XML — <function= pattern (NOT standard <tool_call>)
  if (templateSource.contains('<function=') &&
      templateSource.contains('<parameter=')) {
    return ChatFormat.qwen3CoderXml;
  }

  // Magistral — has both [THINK] and [TOOL_CALLS] (before Mistral Nemo)
  if (templateSource.contains('[TOOL_CALLS]') &&
      templateSource.contains('[THINK]')) {
    return ChatFormat.magistral;
  }

  // Hermes 2 Pro / Qwen — <tool_call> tags (but NOT FunctionGemma)
  if (templateSource.contains('<tool_call>') &&
      !templateSource.contains('<start_function_call>')) {
    return ChatFormat.hermes;
  }

  // Llama 3.x — ipython role
  if (templateSource.contains('<|start_header_id|>ipython<|end_header_id|>')) {
    return ChatFormat.llama3;
  }

  // Mistral Nemo — [TOOL_CALLS] prefix (after Magistral check)
  if (templateSource.contains('[TOOL_CALLS]')) {
    return ChatFormat.mistralNemo;
  }

  // LFM2 — tool list tokens
  if (templateSource.contains('<|tool_list_start|>')) {
    return ChatFormat.lfm2;
  }

  // FunctionGemma — function call tokens
  if (templateSource.contains('<start_function_call>')) {
    return ChatFormat.functionGemma;
  }

  // Gemma 3/3n — start_of_turn without other markers
  if (templateSource.contains('<start_of_turn>') &&
      !templateSource.contains('<|im_start|>')) {
    return ChatFormat.gemma;
  }

  // ChatML fallback — <|im_start|> tokens
  if (templateSource.contains('<|im_start|>')) {
    return ChatFormat.generic;
  }

  // No recognized pattern
  return ChatFormat.contentOnly;
}
