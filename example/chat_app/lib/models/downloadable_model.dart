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
    // ===== SMALL MODELS (Mobile/Low-end) =====
    DownloadableModel(
      name: 'Qwen 2.5 0.5B',
      description:
          '⚡ Tiny (400MB) • Min: 2GB RAM • Fast but limited instruction following.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 398000000,
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
      name: 'Gemma 3 1B',
      description: '📝 Text (850MB) • Min: 2GB RAM • Lightweight Google model.',
      url:
          'https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf?download=true',
      filename: 'google_gemma-3-1b-it-Q4_K_M.gguf',
      sizeBytes: 850000000,
      minRamGb: 2,
    ),

    // ===== MEDIUM MODELS (Desktop/Tablets) =====
    DownloadableModel(
      name: 'LFM 2.5 1.2B',
      description: '📝 Text (800MB) • Min: 3GB RAM • Long context support.',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 800000000,
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
      mmprojFilename: 'ultravox-v0.5-mmproj-f16.gguf',
      supportsAudio: true,
      sizeBytes: 1100000000,
      minRamGb: 3,
    ),
    DownloadableModel(
      name: 'Qwen 2.5 3B Instruct',
      description: '🛠️ Text (2GB) • Min: 4GB RAM • Good for tool calling.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      sizeBytes: 2000000000,
      minRamGb: 4,
    ),

    // ===== LARGE MODELS (High-end Desktop/Workstation) =====
    DownloadableModel(
      name: 'Qwen 2.5 7B Instruct',
      description:
          '🛠️ Text (4.7GB) • Min: 8GB RAM • Excellent instruction following & tools.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-7b-instruct-q4_k_m.gguf',
      sizeBytes: 4700000000,
      minRamGb: 8,
    ),
  ];
}
