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
    : // ignore: deprecated_member_use_from_same_package
      roleString = role,
      roleEnum = null,
      _legacyContent = content,
      _parts = null;

  /// NEW: Enum-based text-only constructor.
  const LlamaChatMessage.text({
    required LlamaChatRole role,
    required String content,
  }) : roleEnum = role,
       // ignore: deprecated_member_use_from_same_package
       roleString = null,
       _legacyContent = content,
       _parts = null;

  /// NEW: Multimodal constructor.
  const LlamaChatMessage.multimodal({
    required LlamaChatRole role,
    required List<LlamaContentPart> parts,
  }) : roleEnum = role,
       // ignore: deprecated_member_use_from_same_package
       roleString = null,
       _parts = parts,
       _legacyContent = null;

  /// Multimodal content parts.
  List<LlamaContentPart> get parts =>
      _parts ?? [LlamaTextContent(_legacyContent!)];

  /// Unified role getter (prefers enum, falls back to string).
  LlamaChatRole get role =>
      roleEnum ??
      // ignore: deprecated_member_use_from_same_package
      LlamaChatRole.values.byName(roleString!);

  /// Backward-compatible content getter (concatenates all text parts).
  String get content =>
      _legacyContent ??
      parts.whereType<LlamaTextContent>().map((p) => p.text).join();
}
