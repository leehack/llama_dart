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
    this.minRamGb = 2,
  });

  bool get isMultimodal => supportsVision || supportsAudio;

  String get sizeMb => (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

  static const List<DownloadableModel> defaultModels = [
    DownloadableModel(
      name: 'FunctionGemma 270M',
      description: '🛠️ Tiny (180MB) • Tool-calling specialized small model.',
      url:
          'https://huggingface.co/unsloth/functiongemma-270m-it-GGUF/resolve/main/functiongemma-270m-it-Q4_K_M.gguf?download=true',
      filename: 'functiongemma-270m-it-Q4_K_M.gguf',
      sizeBytes: 180000000,
      minRamGb: 2,
    ),
    DownloadableModel(
      name: 'SmolVLM 500M Instruct',
      description:
          '👁️ Vision (~640MB) • Min: 2GB RAM • Best for mobile vision tasks.',
      url:
          'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf?download=true',
      filename: 'SmolVLM-500M-Instruct-Q8_0.gguf',
      mmprojUrl:
          'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-f16.gguf?download=true',
      mmprojFilename: 'mmproj-SmolVLM-500M-Instruct-f16.gguf',
      supportsVision: true,
      sizeBytes: 636000000,
      minRamGb: 2,
    ),
    DownloadableModel(
      name: 'DeepSeek R1 Qwen 1.5B',
      description: '🧠 Reasoning (1.1GB) • R1 reasoning in a compact size.',
      url:
          'https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf?download=true',
      filename: 'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
      sizeBytes: 1100000000,
      minRamGb: 3,
    ),
    DownloadableModel(
      name: 'Ultravox v0.5 1B',
      description: '🎤 Audio (1.1GB) • Min: 3GB RAM • Speech understanding.',
      url:
          'https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'ultravox-v0.5-1b-q4_k_m.gguf',
      mmprojUrl:
          'https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf?download=true',
      mmprojFilename: 'mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf',
      supportsAudio: true,
      sizeBytes: 1100000000,
      minRamGb: 3,
    ),
    DownloadableModel(
      name: 'LFM 2.5 1.2B Thinking',
      description: '🧠 Reasoning (1.3GB) • Liquid foundation reasoning model.',
      url:
          'https://huggingface.co/unsloth/LFM2.5-1.2B-Thinking-GGUF/resolve/main/LFM2.5-1.2B-Thinking-Q4_K_M.gguf?download=true',
      filename: 'LFM2.5-1.2B-Thinking-Q4_K_M.gguf',
      sizeBytes: 1300000000,
      minRamGb: 3,
    ),
    DownloadableModel(
      name: 'Llama 3.2 3B Instruct',
      description: '🏠 General (2.1GB) • Excellent balanced mobile model.',
      url:
          'https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2100000000,
      minRamGb: 4,
    ),
    DownloadableModel(
      name: 'Ministral 3B Reasoning',
      description: '🧠 Reasoning (2.3GB) • High-performance reasoning.',
      url:
          'https://huggingface.co/unsloth/Ministral-3-3B-Reasoning-2512-GGUF/resolve/main/Ministral-3-3B-Reasoning-2512-Q4_K_M.gguf?download=true',
      filename: 'Ministral-3-3B-Reasoning-2512-Q4_K_M.gguf',
      sizeBytes: 2300000000,
      minRamGb: 4,
    ),
    DownloadableModel(
      name: 'Phi-4 Mini Reasoning',
      description: '🧠 Reasoning (2.6GB) • Microsoft reasoning specialist.',
      url:
          'https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf',
      filename: 'Phi-4-mini-instruct-Q4_K_M.gguf',
      sizeBytes: 2600000000,
      minRamGb: 4,
    ),
    DownloadableModel(
      name: 'Gemma 3n E4B it',
      description: '🧠 Reasoning (2.8GB) • Experimental Google reasoning.',
      url:
          'https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q4_K_M.gguf?download=true',
      filename: 'gemma-3n-E4B-it-Q4_K_M.gguf',
      sizeBytes: 2800000000,
      minRamGb: 6,
    ),
    DownloadableModel(
      name: 'Qwen 3 4B',
      description: '🧠 Thinking (3.0GB) • Latest Qwen intelligence.',
      url:
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true',
      filename: 'Qwen3-4B-Q4_K_M.gguf',
      sizeBytes: 3000000000,
      minRamGb: 6,
    ),
    DownloadableModel(
      name: 'Gemma 3 4B it',
      description: '🛠️ General (3.2GB) • Capable reasoning & tools.',
      url:
          'https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf?download=true',
      filename: 'gemma-3-4b-it-Q4_K_M.gguf',
      sizeBytes: 3200000000,
      minRamGb: 6,
    ),
    DownloadableModel(
      name: 'DeepSeek R1 Llama 8B',
      description: '🧠 Reasoning (5.3GB) • Powerful R1 logic in 8B format.',
      url:
          'https://huggingface.co/unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf?download=true',
      filename: 'DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf',
      sizeBytes: 5300000000,
      minRamGb: 8,
    ),
  ];
}
