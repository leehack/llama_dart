import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/chat_template_handler.dart';
import 'package:test/test.dart';

void main() {
  const baseTemplate = '{{ "BASE:" ~ messages[0]["content"] }}';
  const overrideTemplate = '{{ "OVERRIDE:" ~ messages[0]["content"] }}';
  const customTemplate = '{{ "CUSTOM:" ~ messages[0]["content"] }}';

  final messages = [const LlamaChatMessage(role: 'user', content: 'hello')];

  setUp(() {
    ChatTemplateEngine.clearCustomHandlers();
    ChatTemplateEngine.clearTemplateOverrides();
  });

  tearDown(() {
    ChatTemplateEngine.clearCustomHandlers();
    ChatTemplateEngine.clearTemplateOverrides();
  });

  group('ChatTemplateEngine custom handlers', () {
    test('uses explicit custom handler id for render and parse', () {
      ChatTemplateEngine.registerHandler(
        id: 'custom',
        handler: _TestCustomHandler(),
      );

      final result = ChatTemplateEngine.render(
        templateSource: baseTemplate,
        messages: messages,
        metadata: const {},
        customHandlerId: 'custom',
      );

      expect(result.handlerId, equals('custom'));
      expect(result.prompt, contains('CUSTOM:hello'));

      final parsed = ChatTemplateEngine.parse(
        result.format,
        'raw-output',
        handlerId: result.handlerId,
      );

      expect(parsed.content, equals('parsed:raw-output'));
    });

    test('auto-selects registered custom handler by matcher', () {
      ChatTemplateEngine.registerHandler(
        id: 'matcher-handler',
        handler: _TestCustomHandler(),
        matcher: (context) =>
            context.templateSource != null &&
            context.templateSource!.contains('MATCH_ME'),
      );

      final result = ChatTemplateEngine.render(
        templateSource: 'MATCH_ME',
        messages: messages,
        metadata: const {},
      );

      expect(result.handlerId, equals('matcher-handler'));
      expect(result.prompt, contains('CUSTOM:hello'));
    });
  });

  group('ChatTemplateEngine template overrides', () {
    test('applies registered template override before metadata template', () {
      ChatTemplateEngine.registerTemplateOverride(
        id: 'always',
        templateSource: overrideTemplate,
      );

      final result = ChatTemplateEngine.render(
        templateSource: baseTemplate,
        messages: messages,
        metadata: const {},
      );

      expect(result.prompt, contains('OVERRIDE:hello'));
      expect(result.prompt, isNot(contains('BASE:hello')));
    });

    test('per-call custom template has highest priority', () {
      ChatTemplateEngine.registerTemplateOverride(
        id: 'always',
        templateSource: overrideTemplate,
      );

      final result = ChatTemplateEngine.render(
        templateSource: baseTemplate,
        messages: messages,
        metadata: const {},
        customTemplate: customTemplate,
      );

      expect(result.prompt, contains('CUSTOM:hello'));
      expect(result.prompt, isNot(contains('OVERRIDE:hello')));
    });

    test('supports unregister and clear operations', () {
      ChatTemplateEngine.registerHandler(
        id: 'to-remove',
        handler: _TestCustomHandler(),
      );
      ChatTemplateEngine.registerTemplateOverride(
        id: 'to-clear',
        templateSource: overrideTemplate,
      );

      expect(ChatTemplateEngine.unregisterHandler('to-remove'), isTrue);
      expect(ChatTemplateEngine.unregisterHandler('to-remove'), isFalse);

      ChatTemplateEngine.clearTemplateOverrides();

      final result = ChatTemplateEngine.render(
        templateSource: baseTemplate,
        messages: messages,
        metadata: const {},
      );

      expect(result.prompt, contains('BASE:hello'));
    });
  });

  group('ChatTemplateEngine grammar routing', () {
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city')],
        handler: _noopHandler,
      ),
    ];

    const grammarMessages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
    ];

    test('applies generic tool grammar for generic templates', () {
      const template =
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>\n<|im_start|>assistant\n';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
    });

    test(
      'does not auto-apply generic grammar for format-specific handlers',
      () {
        const template = '>>>all\n{{ messages[0]["content"] }}';

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: grammarMessages,
          metadata: const {},
          tools: tools,
        );

        expect(result.format, equals(ChatFormat.functionaryV32.index));
        expect(result.grammar, isNull);
      },
    );

    test('uses generic routing for tools + schema requests', () {
      const template =
          '<|END_THINKING|><|START_ACTION|>{{ messages[0]["content"] }}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        responseFormat: const {
          'type': 'json_schema',
          'json_schema': {
            'schema': {
              'type': 'object',
              'properties': {
                'ok': {'type': 'boolean'},
              },
              'required': ['ok'],
            },
          },
        },
      );

      expect(result.format, equals(ChatFormat.generic.index));
    });

    test('uses content-only routing for schema-disabled formats', () {
      const template = '<tool_call>{{ messages[0]["content"] }}</tool_call>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        responseFormat: const {'type': 'json_object'},
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
    });

    test('disables lazy grammar for required tool choice when needed', () {
      const template =
          '<tool_call>\n<function=\n<function>\n<parameters>\n<parameter=\n{{ messages[0]["content"] }}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.qwen3CoderXml.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
    });

    test('keeps lazy grammar for formats that always use lazy mode', () {
      const template =
          '<|system_start|>{{ messages[0]["content"] }}<|system_end|><|tools_prefix|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.apertus.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isTrue);
    });
  });
}

class _TestCustomHandler extends ChatTemplateHandler {
  _TestCustomHandler();

  @override
  ChatFormat get format => ChatFormat.generic;

  @override
  List<String> get additionalStops => const [];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final text = messages.map((m) => m.content).join('|');
    return LlamaChatTemplateResult(
      prompt: 'CUSTOM:$text${addAssistant ? '|assistant' : ''}',
      format: format.index,
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return ChatParseResult(content: 'parsed:$output');
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}

Future<Object?> _noopHandler(_) async {
  return 'ok';
}
