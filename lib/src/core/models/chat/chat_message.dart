// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:convert';
import 'chat_role.dart';
import 'content_part.dart';

/// A message in a chat conversation history.
///
/// Supports multi-modality by allowing a list of [parts] (text, image, audio).
class LlamaChatMessage {
  /// New enum-based role (preferred).
  final LlamaChatRole? roleEnum;

  /// Legacy string role (deprecated, will be removed in v1.0).
  @Deprecated('Use roleEnum instead. Will be removed in v1.0')
  final String? roleString;

  final List<LlamaContentPart>? _parts;
  final String? _legacyContent;

  /// BACKWARD-COMPATIBLE: Text-only constructor (existing API).
  ///
  /// This constructor is kept for full backward compatibility with older versions.
  const LlamaChatMessage({required String role, required String content})
    : roleString = role,
      roleEnum = null,
      _legacyContent = content,
      _parts = null;

  /// Convenience constructor for text-only messages.
  ///
  /// For multimodal messages, use the main constructor with [content] as parts.
  const LlamaChatMessage.fromText({
    required LlamaChatRole role,
    required String text,
  }) : roleEnum = role,
       roleString = null,
       _legacyContent = text,
       _parts = null;

  /// Creates a message with multimodal content parts.
  ///
  /// The [content] parameter follows OpenAI's convention where content
  /// is an array of content parts (text, image, audio, etc.).
  const LlamaChatMessage.withContent({
    required LlamaChatRole role,
    required List<LlamaContentPart> content,
  }) : roleEnum = role,
       roleString = null,
       _parts = content,
       _legacyContent = null;

  /// Multimodal content parts.
  List<LlamaContentPart> get parts =>
      _parts ?? [LlamaTextContent(_legacyContent!)];

  /// Unified role getter (prefers enum, falls back to string).
  LlamaChatRole get role =>
      roleEnum ?? LlamaChatRole.values.byName(roleString!);

  /// Backward-compatible content getter (concatenates all text-like parts).
  ///
  /// Note: This excludes [LlamaThinkingContent] (reasoning) by default to ensure
  /// the main response text is returned without internal monologue.
  String get content {
    if (_legacyContent != null) return _legacyContent;
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is LlamaTextContent) {
        buffer.write(part.text);
      } else if (part is LlamaToolCallContent) {
        buffer.write(part.rawJson);
      } else if (part is LlamaToolResultContent) {
        final res = part.result;
        if (res is String) {
          buffer.write(res);
        } else {
          try {
            buffer.write(jsonEncode(res));
          } catch (_) {
            buffer.write(res.toString());
          }
        }
      }
    }
    return buffer.toString();
  }

  /// Extracts reasoning/thinking content from [parts].
  ///
  /// Returns null if no [LlamaThinkingContent] parts are present.
  String? get reasoning {
    final thinkingParts = parts.whereType<LlamaThinkingContent>().toList();
    if (thinkingParts.isEmpty) return null;
    return thinkingParts.map((t) => t.thinking).join('\n').trim();
  }

  /// Creates a copy of this message with updated properties.
  LlamaChatMessage copyWith({
    LlamaChatRole? role,
    String? content,
    List<LlamaContentPart>? parts,
  }) {
    if (parts != null) {
      return LlamaChatMessage.withContent(
        role: role ?? this.role,
        content: parts,
      );
    }

    if (content != null) {
      return LlamaChatMessage.fromText(role: role ?? this.role, text: content);
    }

    // Preserve existing state
    if (_parts != null) {
      return LlamaChatMessage.withContent(
        role: role ?? this.role,
        content: _parts,
      );
    } else {
      return LlamaChatMessage.fromText(
        role: role ?? this.role,
        text: _legacyContent ?? '',
      );
    }
  }

  /// Serializes the message to JSON.
  ///
  /// This implementation follows OpenAI's Chat Completions format while
  /// supporting extensions like `reasoning_content` for reasoning models
  /// (e.g. DeepSeek R1).
  Map<String, dynamic> toJson() {
    final partsList = parts;
    final json = <String, dynamic>{'role': role.name};

    // 1. Extract Thinking (Reasoning)
    // Reasoning models usually separate thoughts from the final answer.
    final thinkingParts = partsList.whereType<LlamaThinkingContent>().toList();
    if (thinkingParts.isNotEmpty) {
      json['reasoning_content'] = thinkingParts
          .map((t) => t.thinking)
          .join('\n');
    }

    // 2. Extract Tool Calls (Assistant)
    final toolCalls = partsList.whereType<LlamaToolCallContent>().toList();
    if (toolCalls.isNotEmpty) {
      json['role'] = 'assistant'; // Tool calls must be from assistant
      json['tool_calls'] = toolCalls.map((t) => t.toJson()).toList();
    }

    // 3. Extract Tool Results (Tool)
    final toolResults = partsList.whereType<LlamaToolResultContent>().toList();
    if (toolResults.isNotEmpty) {
      json['role'] = 'tool';
      final res = toolResults.first;
      json['tool_call_id'] = res.id;
      json['content'] = res.result;
      // Tool messages are usually flat in OpenAI format
      return json;
    }

    // 4. Handle remaining content (Text, Image, Audio)
    final otherParts = partsList
        .where(
          (p) =>
              p is! LlamaThinkingContent &&
              p is! LlamaToolCallContent &&
              p is! LlamaToolResultContent,
        )
        .toList();

    if (otherParts.isEmpty) {
      // If we have reasoning_content or tool_calls but no other content,
      // 'content' should be null (OpenAI spec for assistant messages).
      if (json.containsKey('reasoning_content') ||
          json.containsKey('tool_calls')) {
        json['content'] = null;
      } else {
        json['content'] = '';
      }
    } else {
      final contentJson = otherParts.map((p) => p.toJson()).toList();

      // Simplify content if it's text-only parts (maximize template compatibility)
      if (contentJson.every((p) => p['type'] == 'text')) {
        json['content'] = contentJson.map((p) => p['text'] as String).join('');
      } else {
        json['content'] = contentJson;
      }
    }

    return json;
  }

  /// Serializes the message to JSON, always keeping content as a list of parts.
  ///
  /// Some templates (e.g. SmolVLM) require `content` to be a list of
  /// `{type: 'text', text: '...'}` or `{type: 'image'}` objects.
  /// This method also normalizes OpenAI's `image_url` type to `image`
  /// for HuggingFace Jinja template compatibility.
  Map<String, dynamic> toJsonMultimodal() {
    final json = toJson();
    final content = json['content'];

    if (content is String) {
      // Text was collapsed to a string — expand back to list format
      json['content'] = [
        {'type': 'text', 'text': content},
      ];
    } else if (content is List) {
      // Normalize image_url → image for template compatibility
      json['content'] = content.map((part) {
        if (part is Map<String, dynamic> && part['type'] == 'image_url') {
          return {'type': 'image'};
        }
        return part;
      }).toList();
    }
    return json;
  }
}
