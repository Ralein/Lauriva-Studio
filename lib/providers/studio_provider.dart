import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/feature_type.dart';
import '../models/history_record.dart';
import '../models/llm_provider.dart';
import '../models/toast_notification.dart';
import '../services/forensic/humanizer/algorithmic_humanizer_service.dart';
import '../services/llm_service.dart';
import '../services/slop_linter.dart';
import '../services/slop_repair_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import 'history_provider.dart';
import 'llm_settings_provider.dart';
import 'plagiarism_provider.dart';
import 'speech_provider.dart';
import 'toast_provider.dart';
import '../services/rephrase_service.dart';

/// Owns the shared text workspace (input/output panes, active feature,
/// streaming state) and orchestrates a transform end-to-end: calling the
/// LLM, kicking off a post-transform plagiarism score, and persisting
/// history — composing the focused [SpeechProvider], [LlmSettingsProvider],
/// [HistoryProvider], [ToastProvider], and [PlagiarismProvider] rather than
/// owning their concerns directly.
class StudioProvider extends ChangeNotifier {
  final StorageService _storageService;
  final LlmService _llmService;
  final SpeechProvider _speech;
  final LlmSettingsProvider _llmSettings;
  final HistoryProvider _history;
  final ToastProvider _toast;
  final PlagiarismProvider _plagiarism;
  final RephraseService _rephraseService;
  final SlopRepairService _slopRepair;

  StudioProvider({
    required StorageService storage,
    required SpeechProvider speech,
    required LlmSettingsProvider llmSettings,
    required HistoryProvider history,
    required ToastProvider toast,
    required PlagiarismProvider plagiarism,
    LlmService? llmService,
    RephraseService? rephraseService,
    SlopRepairService? slopRepairService,
  })  : _storageService = storage,
        _speech = speech,
        _llmSettings = llmSettings,
        _history = history,
        _toast = toast,
        _plagiarism = plagiarism,
        _llmService = llmService ?? LlmService(),
        _rephraseService = rephraseService ?? RephraseService(llmService: llmService),
        _slopRepair = slopRepairService ?? SlopRepairService(llmService: llmService) {
    _selectedLanguage = _storageService.getTargetLanguage();
    _slopAutoPolish = _storageService.getSlopAutoPolish();
  }

  String _inputText = '';
  String _preRecordingText = '';
  String _outputText = '';
  bool _isLoading = false;
  bool _isStreaming = false;
  StreamSubscription<String>? _streamingSubscription;
  Timer? _streamingThrottleTimer; // tracked at class level for stopGeneration() cleanup
  Timer? _generationTimeoutGuard; // 5-min watchdog: kills zombie SSE connections
  String _activeFeatureId = 'Rephrase';
  String _studioActionId = 'Rephrase';
  String _selectedLanguage = 'English';
  bool _showTranslateMenu = false;
  bool _copied = false;
  bool _slopAutoPolish = true;
  bool _isPolishing = false;
  SlopReport? _lastSlopReport;
  SlopRepairResult? _lastSlopRepair;

  // Getters
  String get inputText => _inputText;
  String get outputText => _outputText;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String get activeFeatureId => _activeFeatureId;
  String get studioActionId {
    final raw = FeatureType.fromId(_studioActionId);
    if (raw == null || raw == FeatureType.humanize || raw == FeatureType.plagiarismCheck) {
      return FeatureType.rephrase.id;
    }
    return _studioActionId;
  }
  String get selectedLanguage => _selectedLanguage;
  bool get showTranslateMenu => _showTranslateMenu;
  bool get copied => _copied;
  StorageService get storageService => _storageService;

  /// Whether Studio rewrites get the lint -> targeted repair -> verify pass.
  bool get slopAutoPolish => _slopAutoPolish;

  /// True while the repair pass runs (isLoading stays true throughout).
  bool get isPolishing => _isPolishing;

  /// Lint report for the final output of the latest run; null until one finishes.
  SlopReport? get lastSlopReport => _lastSlopReport;

  /// Repair outcome of the latest run, null when no repair was attempted.
  SlopRepairResult? get lastSlopRepair => _lastSlopRepair;

  void setSlopAutoPolish(bool enabled) {
    if (_slopAutoPolish == enabled) return;
    _slopAutoPolish = enabled;
    _storageService.setSlopAutoPolish(enabled);
    notifyListeners();
  }

  void toggleTranslateMenu() {
    _showTranslateMenu = !_showTranslateMenu;
    notifyListeners();
  }

  void closeTranslateMenu() {
    if (_showTranslateMenu) {
      _showTranslateMenu = false;
      notifyListeners();
    }
  }

  void setSelectedLanguage(String lang) {
    _selectedLanguage = lang;
    _storageService.setTargetLanguage(lang);
    notifyListeners();
  }

  void setActiveFeatureId(String featureId) {
    if (featureId != 'Humanize' && featureId != 'PlagiarismCheck') {
      _studioActionId = featureId;
    }
    if (_activeFeatureId != featureId) {
      _activeFeatureId = featureId;
      notifyListeners();
    }
  }

  int get inputCharCount => _inputText.length;
  int get inputWordCount => _countWords(_inputText);
  int get outputCharCount => _outputText.length;
  int get outputWordCount => _countWords(_outputText);

  static int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  void setInputText(String text) {
    _inputText = text;
    notifyListeners();
  }

  void setOutputText(String text) {
    _outputText = text;
    notifyListeners();
  }

  RephraseService get rephraseService => _rephraseService;

  /// Replace a selected substring span in [outputText] with [replacement].
  void replaceOutputSpan({
    required int startIndex,
    required int endIndex,
    required String replacement,
    String? fallbackTarget,
  }) {
    final updated = _rephraseService.applyReplacement(
      originalText: _outputText,
      startIndex: startIndex,
      endIndex: endIndex,
      replacement: replacement,
      fallbackTarget: fallbackTarget,
    );
    _outputText = updated;
    notifyListeners();
    _toast.showToast('Rephrased in output!', ToastType.success);
  }

  /// Locate sentence spans across current output text.
  List<SentenceSpan> getOutputSentenceSpans() {
    return _rephraseService.extractSentenceSpans(_outputText);
  }

  /// Locate the sentence enclosing a given character selection range.
  SentenceSpan findEnclosingOutputSentence(int startIndex, int endIndex) {
    return _rephraseService.findEnclosingSentence(_outputText, startIndex, endIndex);
  }

  /// Retrieve AI or lexical rephrase alternatives for a targeted word or sentence.
  Future<List<RephraseOption>> getRephraseOptionsForSelection({
    required String selectedText,
    int? startIndex,
    int? endIndex,
  }) async {
    return await _rephraseService.getRephraseOptions(
      selectedText: selectedText,
      fullText: _outputText,
      startIndex: startIndex,
      endIndex: endIndex,
      provider: _llmSettings.activeProvider,
      apiKey: _llmSettings.activeApiKey,
      model: _llmSettings.activeModel,
      customBaseUrl: _llmSettings.activeProvider.isCustom ? _llmSettings.customBaseUrl : null,
    );
  }

  void clearInput() {
    if (_isLoading || _isStreaming) {
      stopGeneration();
    }
    _inputText = '';
    _preRecordingText = '';
    _outputText = '';
    _copied = false;
    _lastSlopReport = null;
    _lastSlopRepair = null;
    _plagiarism.clearPlagiarismReport();
    notifyListeners();
  }

  /// Loads a saved history item back into the shared workspace.
  void restoreFromHistory(String text, {bool toInput = false}) {
    if (toInput) {
      _inputText = text;
    } else {
      _outputText = text;
    }
    notifyListeners();
    _toast.showToast(toInput ? 'Restored to input' : 'Loaded to output', ToastType.success);
  }

  // Speech-To-Text (STT) Trigger
  Future<void> toggleRecording({String? localeId}) async {
    if (_speech.isRecording) {
      await _speech.stopListening();
      _toast.showToast('Listening stopped', ToastType.info);
    } else {
      _preRecordingText = _inputText;
      final targetLocale = localeId ?? SpeechService.getLocaleForLanguage(_selectedLanguage);
      final success = await _speech.startListening(
        localeId: targetLocale,
        onResult: (words, isFinal) {
          if (words.isNotEmpty) {
            final trimmedPre = _preRecordingText.trim();
            if (trimmedPre.isEmpty) {
              _inputText = words;
            } else {
              _inputText = '$trimmedPre $words';
            }
            notifyListeners();
            if (isFinal) {
              _preRecordingText = _inputText;
              _toast.showToast('Speech captured successfully!', ToastType.success);
            }
          }
        },
      );

      if (success) {
        _toast.showToast('Listening... Speak now.', ToastType.info);
      }
    }
  }

  /// Cancel active streaming text generation immediately
  void stopGeneration() {
    _generationTimeoutGuard?.cancel();
    _generationTimeoutGuard = null;
    _streamingThrottleTimer?.cancel();
    _streamingThrottleTimer = null;
    if (_streamingSubscription != null) {
      _streamingSubscription?.cancel();
      _streamingSubscription = null;
    }
    _isStreaming = false;
    _isPolishing = false;
    _isLoading = false;
    notifyListeners();
    _toast.showToast('Generation stopped', ToastType.info);
  }

  /// Keyboard accelerator: Cmd/Ctrl+Enter.
  /// Re-runs the last used feature on current input text if not already loading.
  Future<void> runActiveTransformIfIdle() async {
    if (_isLoading || _inputText.trim().isEmpty) return;
    await handleFeatureClick(studioActionId);
  }

  // Transform / Respond Action with Real-Time SSE Token Streaming
  Future<void> handleFeatureClick(
    String featureId, {
    String? customLang,
    LlmGenerationParams? paramsOverride,
  }) async {
    if (_inputText.trim().isEmpty) {
      _toast.showToast('Please type or record some text first.', ToastType.error);
      return;
    }

    // Guard against a typo'd/unrecognized featureId reaching the LLM with a
    // silently-degraded generic prompt (see AppPrompts.getFeatureInstruction's
    // default branch) — fail loud here instead.
    if (FeatureType.fromId(featureId) == null) {
      AppLogger.error(
        'handleFeatureClick called with unrecognized featureId "$featureId" — refusing to send a malformed request.',
        tag: 'StudioProvider',
      );
      _toast.showToast('Unknown action "$featureId". Please try again.', ToastType.error);
      return;
    }

    // Direct client-side ML execution for Plagiarism & AI Check
    if (featureId == 'PlagiarismCheck') {
      await runPlagiarismCheck();
      return;
    }

    // Verify key exists for non-custom provider
    if (!_llmSettings.hasActiveApiKey) {
      _toast.showToast(
        'Please paste your API key in Settings first.',
        ToastType.error,
      );
      return;
    }

    _activeFeatureId = featureId;
    _isLoading = true;
    _isStreaming = true;
    _outputText = '';
    _lastSlopReport = null;
    _lastSlopRepair = null;
    _speech.stopIfActive();
    notifyListeners();

    // 5-minute zombie guard: if SSE never completes, kill it automatically.
    _generationTimeoutGuard?.cancel();
    _generationTimeoutGuard = Timer(const Duration(minutes: 5), () {
      if (_isStreaming) {
        AppLogger.warn('Generation timed out after 5 minutes — force-stopping.', 'StudioProvider');
        stopGeneration();
        _toast.showToast('Generation timed out. Please try again.', ToastType.error);
      }
    });

    try {
      final allKeys = _llmSettings.getAllConfiguredKeys();

        var effectiveParams = paramsOverride ?? _llmSettings.generationParams;
        if (featureId == 'Humanize') {
          effectiveParams = effectiveParams.copyWith(
            temperature: effectiveParams.temperature <= 0.35 ? 0.78 : effectiveParams.temperature,
            topP: effectiveParams.topP <= 0.90 ? 0.92 : effectiveParams.topP,
            frequencyPenalty: effectiveParams.frequencyPenalty == 0.0 ? 0.28 : effectiveParams.frequencyPenalty,
            presencePenalty: effectiveParams.presencePenalty == 0.0 ? 0.22 : effectiveParams.presencePenalty,
          );
        }

        final stream = _llmService.transformTextStreamWithFailover(
          primaryProvider: _llmSettings.activeProvider,
          primaryApiKey: _llmSettings.activeApiKey,
          featureId: featureId,
          text: _inputText,
          allConfiguredKeys: allKeys,
          primaryModel: _llmSettings.activeModel,
          customBaseUrl: _llmSettings.activeProvider.isCustom ? _llmSettings.customBaseUrl : null,
          targetLanguage: featureId == 'Translate' ? (customLang ?? _selectedLanguage) : null,
          params: effectiveParams,
          onFailover: (fallbackName) {
            _toast.showToast('Switched to fallback provider $fallbackName', ToastType.info);
          },
        );

      final completer = Completer<void>();
      final buffer = StringBuffer();
      DateTime lastFlushTime = DateTime.fromMillisecondsSinceEpoch(0);
      Timer? throttleTimer;

      void flushBuffer() {
        throttleTimer?.cancel();
        _streamingThrottleTimer = null;
        throttleTimer = null;
        lastFlushTime = DateTime.now();
        _outputText = buffer.toString();
        notifyListeners();
      }

      _streamingSubscription?.cancel();
      _streamingSubscription = stream.listen(
        (token) {
          buffer.write(token);
          final now = DateTime.now();
          if (now.difference(lastFlushTime).inMilliseconds >= 40) {
            flushBuffer();
          } else {
            throttleTimer ??= Timer(const Duration(milliseconds: 40), flushBuffer);
            _streamingThrottleTimer = throttleTimer;
          }
        },
        onError: (error) {
          throttleTimer?.cancel();
          throttleTimer = null;
          if (!completer.isCompleted) completer.completeError(error);
        },
        onDone: () {
          throttleTimer?.cancel();
          throttleTimer = null;
          _outputText = buffer.toString();
          notifyListeners();
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;

      final rawOutput = buffer.toString().trim();
      final sanitized = LlmService.sanitizeOutput(rawOutput, featureId: featureId).trim();
      final intermediateResult = sanitized.isNotEmpty ? sanitized : rawOutput;

      String finalResult = intermediateResult;

      // Check -> targeted repair -> verify. Runs before the Humanize
      // algorithmic loop so that loop sees (and can't be undone by) the repair.
      if (_slopAutoPolish && finalResult.isNotEmpty && SlopRepairService.shouldCheck(featureId)) {
        _isPolishing = true;
        notifyListeners();
        final polished = await _slopRepair.polish(
          source: _inputText,
          candidate: finalResult,
          featureId: featureId,
          provider: _llmSettings.activeProvider,
          apiKey: _llmSettings.activeApiKey,
          allConfiguredKeys: allKeys,
          model: _llmSettings.activeModel,
          customBaseUrl: _llmSettings.activeProvider.isCustom ? _llmSettings.customBaseUrl : null,
          params: effectiveParams,
          isCancelled: () => !_isLoading,
        );
        _isPolishing = false;
        // stopGeneration() clears isLoading; honour it and keep what is on screen.
        if (!_isLoading) return;
        finalResult = polished.text;
        if (polished.repaired) _lastSlopRepair = polished;
      }

      if (featureId == 'Humanize') {
        final toneProfile = WritingToneProfile.fromString(paramsOverride?.persona);
        finalResult = const AlgorithmicHumanizerService().postProcessWithQualityLoop(
          finalResult,
          tone: toneProfile,
          originalText: _inputText,
          forensicService: _plagiarism.plagiarismDetector.aiForensics,
        );
      }

      _outputText = finalResult;
      if (finalResult.isNotEmpty && SlopRepairService.shouldCheck(featureId)) {
        _lastSlopReport = const SlopLinter().check(finalResult);
      }
      notifyListeners();

      if (finalResult.isNotEmpty) {
        if (featureId == 'Humanize') {
          await _plagiarism.computeHumanizeVerification(
            originalText: _inputText,
            humanizedText: finalResult,
          );
        }

        final featureName = featureId;

        // Persist structured studio history record with rich telemetry
        final historyRecord = HistoryRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          inputText: _inputText,
          outputText: finalResult,
          featureId: featureId,
          featureLabel: featureName,
          providerName: _llmSettings.activeProvider.name,
          modelUsed: _llmSettings.activeModel,
          inputWordCount: inputWordCount,
          outputWordCount: _countWords(finalResult),
          humanScore: featureId == 'Humanize' ? _plagiarism.outputPlagiarismReport?.humanScore : null,
          aiRiskScore: featureId == 'Humanize' ? _plagiarism.outputPlagiarismReport?.overallScore : null,
        );
        await _history.addHistoryRecord(historyRecord);

        _toast.showToast('$featureName finished!', ToastType.success);
      }
    } catch (e) {
      // Always surface errors — do NOT gate on _isStreaming which may already
      // be false if the stream was cancelled before the error fired.
      _toast.showToast(e.toString(), ToastType.error);
    } finally {
      _generationTimeoutGuard?.cancel();
      _generationTimeoutGuard = null;
      _isLoading = false;
      _isStreaming = false;
      _isPolishing = false;
      _streamingSubscription = null;
      notifyListeners();
    }
  }

  /// Execute ML Plagiarism & AI detection (On-Device or Hugging Face) against
  /// the current workspace text. For the primary (non-output) check, mirrors
  /// the original combined "check + record" behavior: the summary becomes
  /// the new output text and is saved as a legacy history item.
  Future<void> runPlagiarismCheck({
    bool? useHuggingFace,
    String? customModel,
    bool forOutput = false,
  }) async {
    final targetText = forOutput
        ? _outputText.trim()
        : (_inputText.trim().isNotEmpty ? _inputText.trim() : _outputText.trim());

    if (targetText.isEmpty) {
      _toast.showToast('Please enter or generate some text to rate.', ToastType.error);
      return;
    }

    _activeFeatureId = 'PlagiarismCheck';
    _isLoading = true;
    _speech.stopIfActive();
    notifyListeners();

    try {
      final report = await _plagiarism.runPlagiarismCheck(
        targetText,
        useHuggingFace: useHuggingFace,
        customModel: customModel,
        forOutput: forOutput,
      );

      if (!forOutput && report != null) {
        _outputText = report.toSummaryText();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fix detected plagiarism and AI tells using Lauriva LLM humanizer, then
  /// write the result into the shared text workspace. Returns whether the
  /// fix produced a result, so callers (e.g. the Detector screen) know
  /// whether it's safe to navigate to the Humanizer tab to show it.
  Future<bool> fixPlagiarismAndHumanize() async {
    if (_inputText.trim().isEmpty) {
      _toast.showToast('No text available to humanize.', ToastType.error);
      return false;
    }

    if (!_llmSettings.hasActiveApiKey) {
      _toast.showToast(
        'Please paste your API key in Settings to run AI Auto-Fix.',
        ToastType.error,
      );
      return false;
    }

    _speech.stopIfActive();

    final humanized = await _plagiarism.fixPlagiarismAndHumanize(
      text: _inputText,
      provider: _llmSettings.activeProvider,
      apiKey: _llmSettings.activeApiKey,
      model: _llmSettings.activeModel,
      customBaseUrl: _llmSettings.activeProvider.isCustom ? _llmSettings.customBaseUrl : null,
      inputWordCount: inputWordCount,
    );

    if (humanized != null) {
      _outputText = humanized;
      // This produces a genuine humanized result, so it must be tagged the
      // same as a direct Humanize run — otherwise the Humanizer screen's
      // activeFeatureId gate (see zone3_output.dart / humanizer_screen.dart)
      // would treat this result as not belonging to it and hide it.
      _activeFeatureId = 'Humanize';
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Surgically humanizes only the suspicious flagged sentences via PlagiarismProvider
  Future<bool> surgicalHumanizeFlaggedSentences() async {
    if (_inputText.trim().isEmpty) {
      _toast.showToast('No text available to humanize.', ToastType.error);
      return false;
    }

    if (!_llmSettings.hasActiveApiKey) {
      _toast.showToast(
        'Please paste your API key in Settings to run Surgical Fix.',
        ToastType.error,
      );
      return false;
    }

    _speech.stopIfActive();

    final humanized = await _plagiarism.surgicalHumanizeFlaggedSentences(
      text: _inputText,
      provider: _llmSettings.activeProvider,
      apiKey: _llmSettings.activeApiKey,
      model: _llmSettings.activeModel,
      customBaseUrl: _llmSettings.activeProvider.isCustom ? _llmSettings.customBaseUrl : null,
      inputWordCount: inputWordCount,
    );

    if (humanized != null) {
      _outputText = humanized;
      _activeFeatureId = 'Humanize';
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Apply the fixed humanized text (from the current plagiarism report)
  /// back to the input editor.
  void applyFixedTextToInput() {
    final fixedText = _plagiarism.plagiarismReport?.fixedText;
    if (fixedText != null && fixedText.isNotEmpty) {
      _inputText = fixedText;
      _toast.showToast('Applied humanized text to input editor!', ToastType.success);
      notifyListeners();
    }
  }

  // Clipboard Copier
  Future<void> copyOutputToClipboard() async {
    if (_outputText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _outputText));
    _copied = true;
    notifyListeners();
    _toast.showToast('Copied to clipboard!', ToastType.success);

    Future.delayed(const Duration(seconds: 2), () {
      _copied = false;
      notifyListeners();
    });
  }

  /// Export transformed output along with metadata and original text formatted in clean Markdown
  Future<void> exportFormattedMarkdown() async {
    if (_outputText.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('# Lauriva Voice & Writing Studio Transformation');
    buffer.writeln();
    buffer.writeln('- **Model:** ${_llmSettings.activeProvider.name} (${_llmSettings.activeModel})');
    buffer.writeln('- **Persona:** ${_llmSettings.persona.toUpperCase()}');
    buffer.writeln('- **Input Words:** $inputWordCount | **Output Words:** $outputWordCount');
    final report = _plagiarism.plagiarismReport;
    if (report != null) {
      buffer.writeln('- **AI Risk Rating:** ${report.overallScore.round()}% (${report.riskLevel.label})');
    }
    buffer.writeln();
    if (_inputText.trim().isNotEmpty) {
      buffer.writeln('## Original Input');
      buffer.writeln('```');
      buffer.writeln(_inputText.trim());
      buffer.writeln('```');
      buffer.writeln();
    }
    buffer.writeln('## Transformed Result');
    buffer.writeln();
    buffer.writeln(_outputText.trim());

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _toast.showToast('Copied to clipboard!', ToastType.success);
  }

  // Push output back as input
  void useOutputAsInput() {
    if (_outputText.isEmpty) return;
    _inputText = _outputText;
    _outputText = '';
    _activeFeatureId = '';
    _speech.stopIfActive();
    notifyListeners();
    _toast.showToast('Moved to input!', ToastType.success);
  }

  // Text-To-Speech (TTS) Controls — thin wrappers that supply the shared
  // workspace text/language SpeechProvider itself doesn't own.
  Future<void> speakSpeech() async {
    if (_outputText.trim().isEmpty) {
      _toast.showToast('No text to read aloud.', ToastType.error);
      return;
    }
    await _speech.speak(_outputText, targetLanguage: _selectedLanguage);
  }

  Future<void> pauseSpeech() async {
    await _speech.pause();
  }

  Future<void> resumeSpeech() async {
    await _speech.resume();
  }

  Future<void> stopSpeech() async {
    await _speech.stop();
  }

  Future<void> setSpeechSpeed(String speed) async {
    await _speech.setSpeed(speed, replayText: _outputText, targetLanguage: _selectedLanguage);
  }

  @override
  void dispose() {
    _generationTimeoutGuard?.cancel();
    _streamingThrottleTimer?.cancel();
    _streamingSubscription?.cancel();
    super.dispose();
  }
}
