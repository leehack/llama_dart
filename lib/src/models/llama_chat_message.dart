// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:convert';
import 'llama_chat_role.dart';
import 'llama_content_part.dart';

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

  /// NEW: Enum-based text-only constructor.
  const LlamaChatMessage.text({
    required LlamaChatRole role,
    required String content,
  }) : roleEnum = role,
       roleString = null,
       _legacyContent = content,
       _parts = null;

  /// NEW: Multimodal constructor.
  const LlamaChatMessage.multimodal({
    required LlamaChatRole role,
    required List<LlamaContentPart> parts,
  }) : roleEnum = role,
       roleString = null,
       _parts = parts,
       _legacyContent = null;

  /// Multimodal content parts.
  List<LlamaContentPart> get parts =>
      _parts ?? [LlamaTextContent(_legacyContent!)];

  /// Unified role getter (prefers enum, falls back to string).
  LlamaChatRole get role =>
      roleEnum ?? LlamaChatRole.values.byName(roleString!);

  /// Backward-compatible content getter (concatenates all text-like parts).
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
}
