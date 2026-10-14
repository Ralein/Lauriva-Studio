import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  String _lastError = '';
  List<LocaleName> _locales = [];
  Function(String status)? _currentStatusCallback;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isAvailable => _speech.isAvailable;
  String get lastError => _lastError;
  List<LocaleName> get locales => _locales;

  /// Resolves the BCP-47 language tag for a language name selected in Studio
  static String getLocaleForLanguage(String language) {
    switch (language.toLowerCase()) {
      case 'spanish':
        return 'es_ES';
      case 'french':
        return 'fr_FR';
      case 'german':
        return 'de_DE';
      case 'italian':
        return 'it_IT';
      case 'portuguese':
        return 'pt_PT';
      case 'hindi':
        return 'hi_IN';
      case 'japanese':
        return 'ja_JP';
      case 'chinese':
        return 'zh_CN';
      case 'korean':
        return 'ko_KR';
      case 'arabic':
        return 'ar_SA';
      case 'russian':
        return 'ru_RU';
      case 'dutch':
        return 'nl_NL';
      case 'turkish':
        return 'tr_TR';
      case 'polish':
        return 'pl_PL';
      case 'english':
      default:
        return 'en_US';
    }
  }

  /// Initialize the speech recognition engine and request microphone permission
  Future<bool> initialize({
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    // Explicit runtime microphone permission check (required for Android 14/15/16)
    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final req = await Permission.microphone.request();
        if (!req.isGranted) {
          onError?.call('Microphone permission is required for voice input.');
          return false;
        }
      }
    } catch (e) {
      debugPrint('Permission request exception: $e');
    }

    if (_isInitialized) return true;

    try {
      _isInitialized = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Speech status: $status');
          _isListening = _speech.isListening;
          _currentStatusCallback?.call(status);
          onStatus?.call(status);
        },
        onError: (SpeechRecognitionError errorNotification) {
          debugPrint('Speech error: ${errorNotification.errorMsg}');
          _lastError = errorNotification.errorMsg;
          _isListening = false;

          final rawMsg = errorNotification.errorMsg.toLowerCase();
          String userFriendlyMsg;

          if (rawMsg.contains('error_no_match') ||
              rawMsg.contains('error_speech_timeout')) {
            _currentStatusCallback?.call('done');
            userFriendlyMsg = 'No speech detected. Please speak closer to the mic.';
          } else if (rawMsg.contains('error_network')) {
            userFriendlyMsg =
                'Speech recognition network error. Please check your connection.';
          } else if (rawMsg.contains('error_audio')) {
            userFriendlyMsg = 'Audio recording error. Please check microphone settings.';
          } else if (rawMsg.contains('error_permission')) {
            userFriendlyMsg = 'Microphone permission required for voice input.';
          } else if (rawMsg.contains('error_busy')) {
            userFriendlyMsg = 'Speech recognizer busy. Please tap mic again.';
          } else {
            userFriendlyMsg = errorNotification.errorMsg;
          }

          onError?.call(userFriendlyMsg);
        },
        debugLogging: kDebugMode,
      );

      if (_isInitialized) {
        try {
          _locales = await _speech.locales();
        } catch (_) {
          // Some platforms might not support listing locales
        }
      }

      return _isInitialized;
    } catch (e) {
      debugPrint('Speech initialization exception: $e');
      _lastError = e.toString();
      return false;
    }
  }

  /// Start listening for voice input
  Future<bool> startListening({
    required Function(String words, bool isFinal) onResult,
    required Function(String error) onError,
    Function(String status)? onStatus,
    Function(double level)? onSoundLevel,
    String? localeId,
  }) async {
    _currentStatusCallback = onStatus;

    if (!_isInitialized) {
      final initialized = await initialize(onStatus: onStatus, onError: onError);
      if (!initialized) {
        onError('Speech recognition could not be initialized or microphone permission was denied.');
        return false;
      }
    }

    if (_speech.isListening) {
      await stopListening();
    }

    _lastError = '';

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        onSoundLevelChange: onSoundLevel,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          pauseFor: const Duration(seconds: 5),
          listenFor: const Duration(minutes: 5),
          localeId: localeId,
        ),
      );

      _isListening = true;
      return true;
    } catch (e) {
      debugPrint('Failed to start listening: $e');
      _lastError = e.toString();
      _isListening = false;
      onError('Failed to start microphone: $e');
      return false;
    }
  }

  /// Stop listening and commit results
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    _isListening = false;
  }

  /// Cancel listening and discard
  Future<void> cancelListening() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
    _isListening = false;
  }
}
