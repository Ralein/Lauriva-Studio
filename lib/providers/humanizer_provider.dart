import 'package:flutter/foundation.dart';
import '../models/history_record.dart';
import '../models/llm_provider.dart';
import '../models/plagiarism_report.dart';
import '../models/toast_notification.dart';
import '../services/forensic/humanizer/algorithmic_humanizer_service.dart';
import '../services/forensic/humanizer/humanizer_chunk_engine.dart';
import '../services/forensic/humanizer/lauvira_humanize_service.dart';
import '../services/forensic/humanizer/semantic_preservation_verifier.dart';
import '../services/llm_service.dart';
import 'background_task_provider.dart';
import 'history_provider.dart';
import 'llm_settings_provider.dart';
import 'plagiarism_provider.dart';
import 'speech_provider.dart';
import 'toast_provider.dart';
import '../services/background_processing_service.dart';
import '../services/storage_service.dart';

/// Dedicated state provider for the AI Text Humanizer.
/// Completely decoupled from Studio and Plagiarism detectors to prevent
/// cross-feature loading states and input pollution.
class HumanizerProvider extends ChangeNotifier {
  final StorageService? _storageService;
  final ToastProvider _toast;
  final HistoryProvider _history;
  final LlmSettingsProvider _llmSettings;
  final PlagiarismProvider? _plagiarism;
  final SpeechProvider? _speech;
  final BackgroundTaskProvider? _backgroundTask;
  final LlmService _llmService;
  final LauviraHumanizeService _lauviraHumanize;
  final HumanizerChunkEngine _chunkEngine;

  String _inputText = '';
  String _outputText = '';
  String _preRecordingText = '';
  bool _isLoading = false;
  String _selectedTone = 'professional';
  String _selectedStyle = 'balanced';
  int _humanizeIntensity = 85;
  SemanticPreservationReport? _preservationReport;
  PlagiarismReport? _inputPlagiarismReport;
  PlagiarismReport? _outputPlagiarismReport;
  String? _chunkProgressMessage;
  double? _chunkProgressRatio;

  HumanizerProvider({
    StorageService? storage,
    required ToastProvider toast,
    required HistoryProvider history,
    required LlmSettingsProvider llmSettings,
    PlagiarismProvider? plagiarism,
    SpeechProvider? speech,
    BackgroundTaskProvider? backgroundTask,
    LlmService? llmService,
    LauviraHumanizeService? lauviraHumanize,
    HumanizerChunkEngine? chunkEngine,
  })  : _storageService = storage,
        _toast = toast,
        _history = history,
        _llmSettings = llmSettings,
        _plagiarism = plagiarism,
        _speech = speech,
        _backgroundTask = backgroundTask,
        _humanizeIntensity = storage?.getHumanizeIntensity() ?? 85,
        _llmService = llmService ?? LlmService(),
        _lauviraHumanize = lauviraHumanize ?? LauviraHumanizeService(),
        _chunkEngine = chunkEngine ??
            HumanizerChunkEngine(
              lauviraHumanize: lauviraHumanize ?? LauviraHumanizeService(),
            );

  String get inputText => _inputText;
  String get outputText => _outputText;
  bool get isLoading => _isLoading;
  String get selectedTone => _selectedTone;
  String get selectedStyle => _selectedStyle;
  SemanticPreservationReport? get preservationReport => _preservationReport;
  PlagiarismReport? get outputPlagiarismReport => _outputPlagiarismReport ?? _plagiarism?.outputPlagiarismReport;
  PlagiarismReport? get inputPlagiarismReport => _inputPlagiarismReport ?? _plagiarism?.plagiarismReport;
  String? get chunkProgressMessage => _chunkProgressMessage;
  double? get chunkProgressRatio => _chunkProgressRatio;
  LauviraHumanizeService get lauviraHumanize => _lauviraHumanize;

  int get humanizeIntensity => _humanizeIntensity;

  void setHumanizeIntensity(int percent) {
    final clamped = percent.clamp(0, 100);
    if (_humanizeIntensity != clamped) {
      _humanizeIntensity = clamped;
      _storageService?.setHumanizeIntensity(clamped);
      notifyListeners();
    }
  }

  void setInputText(String text) {
    if (_inputText != text) {
      _inputText = text;
      notifyListeners();
    }
  }

  void clearInput() {
    _inputText = '';
    _outputText = '';
    _inputPlagiarismReport = null;
    _outputPlagiarismReport = null;
    _preservationReport = null;
    notifyListeners();
  }

  void clearOutput() {
    _outputText = '';
    _outputPlagiarismReport = null;
    _preservationReport = null;
    notifyListeners();
  }

  void useOutputAsInput() {
    if (_outputText.isNotEmpty) {
      _inputText = _outputText;
      _outputText = '';
      notifyListeners();
    }
  }

  void setTone(String tone) {
    _selectedTone = tone;
    notifyListeners();
  }

  void setStyle(String style) {
    _selectedStyle = style;
    notifyListeners();
  }

  /// Voice dictation trigger isolated to Humanizer's input editor.
  Future<void> toggleRecording({String? localeId}) async {
    final speech = _speech;
    if (speech == null) return;
    if (speech.isRecording) {
      await speech.stopListening();
      _toast.showToast('Listening stopped', ToastType.info);
    } else {
      _preRecordingText = _inputText;
      final success = await speech.startListening(
        localeId: localeId,
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

  /// Master Humanize Pipeline:
  /// Scores text with the same fused detector (stylometric + trained
  /// transformer) as the Detector screen, so humanizer metrics agree with it.
  Future<PlagiarismReport> Function(String text)? _detectorScorer() {
    final plagiarism = _plagiarism;
    if (plagiarism == null) return null;
    return (text) async => (await plagiarism.plagiarismDetector.analyzeForensic(
          text,
          sensitivity: plagiarism.sensitivity,
          enableOnlineSearch: false,
        ))
            .toLegacyPlagiarismReport();
  }

  /// Paragraph Chunking -> ANY LLM (Groq / Claude / OpenAI / Ollama) -> lauvira_humanize -> Authentic Human Prose
  Future<void> runHumanize({String? toneOverride}) async {
    final text = _inputText.trim();
    if (text.isEmpty) {
      _toast.showToast('Please provide text to humanize.', ToastType.error);
      return;
    }

    if (toneOverride != null) {
      _selectedTone = toneOverride;
    }

    _isLoading = true;
    _chunkProgressMessage = 'Segmenting document into semantic chunks...';
    _chunkProgressRatio = 0.0;
    notifyListeners();

    final jobId = 'humanize_${DateTime.now().millisecondsSinceEpoch}';
    _backgroundTask?.service.startJob(
      id: jobId,
      type: BackgroundJobType.humanization,
      title: 'Humanizing Document',
      description: 'Rewriting text with natural human cadence...',
    );

    try {
      final activeProvider = _llmSettings.activeProvider;
      final activeModel = _llmSettings.activeModel;
      final toneProfile = WritingToneProfile.fromString(_selectedTone);
      final allKeys = _llmSettings.getAllConfiguredKeys();

      final bool hasActiveKey = _llmSettings.hasActiveApiKey;
      final effectiveProvider = hasActiveKey
          ? activeProvider
          : LlmProvider.allProviders.firstWhere(
              (p) => p.id == 'pollinations',
              orElse: () => activeProvider,
            );
      final effectiveApiKey = hasActiveKey ? _llmSettings.activeApiKey : '';
      final effectiveModel = hasActiveKey ? activeModel : effectiveProvider.defaultModel;

      if (!hasActiveKey) {
        _toast.showToast(
          'Using free cloud LLM gateway (Pollinations.ai)...',
          ToastType.info,
        );
      } else {
        final lowerModel = effectiveModel.toLowerCase();
        final isSub8bModel = lowerModel.contains('2.6b') ||
            lowerModel.contains('1.1-mini') ||
            lowerModel.contains('mini:free') ||
            lowerModel.contains('1b') ||
            lowerModel.contains('0.5b');
        if (isSub8bModel) {
          _toast.showToast(
            'Model notice: $effectiveModel is lightweight. A 30B–70B model (e.g. Llama 3.3 70B, Gemma 4 31B) is recommended for < 10% AI scores.',
            ToastType.info,
          );
        }
      }

      final result = await _chunkEngine.processDocument(
        rawText: text,
        tone: toneProfile,
        style: _selectedStyle,
        llmService: _llmService,
        activeProvider: effectiveProvider,
        activeApiKey: effectiveApiKey,
        activeModel: effectiveModel,
        allConfiguredKeys: allKeys,
        customBaseUrl: effectiveProvider.isCustom ? _llmSettings.customBaseUrl : null,
        generationParams: _llmSettings.generationParams,
        intensity: _humanizeIntensity,
        throwOnLlmError: false,
        documentScorer: _detectorScorer(),
        onFailoverDetails: (fallbackProvider, fallbackModel, reason) async {
          await _llmSettings.adoptFailoverModel(
            provider: fallbackProvider,
            model: fallbackModel,
            persistPermanently: false,
          );
          _toast.showToast(
            'Failover: switched to ${fallbackProvider.name} ($fallbackModel) - $reason',
            ToastType.info,
            actionLabel: 'Save Default',
            onAction: () async {
              await _llmSettings.savePendingFailoverAsDefault();
              _toast.showToast('Saved ${fallbackProvider.name} ($fallbackModel) as permanent default.', ToastType.success);
            },
            duration: const Duration(seconds: 6),
          );
          notifyListeners();
        },
        onProgress: (progress) {
          _chunkProgressMessage = progress.message;
          _chunkProgressRatio = progress.ratio;
          _backgroundTask?.service.updateProgress(
            jobId,
            progress.ratio,
            message: progress.message,
          );
          notifyListeners();
        },
      );

      _outputText = result.humanizedText;
      _inputPlagiarismReport = result.beforeReport;
      _outputPlagiarismReport = result.afterReport;
      _preservationReport = result.preservationReport;

      // Save structured history record
      await _history.addHistoryRecord(
        HistoryRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          inputText: text,
          outputText: _outputText,
          featureId: 'Humanize',
          featureLabel: 'AI Humanizer',
          providerName: _llmSettings.activeProvider.name,
          modelUsed: _llmSettings.activeModel,
          inputWordCount: text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
          outputWordCount: _outputText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
          humanScore: _outputPlagiarismReport?.humanScore,
          aiRiskScore: _outputPlagiarismReport?.overallScore,
        ),
      );

      _backgroundTask?.service.completeJob(
        jobId,
        result: _outputText,
        message: 'Humanization complete.',
      );

      if (result.usedLocalFallback) {
        _toast.showToast(
          'Humanized using on-device neural fallback engine.',
          ToastType.info,
        );
      } else {
        _toast.showToast(
          result.totalChunksProcessed > 1
              ? 'Humanized ${result.totalChunksProcessed} sections successfully!'
              : 'Humanized successfully!',
          ToastType.success,
        );
      }
    } catch (e) {
      _backgroundTask?.service.failJob(jobId, e.toString());
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('Network is unreachable') ||
          errStr.contains('ClientException')) {
        _toast.showToast(
          'Humanization failed: Internet connection required. Please connect to the internet to use Humanizer.',
          ToastType.error,
        );
      } else {
        _toast.showToast('Humanization failed: $e', ToastType.error);
      }
    } finally {
      _isLoading = false;
      _chunkProgressMessage = null;
      _chunkProgressRatio = null;
      notifyListeners();
    }
  }
}
