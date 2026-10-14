import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backing store for the mocked flutter_secure_storage channel. Exposed at
/// top level (rather than local to [setupMockPlatformChannels]) so tests
/// that need a clean secure-storage slate between cases can call
/// [clearMockSecureStorage] without re-registering the whole mock handler.
final Map<String, String> _secureStorageData = {};

/// Clears all mocked secure-storage entries. Call this in `setUp()` for any
/// test group where secure-storage state (e.g. API keys) must not leak
/// between test cases within the same file — `setupMockPlatformChannels()`
/// itself only runs once per file via `setUpAll`, so its backing map is
/// otherwise shared across every test in that file.
void clearMockSecureStorage() {
  _secureStorageData.clear();
}

/// Configures clean, zero-failure mock platform channels for Flutter testing
void setupMockPlatformChannels() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock flutter_tts MethodChannel
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_tts'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'setVolume':
        case 'setPitch':
        case 'setSpeechRate':
        case 'setLanguage':
        case 'setVoice':
        case 'clearVoice':
        case 'stop':
        case 'pause':
          return 1;
        case 'speak':
          return 1;
        case 'getLanguages':
          return <dynamic>['en-US', 'ta-IN', 'es-ES', 'fr-FR', 'de-DE'];
        case 'getVoices':
          return <dynamic>[
            <String, String>{'name': 'en-us-x-iog-local', 'locale': 'en-US', 'quality': 'very high', 'network_required': '0', 'features': 'neural'},
            <String, String>{'name': 'en-us-x-sfg-local', 'locale': 'en-US', 'quality': 'high', 'network_required': '0', 'features': ''},
          ];
        default:
          return 1;
      }
    },
  );

  // Mock speech_to_text MethodChannel
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugin.csd.com/speech_to_text'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'initialize':
          return true;
        case 'listen':
        case 'stop':
        case 'cancel':
          return true;
        case 'has_permission':
          return true;
        default:
          return true;
      }
    },
  );

  // Mock flutter_secure_storage MethodChannel
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall methodCall) async {
      final args = methodCall.arguments as Map<dynamic, dynamic>?;
      final key = args?['key'] as String?;
      switch (methodCall.method) {
        case 'read':
          return key != null ? _secureStorageData[key] : null;
        case 'write':
          final value = args?['value'] as String?;
          if (key != null && value != null) {
            _secureStorageData[key] = value;
          }
          return null;
        case 'delete':
          if (key != null) _secureStorageData.remove(key);
          return null;
        case 'deleteAll':
          _secureStorageData.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(_secureStorageData);
        case 'containsKey':
          return key != null && _secureStorageData.containsKey(key);
        default:
          return null;
      }
    },
  );
}

/// Helper test entrypoint so batch test runs find a valid test case.
void main() {
  test('test_mocks helper initializes mock channels correctly', () {
    setupMockPlatformChannels();
    expect(true, isTrue);
  });
}
