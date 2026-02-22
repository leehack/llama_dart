class ModelPreset {
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double penalty;
  final int thinkingBudgetTokens;
  final int contextSize;
  final int maxTokens;
  final bool thinkingEnabled;

  /// A value of 99 keeps auto-estimation behavior in ChatProvider.
  final int gpuLayers;

  const ModelPreset({
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.9,
    this.minP = 0.0,
    this.penalty = 1.1,
    this.thinkingBudgetTokens = 0,
    this.contextSize = 4096,
    this.maxTokens = 4096,
    this.gpuLayers = 99,
    this.thinkingEnabled = true,
  });
}

class DownloadableModel {
  final String name;
  final String description;
  final String url;
  final String filename;
  final String? mmprojUrl;
  final String? mmprojFilename;
  final int sizeBytes;
  final bool supportsVision;
  final bool supportsAudio;
  final bool supportsVideo;
  final bool supportsToolCalling;
  final bool supportsThinking;

  /// Recommended generation/model-loading preset for this model.
  final ModelPreset preset;

  /// Minimum RAM/VRAM in GB recommended for this model.
  final int minRamGb;

  const DownloadableModel({
    required this.name,
    required this.description,
    required this.url,
    required this.filename,
    required this.sizeBytes,
    this.mmprojUrl,
    this.mmprojFilename,
    this.supportsVision = false,
    this.supportsAudio = false,
    this.supportsVideo = false,
    this.supportsToolCalling = false,
    this.supportsThinking = false,
    this.minRamGb = 2,
    this.preset = const ModelPreset(),
  });

  bool get isMultimodal => supportsVision || supportsAudio;

  String get sizeMb => (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

  static const List<DownloadableModel> defaultModels = [
    DownloadableModel(
      name: 'FunctionGemma 270M',
      description:
          '🛠️ Tiny tools model (253MB) • Great function-calling demo.',
      url:
          'https://huggingface.co/unsloth/functiongemma-270m-it-GGUF/resolve/main/functiongemma-270m-it-Q4_K_M.gguf?download=true',
      filename: 'functiongemma-270m-it-Q4_K_M.gguf',
      sizeBytes: 253127904,
      minRamGb: 2,
      supportsToolCalling: true,
      preset: ModelPreset(
        temperature: 0.0,
        topK: 40,
        topP: 0.9,
        contextSize: 4096,
        maxTokens: 1024,
      ),
    ),
    DownloadableModel(
      name: 'Qwen2.5 0.5B Instruct',
      description:
          '⚡ Ultra-light (491MB) • Fast and reliable web/mobile starter.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 491400032,
      minRamGb: 2,
      supportsToolCalling: true,
      preset: ModelPreset(
        temperature: 0.1,
        topK: 40,
        topP: 0.9,
        contextSize: 4096,
        maxTokens: 2048,
      ),
    ),
    DownloadableModel(
      name: 'Llama 3.2 1B Instruct',
      description: '🧰 General + tools (808MB) • Reliable everyday assistant.',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sizeBytes: 807694464,
      minRamGb: 3,
      supportsToolCalling: true,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 2048,
      ),
    ),
    DownloadableModel(
      name: 'Gemma 3 1B it',
      description:
          '🧩 Gemma template (806MB) • Lightweight multilingual baseline.',
      url:
          'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf?download=true',
      filename: 'gemma-3-1b-it-Q4_K_M.gguf',
      sizeBytes: 806058240,
      minRamGb: 3,
      preset: ModelPreset(
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 2048,
      ),
    ),
    DownloadableModel(
      name: 'LFM2.5 1.2B Instruct',
      description: '🌊 LFM baseline (731MB) • Popular small Liquid text model.',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 730895168,
      minRamGb: 3,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 2048,
      ),
    ),
    DownloadableModel(
      name: 'Qwen2.5 1.5B Instruct',
      description:
          '💬 Popular compact assistant (1.12GB) • Strong quality/size ratio.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeBytes: 1117320736,
      minRamGb: 3,
      supportsToolCalling: true,
      preset: ModelPreset(
        temperature: 0.1,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 2048,
      ),
    ),
    DownloadableModel(
      name: 'LFM2.5 1.2B Thinking',
      description:
          '🧠 Reasoning-focused LFM (731MB) • Good compact thinking model.',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF/resolve/main/LFM2.5-1.2B-Thinking-Q4_K_M.gguf?download=true',
      filename: 'LFM2.5-1.2B-Thinking-Q4_K_M.gguf',
      sizeBytes: 730895360,
      minRamGb: 3,
      supportsThinking: true,
      preset: ModelPreset(
        temperature: 0.05,
        topK: 50,
        topP: 0.1,
        contextSize: 16384,
        maxTokens: 4096,
      ),
    ),
    DownloadableModel(
      name: 'SmolVLM 500M Instruct',
      description:
          '👁️ Vision bundle (636MB) • Proven lightweight image understanding.',
      url:
          'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf?download=true',
      filename: 'SmolVLM-500M-Instruct-Q8_0.gguf',
      mmprojUrl:
          'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-f16.gguf?download=true',
      mmprojFilename: 'mmproj-SmolVLM-500M-Instruct-f16.gguf',
      sizeBytes: 636275712,
      minRamGb: 3,
      supportsVision: true,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 4096,
        maxTokens: 1024,
      ),
    ),
    DownloadableModel(
      name: 'LFM2-VL 450M',
      description:
          '🖼️ Tiny VLM bundle (323MB) • Fast multimodal demo for mobile.',
      url:
          'https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q4_0.gguf?download=true',
      filename: 'LFM2-VL-450M-Q4_0.gguf',
      mmprojUrl:
          'https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf?download=true',
      mmprojFilename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
      sizeBytes: 323197440,
      minRamGb: 2,
      supportsVision: true,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 1024,
      ),
    ),
    DownloadableModel(
      name: 'Ultravox v0.5 1B',
      description:
          '🎤 Audio bundle (2.18GB) • Reliable speech understanding demo.',
      url:
          'https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'ultravox-v0.5-1b-q4_k_m.gguf',
      mmprojUrl:
          'https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf?download=true',
      mmprojFilename: 'mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf',
      sizeBytes: 2178818080,
      minRamGb: 4,
      supportsAudio: true,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 4096,
        maxTokens: 1024,
      ),
    ),
    DownloadableModel(
      name: 'Llama 3.2 3B Instruct',
      description:
          '🏠 Balanced large model (2.02GB) • Strong general assistant.',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2019377696,
      minRamGb: 4,
      supportsToolCalling: true,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 2048,
      ),
    ),
    DownloadableModel(
      name: 'Qwen3 4B',
      description:
          '🧠 Thinking + tools (2.50GB) • Best all-around reasoning upgrade.',
      url:
          'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true',
      filename: 'Qwen3-4B-Q4_K_M.gguf',
      sizeBytes: 2497280256,
      minRamGb: 6,
      supportsToolCalling: true,
      supportsThinking: true,
      preset: ModelPreset(
        temperature: 0.6,
        topK: 20,
        topP: 0.95,
        contextSize: 8192,
        maxTokens: 4096,
      ),
    ),
    DownloadableModel(
      name: 'Meta-Llama 3.1 8B Instruct',
      description:
          '🚀 Flagship quality (4.92GB) • Popular large model benchmark.',
      url:
          'https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf',
      sizeBytes: 4920739232,
      minRamGb: 8,
      supportsToolCalling: true,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: 8192,
        maxTokens: 2048,
      ),
    ),
  ];
}
