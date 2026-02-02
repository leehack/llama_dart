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
  });

  bool get isMultimodal => supportsVision || supportsAudio;

  String get sizeMb => (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

  static const List<DownloadableModel> defaultModels = [
    DownloadableModel(
      name: 'SmolVLM 500M Instruct',
      description:
          'Ultra-tiny vision model (~640MB total). Best for mobile devices.',
      url:
          'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf?download=true',
      filename: 'SmolVLM-500M-Instruct-Q8_0.gguf',
      mmprojUrl:
          'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-f16.gguf?download=true',
      mmprojFilename: 'mmproj-SmolVLM-500M-Instruct-f16.gguf',
      supportsVision: true,
      sizeBytes:
          636000000, // ~436MB (Model) + ~200MB (Projector) = ~640MB Total
    ),
    DownloadableModel(
      name: 'Ultravox v0.5 1B',
      description: 'High-performance audio-native model (Llama 3.2 based).',
      url:
          'https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'ultravox-v0.5-1b-q4_k_m.gguf',
      mmprojUrl:
          'https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf?download=true',
      mmprojFilename: 'ultravox-v0.5-mmproj-f16.gguf',
      supportsAudio: true,
      sizeBytes: 1100000000, // ~1.1GB
    ),
    DownloadableModel(
      name: 'LFM 2.5 1.2B',
      description: 'LiquidAI efficient text model with long context support.',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 800000000,
    ),
    DownloadableModel(
      name: 'Gemma 3 1B',
      description: 'Ultra-lightweight text-only variant of Google Gemma 3.',
      url:
          'https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf?download=true',
      filename: 'google_gemma-3-1b-it-Q4_K_M.gguf',
      sizeBytes: 850000000,
    ),
    DownloadableModel(
      name: 'Qwen 2.5 0.5B',
      description: 'Tiny and fast text-only model. Ideal for older devices.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 398000000,
    ),
  ];
}
