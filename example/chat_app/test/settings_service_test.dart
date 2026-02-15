import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:llamadart_chat_example/models/chat_settings.dart';
import 'package:llamadart_chat_example/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService context size', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('preserves explicit auto context size from storage', () async {
      SharedPreferences.setMockInitialValues({'context_size': 0});

      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.contextSize, 0);
    });

    test('normalizes invalid legacy context size values', () async {
      SharedPreferences.setMockInitialValues({'context_size': 128});

      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.contextSize, 4096);
    });

    test('saves zero context size for auto mode', () async {
      final service = SettingsService();
      const settings = ChatSettings(contextSize: 0);

      await service.saveSettings(settings);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getInt('context_size'), 0);
    });
  });
}
