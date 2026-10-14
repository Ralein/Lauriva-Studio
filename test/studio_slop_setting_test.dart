import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/storage_service.dart';
import 'test_mocks.dart';

Future<(StudioProvider, StorageService)> _build() async {
  final storage = StorageService();
  await storage.init();
  final toast = ToastProvider();
  final history = HistoryProvider(storage: storage, toast: toast);
  final studio = StudioProvider(
    storage: storage,
    speech: SpeechProvider(storage: storage, toast: toast),
    llmSettings: LlmSettingsProvider(storage: storage),
    history: history,
    toast: toast,
    plagiarism: PlagiarismProvider(storage: storage, toast: toast, history: history),
  );
  return (studio, storage);
}

void main() {
  setUpAll(setupMockPlatformChannels);

  setUp(() {
    clearMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  test('slopAutoPolish defaults on, persists, and starts with no report', () async {
    final (studio, storage) = await _build();
    expect(studio.slopAutoPolish, isTrue);
    expect(studio.lastSlopReport, isNull);

    studio.setSlopAutoPolish(false);
    expect(studio.slopAutoPolish, isFalse);
    expect(storage.getSlopAutoPolish(), isFalse);
  });

  test('clearInput resets the slop report', () async {
    final (studio, _) = await _build();
    studio.clearInput();
    expect(studio.lastSlopReport, isNull);
    expect(studio.lastSlopRepair, isNull);
  });
}
