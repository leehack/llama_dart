import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_chat_example/models/chat_settings.dart';
import 'package:llamadart_chat_example/providers/chat_provider.dart';
import 'package:llamadart_chat_example/widgets/tool_declarations_dialog.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'switching to Visual Editor surfaces validation error for non-string description',
    (tester) async {
      final provider = ChatProvider(
        chatService: MockChatService(engine: MockLlamaEngine()),
        settingsService: MockSettingsService(),
        initialSettings: const ChatSettings(
          modelPath: 'test_model.gguf',
          toolDeclarations:
              '[{"name":"test","description":1,"parameters":{"type":"object","properties":{}}}]',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () =>
                      showToolDeclarationsDialog(context, provider),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Function declarations'), findsOneWidget);

      await tester.tap(find.text('Visual Editor'));
      await tester.pump();

      expect(
        find.textContaining('description must be a string'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
