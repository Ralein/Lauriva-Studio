import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/toast_notification.dart';
import '../models/tts_highlight.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import 'toast_provider.dart';

/// Owns the device speech subsystem: microphone dictation (STT) recording
/// state and text-to-speech (TTS) playback state. Recording level/timer
/// updates stay on isolated ValueNotifiers rather than notifyListeners() so
/// high-frequency audio-level frames never trigger a full provider rebuild
/// (see AGENTS.md's streaming-performance rule).
class SpeechProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SpeechService _speechService;
  final TtsService _ttsService;
  final ToastProvider _toast;

  bool _isRecording = false;
  final ValueNotifier<double> soundLevelNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> recordingSecondsNotifier = ValueNotifier<int>(0);
  Timer? _recordingTimer;

  List<Map<String, String>> _availableVoices = [];
  bool _voicesLoaded = false;

  SpeechProvider({
    required StorageService storage,
    required ToastProvider toast,
    SpeechService? speechService,
    TtsService? ttsService,
  })  : _storageService = storage,
        _toast = toast,
        _speechService = speechService ?? SpeechService(),
        _ttsService = ttsService ?? TtsService() {
    _init();
  }

  void _init() {
    final speed = _storageService.getSpeechSpeed();
    final savedVoiceName = _storageService.getTtsVoiceName();
    final savedVoiceLocale = _storageService.getTtsVoiceLocale();

    _ttsService
        .init(
          savedVoiceName: savedVoiceName,
          savedVoiceLocale: savedVoiceLocale,
        )
        .then((_) {
      _ttsService.setSpeed(speed);
      _ttsService.onStateChanged = (state) {
        if (!_disposed) notifyListeners();
      };
      _ttsService.onError = (error) {
        _toast.showToast(error, ToastType.error);
        if (!_disposed) notifyListeners();
      };
      _availableVoices = List.of(_ttsService.availableVoices);
      _voicesLoaded = true;
      if (!_disposed) notifyListeners();
    });
  }

  bool get isRecording => _isRecording;
  double get soundLevel => soundLevelNotifier.value;
  int get recordingSeconds => recordingSecondsNotifier.value;
  String get formattedRecordingTime {
    final seconds = recordingSecondsNotifier.value;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  TtsState get speechState => _ttsService.state;
  String get speechSpeed => _ttsService.currentSpeed;
  List<Map<String, String>> get availableVoices => _availableVoices;
  Map<String, String>? get selectedVoice => _ttsService.selectedVoice;
  bool get voicesLoaded => _voicesLoaded;

  /// High-precision word highlight stream. Kept on an isolated ValueNotifier
  /// so per-word updates never trigger high-frequency provider rebuilds.
  ValueNotifier<TtsHighlight?> get highlightNotifier => _ttsService.highlightNotifier;
  TtsHighlight? get currentHighlight => _ttsService.currentHighlight;

  /// Full text being read or paused in TTS.
  String get fullTextBeingRead => _ttsService.fullTextBeingRead;

  /// Char offset where TTS playback was paused.
  int get pausedCharOffset => _ttsService.pausedCharOffset;

  /// Word token index where TTS playback was paused.
  int get pausedTokenIndex => _ttsService.pausedTokenIndex;

  /// Low-level recording primitive. The caller (StudioProvider) owns the
  /// resulting transcribed text — this provider only owns recording UI state.
  Future<bool> startListening({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  }) async {
    recordingSecondsNotifier.value = 0;
    final success = await _speechService.startListening(
      onResult: onResult,
      localeId: localeId,
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_isRecording) {
            _resetRecordingState();
          }
        }
      },
      onError: (error) {
        _resetRecordingState();
        _toast.showToast(error, ToastType.error);
      },
      onSoundLevel: (level) {
        soundLevelNotifier.value = level;
      },
    );

    if (success) {
      _isRecording = true;
      recordingSecondsNotifier.value = 0;
      _recordingTimer?.cancel();
      // Isolated periodic tick on recordingSecondsNotifier prevents 60fps widget rebuilds
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        recordingSecondsNotifier.value++;
      });
      notifyListeners();
    }
    return success;
  }

  Future<void> stopListening() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _speechService.stopListening();
    _resetRecordingState();
  }

  void _resetRecordingState() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _isRecording = false;
    soundLevelNotifier.value = 0.0;
    recordingSecondsNotifier.value = 0;
    notifyListeners();
  }

  Future<void> speak(String text, {String? targetLanguage}) async {
    await _ttsService.speak(text, targetLanguage: targetLanguage);
    notifyListeners();
  }

  Future<void> pause() async {
    await _ttsService.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    await _ttsService.resume();
    notifyListeners();
  }

  Future<void> stop() async {
    await _ttsService.stop();
    notifyListeners();
  }

  /// Stops playback only if TTS is currently active — used before starting a
  /// new operation (recording, transform, plagiarism fix) that should not
  /// overlap with in-flight speech.
  void stopIfActive() {
    if (speechState != TtsState.idle) {
      _ttsService.stop();
    }
  }

  Future<void> setSpeed(String speed, {String? replayText, String? targetLanguage}) async {
    await _ttsService.setSpeed(speed);
    await _storageService.setSpeechSpeed(speed);
    if (speechState == TtsState.playing && replayText != null && replayText.trim().isNotEmpty) {
      await _ttsService.speak(replayText, targetLanguage: targetLanguage);
    }
    notifyListeners();
  }

  /// Refreshes the device voice list and notifies listeners.
  Future<void> refreshVoices() async {
    final savedVoiceName = _storageService.getTtsVoiceName();
    final savedVoiceLocale = _storageService.getTtsVoiceLocale();
    _availableVoices = await _ttsService.refreshVoices(
      savedVoiceName: savedVoiceName,
      savedVoiceLocale: savedVoiceLocale,
    );
    _voicesLoaded = true;
    notifyListeners();
  }

  /// Selects a TTS voice and persists the choice.
  Future<void> selectVoice(Map<String, String>? voice) async {
    if (voice == null) {
      await _ttsService.refreshVoices();
      await _storageService.clearTtsVoice();
    } else {
      await _ttsService.setVoice(voice);
      await _storageService.setTtsVoice(
        name: voice['name'] ?? '',
        locale: voice['locale'] ?? '',
      );
    }
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _ttsService.onStateChanged = null;
    _ttsService.onError = null;
    soundLevelNotifier.dispose();
    recordingSecondsNotifier.dispose();
    _recordingTimer?.cancel();
    // Wrap platform-channel teardown calls — these can throw if the platform
    // side has already been torn down during app shutdown.
    try {
      _speechService.cancelListening();
    } catch (_) {}
    try {
      _ttsService.stop();
    } catch (_) {}
    super.dispose();
  }
}
