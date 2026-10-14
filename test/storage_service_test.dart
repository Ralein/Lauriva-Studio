import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/services/storage_service.dart';

import 'test_mocks.dart';

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  // Secure-storage state is process-wide across tests in this file (the mock
  // handler is only installed once via setUpAll), so each test must start
  // from a clean slate to avoid API keys leaking between cases.
  setUp(clearMockSecureStorage);

  group('StorageService API key persistence', () {
    test('getApiKey returns null when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      expect(storage.getApiKey('groq'), isNull);
    });

    test('setApiKey persists and trims whitespace, getApiKey reflects it immediately', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await storage.setApiKey('groq', '  gsk_abc123  ');
      expect(storage.getApiKey('groq'), 'gsk_abc123');
    });

    test('clearApiKey removes a previously stored key', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await storage.setApiKey('openrouter', 'sk-or-v1-test');
      expect(storage.getApiKey('openrouter'), 'sk-or-v1-test');

      await storage.clearApiKey('openrouter');
      expect(storage.getApiKey('openrouter'), isNull);
    });

    test('keys persisted in one StorageService instance are readable by a fresh instance', () async {
      SharedPreferences.setMockInitialValues({});
      final first = StorageService();
      await first.init();
      await first.setApiKey('gemini', 'AIzaSyPersisted');

      // Simulates an app relaunch: a brand new StorageService re-reading
      // from the same underlying secure storage / SharedPreferences mocks.
      final second = StorageService();
      await second.init();
      expect(second.getApiKey('gemini'), 'AIzaSyPersisted');
    });

    test('legacy groq key stored under the old SharedPreferences key migrates to secure storage', () async {
      SharedPreferences.setMockInitialValues({
        'Lauriva_api_key_groq': 'gsk_legacy_value',
      });
      final storage = StorageService();
      await storage.init();

      expect(storage.getApiKey('groq'), 'gsk_legacy_value');
    });
  });

  group('StorageService active provider & model selection', () {
    test('defaults to groq when nothing has been selected', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      expect(storage.getActiveProviderId(), 'groq');
    });

    test('persists active provider id across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final first = StorageService();
      await first.init();
      await first.setActiveProviderId('cerebras');

      final second = StorageService();
      await second.init();
      expect(second.getActiveProviderId(), 'cerebras');
    });

    test('per-provider selected model is isolated per provider id', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await storage.setSelectedModel('groq', 'llama-3.1-8b-instant');
      await storage.setSelectedModel('gemini', 'gemini-2.0-flash-lite');

      expect(storage.getSelectedModel('groq'), 'llama-3.1-8b-instant');
      expect(storage.getSelectedModel('gemini'), 'gemini-2.0-flash-lite');
      expect(storage.getSelectedModel('cerebras'), isNull);
    });
  });

  group('StorageService generation params & failover settings', () {
    test('temperature, max tokens, persona, and auto-failover round-trip with sane defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      expect(storage.getTemperature(), 0.3);
      expect(storage.getMaxTokens(), 2048);
      expect(storage.getPersona(), 'standard');
      expect(storage.getAutoFailover(), isTrue);

      await storage.setTemperature(0.9);
      await storage.setMaxTokens(4096);
      await storage.setPersona('creative');
      await storage.setAutoFailover(false);

      expect(storage.getTemperature(), 0.9);
      expect(storage.getMaxTokens(), 4096);
      expect(storage.getPersona(), 'creative');
      expect(storage.getAutoFailover(), isFalse);
    });

    test(
      'LoRA adapter and RAG context clear when set to null or blank',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.init();

        await storage.setLoraAdapter('my-adapter');
        expect(storage.getLoraAdapter(), 'my-adapter');
        await storage.setLoraAdapter('   ');
        expect(storage.getLoraAdapter(), isNull);

        await storage.setRagContext('grounding text');
        expect(storage.getRagContext(), 'grounding text');
        await storage.setRagContext(null);
        expect(storage.getRagContext(), isNull);
      },
    );
  });

  group('StorageService history persistence', () {
    test(
      'addHistoryItem caps the list at 50 entries, dropping the oldest',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.init();

        for (var i = 0; i < 55; i++) {
          await storage.addHistoryItem('output number $i');
        }

        final history = storage.getHistory();
        expect(history.length, 50);
        // Most recent insert is at the front; the oldest 5 were evicted.
        expect(history.first, 'output number 54');
        expect(history.contains('output number 0'), isFalse);
      },
    );

    test(
      'does not insert an immediate duplicate of the most recent output',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.init();

        await storage.addHistoryItem('same output');
        await storage.addHistoryItem('same output');

        expect(storage.getHistory().length, 1);
      },
    );
  });

  group('StorageService resilience and uninitialized fallback tests', () {
    test(
      'all getters return safe defaults even when storage is uninitialized',
      () {
        final uninitialized = StorageService();

        expect(uninitialized.getActiveProviderId(), equals('groq'));
        expect(uninitialized.getSpeechSpeed(), equals('normal'));
        expect(uninitialized.getThemeMode(), equals('system'));
        expect(uninitialized.getTargetLanguage(), equals('English'));
        expect(uninitialized.getHistory(), isEmpty);
        expect(uninitialized.getStructuredHistory(), isEmpty);
        expect(uninitialized.getTemperature(), equals(0.3));
        expect(uninitialized.getMaxTokens(), equals(2048));
        expect(uninitialized.getPersona(), equals('standard'));
        expect(uninitialized.getAutoFailover(), isTrue);
        expect(uninitialized.getLangsmithTracing(), isFalse);
        expect(uninitialized.getLoraAdapter(), isNull);
        expect(uninitialized.getRagContext(), isNull);
        expect(uninitialized.getCustomBaseUrl(), isNull);
        expect(uninitialized.getSelectedModel('groq'), isNull);
      },
    );

    test('safe mutations when uninitialized do not throw exceptions', () async {
      final uninitialized = StorageService();

      // Calling setters should safely handle null prefs without crashing
      await expectLater(
        uninitialized.setActiveProviderId('cerebras'),
        completes,
      );
      await expectLater(uninitialized.setSpeechSpeed('fast'), completes);
      await expectLater(uninitialized.setThemeMode('dark'), completes);
      await expectLater(uninitialized.setTargetLanguage('French'), completes);
      await expectLater(uninitialized.setTemperature(0.7), completes);
      await expectLater(uninitialized.setMaxTokens(1024), completes);
      await expectLater(uninitialized.setPersona('concise'), completes);
      await expectLater(uninitialized.setAutoFailover(false), completes);
      await expectLater(uninitialized.setLangsmithTracing(true), completes);
      await expectLater(uninitialized.clearHistory(), completes);
      await expectLater(uninitialized.removeHistoryItem(0), completes);
    });
  });

  group('slop auto-polish setting', () {
    test('defaults to true, persists, and reads the legacy key', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      expect(storage.getSlopAutoPolish(), isTrue);
      await storage.setSlopAutoPolish(false);
      expect(storage.getSlopAutoPolish(), isFalse);

      SharedPreferences.setMockInitialValues({'Lauriva_slop_auto_polish': false});
      final legacy = StorageService();
      await legacy.init();
      expect(legacy.getSlopAutoPolish(), isFalse);
    });
  });
}
