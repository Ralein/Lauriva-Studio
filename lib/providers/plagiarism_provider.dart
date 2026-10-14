import 'package:flutter/foundation.dart';
import '../models/forensic/forensic_progress.dart';
import '../models/forensic/forensic_report.dart';
import '../models/history_record.dart';
import '../models/llm_provider.dart';
import '../models/plagiarism_report.dart';
import '../models/toast_notification.dart';
import '../services/forensic/ai/stylometric_feature_extractor.dart';
import '../services/forensic/forensic_coordinator_service.dart';
import '../services/forensic/humanizer/algorithmic_humanizer_service.dart';
import '../services/forensic/humanizer/humanizer_chunk_engine.dart';
import '../services/forensic/humanizer/semantic_preservation_verifier.dart';
import '../services/forensic/humanizer/surgical_humanizer_bridge.dart';
import '../services/llm_service.dart';
import '../services/plagiarism_detector_service.dart';
import '../services/storage_service.dart';
import 'background_task_provider.dart';
import 'history_provider.dart';
import 'llm_settings_provider.dart';
import 'toast_provider.dart';
import '../services/background_processing_service.dart';

/// Owns AI/plagiarism detection state and the LLM-backed "humanize fix" flow.
/// Deliberately decoupled from the shared text workspace: callers pass the
/// text to analyze/fix explicitly and are responsible for writing any result
/// (e.g. a humanized rewrite) back into the workspace they own.
class PlagiarismProvider extends ChangeNotifier {
  final StorageService _storageService;
  final LlmSettingsProvider? _llmSettings;
  final LlmService _llmService;
  final PlagiarismDetectorService _plagiarismDetector;
  final ToastProvider _toast;
  final HistoryProvider _history;
  final HumanizerChunkEngine _chunkEngine;
  final BackgroundTaskProvider? _backgroundTask;

  PlagiarismProvider({
    required StorageService storage,
    required ToastProvider toast,
    required HistoryProvider history,
    LlmSettingsProvider? llmSettings,
    LlmService? llmService,
    PlagiarismDetectorService? plagiarismDetector,
    HumanizerChunkEngine? chunkEngine,
    BackgroundTaskProvider? backgroundTask,
  })  : _storageService = storage,
        _toast = toast,
        _history = history,
        _llmSettings = llmSettings,
        _llmService = llmService ?? LlmService(),
        _plagiarismDetector = plagiarismDetector ?? PlagiarismDetectorService(),
        _chunkEngine = chunkEngine ?? HumanizerChunkEngine(),
        _backgroundTask = backgroundTask;

  PlagiarismReport? _plagiarismReport;
  PlagiarismReport? _outputPlagiarismReport;
  ForensicReport? _forensicReport;
  ForensicReport? _outputForensicReport;
  SemanticPreservationReport? _semanticPreservationReport;
  ForensicScanMode _scanMode = ForensicScanMode.fullForensic;
  ForensicSensitivity _sensitivity = ForensicSensitivity.balanced;
  bool _enableOnlineSearch = true;
  bool _enableDeepWatermark = true;
  bool _enableHomoglyphCheck = true;
  ForensicProgress? _currentProgress;
  final ValueNotifier<ForensicProgress?> progressNotifier = ValueNotifier<ForensicProgress?>(null);

  bool _isFixingPlagiarism = false;
  bool _isScanning = false;
  String _inputText = '';
  String? _chunkProgressMessage;
  double? _chunkProgressRatio;
  String _detectorEngine = 'llm'; // 'llm', 'huggingface'
  String _huggingFaceDetectorModel = 'Hello-SimpleAI/chatgpt-detector-roberta';

  PlagiarismDetectorService get plagiarismDetector => _plagiarismDetector;
  PlagiarismReport? get plagiarismReport => _plagiarismReport;
  PlagiarismReport? get outputPlagiarismReport => _outputPlagiarismReport;
  ForensicReport? get forensicReport => _forensicReport;
  ForensicReport? get outputForensicReport => _outputForensicReport;
  SemanticPreservationReport? get semanticPreservationReport => _semanticPreservationReport;
  ForensicScanMode get scanMode => _scanMode;
  ForensicSensitivity get sensitivity => _sensitivity;
  bool get enableOnlineSearch => _enableOnlineSearch;
  bool get enableDeepWatermark => _enableDeepWatermark;
  bool get enableHomoglyphCheck => _enableHomoglyphCheck;
  ForensicProgress? get currentProgress => _currentProgress;
  bool get isFixingPlagiarism => _isFixingPlagiarism;
  bool get isScanning => _isScanning;
  String get inputText => _inputText;
  String? get chunkProgressMessage => _chunkProgressMessage;
  double? get chunkProgressRatio => _chunkProgressRatio;
  String get detectorEngine => _detectorEngine;
  String get huggingFaceDetectorModel => _huggingFaceDetectorModel;

  void setInputText(String text) {
    if (_inputText != text) {
      _inputText = text;
      notifyListeners();
    }
  }

  void clearInput() {
    _inputText = '';
    _plagiarismReport = null;
    _forensicReport = null;
    notifyListeners();
  }

  void setScanMode(ForensicScanMode mode) {
    _scanMode = mode;
    notifyListeners();
  }

  void setSensitivity(ForensicSensitivity sensitivity) {
    _sensitivity = sensitivity;
    notifyListeners();
  }

  void setEnableOnlineSearch(bool enable) {
    _enableOnlineSearch = enable;
    notifyListeners();
  }

  void setEnableDeepWatermark(bool enable) {
    _enableDeepWatermark = enable;
    notifyListeners();
  }

  void setEnableHomoglyphCheck(bool enable) {
    _enableHomoglyphCheck = enable;
    notifyListeners();
  }

  void setDetectorEngine(String engine) {
    _detectorEngine = engine;
    notifyListeners();
  }

  void setHuggingFaceDetectorModel(String model) {
    _huggingFaceDetectorModel = model;
    notifyListeners();
  }


  /// Analyzes [text] with the trained on-device forensic engine (or Hugging Face if configured),
  /// stores the resulting report (as [plagiarismReport], or [outputPlagiarismReport] if [forOutput]),
  /// and returns it. Returns null (after an error toast) if [text] is blank or analysis fails.
  Future<PlagiarismReport?> runPlagiarismCheck(
    String text, {
    bool? useHuggingFace,
    String? customModel,
    bool forOutput = false,
  }) async {
    final targetText = text.trim();
    if (targetText.isEmpty) {
      _toast.showToast('Please enter or generate some text to rate.', ToastType.error);
      return null;
    }

    final shouldUseHf = useHuggingFace ?? (_detectorEngine == 'huggingface');
    if (shouldUseHf) {
      final hfKey = _storageService.getApiKey('huggingface') ?? '';
      if (hfKey.trim().isEmpty) {
        _toast.showToast(
          'Hugging Face API token required for cloud detector. Please configure it in Settings.',
          ToastType.error,
        );
        return null;
      }
    }

    _isScanning = true;
    notifyListeners();

    final jobId = 'forensic_${DateTime.now().millisecondsSinceEpoch}';
    _backgroundTask?.service.startJob(
      id: jobId,
      title: _scanMode == ForensicScanMode.sourceScan
          ? 'Source Literature Audit'
          : 'Forensic AI & Plagiarism Scan',
      description: 'Analyzing document structure, stylometry, and perplexity...',
      type: BackgroundJobType.forensicScan,
    );

    try {
      final model = customModel ?? _huggingFaceDetectorModel;

      PlagiarismReport report;
      if (shouldUseHf) {
        final hfKey = _storageService.getApiKey('huggingface') ?? '';
        report = await _plagiarismDetector.analyzeWithHuggingFace(
          text: targetText,
          apiKey: hfKey,
          model: model,
          fallbackToOffline: false,
        );
      } else {
        final words = targetText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        _currentProgress = ForensicProgress.initial(totalWords: words);
        progressNotifier.value = _currentProgress;

        final forensic = await _plagiarismDetector.analyzeForensic(
          targetText,
          mode: _scanMode,
          sensitivity: _sensitivity,
          enableOnlineSearch: _enableOnlineSearch,
          enableWatermarkDetection: _enableDeepWatermark,
          enableHomoglyphDetection: _enableHomoglyphCheck,
          onProgress: (p) {
            _currentProgress = p;
            progressNotifier.value = p;
            _backgroundTask?.service.updateProgress(
              jobId,
              p.progressRatio,
              message: p.stage,
            );
          },
        );
        report = forensic.toLegacyPlagiarismReport();
        if (forOutput) {
          _outputForensicReport = forensic;
        } else {
          _forensicReport = forensic;
        }
      }

      if (forOutput) {
        _outputPlagiarismReport = report;
      } else {
        _plagiarismReport = report;
      }
      _currentProgress = null;
      progressNotifier.value = null;

      if (_scanMode == ForensicScanMode.sourceScan && _forensicReport != null) {
        final matchesCount = _forensicReport!.sourceSimilarity.matches.length;
        final score = _forensicReport!.sourceSimilarity.overallSimilarityScore;
        if (score < 5.0 || matchesCount == 0) {
          _toast.showToast(
            'Source Scan: 100% Original',
            ToastType.success,
          );
        } else {
          _toast.showToast(
            'Source Scan: ${score.toStringAsFixed(0)}% Match ($matchesCount source${matchesCount == 1 ? '' : 's'})',
            score > 25.0 ? ToastType.error : ToastType.info,
          );
        }
      } else if (_scanMode == ForensicScanMode.forensic) {
        _toast.showToast(
          'Forensic AI: ${report.riskLevel.badge} (${report.humanScore.toStringAsFixed(0)}% Human)',
          report.overallScore < 38.0 ? ToastType.success : ToastType.info,
        );
      } else {
        _toast.showToast(
          'Audit: ${report.riskLevel.badge} (${report.humanScore.toStringAsFixed(0)}% Human · ${report.plagiarismRiskScore.toStringAsFixed(0)}% Match)',
          report.overallScore < 38.0 ? ToastType.success : ToastType.info,
        );
      }

      _backgroundTask?.service.completeJob(
        jobId,
        message: 'Audit Complete: ${report.humanScore.toStringAsFixed(0)}% Human · ${report.riskLevel.badge}',
      );

      if (!forOutput) {
        final words = targetText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final historyRecord = HistoryRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          inputText: targetText,
          outputText: report.toSummaryText(),
          featureId: _scanMode == ForensicScanMode.sourceScan
              ? 'SourceScan'
              : (_scanMode == ForensicScanMode.forensic ? 'ForensicScan' : 'Audit'),
          featureLabel: _scanMode == ForensicScanMode.sourceScan
              ? 'Source Scan'
              : (_scanMode == ForensicScanMode.forensic ? 'Forensic AI Scan' : 'Forensic Audit'),
          providerName: shouldUseHf ? 'HuggingFace' : 'Lauriva Forensic Engine',
          modelUsed: shouldUseHf ? model : 'Stylometry + Forensic Engine',
          inputWordCount: words,
          outputWordCount: _countWords(report.toSummaryText()),
          humanScore: report.humanScore,
          aiRiskScore: report.overallScore,
        );
        await _history.addHistoryRecord(historyRecord);
      }

      return report;
    } catch (e) {
      _currentProgress = null;
      progressNotifier.value = null;
      _backgroundTask?.service.failJob(jobId, e.toString());
      _toast.showToast('Plagiarism check error: $e', ToastType.error);
      return null;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Silently (no toast) analyzes [text] with the trained forensic model and stores it
  /// as the output report, syncing any existing primary report's post-fix score.
  Future<void> analyzeOutputSilently(String text) async {
    if (text.trim().isEmpty) return;

    try {
      final forensic = await _plagiarismDetector.analyzeForensic(
        text,
        mode: _scanMode,
        sensitivity: _sensitivity,
        enableOnlineSearch: _enableOnlineSearch,
        enableWatermarkDetection: _enableDeepWatermark,
        enableHomoglyphDetection: _enableHomoglyphCheck,
      );
      final report = forensic.toLegacyPlagiarismReport();
      _outputForensicReport = forensic;
      _outputPlagiarismReport = report;
      if (_plagiarismReport != null) {
        _plagiarismReport = _plagiarismReport!.withFix(
          fixedText: text,
          fixedScore: report.overallScore,
          fixedRiskLevel: report.riskLevel,
        );
      }
      notifyListeners();
    } catch (e) {
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
    }
  }

  /// Computes baseline forensic analysis for [originalText] (if not already present),
  /// scores [humanizedText], and generates the [SemanticPreservationReport] delta.
  /// Used by the Humanizer to provide live Before/After audit verification.
  Future<void> computeHumanizeVerification({
    required String originalText,
    required String humanizedText,
  }) async {
    if (originalText.trim().isEmpty || humanizedText.trim().isEmpty) return;

    try {
      if (_forensicReport == null && _plagiarismReport == null) {
        _forensicReport = await _plagiarismDetector.analyzeForensic(
          originalText,
          mode: _scanMode,
          sensitivity: _sensitivity,
          enableOnlineSearch: false,
        );
        _plagiarismReport = _forensicReport!.toLegacyPlagiarismReport();
      }
      final postForensic = await _plagiarismDetector.analyzeForensic(
        humanizedText,
        mode: _scanMode,
        sensitivity: _sensitivity,
        enableOnlineSearch: false,
      );
      final postReport = postForensic.toLegacyPlagiarismReport();
      _outputForensicReport = postForensic;
      _outputPlagiarismReport = postReport;

      final extractor = StylometricFeatureExtractor();
      final origMetrics = extractor.extractFromText(originalText).surfaceMetrics;
      final postMetrics = extractor.extractFromText(humanizedText).surfaceMetrics;
      final verifier = SemanticPreservationVerifier();
      _semanticPreservationReport = verifier.verify(
        originalText: originalText,
        humanizedText: humanizedText,
        aiProbabilityBefore: _forensicReport?.aiAuthorship.aiProbability ??
            (_plagiarismReport?.overallScore ?? 0),
        aiProbabilityAfter: postForensic.aiAuthorship.aiProbability,
        burstinessBefore: origMetrics['burstiness'] ?? 0.0,
        burstinessAfter: postMetrics['burstiness'] ?? 0.0,
      );

      if (_plagiarismReport != null) {
        _plagiarismReport = _plagiarismReport!.withFix(
          fixedText: humanizedText,
          fixedScore: postReport.overallScore,
          fixedRiskLevel: postReport.riskLevel,
        );
      }
      notifyListeners();
    } catch (_) {
      // Best-effort verification — should not throw or disrupt user experience
    }
  }

  /// Rewrites [text] via the LLM humanizer, records post-fix originality and
  /// a history entry, and returns the humanized string (or null on failure,
  /// after showing an error toast). The caller is responsible for writing the
  /// result into whatever text workspace it owns.
  Future<String?> fixPlagiarismAndHumanize({
    required String text,
    required LlmProvider provider,
    required String apiKey,
    required String model,
    String? customBaseUrl,
    required int inputWordCount,
  }) async {
    _isFixingPlagiarism = true;
    _chunkProgressMessage = 'Segmenting document into semantic chunks...';
    _chunkProgressRatio = 0.0;
    notifyListeners();

    try {
      final scored = <String, ForensicReport>{};
      final chunkResult = await _chunkEngine.processDocument(
        rawText: text,
        tone: WritingToneProfile.professional,
        llmService: _llmService,
        activeProvider: provider,
        activeApiKey: apiKey,
        activeModel: model,
        allConfiguredKeys: _llmSettings?.getAllConfiguredKeys() ?? {},
        customBaseUrl: customBaseUrl,
        throwOnLlmError: true,
        documentScorer: (t) async {
          final forensic = await _plagiarismDetector.analyzeForensic(
            t,
            mode: _scanMode,
            sensitivity: _sensitivity,
            enableOnlineSearch: false,
          );
          scored[t] = forensic;
          return forensic.toLegacyPlagiarismReport();
        },
        onProgress: (p) {
          _chunkProgressMessage = p.message;
          _chunkProgressRatio = p.ratio;
          notifyListeners();
        },
      );

      final humanized = chunkResult.humanizedText;
      final postReport = chunkResult.afterReport;
      final postForensic = scored[humanized] ??
          await _plagiarismDetector.analyzeForensic(
            humanized,
            mode: _scanMode,
            sensitivity: _sensitivity,
            enableOnlineSearch: false,
          );
      _outputForensicReport = postForensic;
      _outputPlagiarismReport = postReport;
      _semanticPreservationReport = chunkResult.preservationReport;

      if (_plagiarismReport != null) {
        _plagiarismReport = _plagiarismReport!.withFix(
          fixedText: humanized,
          fixedScore: postReport.overallScore,
          fixedRiskLevel: postReport.riskLevel,
        );
      }

      final historyRecord = HistoryRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        inputText: text,
        outputText: humanized,
        featureId: 'Humanize',
        featureLabel: 'Humanize (Forensic Fix)',
        providerName: provider.name,
        modelUsed: model,
        inputWordCount: inputWordCount,
        outputWordCount: _countWords(humanized),
        humanScore: postReport.humanScore,
        aiRiskScore: postReport.overallScore,
      );
      await _history.addHistoryRecord(historyRecord);

      _toast.showToast(
        'Humanized! AI Plagiarism reduced to ${postReport.overallScore.toStringAsFixed(0)}%',
        ToastType.success,
      );
      return humanized;
    } catch (e) {
      _toast.showToast('Humanizer fix failed: $e', ToastType.error);
      return null;
    } finally {
      _isFixingPlagiarism = false;
      _chunkProgressMessage = null;
      _chunkProgressRatio = null;
      notifyListeners();
    }
  }

  /// Surgically humanizes ONLY the sentences flagged with high AI risk,
  /// preserving 100% of surrounding human text, facts, numbers, dates, and citations.
  Future<String?> surgicalHumanizeFlaggedSentences({
    required String text,
    required LlmProvider provider,
    required String apiKey,
    required String model,
    String? customBaseUrl,
    required int inputWordCount,
  }) async {
    final currentReport = _plagiarismReport;
    if (currentReport == null) {
      _toast.showToast('Please run a forensic scan first.', ToastType.info);
      return null;
    }

    _isFixingPlagiarism = true;
    notifyListeners();

    try {
      final bridge = SurgicalHumanizerBridge(
        llmService: _llmService,
        scorer: (t) async => (await _plagiarismDetector.analyzeForensic(
          t,
          mode: _scanMode,
          sensitivity: _sensitivity,
          enableOnlineSearch: false,
        )).toLegacyPlagiarismReport(),
      );
      final result = await bridge.surgicallyHumanize(
        originalText: text,
        report: currentReport,
        provider: provider,
        apiKey: apiKey,
        model: model,
        customBaseUrl: customBaseUrl,
      );

      // Already post-processed per rewritten sentence by the bridge; a
      // whole-document pass here would also rewrite the unflagged human
      // sentences the surgical mode promises to leave untouched.
      final humanized = result.humanizedText;
      final postForensic = await _plagiarismDetector.analyzeForensic(
        humanized,
        mode: _scanMode,
        sensitivity: _sensitivity,
        enableOnlineSearch: false,
      );
      final postReport = postForensic.toLegacyPlagiarismReport();
      _outputForensicReport = postForensic;

      // Run Semantic Preservation Verifier
      final extractor = StylometricFeatureExtractor();
      final origMetrics = extractor.extractFromText(text).surfaceMetrics;
      final postMetrics = extractor.extractFromText(humanized).surfaceMetrics;

      final verifier = SemanticPreservationVerifier();
      _semanticPreservationReport = verifier.verify(
        originalText: text,
        humanizedText: humanized,
        aiProbabilityBefore: _forensicReport?.aiAuthorship.aiProbability ?? (_plagiarismReport?.overallScore ?? 0),
        aiProbabilityAfter: postForensic.aiAuthorship.aiProbability,
        burstinessBefore: origMetrics['burstiness'] ?? 0.0,
        burstinessAfter: postMetrics['burstiness'] ?? 0.0,
      );

      if (_plagiarismReport != null) {
        _plagiarismReport = _plagiarismReport!.withFix(
          fixedText: humanized,
          fixedScore: postReport.overallScore,
          fixedRiskLevel: postReport.riskLevel,
        );
      }

      final historyRecord = HistoryRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        inputText: text,
        outputText: humanized,
        featureId: 'SurgicalHumanize',
        featureLabel: 'Surgical Humanizer (Flagged Spans)',
        providerName: provider.name,
        modelUsed: model,
        inputWordCount: inputWordCount,
        outputWordCount: _countWords(humanized),
        humanScore: postReport.humanScore,
        aiRiskScore: postReport.overallScore,
      );
      await _history.addHistoryRecord(historyRecord);

      _toast.showToast(
        result.summary,
        ToastType.success,
      );
      return humanized;
    } catch (e) {
      _toast.showToast('Surgical fix failed: $e', ToastType.error);
      return null;
    } finally {
      _isFixingPlagiarism = false;
      notifyListeners();
    }
  }

  static int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  void clearPlagiarismReport() {
    _plagiarismReport = null;
    _outputPlagiarismReport = null;
    _forensicReport = null;
    _outputForensicReport = null;
    _semanticPreservationReport = null;
    notifyListeners();
  }
}
