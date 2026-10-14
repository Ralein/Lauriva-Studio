import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/tts_highlight.dart';

enum TtsState { idle, playing, paused }

/// High-fidelity Text-To-Speech service supporting sentence-preserving
/// chunking for arbitrarily long documents (preventing Android 4000-char
/// -8 ERROR_INVALID_REQUEST limits), automatic neural/best voice selection,
/// custom voice selection, pause/resume capabilities, and microsecond-precise
/// word-by-word speech synchronization & highlighting.
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();

  TtsState _state = TtsState.idle;
  double _rate = 0.5; // flutter_tts normalized rate (0.5 represents normal 1.0x)
  String _currentSpeed = 'normal'; // 'slow', 'normal', 'fast'
  String _currentLanguage = 'en-US';

  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;

  List<String> _chunks = [];
  List<TtsChunkSpan> _chunkSpans = [];
  int _currentChunkIndex = 0;

  // ── Word-Level Highlight State ─────────────────────────────────────────────
  final ValueNotifier<TtsHighlight?> highlightNotifier = ValueNotifier<TtsHighlight?>(null);
  String _fullTextBeingRead = '';
  List<TtsWordToken> _tokens = [];
  int _lastReportedTokenIndex = 0;
  int _fallbackTokenIndex = 0;
  int _pausedCharOffset = 0;
  int _pausedTokenIndex = 0;
  bool _nativeProgressReceived = false;
  Timer? _adaptiveSyncTimer;

  TtsState get state => _state;
  String get currentSpeed => _currentSpeed;
  String get currentLanguage => _currentLanguage;
  List<Map<String, String>> get availableVoices => List.unmodifiable(_availableVoices);
  Map<String, String>? get selectedVoice => _selectedVoice;
  int get currentChunkIndex => _currentChunkIndex;
  int get totalChunks => _chunks.length;
  bool get isSpeakingChunks => _chunks.length > 1;

  /// Full source document text currently being spoken or paused.
  String get fullTextBeingRead => _fullTextBeingRead;

  /// Character offset in [fullTextBeingRead] where speech was paused.
  int get pausedCharOffset => _pausedCharOffset;

  /// Word token index where speech was paused.
  int get pausedTokenIndex => _pausedTokenIndex;

  /// Current active word highlight token, or null if idle.
  TtsHighlight? get currentHighlight => highlightNotifier.value;

  Function(TtsState state)? onStateChanged;
  Function(String error)? onError;

  Future<void> init({String? savedVoiceName, String? savedVoiceLocale}) async {
    try {
      _flutterTts.setStartHandler(() {
        _state = TtsState.playing;
        onStateChanged?.call(_state);
        _startAdaptiveSyncTimer();
      });

      _flutterTts.setCompletionHandler(() async {
        // When paused, native engine may emit completion for stopped slice — ignore it
        if (_state == TtsState.paused) return;

        if (_state == TtsState.playing && _currentChunkIndex + 1 < _chunkSpans.length) {
          _currentChunkIndex++;
          try {
            final res = await _flutterTts.speak(_chunkSpans[_currentChunkIndex].text);
            if (res != 1) {
              _finishPlayback();
            }
          } catch (e) {
            debugPrint('TTS chunk progression error: $e');
            _finishPlayback();
          }
        } else {
          _finishPlayback();
        }
      });

      _flutterTts.setPauseHandler(() {
        _state = TtsState.paused;
        _adaptiveSyncTimer?.cancel();
        _adaptiveSyncTimer = null;
        onStateChanged?.call(_state);
      });

      _flutterTts.setContinueHandler(() {
        _state = TtsState.playing;
        onStateChanged?.call(_state);
        if (!_nativeProgressReceived) {
          _startAdaptiveSyncTimer();
        }
      });

      _flutterTts.setCancelHandler(() {
        // If we are intentionally paused, do not wipe playback session
        if (_state == TtsState.paused) return;
        _finishPlayback();
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('TTS Error: $msg');
        if (_state == TtsState.paused) return;
        _finishPlayback();
        onError?.call(msg.toString());
      });

      // Platform real-time word boundary handler (Android onRangeStart & iOS willSpeakRangeOfSpeechString)
      _flutterTts.setProgressHandler((String text, int startOffset, int endOffset, String word) {
        _onPlatformProgress(text, startOffset, endOffset, word);
      });

      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await setSpeed(_currentSpeed);

      await _loadVoices(savedVoiceName: savedVoiceName, savedVoiceLocale: savedVoiceLocale);
    } catch (e) {
      debugPrint('TTS Init error: $e');
    }
  }

  void _finishPlayback() {
    _adaptiveSyncTimer?.cancel();
    _adaptiveSyncTimer = null;
    _state = TtsState.idle;
    _chunks = [];
    _chunkSpans = [];
    _tokens = const [];
    _currentChunkIndex = 0;
    _lastReportedTokenIndex = 0;
    _fallbackTokenIndex = 0;
    _pausedCharOffset = 0;
    _pausedTokenIndex = 0;
    _nativeProgressReceived = false;
    _fullTextBeingRead = '';
    highlightNotifier.value = null;
    onStateChanged?.call(_state);
  }

  /// Refreshes and returns the list of voices available on the device
  Future<List<Map<String, String>>> refreshVoices({
    String? savedVoiceName,
    String? savedVoiceLocale,
  }) async {
    await _loadVoices(savedVoiceName: savedVoiceName, savedVoiceLocale: savedVoiceLocale);
    return _availableVoices;
  }

  Future<void> _loadVoices({String? savedVoiceName, String? savedVoiceLocale}) async {
    try {
      final dynamic raw = await _flutterTts.getVoices;
      if (raw is List) {
        final list = <Map<String, String>>[];
        for (final item in raw) {
          if (item is Map) {
            final name = item['name']?.toString() ?? '';
            final locale = item['locale']?.toString() ?? '';
            if (name.isNotEmpty) {
              list.add({
                'name': name,
                'locale': locale,
                'quality': item['quality']?.toString() ?? '',
                'network_required': item['network_required']?.toString() ?? '',
                'features': item['features']?.toString() ?? '',
              });
            }
          }
        }
        _availableVoices = list;
      }

      // 1. If saved voice exists, apply it
      if (savedVoiceName != null && savedVoiceName.isNotEmpty) {
        final match = _availableVoices.where((v) => v['name'] == savedVoiceName).firstOrNull;
        if (match != null) {
          _selectedVoice = match;
          await _flutterTts.setVoice(_selectedVoice!);
          return;
        }
      }

      // 2. Automatically select the best voice (highest fidelity / neural / wavenet)
      final best = findBestVoice(_availableVoices, targetLocale: _currentLanguage);
      if (best != null) {
        _selectedVoice = best;
        await _flutterTts.setVoice(_selectedVoice!);
        debugPrint('TTS: Selected best voice: ${_selectedVoice!['name']}');
      }
    } catch (e) {
      debugPrint('TTS loadVoices error: $e');
    }
  }

  /// Sets speech rate based on preset ('slow' = 0.7x, 'normal' = 1.0x, 'fast' = 1.4x)
  Future<void> setSpeed(String speed) async {
    _currentSpeed = speed;
    if (speed == 'slow') {
      _rate = 0.35;
    } else if (speed == 'fast') {
      _rate = 0.7;
    } else {
      _rate = 0.5; // normal 1.0x
    }

    try {
      await _flutterTts.setSpeechRate(_rate);
    } catch (e) {
      debugPrint('Error setting TTS rate: $e');
    }
  }

  /// Manually select a voice
  Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoice = voice;
    try {
      await _flutterTts.setVoice(voice);
    } catch (e) {
      debugPrint('Error setting TTS voice: $e');
    }
  }

  /// Splits long text into sentence-safe chunks that strictly obey the platform
  /// TTS length ceiling (typically 4000 characters on Android).
  /// Kept for backwards compatibility.
  static List<String> splitTextIntoChunks(String text, {int maxChunkLength = 1200}) {
    final spans = TtsChunkSpan.createChunks(text, maxChunkLength: maxChunkLength);
    return spans.map((s) => s.text).toList();
  }

  /// Finds and ranks the highest-quality natural / neural voice for a locale.
  static Map<String, String>? findBestVoice(
    List<Map<String, String>> voices, {
    String targetLocale = 'en-US',
  }) {
    if (voices.isEmpty) return null;

    final targetLower = targetLocale.toLowerCase().replaceAll('_', '-');
    final langPrefix = targetLower.split('-').first;

    var candidates = voices.where((v) {
      final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
      return loc == targetLower;
    }).toList();

    if (candidates.isEmpty) {
      candidates = voices.where((v) {
        final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
        return loc.startsWith(langPrefix);
      }).toList();
    }

    if (candidates.isEmpty) {
      candidates = List.of(voices);
    }

    int scoreVoice(Map<String, String> v) {
      int score = 0;
      final name = (v['name'] ?? '').toLowerCase();
      final quality = (v['quality'] ?? '').toLowerCase();
      final features = (v['features'] ?? '').toLowerCase();
      final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');

      // 1. Explicit Quality rating from platform
      if (quality == 'very high') {
        score += 100;
      } else if (quality == 'high') {
        score += 60;
      } else if (quality == 'normal') {
        score += 20;
      } else if (quality == 'low' || quality == 'very low') {
        score -= 50;
      }

      // 2. High fidelity / Neural / Natural voice tags
      if (name.contains('neural') || features.contains('neural')) score += 80;
      if (name.contains('natural') || features.contains('natural')) score += 80;
      if (name.contains('wavenet') || features.contains('wavenet')) score += 70;
      if (name.contains('ptts') || name.contains('samsung')) score += 60;
      if (name.contains('-network') || features.contains('network')) score += 50;
      if (name.contains('premium') || name.contains('enhanced')) score += 50;

      // 3. Exact locale match bonus
      if (loc == targetLower) score += 30;

      // 4. Deprecate legacy robotic server fallbacks
      if (name.contains('-server') || name.contains('legacy') || name.contains('robotic')) {
        score -= 40;
      }

      return score;
    }

    candidates.sort((a, b) => scoreVoice(b).compareTo(scoreVoice(a)));
    return candidates.first;
  }

  bool _voiceMatchesLanguage(Map<String, String> voice, String language) {
    final vLoc = (voice['locale'] ?? '').toLowerCase().replaceAll('_', '-');
    final target = language.toLowerCase().replaceAll('_', '-');
    if (vLoc == target) return true;
    final prefix = target.split('-').first;
    return vLoc.startsWith(prefix);
  }

  /// Speaks the given text with automatic language detection, sentence-chunked
  /// delivery for long documents, and best voice application.
  Future<void> speak(String text, {String? targetLanguage}) async {
    if (text.trim().isEmpty) return;

    // Reset previous speech state cleanly
    await stop();

    _fullTextBeingRead = text;
    _tokens = TtsWordToken.tokenize(text);
    _chunkSpans = TtsChunkSpan.createChunks(text);
    _chunks = _chunkSpans.map((s) => s.text).toList();
    _currentChunkIndex = 0;
    _lastReportedTokenIndex = 0;
    _fallbackTokenIndex = 0;
    _pausedCharOffset = 0;
    _pausedTokenIndex = 0;
    _nativeProgressReceived = false;

    if (_chunkSpans.isEmpty) return;

    // Language resolution
    final hasTamil = RegExp(r'[\u0B80-\u0BFF]').hasMatch(text);
    if (hasTamil || targetLanguage == 'Tamil') {
      _currentLanguage = 'ta-IN';
    } else if (targetLanguage == 'Spanish') {
      _currentLanguage = 'es-ES';
    } else if (targetLanguage == 'French') {
      _currentLanguage = 'fr-FR';
    } else if (targetLanguage == 'German') {
      _currentLanguage = 'de-DE';
    } else if (targetLanguage == 'Hindi') {
      _currentLanguage = 'hi-IN';
    } else if (targetLanguage == 'Japanese') {
      _currentLanguage = 'ja-JP';
    } else {
      _currentLanguage = 'en-US';
    }

    try {
      await _flutterTts.setLanguage(_currentLanguage);
      await _flutterTts.setSpeechRate(_rate);

      if (_selectedVoice != null && _voiceMatchesLanguage(_selectedVoice!, _currentLanguage)) {
        await _flutterTts.setVoice(_selectedVoice!);
      } else if (_availableVoices.isNotEmpty) {
        final bestForLang = findBestVoice(_availableVoices, targetLocale: _currentLanguage);
        if (bestForLang != null) {
          await _flutterTts.setVoice(bestForLang);
        }
      }

      _state = TtsState.playing;
      onStateChanged?.call(_state);

      // Instantly highlight the first word for immediate visual feedback
      if (_tokens.isNotEmpty) {
        final first = _tokens.first;
        highlightNotifier.value = TtsHighlight(
          fullText: _fullTextBeingRead,
          charStart: first.charStart,
          charEnd: first.charEnd,
          word: first.word,
          wordIndex: first.index,
          totalWords: _tokens.length,
          progress: 1.0 / _tokens.length,
          chunkIndex: 0,
          totalChunks: _chunkSpans.length,
        );
      }

      final result = await _flutterTts.speak(_chunkSpans[_currentChunkIndex].text);
      if (result != 1) {
        _finishPlayback();
      }
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      _finishPlayback();
      onError?.call('Could not play speech on this device: $e');
    }
  }

  /// Processes platform-channel word progress events (`speak.onProgress`).
  /// Maps chunk-relative character offsets to global document coordinates
  /// and updates [highlightNotifier] with 100% precision.
  void _onPlatformProgress(String text, int startOffset, int endOffset, String word) {
    if (_state != TtsState.playing) return;
    _nativeProgressReceived = true;
    _adaptiveSyncTimer?.cancel();

    if (_tokens.isEmpty || _chunkSpans.isEmpty) return;

    final currentChunk = (_currentChunkIndex < _chunkSpans.length)
        ? _chunkSpans[_currentChunkIndex]
        : _chunkSpans.last;

    final globalStart = currentChunk.charStart + startOffset;
    final globalEnd = currentChunk.charStart + endOffset;

    final matched = _findTokenForRange(globalStart, globalEnd, word);
    if (matched != null) {
      _lastReportedTokenIndex = matched.index;
      _fallbackTokenIndex = matched.index;

      highlightNotifier.value = TtsHighlight(
        fullText: _fullTextBeingRead,
        charStart: matched.charStart,
        charEnd: matched.charEnd,
        word: matched.word,
        wordIndex: matched.index,
        totalWords: _tokens.length,
        progress: (matched.index + 1) / _tokens.length,
        chunkIndex: _currentChunkIndex,
        totalChunks: _chunkSpans.length,
      );
    }
  }

  /// 3-Tier Matcher:
  /// 1. Direct overlap: matches exact token boundaries in the document
  /// 2. Proximity: handles small UTF-16 code-point differences
  /// 3. Lexical search: locates the word in a forward window
  TtsWordToken? _findTokenForRange(int globalStart, int globalEnd, String word) {
    if (_tokens.isEmpty) return null;

    // 1. Direct overlap
    for (int i = 0; i < _tokens.length; i++) {
      final token = _tokens[i];
      if (token.charStart < globalEnd && token.charEnd > globalStart) {
        return token;
      }
    }

    // 2. Proximity search around globalStart
    TtsWordToken? closest;
    int minDiff = 1000000;
    for (int i = 0; i < _tokens.length; i++) {
      final token = _tokens[i];
      final diff = (token.charStart - globalStart).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = token;
      }
    }
    if (minDiff <= 12) {
      return closest;
    }

    // 3. Forward lexical search
    final clean = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
    if (clean.isNotEmpty) {
      final searchStart = (_lastReportedTokenIndex - 2).clamp(0, _tokens.length - 1);
      final searchEnd = (_lastReportedTokenIndex + 15).clamp(0, _tokens.length);
      for (int i = searchStart; i < searchEnd; i++) {
        if (_tokens[i].word.toLowerCase() == clean) {
          return _tokens[i];
        }
      }
    }

    return closest;
  }

  /// Starts the adaptive timing engine. Operates as a seamless watchdog
  /// and fallback for platforms or devices where `onRangeStart` is delayed
  /// or unsupported, guaranteeing that highlighting never gets stuck.
  void _startAdaptiveSyncTimer() {
    _adaptiveSyncTimer?.cancel();
    if (_tokens.isEmpty) return;

    double multiplier;
    if (_currentSpeed == 'slow') {
      multiplier = 1.45;
    } else if (_currentSpeed == 'fast') {
      multiplier = 0.72;
    } else {
      multiplier = 1.0;
    }

    // Initial grace window: wait 300ms to allow native onProgress to take over
    Timer(const Duration(milliseconds: 300), () {
      if (_state != TtsState.playing || _nativeProgressReceived) return;
      _scheduleNextAdaptiveStep(multiplier);
    });
  }

  void _scheduleNextAdaptiveStep(double multiplier) {
    if (_state != TtsState.playing || _nativeProgressReceived) return;
    if (_fallbackTokenIndex >= _tokens.length) return;

    final token = _tokens[_fallbackTokenIndex];
    int baseMs = (340 * multiplier).round();

    // Syllable/word length heuristic
    if (token.word.length > 5) {
      baseMs += (token.word.length - 5) * 20;
    }

    // Punctuation pause heuristic
    if (token.charEnd < _fullTextBeingRead.length) {
      final nextSlice = _fullTextBeingRead.substring(
        token.charEnd,
        (token.charEnd + 3).clamp(0, _fullTextBeingRead.length),
      );
      if (nextSlice.contains('.') || nextSlice.contains('!') || nextSlice.contains('?')) {
        baseMs += (260 * multiplier).round();
      } else if (nextSlice.contains(',') || nextSlice.contains(';') || nextSlice.contains(':')) {
        baseMs += (130 * multiplier).round();
      }
    }

    _adaptiveSyncTimer = Timer(Duration(milliseconds: baseMs), () {
      if (_state != TtsState.playing || _nativeProgressReceived) return;

      _fallbackTokenIndex++;
      if (_fallbackTokenIndex < _tokens.length) {
        final nextToken = _tokens[_fallbackTokenIndex];
        _lastReportedTokenIndex = nextToken.index;

        highlightNotifier.value = TtsHighlight(
          fullText: _fullTextBeingRead,
          charStart: nextToken.charStart,
          charEnd: nextToken.charEnd,
          word: nextToken.word,
          wordIndex: nextToken.index,
          totalWords: _tokens.length,
          progress: (nextToken.index + 1) / _tokens.length,
          chunkIndex: _currentChunkIndex,
          totalChunks: _chunkSpans.length,
        );

        _scheduleNextAdaptiveStep(multiplier);
      }
    });
  }

  /// Pauses playback and freezes the current word position so that clicking
  /// play subsequently resumes reading from this exact position.
  Future<void> pause() async {
    if (_state != TtsState.playing) return;

    _state = TtsState.paused;
    _adaptiveSyncTimer?.cancel();
    _adaptiveSyncTimer = null;

    // Capture the exact word token and character offset where playback was paused
    if (highlightNotifier.value != null) {
      _pausedCharOffset = highlightNotifier.value!.charStart;
      _pausedTokenIndex = highlightNotifier.value!.wordIndex;
    } else if (_tokens.isNotEmpty) {
      final safeIdx = _lastReportedTokenIndex.clamp(0, _tokens.length - 1);
      _pausedCharOffset = _tokens[safeIdx].charStart;
      _pausedTokenIndex = safeIdx;
    }

    try {
      // Stop native audio engine output immediately
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS pause platform stop error: $e');
    }

    onStateChanged?.call(_state);
  }

  /// Resumes playback starting from the exact word where speech was paused.
  Future<void> resume() async {
    if (_state != TtsState.paused) return;
    if (_fullTextBeingRead.isEmpty || _pausedCharOffset >= _fullTextBeingRead.length) {
      _finishPlayback();
      return;
    }

    _state = TtsState.playing;
    onStateChanged?.call(_state);

    // Calculate remainder of document starting cleanly from the paused word boundary
    var resumeOffset = _pausedCharOffset;
    while (resumeOffset < _fullTextBeingRead.length &&
        _fullTextBeingRead[resumeOffset].trim().isEmpty) {
      resumeOffset++;
    }

    final remainingText = _fullTextBeingRead.substring(resumeOffset);
    if (remainingText.trim().isEmpty) {
      _finishPlayback();
      return;
    }

    // Create sentence-safe chunks for the remaining text with global char offset base
    _chunkSpans = TtsChunkSpan.createChunks(
      remainingText,
      baseOffset: resumeOffset,
    );
    _chunks = _chunkSpans.map((s) => s.text).toList();
    _currentChunkIndex = 0;
    _lastReportedTokenIndex = _pausedTokenIndex;
    _fallbackTokenIndex = _pausedTokenIndex;
    _nativeProgressReceived = false;

    // Immediately highlight the paused token so visual feedback is instant
    if (_pausedTokenIndex < _tokens.length) {
      final token = _tokens[_pausedTokenIndex];
      highlightNotifier.value = TtsHighlight(
        fullText: _fullTextBeingRead,
        charStart: token.charStart,
        charEnd: token.charEnd,
        word: token.word,
        wordIndex: token.index,
        totalWords: _tokens.length,
        progress: (token.index + 1) / _tokens.length,
        chunkIndex: 0,
        totalChunks: _chunkSpans.length,
      );
    }

    // Start adaptive timer fallback from _pausedTokenIndex
    _startAdaptiveSyncTimer();

    try {
      final res = await _flutterTts.speak(_chunkSpans[0].text);
      if (res != 1) {
        _finishPlayback();
      }
    } catch (e) {
      debugPrint('TTS resume error: $e');
      _finishPlayback();
    }
  }

  /// Stops playback and completely resets position so that next playback
  /// begins cleanly from the start (beginning) of the document.
  Future<void> stop() async {
    _adaptiveSyncTimer?.cancel();
    _adaptiveSyncTimer = null;
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS stop failed: $e');
    } finally {
      _finishPlayback();
    }
  }

  void dispose() {
    _adaptiveSyncTimer?.cancel();
    _adaptiveSyncTimer = null;
    highlightNotifier.dispose();
  }
}
