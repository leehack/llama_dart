import 'package:llamadart/llamadart.dart';

/// Runtime configuration for the llama.cpp-style CLI.
class LlamaCliConfig {
  /// Shows usage output instead of running inference.
  final bool showHelp;

  /// Local model path or direct model URL.
  final String? modelPathOrUrl;

  /// Hugging Face shorthand (`repo[:file-hint]`) used by `-hf`.
  final String? huggingFaceSpec;

  /// Local directory used for downloaded model files.
  final String modelsDirectory;

  /// Optional one-shot prompt.
  final String? prompt;

  /// Optional prompt file path.
  final String? promptFile;

  /// Enables interactive chat mode.
  final bool interactive;

  /// Runs prompt first, then keeps interactive mode enabled.
  final bool interactiveFirst;

  /// Optional system prompt prepended to each request.
  final String? systemPrompt;

  /// Requested context size.
  final int contextSize;

  /// Number of layers to offload to GPU.
  final int gpuLayers;

  /// Number of generation threads.
  final int threads;

  /// Number of batch threads.
  final int threadsBatch;

  /// Maximum generated tokens per assistant turn.
  final int maxTokens;

  /// Optional random seed.
  final int? seed;

  /// Sampling temperature.
  final double temperature;

  /// Top-k sampling parameter.
  final int topK;

  /// Top-p sampling parameter.
  final double topP;

  /// Min-p sampling parameter.
  final double minP;

  /// Repeat penalty.
  final double repeatPenalty;

  /// Whether fitting/truncation behavior is enabled.
  final bool fitContext;

  /// Compatibility flag accepted for llama.cpp parity.
  final bool jinja;

  /// Instruct-mode compatibility flag.
  final bool instruct;

  /// Enables plain stdin/stdout behavior similar to llama.cpp `--simple-io`.
  final bool simpleIo;

  /// Enables colorized output when supported.
  final bool color;

  /// Reverse prompts mapped to generation stop sequences.
  final List<String> reversePrompts;

  /// Creates an immutable CLI configuration.
  const LlamaCliConfig({
    required this.showHelp,
    required this.modelsDirectory,
    required this.interactive,
    required this.interactiveFirst,
    required this.contextSize,
    required this.gpuLayers,
    required this.threads,
    required this.threadsBatch,
    required this.maxTokens,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.minP,
    required this.repeatPenalty,
    required this.fitContext,
    required this.jinja,
    required this.instruct,
    required this.simpleIo,
    required this.color,
    required this.reversePrompts,
    this.modelPathOrUrl,
    this.huggingFaceSpec,
    this.prompt,
    this.promptFile,
    this.systemPrompt,
    this.seed,
  });

  /// Builds generation parameters from this CLI config.
  GenerationParams toGenerationParams() {
    final effectiveMaxTokens = maxTokens <= 0 ? 8192 : maxTokens;
    return GenerationParams(
      maxTokens: effectiveMaxTokens,
      temp: temperature,
      topK: topK,
      topP: topP,
      minP: minP,
      penalty: repeatPenalty,
      seed: seed,
      stopSequences: List<String>.unmodifiable(reversePrompts),
    );
  }
}
