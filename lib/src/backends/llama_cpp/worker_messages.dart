import 'dart:isolate';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/log_level.dart';

/// Base class for all worker requests.
abstract class WorkerRequest {
  /// The port to send responses to.
  final SendPort sendPort;

  /// Creates a new [WorkerRequest].
  WorkerRequest(this.sendPort);
}

/// Request to load a model.
class ModelLoadRequest extends WorkerRequest {
  /// The path to the model file.
  final String modelPath;

  /// Parameters for loading the model.
  final ModelParams modelParams;

  /// Creates a new [ModelLoadRequest].
  ModelLoadRequest(this.modelPath, this.modelParams, super.sendPort);
}

/// Request to free a model.
class ModelFreeRequest extends WorkerRequest {
  /// The handle of the model to free.
  final int modelHandle;

  /// Creates a new [ModelFreeRequest].
  ModelFreeRequest(this.modelHandle, super.sendPort);
}

/// Request to create an inference context.
class ContextCreateRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// Parameters for the context.
  final ModelParams params;

  /// Creates a new [ContextCreateRequest].
  ContextCreateRequest(this.modelHandle, this.params, super.sendPort);
}

/// Request to free an inference context.
class ContextFreeRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Creates a new [ContextFreeRequest].
  ContextFreeRequest(this.contextHandle, super.sendPort);
}

/// Request to generate text.
class GenerateRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// The input prompt.
  final String prompt;

  /// Generation parameters.
  final GenerationParams params;

  /// Address of the cancel token.
  final int cancelTokenAddress;

  /// Multimodal content parts.
  final List<LlamaContentPart>? parts;

  /// Creates a new [GenerateRequest].
  GenerateRequest(
    this.contextHandle,
    this.prompt,
    this.params,
    this.cancelTokenAddress,
    super.sendPort, {
    this.parts,
  });
}

/// Request to tokenize text.
class TokenizeRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// The text to tokenize.
  final String text;

  /// Whether to add special tokens.
  final bool addSpecial;

  /// Creates a new [TokenizeRequest].
  TokenizeRequest(this.modelHandle, this.text, this.addSpecial, super.sendPort);
}

/// Request to detokenize tokens.
class DetokenizeRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// The token IDs to detokenize.
  final List<int> tokens;

  /// Whether to include special tokens.
  final bool special;

  /// Creates a new [DetokenizeRequest].
  DetokenizeRequest(
    this.modelHandle,
    this.tokens,
    this.special,
    super.sendPort,
  );
}

/// Request to get model metadata.
class MetadataRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// Creates a new [MetadataRequest].
  MetadataRequest(this.modelHandle, super.sendPort);
}

/// Request for LoRA operations.
class LoraRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Path to the LoRA file.
  final String? path;

  /// Strength scale.
  final double? scale;

  /// Operation: set, remove, clear.
  final String op;

  /// Creates a new [LoraRequest].
  LoraRequest(
    this.contextHandle,
    this.op, {
    this.path,
    this.scale,
    required SendPort sendPort,
  }) : super(sendPort);
}

/// Request for backend information.
class BackendInfoRequest extends WorkerRequest {
  /// Creates a new [BackendInfoRequest].
  BackendInfoRequest(super.sendPort);
}

/// Request to check for GPU support.
class GpuSupportRequest extends WorkerRequest {
  /// Creates a new [GpuSupportRequest].
  GpuSupportRequest(super.sendPort);
}

/// Request to dispose the worker.
class DisposeRequest extends WorkerRequest {
  /// Creates a new [DisposeRequest].
  DisposeRequest(super.sendPort);
}

/// Request to update log level.
class LogLevelRequest extends WorkerRequest {
  /// The target log level.
  final LlamaLogLevel logLevel;

  /// Creates a new [LogLevelRequest].
  LogLevelRequest(this.logLevel, super.sendPort);
}

/// Request to get the actual context size.
class GetContextSizeRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Creates a new [GetContextSizeRequest].
  GetContextSizeRequest(this.contextHandle, super.sendPort);
}

/// Request to create a multimodal context.
class MultimodalContextCreateRequest extends WorkerRequest {
  /// The handle of the text model.
  final int modelHandle;

  /// Path to the multimodal projector file (mmproj).
  final String mmProjPath;

  /// Creates a new [MultimodalContextCreateRequest].
  MultimodalContextCreateRequest(
    this.modelHandle,
    this.mmProjPath,
    super.sendPort,
  );
}

/// Request to free a multimodal context.
class MultimodalContextFreeRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a new [MultimodalContextFreeRequest].
  MultimodalContextFreeRequest(this.mmContextHandle, super.sendPort);
}

/// Request to check for vision support.
class SupportsVisionRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a new [SupportsVisionRequest].
  SupportsVisionRequest(this.mmContextHandle, super.sendPort);
}

/// Request to check for audio support.
class SupportsAudioRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a new [SupportsAudioRequest].
  SupportsAudioRequest(this.mmContextHandle, super.sendPort);
}

/// Request for system information (VRAM/RAM).
class SystemInfoRequest extends WorkerRequest {
  /// Creates a new [SystemInfoRequest].
  SystemInfoRequest(super.sendPort);
}

/// Request to apply a chat template.
class ChatTemplateRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// The list of messages.
  final List<Map<String, dynamic>> messages;

  /// Optional custom template string.
  final String? customTemplate;

  /// Whether to add assistant prompt.
  final bool addAssistant;

  /// Creates a new [ChatTemplateRequest].
  ChatTemplateRequest(
    this.modelHandle,
    this.messages,
    this.customTemplate,
    this.addAssistant,
    super.sendPort,
  );
}

/// Response containing a resource handle.
class HandleResponse {
  /// The unique handle.
  final int handle;

  /// Creates a new [HandleResponse].
  HandleResponse(this.handle);
}

/// Response containing token bytes.
class TokenResponse {
  /// The generated bytes.
  final List<int> bytes;

  /// Creates a new [TokenResponse].
  TokenResponse(this.bytes);
}

/// Response containing a list of token IDs.
class TokenizeResponse {
  /// The resulting tokens.
  final List<int> tokens;

  /// Creates a new [TokenizeResponse].
  TokenizeResponse(this.tokens);
}

/// Response containing detokenized text.
class DetokenizeResponse {
  /// The resulting text.
  final String text;

  /// Creates a new [DetokenizeResponse].
  DetokenizeResponse(this.text);
}

/// Response containing model metadata.
class MetadataResponse {
  /// The metadata key-value pairs.
  final Map<String, String> metadata;

  /// Creates a new [MetadataResponse].
  MetadataResponse(this.metadata);
}

/// Response containing the context size.
class GetContextSizeResponse {
  /// The context size.
  final int size;

  /// Creates a new [GetContextSizeResponse].
  GetContextSizeResponse(this.size);
}

/// Response containing an error message.
class ErrorResponse {
  /// The error message.
  final String message;

  /// Creates a new [ErrorResponse].
  ErrorResponse(this.message);
}

/// Response containing backend name.
class BackendInfoResponse {
  /// The backend name.
  final String name;

  /// Creates a new [BackendInfoResponse].
  BackendInfoResponse(this.name);
}

/// Response containing GPU support status.
class GpuSupportResponse {
  /// Whether supported.
  final bool support;

  /// Creates a new [GpuSupportResponse].
  GpuSupportResponse(this.support);
}

/// Response containing system information.
class SystemInfoResponse {
  /// Total VRAM in bytes.
  final int totalVram;

  /// Free VRAM in bytes.
  final int freeVram;

  /// Creates a new [SystemInfoResponse].
  SystemInfoResponse(this.totalVram, this.freeVram);
}

/// Response containing the formatted chat template result.
class ChatTemplateResponse {
  /// The formatted prompt string.
  final String result;

  /// Creates a new [ChatTemplateResponse].
  ChatTemplateResponse(this.result);
}

/// Response indicating an operation has completed.
class DoneResponse {}

/// Handshake message sent from main to worker.
class WorkerHandshake {
  /// The initial log level to set before backend initialization.
  final LlamaLogLevel initialLogLevel;

  /// Creates a new [WorkerHandshake].
  WorkerHandshake(this.initialLogLevel);
}
