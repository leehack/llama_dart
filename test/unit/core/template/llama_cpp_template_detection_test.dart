import 'dart:io';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:test/test.dart';

void main() {
  final templatesDir = Directory('third_party/llama_cpp/models/templates');
  final hasVendoredLlamaCppTemplates = templatesDir.existsSync();

  group('llama.cpp template detection parity', () {
    final expected = <String, ChatFormat>{
      'Apertus-8B-Instruct.jinja': ChatFormat.apertus,
      'ByteDance-Seed-OSS.jinja': ChatFormat.seedOss,
      'CohereForAI-c4ai-command-r-plus-tool_use.jinja': ChatFormat.contentOnly,
      'CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja':
          ChatFormat.commandR7B,
      'GLM-4.6.jinja': ChatFormat.glm45,
      'Kimi-K2-Instruct.jinja': ChatFormat.kimiK2,
      'Kimi-K2-Thinking.jinja': ChatFormat.kimiK2,
      'MiMo-VL.jinja': ChatFormat.hermes,
      'MiniMax-M2.jinja': ChatFormat.minimaxM2,
      'Mistral-Small-3.2-24B-Instruct-2506.jinja': ChatFormat.magistral,
      'NVIDIA-Nemotron-3-Nano-30B-A3B-BF16.jinja': ChatFormat.qwen3CoderXml,
      'NVIDIA-Nemotron-Nano-v2.jinja': ChatFormat.nemotronV2,
      'NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja': ChatFormat.hermes,
      'NousResearch-Hermes-3-Llama-3.1-8B-tool_use.jinja': ChatFormat.hermes,
      'Qwen-QwQ-32B.jinja': ChatFormat.hermes,
      'Qwen-Qwen2.5-7B-Instruct.jinja': ChatFormat.hermes,
      'Qwen-Qwen3-0.6B.jinja': ChatFormat.hermes,
      'Qwen3-Coder.jinja': ChatFormat.qwen3CoderXml,
      'deepseek-ai-DeepSeek-R1-Distill-Llama-8B.jinja': ChatFormat.deepseekR1,
      'deepseek-ai-DeepSeek-R1-Distill-Qwen-32B.jinja': ChatFormat.deepseekR1,
      'deepseek-ai-DeepSeek-V3.1.jinja': ChatFormat.deepseekV3,
      'fireworks-ai-llama-3-firefunction-v2.jinja': ChatFormat.firefunctionV2,
      'google-gemma-2-2b-it.jinja': ChatFormat.gemma,
      'ibm-granite-granite-3.3-2B-Instruct.jinja': ChatFormat.granite,
      'llama-cpp-deepseek-r1.jinja': ChatFormat.deepseekR1,
      'llama-cpp-lfm2.jinja': ChatFormat.lfm2,
      'llama-cpp-rwkv-world.jinja': ChatFormat.contentOnly,
      'meetkai-functionary-medium-v3.1.jinja': ChatFormat.functionaryV31Llama31,
      'meetkai-functionary-medium-v3.2.jinja': ChatFormat.functionaryV32,
      'meta-llama-Llama-3.1-8B-Instruct.jinja': ChatFormat.llama3,
      'meta-llama-Llama-3.2-3B-Instruct.jinja': ChatFormat.llama3,
      'meta-llama-Llama-3.3-70B-Instruct.jinja': ChatFormat.llama3,
      'microsoft-Phi-3.5-mini-instruct.jinja': ChatFormat.generic,
      'mistralai-Ministral-3-14B-Reasoning-2512.jinja': ChatFormat.magistral,
      'mistralai-Mistral-Nemo-Instruct-2407.jinja': ChatFormat.mistralNemo,
      'moonshotai-Kimi-K2.jinja': ChatFormat.kimiK2,
      'openai-gpt-oss-120b.jinja': ChatFormat.gptOss,
      'unsloth-Apriel-1.5.jinja': ChatFormat.hermes,
      'unsloth-mistral-Devstral-Small-2507.jinja': ChatFormat.magistral,
      'upstage-Solar-Open-100B.jinja': ChatFormat.solarOpen,
    };

    for (final entry in expected.entries) {
      test(
        'detects ${entry.key}',
        () {
          final file = File(
            'third_party/llama_cpp/models/templates/${entry.key}',
          );
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing llama.cpp template fixture',
          );

          final source = file.readAsStringSync();
          final detected = detectChatFormat(source);
          expect(detected, equals(entry.value));
        },
        skip: hasVendoredLlamaCppTemplates
            ? false
            : 'Requires local third_party llama.cpp template fixtures.',
      );
    }

    test(
      'maps every vendored llama.cpp template',
      () {
        expect(templatesDir.existsSync(), isTrue);

        final files = templatesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jinja'))
            .map((f) => f.uri.pathSegments.last)
            .toSet();

        final missing =
            files.where((name) => !expected.containsKey(name)).toList()..sort();
        expect(
          missing,
          isEmpty,
          reason:
              'Unmapped llama.cpp templates detected. Add expectations for: ${missing.join(', ')}',
        );
      },
      skip: hasVendoredLlamaCppTemplates
          ? false
          : 'Requires local third_party llama.cpp template fixtures.',
    );
  });
}
