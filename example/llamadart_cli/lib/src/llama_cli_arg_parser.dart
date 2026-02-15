import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'llama_cli_config.dart';

/// Parse failure for llama CLI arguments.
class LlamaCliArgException implements Exception {
  /// Human-readable parse or validation error.
  final String message;

  /// Creates an argument parsing exception.
  const LlamaCliArgException(this.message);

  @override
  String toString() => message;
}

/// Converts command-line flags into [LlamaCliConfig].
class LlamaCliArgParser {
  static const Map<String, String> _aliases = {
    '-hf': '--hf-file',
    '-ngl': '--gpu-layers',
    '-tb': '--threads-batch',
    '-c': '--ctx-size',
    '-sp': '--system-prompt',
    '-cnv': '--interactive',
    '-ins': '--instruct',
    '--hf': '--hf-file',
    '--n-predict': '--predict',
    '--ctx_size': '--ctx-size',
    '--top_k': '--top-k',
    '--top_p': '--top-p',
    '--min_p': '--min-p',
    '--repeat_penalty': '--repeat-penalty',
    '--reverse_prompt': '--reverse-prompt',
    '--simple_io': '--simple-io',
    '--system_prompt': '--system-prompt',
  };

  final ArgParser _parser = ArgParser(allowTrailingOptions: true)
    ..addOption('model', abbr: 'm', help: 'Path or URL to a GGUF model.')
    ..addOption(
      'hf-file',
      help:
          'Hugging Face model shorthand (repo[:file-hint]), '
          'for example unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL.',
    )
    ..addOption(
      'models-dir',
      help: 'Download/cache directory for model files.',
      defaultsTo: p.join(Directory.current.path, 'models'),
    )
    ..addOption('file', abbr: 'f', help: 'Read one-shot prompt from a file.')
    ..addOption('prompt', abbr: 'p', help: 'Run one prompt and print output.')
    ..addFlag(
      'interactive',
      abbr: 'i',
      help: 'Enable interactive conversation mode.',
      defaultsTo: true,
    )
    ..addFlag(
      'interactive-first',
      help: 'Run prompt first, then keep interactive mode.',
      defaultsTo: false,
    )
    ..addOption(
      'system-prompt',
      help: 'Optional system instruction prepended each turn.',
    )
    ..addOption(
      'ctx-size',
      help: 'Context size in tokens.',
      defaultsTo: '16384',
    )
    ..addOption(
      'gpu-layers',
      help: 'Number of layers to offload to GPU.',
      defaultsTo: '99',
    )
    ..addOption(
      'threads',
      abbr: 't',
      help: 'Generation threads (0 = auto).',
      defaultsTo: '0',
    )
    ..addOption(
      'threads-batch',
      help: 'Batch threads (0 = auto).',
      defaultsTo: '0',
    )
    ..addOption(
      'predict',
      abbr: 'n',
      help: 'Max generated tokens (<=0 means uncapped-style).',
      defaultsTo: '1024',
    )
    ..addOption('temp', help: 'Sampling temperature.', defaultsTo: '0.8')
    ..addOption('top-k', help: 'Top-k sampling parameter.', defaultsTo: '40')
    ..addOption('top-p', help: 'Top-p sampling parameter.', defaultsTo: '0.95')
    ..addOption('min-p', help: 'Min-p sampling parameter.', defaultsTo: '0.05')
    ..addOption(
      'repeat-penalty',
      help: 'Repeat penalty (llama.cpp naming).',
      defaultsTo: '1.0',
    )
    ..addOption('penalty', help: 'Alias of --repeat-penalty.')
    ..addOption('seed', abbr: 's', help: 'Random seed.')
    ..addOption(
      'fit',
      allowed: ['on', 'off'],
      defaultsTo: 'on',
      help: 'Fit prompt/context behavior (compatibility option).',
    )
    ..addFlag(
      'jinja',
      help: 'Accepted for llama.cpp parity. Chat templates are automatic.',
      defaultsTo: true,
    )
    ..addMultiOption(
      'reverse-prompt',
      abbr: 'r',
      help: 'Stop generation when one of these strings is produced.',
    )
    ..addFlag(
      'instruct',
      help: 'Compatibility flag for llama.cpp-style instruct mode.',
      defaultsTo: false,
    )
    ..addFlag(
      'color',
      help: 'Compatibility flag (accepted, no effect).',
      defaultsTo: true,
    )
    ..addFlag(
      'simple-io',
      help: 'Enable llama.cpp simple-io compatibility behavior.',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    );

  /// User-visible usage string.
  String get usage => _parser.usage;

  /// Parses raw CLI args into a validated [LlamaCliConfig].
  LlamaCliConfig parse(List<String> rawArguments) {
    final normalized = normalizeArguments(rawArguments);

    ArgResults results;
    try {
      results = _parser.parse(normalized);
    } on FormatException catch (e) {
      throw LlamaCliArgException(e.message);
    }

    final showHelp = results['help'] as bool;
    final model = _trimmedOrNull(results['model'] as String?);
    final hfSpec = _trimmedOrNull(results['hf-file'] as String?);
    final promptFile = _trimmedOrNull(results['file'] as String?);
    final prompt = _resolvePrompt(results);

    if (prompt != null && promptFile != null) {
      throw const LlamaCliArgException(
        'Use only one prompt source: --prompt/positional text or --file.',
      );
    }

    if (!showHelp && model == null && hfSpec == null) {
      throw const LlamaCliArgException(
        'You must provide either --model or -hf.',
      );
    }

    if (model != null && hfSpec != null) {
      throw const LlamaCliArgException(
        'Use only one model source: --model or -hf.',
      );
    }

    var interactive = results['interactive'] as bool;
    final interactiveFirst = results['interactive-first'] as bool;
    final hasSingleInput = prompt != null || promptFile != null;
    if (hasSingleInput &&
        !results.wasParsed('interactive') &&
        !interactiveFirst) {
      interactive = false;
    }

    if (!showHelp && !hasSingleInput && !interactive && !interactiveFirst) {
      throw const LlamaCliArgException(
        'No prompt provided and interactive mode is disabled.',
      );
    }

    final penaltyInput = results.wasParsed('penalty')
        ? results['penalty'] as String
        : results['repeat-penalty'] as String;

    return LlamaCliConfig(
      showHelp: showHelp,
      modelPathOrUrl: model,
      huggingFaceSpec: hfSpec,
      modelsDirectory: results['models-dir'] as String,
      prompt: prompt,
      promptFile: promptFile,
      interactive: interactive,
      interactiveFirst: interactiveFirst,
      systemPrompt: _trimmedOrNull(results['system-prompt'] as String?),
      contextSize: _parseInt(results['ctx-size'] as String, 'ctx-size'),
      gpuLayers: _parseInt(results['gpu-layers'] as String, 'gpu-layers'),
      threads: _parseInt(results['threads'] as String, 'threads'),
      threadsBatch: _parseInt(
        results['threads-batch'] as String,
        'threads-batch',
      ),
      maxTokens: _parseInt(results['predict'] as String, 'predict'),
      seed: _parseNullableInt(results['seed'] as String?),
      temperature: _parseDouble(results['temp'] as String, 'temp'),
      topK: _parseInt(results['top-k'] as String, 'top-k'),
      topP: _parseDouble(results['top-p'] as String, 'top-p'),
      minP: _parseDouble(results['min-p'] as String, 'min-p'),
      repeatPenalty: _parseDouble(penaltyInput, 'repeat-penalty'),
      fitContext: (results['fit'] as String).toLowerCase() == 'on',
      jinja: results['jinja'] as bool,
      instruct: results['instruct'] as bool,
      simpleIo: results['simple-io'] as bool,
      color: results['color'] as bool,
      reversePrompts: List<String>.unmodifiable(
        (results['reverse-prompt'] as List<String>)
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      ),
    );
  }

  /// Rewrites llama.cpp multi-letter short options into parseable long forms.
  List<String> normalizeArguments(List<String> rawArguments) {
    final normalized = <String>[];

    for (final argument in rawArguments) {
      final exact = _aliases[argument];
      if (exact != null) {
        normalized.add(exact);
        continue;
      }

      final separatorIndex = argument.indexOf('=');
      if (separatorIndex > 0) {
        final key = argument.substring(0, separatorIndex);
        final value = argument.substring(separatorIndex + 1);
        final alias = _aliases[key];
        if (alias != null) {
          normalized.add('$alias=$value');
          continue;
        }
      }

      normalized.add(argument);
    }

    return normalized;
  }

  String? _resolvePrompt(ArgResults results) {
    final optionPrompt = _trimmedOrNull(results['prompt'] as String?);
    if (optionPrompt != null) {
      return optionPrompt;
    }

    if (results.rest.isEmpty) {
      return null;
    }

    return results.rest.join(' ').trim();
  }

  String? _trimmedOrNull(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int _parseInt(String raw, String name) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw LlamaCliArgException('Invalid integer for --$name: $raw');
    }
    return parsed;
  }

  int? _parseNullableInt(String? raw) {
    final value = _trimmedOrNull(raw);
    if (value == null) {
      return null;
    }

    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw LlamaCliArgException('Invalid integer for --seed: $value');
    }
    return parsed;
  }

  double _parseDouble(String raw, String name) {
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      throw LlamaCliArgException('Invalid number for --$name: $raw');
    }
    return parsed;
  }
}
