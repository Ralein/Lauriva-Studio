import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/forensic/ai_authorship_evidence.dart';
import '../../models/forensic/forensic_progress.dart';
import '../../models/forensic/forensic_report.dart';
import '../../models/forensic/forensic_scan_mode.dart';
import '../../models/forensic/source_similarity_evidence.dart';
import '../../models/llm_provider.dart';
import '../../models/plagiarism_report.dart';
import '../llm_service.dart';
import '../text_forensics_lexicons.dart';
import 'ai/neural/neural_detector_service.dart';
import 'ai/neural/neural_model_registry.dart';
import 'ai/neural/onnx_neural_runner.dart';
import 'forensic_engine.dart';
import 'sources/compact_corpus_index.dart';
import 'sources/corpus_delivery_service.dart';
import 'sources/online/online_source_search_service.dart';
import 'sources/source_repository.dart';

export '../../models/forensic/forensic_scan_mode.dart';

/// High-level coordinator that manages scan modes, chunk partitioning for arbitrary word counts,
/// offloading to background isolates for long documents, and dynamic load time tracking.
class ForensicCoordinatorService {
  final ForensicEngine _engine;
  final OnlineSourceSearchService _onlineSearchService;
  final Future<NeuralDetectorService?> Function() _neuralLoader;

  /// Languages the neural stream runs on; checked before [_neuralLoader] so
  /// uncovered text never loads the model.
  final Set<String> _neuralLanguages;

  /// [neuralLanguages] defaults to the bundled model's `supportedLanguages`.
  ForensicCoordinatorService({
    ForensicEngine? engine,
    OnlineSourceSearchService? onlineSearchService,
    Future<NeuralDetectorService?> Function()? neuralLoader,
    Set<String>? neuralLanguages,
  })  : _engine = engine ?? ForensicEngine(neuralLanguages: neuralLanguages),
        _onlineSearchService = onlineSearchService ?? OnlineSourceSearchService.withDefaults(),
        _neuralLoader = neuralLoader ?? loadBundledNeuralDetector,
        _neuralLanguages = neuralLanguages ?? bundledNeuralLanguages;

  /// Registry version of the detector bundled in assets/models.
  static const String bundledModelVersion = NeuralModelRegistry.bundledModelVersion;

  /// Languages the bundled detector was trained on.
  static Set<String> get bundledNeuralLanguages => NeuralModelRegistry.bundledConfig.supportedLanguages;

  static Future<NeuralDetectorService?>? _bundledNeural;

  /// Loads the trained `lauvira_plagiarism` ONNX detector once per process.
  /// Resolves to null when ONNX Runtime or the model is unavailable, in which
  /// case scans run on the statistical engine alone.
  static Future<NeuralDetectorService?> loadBundledNeuralDetector() {
    final pending = _bundledNeural ??= () async {
      try {
        final runner = await NeuralModelRegistry.getRunner(modelVersion: bundledModelVersion);
        if (runner is FallbackNeuralRunner) {
          debugPrint('[ForensicCoordinator] Neural detector unavailable: ${runner.reason}');
          return null;
        }
        final tokenizer = await NeuralModelRegistry.getTokenizer(modelVersion: bundledModelVersion);
        return NeuralDetectorService(
          runner: runner,
          tokenizer: tokenizer,
          config: NeuralModelRegistry.getConfig(bundledModelVersion) ?? NeuralModelRegistry.activeConfig,
        );
      } catch (e) {
        debugPrint('[ForensicCoordinator] Neural detector failed to load: $e');
        return null;
      }
    }();
    // A missing detector (not downloaded yet) must not be cached forever: retry on the next scan.
    pending.then((loaded) {
      if (loaded == null && identical(_bundledNeural, pending)) _bundledNeural = null;
    });
    return pending;
  }

  ForensicEngine get engine => _engine;
  OnlineSourceSearchService get onlineSearchService => _onlineSearchService;

  /// Runs forensic analysis on [text] across arbitrary document sizes (20 to 50,000+ words).
  ///
  /// Emits real-time [ForensicProgress] via [onProgress] with dynamic remaining load times
  /// computed from the active chunk count and rolling average execution latency.
  Future<ForensicReport> coordinate({
    required String text,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
    bool enableOnlineSearch = true,
    bool enableWatermarkDetection = true,
    bool enableHomoglyphDetection = true,
    void Function(ForensicProgress)? onProgress,
  }) async {
    final report = await _coordinateStatistical(
      text: text,
      mode: mode,
      sensitivity: sensitivity,
      enableOnlineSearch: enableOnlineSearch,
      enableWatermarkDetection: enableWatermarkDetection,
      enableHomoglyphDetection: enableHomoglyphDetection,
      onProgress: onProgress,
    );
    if (mode == ForensicScanMode.sourceScan || report.rawText.trim().isEmpty) return report;
    return _applyNeuralStream(report, mode: mode, sensitivity: sensitivity);
  }

  /// Fuses the trained transformer's verdict into [report]. Any failure leaves
  /// the statistical report untouched.
  Future<ForensicReport> _applyNeuralStream(
    ForensicReport report, {
    required ForensicScanMode mode,
    required ForensicSensitivity sensitivity,
  }) async {
    if (!ForensicEngine.neuralCovers(report.rawText, languages: _neuralLanguages)) return report;
    try {
      final neural = await _neuralLoader();
      if (neural == null) {
        debugPrint('[ForensicCoordinator] Neural stream not loaded; using stylometry only.');
        return report;
      }
      final result = await neural.analyze(text: report.rawText);
      if (result.isFallback) {
        debugPrint('[ForensicCoordinator] Neural stream fell back (${result.error}); using stylometry only.');
      } else {
        debugPrint('[ForensicCoordinator] Neural stream ok: ${result.modelVersion} '
            'p_ai=${result.aiProbability.toStringAsFixed(3)} in ${result.inferenceTime.inMilliseconds} ms');
      }
      return _engine.fuseWithNeural(report, result, mode: mode, sensitivity: sensitivity);
    } catch (e) {
      debugPrint('[ForensicCoordinator] Neural stream skipped: $e');
      return report;
    }
  }

  Future<ForensicReport> _coordinateStatistical({
    required String text,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
    bool enableOnlineSearch = true,
    bool enableWatermarkDetection = true,
    bool enableHomoglyphDetection = true,
    void Function(ForensicProgress)? onProgress,
  }) async {
    final cleanText = text.trim();

    // Offline fingerprint corpus: make sure it is extracted before the (possibly isolated) scan runs.
    // Cheap after the first launch (a 32-byte id asset is compared); null until the corpus has been downloaded.
    if (cleanText.isNotEmpty && (mode == ForensicScanMode.fullForensic || mode == ForensicScanMode.sourceScan)) {
      if (await CompactCorpusIndex.ensureReady() == null) CorpusDeliveryService.ensureInBackground();
    }

    // Guard: empty text — return safe empty report without running the engine.
    if (cleanText.isEmpty) {
      return _engine.emptyReport(scanMode: mode, sensitivity: sensitivity);
    }

    final totalWords = TextForensicsLexicons.countWordUnits(cleanText);
    final totalChunks = (totalWords / 300).ceil().clamp(1, 999);
    final stopwatch = Stopwatch()..start();

    // Emit stage 1: Partitioning & setup
    onProgress?.call(ForensicProgress(
      currentChunk: 0,
      totalChunks: totalChunks,
      progressRatio: 0.05,
      elapsed: stopwatch.elapsed,
      estimatedRemaining: Duration(milliseconds: totalChunks * 25 + (mode == ForensicScanMode.sourceScan ? 400 : 80)),
      estimatedTotal: Duration(milliseconds: totalChunks * 25 + (mode == ForensicScanMode.sourceScan ? 400 : 80)),
      stage: totalChunks > 1
          ? 'Partitioning $totalWords words into $totalChunks chunks...'
          : 'Initializing neural forensic engine...',
      wordsProcessed: 0,
      totalWords: totalWords,
    ));

    // Fetch live online sources (OpenAlex, Crossref, Wikipedia, DOAJ, PubMed, Semantic Scholar, arXiv)
    // with adaptive timeout (7s for dedicated source scan, 5s for full forensic) to maximize recall.
    List<SourceCorpusDocument> onlineDocs = const [];
    if (enableOnlineSearch && (mode == ForensicScanMode.fullForensic || mode == ForensicScanMode.sourceScan)) {
      onProgress?.call(ForensicProgress(
        currentChunk: 0,
        totalChunks: totalChunks,
        progressRatio: 0.12,
        elapsed: stopwatch.elapsed,
        estimatedRemaining: Duration(milliseconds: totalChunks * 25 + 350),
        estimatedTotal: Duration(milliseconds: totalChunks * 25 + 400),
        stage: 'Indexing global academic & web literature repositories...',
        wordsProcessed: 0,
        totalWords: totalWords,
      ));

      try {
        final searchTimeout = mode == ForensicScanMode.sourceScan
            ? const Duration(seconds: 10)
            : const Duration(seconds: 8);
        final onlineResult = await _onlineSearchService.search(cleanText).timeout(
          searchTimeout,
          onTimeout: () => OnlineSourceSearchResult.empty,
        );
        onlineDocs = onlineResult.documents;
        for (final doc in onlineDocs) {
          SourceRepository.baselineLiterature.addDocument(doc);
        }
      } catch (e) {
        debugPrint('[ForensicCoordinator] Online search warning: $e');
      }
    }

    if (cleanText.length < 1200) {
      return _safeAnalyzeSync(
        cleanText,
        mode: mode,
        sensitivity: sensitivity,
        enableOnlineSearch: enableOnlineSearch,
        enableWatermarkDetection: enableWatermarkDetection,
        enableHomoglyphDetection: enableHomoglyphDetection,
        onProgress: onProgress,
      );
    }

    // Offload heavy computation to a background isolate and consume the result.
    try {
      // Simulate chunk-by-chunk progress ticks during isolate execution
      final jsonFuture = compute(_runIsolatedForensicScan, jsonEncode({
        'rawText': cleanText,
        'scanModeName': mode.name,
        'sensitivityName': sensitivity.name,
        'enableWatermark': enableWatermarkDetection,
        'enableHomoglyph': enableHomoglyphDetection,
        'onlineDocs': [for (final d in onlineDocs) d.toJson()],
        'neuralLanguages': _neuralLanguages.toList(),
      }));

      // Stream realistic chunk progress while isolate computes
      final chunkTimeMs = 28;
      for (int c = 1; c <= totalChunks; c++) {
        final wordsSoFar = ((c / totalChunks) * totalWords).round();
        final remChunks = totalChunks - c;
        final estRemainingMs = remChunks * chunkTimeMs + 40;

        onProgress?.call(ForensicProgress(
          currentChunk: c,
          totalChunks: totalChunks,
          progressRatio: (0.15 + (c / totalChunks) * 0.75).clamp(0.0, 0.92),
          elapsed: stopwatch.elapsed,
          estimatedRemaining: Duration(milliseconds: estRemainingMs),
          estimatedTotal: Duration(milliseconds: totalChunks * chunkTimeMs + 100),
          stage: totalChunks > 1
              ? 'Analyzing chunk $c of $totalChunks ($wordsSoFar of $totalWords words)...'
              : 'Executing neural stylometric analysis...',
          wordsProcessed: wordsSoFar,
          totalWords: totalWords,
        ));

        // Yield execution to allow UI animations to paint smoothly
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }

      final jsonString = await jsonFuture;

      // Detect error sentinel — isolate caught an exception and returned it encoded.
      if (jsonString.startsWith('{"__error":')) {
        final errDecoded = jsonDecode(jsonString) as Map<String, dynamic>;
        debugPrint(
          '[ForensicCoordinator] Isolate error: ${errDecoded["__error"]}. Falling back to sync.',
        );
        return _safeAnalyzeSync(
          cleanText,
          mode: mode,
          sensitivity: sensitivity,
          enableOnlineSearch: enableOnlineSearch,
          enableWatermarkDetection: enableWatermarkDetection,
          enableHomoglyphDetection: enableHomoglyphDetection,
          onProgress: onProgress,
        );
      }

      final isolateReport = ForensicReport.fromJsonSafe(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );

      onProgress?.call(ForensicProgress(
        currentChunk: totalChunks,
        totalChunks: totalChunks,
        progressRatio: 1.0,
        elapsed: stopwatch.elapsed,
        estimatedRemaining: Duration.zero,
        estimatedTotal: stopwatch.elapsed,
        stage: 'Forensic audit finalized',
        wordsProcessed: totalWords,
        totalWords: totalWords,
      ));

      // Rebuild sentence audits on main thread (they reference PlagiarismRiskLevel colors)
      return _engine.rebuildSentences(isolateReport);
    } catch (e) {
      // Isolate or deserialisation error — fall back to synchronous analysis.
      debugPrint('[ForensicCoordinator] Isolate failed: $e. Falling back to sync.');
      return _safeAnalyzeSync(
        cleanText,
        mode: mode,
        sensitivity: sensitivity,
        enableOnlineSearch: enableOnlineSearch,
        enableWatermarkDetection: enableWatermarkDetection,
        enableHomoglyphDetection: enableHomoglyphDetection,
        onProgress: onProgress,
      );
    }
  }

  /// Synchronous analysis with a defensive try/catch — even a sync engine
  /// exception returns an empty safe report rather than crashing.
  ForensicReport _safeAnalyzeSync(
    String text, {
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
    bool enableOnlineSearch = true,
    bool enableWatermarkDetection = true,
    bool enableHomoglyphDetection = true,
    void Function(ForensicProgress)? onProgress,
  }) {
    try {
      return _engine.analyze(
        text,
        neuralLanguages: _neuralLanguages,
        mode: mode,
        sensitivity: sensitivity,
        enableOnlineSearch: enableOnlineSearch,
        enableWatermarkDetection: enableWatermarkDetection,
        enableHomoglyphDetection: enableHomoglyphDetection,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[ForensicCoordinator] Sync analysis failed: $e. Returning empty report.');
      return _engine.emptyReport(scanMode: mode, sensitivity: sensitivity);
    }
  }

  static String _runIsolatedForensicScan(String jsonPayload) {
    try {
      final decoded = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final rawText = decoded['rawText'] as String;
      final mode = ForensicScanMode.fromName(decoded['scanModeName'] as String?);
      final sensitivity = ForensicSensitivity.fromName(decoded['sensitivityName'] as String?);
      final enableWatermark = decoded['enableWatermark'] as bool? ?? true;
      final enableHomoglyph = decoded['enableHomoglyph'] as bool? ?? true;

      if (decoded['onlineDocs'] is List) {
        for (final d in decoded['onlineDocs'] as List) {
          if (d is Map<String, dynamic>) {
            SourceRepository.baselineLiterature.addDocument(SourceCorpusDocument.fromJson(d));
          }
        }
      }
      final neuralLanguages = (decoded['neuralLanguages'] as List?)?.map((e) => e.toString()).toSet();
      final engine = ForensicEngine();
      final report = engine.analyze(
        rawText,
        neuralLanguages: neuralLanguages,
        mode: mode,
        sensitivity: sensitivity,
        enableWatermarkDetection: enableWatermark,
        enableHomoglyphDetection: enableHomoglyph,
      );
      return jsonEncode(report.toJson());
    } catch (e) {
      // Return error sentinel so the main thread can detect and fall back.
      return jsonEncode({'__error': e.toString()});
    }
  }

  /// Cloud LLM-backed Forensic Audit. Never falls back to offline execution.
  /// Requires active API key and internet connectivity.
  Future<ForensicReport> coordinateWithLlm({
    required String text,
    required LlmService llmService,
    required LlmProvider provider,
    required String apiKey,
    required String model,
    Map<String, String>? allConfiguredKeys,
    String? customBaseUrl,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
    bool enableOnlineSearch = true,
    void Function(ForensicProgress)? onProgress,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return _engine.emptyReport(scanMode: mode, sensitivity: sensitivity);
    }

    if (provider.requiresKey && apiKey.trim().isEmpty) {
      throw LlmApiException('API key required for ${provider.name}. Offline engine is disabled.');
    }

    final totalWords = TextForensicsLexicons.countWordUnits(cleanText);
    final stopwatch = Stopwatch()..start();

    // Stage 1: Setup
    onProgress?.call(ForensicProgress(
      currentChunk: 0,
      totalChunks: 1,
      progressRatio: 0.1,
      elapsed: stopwatch.elapsed,
      estimatedRemaining: const Duration(seconds: 4),
      estimatedTotal: const Duration(seconds: 4),
      stage: 'Connecting to ${provider.name} cloud LLM...',
      wordsProcessed: 0,
      totalWords: totalWords,
    ));

    // Stage 2: Online Source Search across global academic APIs
    List<SourceCorpusDocument> onlineDocs = const [];
    if (enableOnlineSearch && (mode == ForensicScanMode.fullForensic || mode == ForensicScanMode.sourceScan)) {
      onProgress?.call(ForensicProgress(
        currentChunk: 0,
        totalChunks: 1,
        progressRatio: 0.25,
        elapsed: stopwatch.elapsed,
        estimatedRemaining: const Duration(seconds: 3),
        estimatedTotal: const Duration(seconds: 4),
        stage: 'Indexing global academic & web literature repositories...',
        wordsProcessed: 0,
        totalWords: totalWords,
      ));

      try {
        final searchTimeout = mode == ForensicScanMode.sourceScan
            ? const Duration(seconds: 10)
            : const Duration(seconds: 8);
        final onlineResult = await _onlineSearchService.search(cleanText).timeout(
          searchTimeout,
          onTimeout: () => OnlineSourceSearchResult.empty,
        );
        onlineDocs = onlineResult.documents;
        for (final doc in onlineDocs) {
          SourceRepository.baselineLiterature.addDocument(doc);
        }
      } catch (e) {
        debugPrint('[ForensicCoordinator] Online search warning: $e');
      }
    }

    // Stage 3: Frontier LLM Audit
    onProgress?.call(ForensicProgress(
      currentChunk: 1,
      totalChunks: 1,
      progressRatio: 0.6,
      elapsed: stopwatch.elapsed,
      estimatedRemaining: const Duration(seconds: 2),
      estimatedTotal: const Duration(seconds: 4),
      stage: 'Auditing text with ${provider.name} ($model)...',
      wordsProcessed: 0,
      totalWords: totalWords,
    ));

    final auditMap = await llmService.auditPlagiarismWithLlm(
      provider: provider,
      apiKey: apiKey,
      text: cleanText,
      model: model,
      allConfiguredKeys: allConfiguredKeys,
      customBaseUrl: customBaseUrl,
    );

    // Stage 4: Multi-signal stylometric & literature analysis
    final engineReport = await _applyNeuralStream(
      _engine.analyze(
        cleanText,
        neuralLanguages: _neuralLanguages,
        mode: mode,
        sensitivity: sensitivity,
        enableOnlineSearch: enableOnlineSearch,
        enableWatermarkDetection: true,
        enableHomoglyphDetection: true,
      ),
      mode: mode,
      sensitivity: sensitivity,
    );

    final engineAi = engineReport.aiAuthorship.aiProbability;
    final llmAi = (auditMap['overallScore'] as num?)?.toDouble() ?? 0.0;

    // Decisive fusion: ensure AI likelihood is not diluted by timid LLM responses.
    // If the 38-feature stylometric engine identifies AI structures (low burstiness, high perplexity,
    // repetitive n-grams) with confidence, or if the LLM flagged AI, take the decisive maximum.
    final overallAi = max(engineAi, llmAi).clamp(0.0, 100.0);

    final llmPlagScore = (auditMap['plagiarismRiskScore'] as num?)?.toDouble() ?? 0.0;
    final enginePlagScore = engineReport.sourceSimilarity.overallSimilarityScore;
    final overallPlag = max(enginePlagScore, llmPlagScore).clamp(0.0, 100.0);

    // Merge detected tells and signals
    final llmTells = (auditMap['detectedTells'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? <String>[];
    final mergedSignals = <AiSignalItem>[
      ...engineReport.aiAuthorship.detectedSignals,
      for (final tell in llmTells)
        if (!engineReport.aiAuthorship.detectedSignals.any((s) => s.name.toLowerCase() == tell.toLowerCase()))
          AiSignalItem(
            family: 'CloudLLM',
            name: tell,
            score: 1.0,
            weight: 1.0,
            description: tell,
          ),
    ];

    // Merge sentence-level audits with maximum risk preservation
    final sentencesList = <SentenceAudit>[];
    final sentencesRaw = auditMap['sentences'] as List<dynamic>?;
    final llmSentencesMap = <int, Map<String, dynamic>>{};
    if (sentencesRaw != null) {
      for (int i = 0; i < sentencesRaw.length; i++) {
        final sObj = sentencesRaw[i];
        if (sObj is Map<String, dynamic>) {
          final idx = (sObj['index'] as num?)?.toInt() ?? i;
          llmSentencesMap[idx] = sObj;
        }
      }
    }

    if (engineReport.sentences.isNotEmpty) {
      for (int i = 0; i < engineReport.sentences.length; i++) {
        final engS = engineReport.sentences[i];
        final llmS = llmSentencesMap[i];
        double sScore = engS.aiProbability;
        final sTells = List<String>.from(engS.detectedTells);
        if (llmS != null) {
          final llmScore = (llmS['aiProbability'] as num?)?.toDouble();
          if (llmScore != null) {
            sScore = max(sScore, llmScore);
          }
          final extraTells = (llmS['detectedTells'] as List<dynamic>?)?.map((t) => t.toString()).toList();
          if (extraTells != null) {
            for (final t in extraTells) {
              if (!sTells.contains(t)) sTells.add(t);
            }
          }
        }
        sentencesList.add(SentenceAudit(
          index: i,
          text: engS.text,
          aiProbability: sScore,
          riskLevel: PlagiarismRiskLevel.fromScore(sScore),
          detectedTells: sTells,
          wordCount: engS.wordCount,
          burstinessDelta: engS.burstinessDelta,
        ));
      }
    } else {
      final extractedSentences = TextForensicsLexicons.splitSentences(cleanText);
      for (int i = 0; i < extractedSentences.length; i++) {
        final sText = extractedSentences[i];
        sentencesList.add(SentenceAudit(
          index: i,
          text: sText,
          aiProbability: overallAi,
          riskLevel: PlagiarismRiskLevel.fromScore(overallAi),
          detectedTells: const [],
          wordCount: TextForensicsLexicons.countWordUnits(sText),
        ));
      }
    }

    final AuthorshipClass authorshipClass;
    if (totalWords < 25) {
      authorshipClass = AuthorshipClass.inconclusive;
    } else if (overallAi >= 70.0) {
      authorshipClass = AuthorshipClass.likelyAi;
    } else if (overallAi <= 35.0) {
      authorshipClass = AuthorshipClass.likelyHuman;
    } else {
      authorshipClass = AuthorshipClass.mixedOrEdited;
    }

    final summary = (auditMap['defensibleSummary'] as String?)?.isNotEmpty == true
        ? auditMap['defensibleSummary'] as String
        : engineReport.summary;

    final report = ForensicReport(
      metadata: ForensicReportMetadata(
        analysisId: DateTime.now().millisecondsSinceEpoch.toString(),
        textHash: cleanText.hashCode.toString(),
        analyzedAt: DateTime.now(),
        scanMode: mode,
        sensitivity: sensitivity,
        engineVersion: 'Lauriva Cloud LLM (${provider.name} / $model)',
        executionDuration: stopwatch.elapsed,
      ),
      rawText: cleanText,
      normalizedText: engineReport.normalizedText,
      wordCount: totalWords,
      charCount: cleanText.length,
      sentenceCount: sentencesList.length,
      paragraphCount: engineReport.paragraphCount,
      aiAuthorship: AiAuthorshipEvidence(
        aiProbability: overallAi,
        humanProbability: (100.0 - overallAi).clamp(0.0, 100.0),
        authorshipClass: authorshipClass,
        uncertainty: engineReport.aiAuthorship.uncertainty,
        detectedSignals: mergedSignals,
        windows: engineReport.aiAuthorship.windows,
        featureVector: engineReport.aiAuthorship.featureVector,
        defensibleSummary: summary,
      ),
      sourceSimilarity: SourceSimilarityEvidence(
        overallSimilarityScore: overallPlag,
        documentCoveragePercent: max(engineReport.sourceSimilarity.documentCoveragePercent, overallPlag),
        matchedTokenCount: engineReport.sourceSimilarity.matchedTokenCount,
        longestContiguousTokenMatch: engineReport.sourceSimilarity.longestContiguousTokenMatch,
        uniqueSourceCount: engineReport.sourceSimilarity.uniqueSourceCount,
        matches: engineReport.sourceSimilarity.matches,
        defensibleSummary: engineReport.sourceSimilarity.defensibleSummary,
      ),
      internalRepetition: engineReport.internalRepetition,
      confidence: engineReport.confidence,
      tokenPredictability: engineReport.tokenPredictability,
      adversarialEvidence: engineReport.adversarialEvidence,
      spans: engineReport.spans,
      sentences: sentencesList,
      summary: summary,
    );

    onProgress?.call(ForensicProgress(
      currentChunk: 1,
      totalChunks: 1,
      progressRatio: 1.0,
      elapsed: stopwatch.elapsed,
      estimatedRemaining: Duration.zero,
      estimatedTotal: stopwatch.elapsed,
      stage: 'Forensic audit finalized.',
      wordsProcessed: totalWords,
      totalWords: totalWords,
    ));

    return report;
  }
}
