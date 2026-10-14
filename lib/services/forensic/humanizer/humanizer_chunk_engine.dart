import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../models/llm_provider.dart';
import '../../../models/plagiarism_report.dart';
import '../../ai_forensic_service.dart';
import '../../llm_service.dart';
import '../../text_forensics_lexicons.dart';
import '../document/document_segmenter.dart';
import 'algorithmic_humanizer_service.dart';
import 'document_coherence_pass.dart';
import 'document_style_profiler.dart';
import 'humanizer_model.dart';
import 'lauvira_humanize_service.dart';
import 'paragraph_reconstructor.dart';
import 'protected_content_manager.dart';
import 'on_device_t5_humanizer_model.dart';
import 'semantic_preservation_verifier.dart';
import 't5_humanizer_registry.dart';

/// A discrete semantic chunk of a larger document prepared for independent
/// high-attention humanization and on-device model inference.
class HumanizerChunk {
  final int index;
  final int totalChunks;
  final String text;
  final String trailingDelimiter;
  final int paragraphIndex;
  final String precedingContext;
  final String followingContext;
  final String paragraphTopic;

  const HumanizerChunk({
    required this.index,
    required this.totalChunks,
    required this.text,
    this.trailingDelimiter = '\n\n',
    this.paragraphIndex = 0,
    this.precedingContext = '',
    this.followingContext = '',
    this.paragraphTopic = '',
  });

  int get wordCount => text.trim().isEmpty
      ? 0
      : text.trim().split(RegExp(r'\s+')).length;
}

/// Chunk progress event emitted during multi-chunk humanization.
class HumanizerChunkProgress {
  final int currentChunk;
  final int totalChunks;
  final double ratio; // 0.0 to 1.0
  final String message;

  const HumanizerChunkProgress({
    required this.currentChunk,
    required this.totalChunks,
    required this.ratio,
    required this.message,
  });
}

/// Result of full chunked humanization.
class HumanizerResult {
  final String humanizedText;
  final PlagiarismReport beforeReport;
  final PlagiarismReport afterReport;
  final SemanticPreservationReport preservationReport;
  final int totalChunksProcessed;
  final bool usedLocalFallback;

  const HumanizerResult({
    required this.humanizedText,
    required this.beforeReport,
    required this.afterReport,
    required this.preservationReport,
    required this.totalChunksProcessed,
    this.usedLocalFallback = false,
  });
}

/// Senior Principal Developer Architecture:
/// HumanizerChunkEngine orchestrates a 13-stage hierarchical pipeline:
/// Document Segmentation -> Paragraph Segmentation -> Sentence Segmentation ->
/// Semantic Chunking -> Context-Aware Rewrite -> Local Quality Validation ->
/// Cross-Chunk Consistency -> Paragraph Reconstruction -> Document-Level Coherence ->
/// Protected Content Restoration -> On-Device AI Audit -> Final Quality Gate.
class HumanizerChunkEngine {
  final LauviraHumanizeService _lauviraHumanize;
  final AiForensicService _forensicService;
  final SemanticPreservationVerifier _verifier;
  final ProtectedContentManager _protectedManager;
  final DocumentStyleProfiler _styleProfiler;
  final ParagraphReconstructor _paragraphReconstructor;
  final DocumentCoherencePass _coherencePass;
  final DocumentSegmenter _documentSegmenter;

  /// Supplies the optional on-device T5 model for the local fallback stage
  /// (cloud LLM -> on-device T5 ONNX -> rule-based). Defaults to the process
  /// registry, which yields null until the model files are downloaded.
  final Future<HumanizerModel?> Function() _onDeviceT5Provider;

  HumanizerChunkEngine({
    LauviraHumanizeService? lauviraHumanize,
    AiForensicService? forensicService,
    SemanticPreservationVerifier? verifier,
    ProtectedContentManager? protectedManager,
    DocumentStyleProfiler? styleProfiler,
    ParagraphReconstructor? paragraphReconstructor,
    DocumentCoherencePass? coherencePass,
    DocumentSegmenter? documentSegmenter,
    Future<HumanizerModel?> Function()? onDeviceT5Provider,
  })  : _onDeviceT5Provider = onDeviceT5Provider ?? T5HumanizerRegistry.instance.tryGet,
        _lauviraHumanize = lauviraHumanize ?? LauviraHumanizeService(),
        _forensicService = forensicService ?? AiForensicService(),
        _verifier = verifier ?? SemanticPreservationVerifier(),
        _protectedManager = protectedManager ?? ProtectedContentManager(),
        _styleProfiler = styleProfiler ?? DocumentStyleProfiler(),
        _paragraphReconstructor = paragraphReconstructor ?? ParagraphReconstructor(),
        _coherencePass = coherencePass ?? DocumentCoherencePass(),
        _documentSegmenter = documentSegmenter ?? DocumentSegmenter();

  DocumentSegmenter get documentSegmenter => _documentSegmenter;

  /// Local fallback stage: on-device T5 when available, otherwise the rules.
  HumanizerModel _localFallbackModel() => LocalHumanizerFallbackModel(
        t5Provider: _onDeviceT5Provider,
        rules: LocalAlgorithmicHumanizerModel(lauviraService: _lauviraHumanize),
      );

  /// Partitions [rawText] into optimal semantic chunks targeting [targetWordsPerChunk] words (default 120).
  List<HumanizerChunk> partitionIntoChunks(String rawText, {int targetWordsPerChunk = 120}) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return const [];

    final totalWords = trimmed.split(RegExp(r'\s+')).length;
    if (totalWords <= 150) {
      return [
        HumanizerChunk(
          index: 1,
          totalChunks: 1,
          text: trimmed,
          trailingDelimiter: '',
        ),
      ];
    }

    // Split on paragraph boundaries
    final paragraphRegex = RegExp(r'(\r?\n\s*){2,}');
    final rawParagraphs = rawText.split(paragraphRegex);

    final rawChunks = <String>[];
    for (final p in rawParagraphs) {
      final pTrimmed = p.trim();
      if (pTrimmed.isEmpty) continue;

      final pWords = pTrimmed.split(RegExp(r'\s+')).length;
      if (pWords > (targetWordsPerChunk * 1.5)) {
        // Sub-partition giant paragraphs by sentences
        final sentences = _splitIntoSentences(pTrimmed);
        var currentSub = <String>[];
        int currentSubWords = 0;

        for (final s in sentences) {
          final sWords = s.split(RegExp(r'\s+')).length;
          currentSub.add(s);
          currentSubWords += sWords;

          if (currentSubWords >= targetWordsPerChunk) {
            rawChunks.add(currentSub.join(' '));
            currentSub.clear();
            currentSubWords = 0;
          }
        }
        if (currentSub.isNotEmpty) {
          if (rawChunks.isNotEmpty && currentSubWords < 40) {
            rawChunks[rawChunks.length - 1] = '${rawChunks.last} ${currentSub.join(' ')}';
          } else {
            rawChunks.add(currentSub.join(' '));
          }
        }
      } else {
        // Normal paragraph - bundle tiny adjacent paragraphs
        if (rawChunks.isNotEmpty && pWords < 40) {
          final prevWords = rawChunks.last.split(RegExp(r'\s+')).length;
          if (prevWords + pWords <= targetWordsPerChunk) {
            rawChunks[rawChunks.length - 1] = '${rawChunks.last}\n\n$pTrimmed';
            continue;
          }
        }
        rawChunks.add(pTrimmed);
      }
    }

    if (rawChunks.isEmpty) {
      rawChunks.add(trimmed);
    }

    final total = rawChunks.length;
    final result = <HumanizerChunk>[];
    for (int i = 0; i < total; i++) {
      result.add(
        HumanizerChunk(
          index: i + 1,
          totalChunks: total,
          text: rawChunks[i],
          trailingDelimiter: i == total - 1 ? '' : '\n\n',
        ),
      );
    }
    return result;
  }

  /// Builds adaptive, context-rich chunks across paragraphs and sentences.
  List<HumanizerChunk> buildHierarchicalChunks({
    required String maskedText,
    int targetWordsPerChunk = 120,
  }) {
    final paragraphRegex = RegExp(r'(\r?\n\s*){2,}');
    final rawParagraphs = maskedText.split(paragraphRegex).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (rawParagraphs.isEmpty) return const [];

    final rawChunksList = <_RawChunkInfo>[];

    for (int pIdx = 0; pIdx < rawParagraphs.length; pIdx++) {
      final pText = rawParagraphs[pIdx];
      final pSentences = _splitIntoSentences(pText);
      final pWords = pText.split(RegExp(r'\s+')).length;
      final topic = pSentences.isNotEmpty ? pSentences.first : '';

      // Keep complete paragraphs intact whenever <= targetWordsPerChunk (120 words).
      // This preserves intra-paragraph burstiness while adaptively chunking longer prose.
      if (pWords <= targetWordsPerChunk) {
        rawChunksList.add(_RawChunkInfo(
          paragraphIndex: pIdx,
          text: pText,
          paragraphTopic: topic,
        ));
      } else {
        // Very large paragraphs (>220 words): chunk along natural sentence boundaries
        var currentSentences = <String>[];
        int currentWords = 0;

        for (final s in pSentences) {
          final sWords = s.split(RegExp(r'\s+')).length;
          currentSentences.add(s);
          currentWords += sWords;

          if (currentWords >= targetWordsPerChunk) {
            rawChunksList.add(_RawChunkInfo(
              paragraphIndex: pIdx,
              text: currentSentences.join(' '),
              paragraphTopic: topic,
            ));
            currentSentences = <String>[];
            currentWords = 0;
          }
        }

        if (currentSentences.isNotEmpty) {
          // If trailing chunk is very short (< 25 words), append to last chunk of this paragraph if possible
          if (rawChunksList.isNotEmpty &&
              rawChunksList.last.paragraphIndex == pIdx &&
              currentWords < 25) {
            final lastChunk = rawChunksList.removeLast();
            rawChunksList.add(_RawChunkInfo(
              paragraphIndex: pIdx,
              text: '${lastChunk.text} ${currentSentences.join(" ")}',
              paragraphTopic: topic,
            ));
          } else {
            rawChunksList.add(_RawChunkInfo(
              paragraphIndex: pIdx,
              text: currentSentences.join(' '),
              paragraphTopic: topic,
            ));
          }
        }
      }
    }

    final total = rawChunksList.length;
    final finalChunks = <HumanizerChunk>[];

    for (int i = 0; i < total; i++) {
      final curr = rawChunksList[i];

      // Extract preceding context (last 1-2 sentences of previous chunk)
      String preceding = '';
      if (i > 0) {
        final prevSentences = _splitIntoSentences(rawChunksList[i - 1].text);
        if (prevSentences.isNotEmpty) {
          preceding = prevSentences.length >= 2
              ? '${prevSentences[prevSentences.length - 2]} ${prevSentences.last}'
              : prevSentences.last;
        }
      }

      // Extract following context (first 1-2 sentences of next chunk)
      String following = '';
      if (i < total - 1) {
        final nextSentences = _splitIntoSentences(rawChunksList[i + 1].text);
        if (nextSentences.isNotEmpty) {
          following = nextSentences.length >= 2
              ? '${nextSentences[0]} ${nextSentences[1]}'
              : nextSentences.first;
        }
      }

      finalChunks.add(HumanizerChunk(
        index: i + 1,
        totalChunks: total,
        text: curr.text,
        paragraphIndex: curr.paragraphIndex,
        paragraphTopic: curr.paragraphTopic,
        precedingContext: preceding,
        followingContext: following,
        trailingDelimiter: (i < total - 1 && rawChunksList[i + 1].paragraphIndex != curr.paragraphIndex)
            ? '\n\n'
            : ' ',
      ));
    }

    return finalChunks;
  }

  List<String> _splitIntoSentences(String text) {
    final list = TextForensicsLexicons.splitSentences(text);
    return list.isNotEmpty ? list : [text];
  }

  /// Processes document through the 13-stage hierarchical pipeline.
  Future<HumanizerResult> processDocument({
    required String rawText,
    required WritingToneProfile tone,
    String style = 'balanced',
    required LlmService llmService,
    required LlmProvider activeProvider,
    required String activeApiKey,
    required String activeModel,
    Map<String, String>? allConfiguredKeys,
    String? customBaseUrl,
    LlmGenerationParams? generationParams,
    int intensity = 85,
    bool throwOnLlmError = false,
    HumanizerModel? customModel,
    void Function(LlmProvider provider, String model, String reason)? onFailoverDetails,
    void Function(HumanizerChunkProgress progress)? onProgress,
    Future<PlagiarismReport> Function(String text)? documentScorer,
  }) async {
    final cleanInput = rawText.trim();
    if (cleanInput.isEmpty) {
      throw LlmApiException('Cannot humanize empty text.');
    }

    // Stage 1 & 2: Document & Style Profiling
    onProgress?.call(const HumanizerChunkProgress(
      currentChunk: 0,
      totalChunks: 1,
      ratio: 0.05,
      message: 'Extracting authorial style profile and syntactic markers...',
    ));
    final styleProfile = _styleProfiler.profile(cleanInput);

    // Stage 3: Protected Content Masking (quotes, citations, numbers, dates, formulas)
    final maskedResult = _protectedManager.mask(cleanInput);

    // Stage 4: Hierarchical & Context-Aware Chunking
    final chunks = buildHierarchicalChunks(maskedText: maskedResult.maskedText);
    final total = chunks.length;

    // Stage 5: Instantiate Model (Cloud LLM or Custom)
    final HumanizerModel model = customModel ??
        CloudLlmHumanizerModel(
          llmService: llmService,
          provider: activeProvider,
          apiKey: activeApiKey,
          model: activeModel,
          allConfiguredKeys: allConfiguredKeys,
          customBaseUrl: customBaseUrl,
          generationParams: generationParams,
          onFailoverDetails: onFailoverDetails,
        );

    // Group rewritten chunks by paragraph index
    final Map<int, List<String>> rewrittenParagraphsMap = {};
    bool anyChunkUsedFallback = false;

    for (int i = 0; i < total; i++) {
      final chunk = chunks[i];
      final ratio = 0.10 + ((i + 1) / total) * 0.65; // 10% to 75%

      onProgress?.call(
        HumanizerChunkProgress(
          currentChunk: i + 1,
          totalChunks: total,
          ratio: ratio,
          message: total > 1
              ? 'Section ${i + 1} of $total (${chunk.wordCount} words)'
              : 'Section 1 of 1 (${chunk.wordCount} words)',
        ),
      );

      final chunkProtected = _protectedManager.filterForChunk(
        chunk.text,
        maskedResult.tokenMap,
      );

      var rewriteContext = ChunkRewriteContext(
        targetChunk: chunk.text,
        precedingContext: chunk.precedingContext,
        followingContext: chunk.followingContext,
        paragraphTopic: chunk.paragraphTopic,
        styleProfile: styleProfile,
        tone: tone,
        style: style,
        protectedPlaceholders: chunkProtected.keys.toList(),
        intensity: intensity,
      );

      String rewrittenChunk = '';
      int retryCount = 0;
      const maxRetries = 2;
      bool usedLocalFallback = false;

      while (retryCount <= maxRetries) {
        try {
          rewrittenChunk = await model.rewriteChunk(rewriteContext);
          if (rewrittenChunk.trim().isNotEmpty) {
            // Stage 6: Local Quality Validation for chunk
            // Verify protected placeholders survived LLM generation
            bool allPlaceholdersSurvive = true;
            for (final tokenKey in chunkProtected.keys) {
              if (!rewrittenChunk.contains(tokenKey.replaceAll(RegExp(r'\s+'), ''))) {
                allPlaceholdersSurvive = false;
                break;
              }
            }

            // Length floor guard: allow natural human conciseness down to 70% of source chunk length
            final srcWords = chunk.wordCount;
            final outWords = rewrittenChunk.trim().split(RegExp(r'\s+')).length;
            final lengthRatio = srcWords == 0 ? 1.0 : (outWords / srcWords);
            final lengthOk = lengthRatio >= 0.70;

            // Verbatim echo guard: detect if LLM merely echoed the input text without restructuring
            final wordOverlap = computeWordOverlap(chunk.text, rewrittenChunk);
            final notEcho = customModel != null || wordOverlap <= 0.85; // Over 85% word overlap is an un-humanized echo

            if (allPlaceholdersSurvive && lengthOk && notEcho) {
              break;
            }

            if (!notEcho && retryCount < maxRetries) {
              debugPrint('[HumanizerChunkEngine] Chunk ${i + 1} rejected: verbatim echo detected (${(wordOverlap * 100).toStringAsFixed(1)}% overlap). Re-prompting with forced syntactic restructuring.');
              rewriteContext = rewriteContext.withDetectorFeedback(
                'CRITICAL REJECTION: Your previous rewrite retained ${(wordOverlap * 100).toStringAsFixed(0)}% verbatim word overlap with the original text. '
                'An AI detector flags verbatim sentence structures immediately. You MUST radically reconstruct the sentence grammar: '
                'invert clauses, lead with dependent conditions or adverbials, vary sentence lengths between 4 and 30 words, and use fresh phrasing while preserving all facts.',
              );
              retryCount++;
              continue;
            }

            if (retryCount == maxRetries) {
              // Retain the LLM output if non-empty rather than overwriting with local fallback
              break;
            }
          }
        } catch (e) {
          debugPrint('[HumanizerChunkEngine] Rewrite error on chunk ${i + 1} (attempt ${retryCount + 1}): $e');
          if (retryCount >= maxRetries) {
            if (throwOnLlmError) rethrow;
            // Attempt cloud keyless LLM failover first (Pollinations) before local fallback
            if (customModel == null && activeProvider.id != 'pollinations') {
              try {
                final pollinationsProvider = LlmProvider.allProviders.firstWhere(
                  (p) => p.id == 'pollinations',
                );
                final failoverModel = CloudLlmHumanizerModel(
                  llmService: llmService,
                  provider: pollinationsProvider,
                  apiKey: '',
                  model: pollinationsProvider.defaultModel,
                  generationParams: generationParams,
                );
                rewrittenChunk = await failoverModel.rewriteChunk(rewriteContext);
                if (rewrittenChunk.trim().isNotEmpty) {
                  break;
                }
              } catch (failoverError) {
                debugPrint('[HumanizerChunkEngine] Failover LLM error: $failoverError');
              }
            }
            // Graceful fallback to local algorithmic humanizer for this chunk
            rewrittenChunk = await _localFallbackModel().rewriteChunk(rewriteContext);
            usedLocalFallback = true;
            break;
          }
        }
        retryCount++;
      }

      if (rewrittenChunk.trim().isEmpty) {
        rewrittenChunk = chunk.text;
      }

      // Stage 7: Local Post-Processing (lauvira neural burstiness + quality loop)
      var processedChunk = await _lauviraHumanize.humanizeLlmOutput(
        rewrittenChunk,
        tone: tone,
        style: style,
        originalText: chunk.text,
        intensity: intensity,
      );

      // Stage 7b: Detector-guided refinement of chunks that still read as AI
      if (documentScorer != null && !usedLocalFallback) {
        processedChunk = await _refineWithDetector(
          model: model,
          context: rewriteContext,
          firstPass: processedChunk,
          chunkProtected: chunkProtected,
          tokenMap: maskedResult.tokenMap,
          tone: tone,
          style: style,
          intensity: intensity,
          scorer: documentScorer,
        );
      }

      if (usedLocalFallback) {
        anyChunkUsedFallback = true;
      }
      rewrittenParagraphsMap.putIfAbsent(chunk.paragraphIndex, () => []).add(processedChunk);
    }

    // Stage 8: Paragraph-Level Reconstruction & Cross-Chunk Smoothing
    onProgress?.call(const HumanizerChunkProgress(
      currentChunk: 0,
      totalChunks: 1,
      ratio: 0.80,
      message: 'Reconstructing paragraphs and smoothing transition boundaries...',
    ));

    final reconstructedParagraphs = <String>[];
    final originalParagraphs = cleanInput.split(RegExp(r'(\r?\n\s*){2,}'));

    for (final entry in rewrittenParagraphsMap.entries) {
      final pIdx = entry.key;
      final pChunks = entry.value;
      final origP = pIdx < originalParagraphs.length ? originalParagraphs[pIdx] : '';

      final reconResult = _paragraphReconstructor.reconstruct(
        rewrittenChunks: pChunks,
        originalParagraph: origP,
      );
      reconstructedParagraphs.add(reconResult.text);
    }

    // Stage 9: Document-Level Coherence Pass
    onProgress?.call(const HumanizerChunkProgress(
      currentChunk: 0,
      totalChunks: 1,
      ratio: 0.88,
      message: 'Running document-level coherence and inter-paragraph verification...',
    ));

    final coherenceResult = _coherencePass.harmonize(reconstructedParagraphs);
    var coherentText = coherenceResult.coherentText;

    // Stage 10: Protected Content Restoration
    final restoration = _protectedManager.restore(
      text: coherentText,
      tokenMap: maskedResult.tokenMap,
    );
    coherentText = restoration.restoredText;

    // Stage 11: Final High-Entropy Healing & AI Authorship Audit
    onProgress?.call(const HumanizerChunkProgress(
      currentChunk: 0,
      totalChunks: 1,
      ratio: 0.94,
      message: 'Performing on-device neural forensic audit and quality gate check...',
    ));

    final initialGlobalAudit = _forensicService.auditText(coherentText);
    if (initialGlobalAudit.aiProbability > 10.0) {
      const algorithmicService = AlgorithmicHumanizerService();
      coherentText = algorithmicService.postProcessWithQualityLoop(
        coherentText,
        tone: tone,
        style: style,
        originalText: cleanInput,
        forensicService: _forensicService,
        verifier: _verifier,
      );
    }

    // Stage 12 & 13: Final Quality Gate & Semantic Preservation Verification
    // Scored by the same detector the user audits with, when one is supplied,
    // so the humanizer's before/after figures match the Detector screen.
    final PlagiarismReport beforeReport;
    PlagiarismReport afterReport;
    if (documentScorer != null) {
      beforeReport = await documentScorer(cleanInput);
      afterReport = await documentScorer(coherentText);
    } else {
      beforeReport = _buildPlagiarismReport(cleanInput, _forensicService.auditText(cleanInput));
      afterReport = _buildPlagiarismReport(coherentText, _forensicService.auditText(coherentText));
    }

    // Iterative Quality Gate: Ensure score drops below 10% threshold
    const double targetAiThreshold = 10.0;
    if (afterReport.overallScore > targetAiThreshold) {
      const algorithmicService = AlgorithmicHumanizerService();
      final healedCandidate = algorithmicService.postProcessWithQualityLoop(
        coherentText,
        tone: tone,
        style: style,
        originalText: cleanInput,
        forensicService: _forensicService,
        verifier: _verifier,
      );
      if (healedCandidate.trim().isNotEmpty && healedCandidate != coherentText) {
        final healedPreservation = _verifier.verify(
          originalText: cleanInput,
          humanizedText: healedCandidate,
        );
        if (healedPreservation.verdict != SemanticPreservationVerdict.factualDriftAlert &&
            !healedPreservation.hasNumericalDrift &&
            !healedPreservation.hasCitationLoss) {
          final healedReport = documentScorer != null
              ? await documentScorer(healedCandidate)
              : _buildPlagiarismReport(healedCandidate, _forensicService.auditText(healedCandidate));
          if (healedReport.overallScore < afterReport.overallScore) {
            coherentText = healedCandidate;
            afterReport = healedReport;
          }
        }
      }
    }

    var preservation = _verifier.verify(
      originalText: cleanInput,
      humanizedText: coherentText,
      aiProbabilityBefore: beforeReport.overallScore,
      aiProbabilityAfter: afterReport.overallScore,
    );

    // Final safety check: ensure output is non-empty; only fall back if generation produced empty string
    if (coherentText.trim().isEmpty) {
      const algorithmicService = AlgorithmicHumanizerService();
      coherentText = algorithmicService.postProcess(cleanInput, tone: tone, style: style);
      afterReport = documentScorer != null
          ? await documentScorer(coherentText)
          : _buildPlagiarismReport(coherentText, _forensicService.auditText(coherentText));
      preservation = _verifier.verify(
        originalText: cleanInput,
        humanizedText: coherentText,
        aiProbabilityBefore: beforeReport.overallScore,
        aiProbabilityAfter: afterReport.overallScore,
      );
    }

    onProgress?.call(const HumanizerChunkProgress(
      currentChunk: 1,
      totalChunks: 1,
      ratio: 1.0,
      message: 'Humanization complete!',
    ));

    return HumanizerResult(
      humanizedText: coherentText,
      beforeReport: beforeReport,
      afterReport: afterReport,
      preservationReport: preservation,
      totalChunksProcessed: total,
      usedLocalFallback: anyChunkUsedFallback,
    );
  }

  /// Chunks scoring at or above this AI likelihood get one feedback-driven rewrite.
  static const double chunkRetryThreshold = 15.0;

  /// Re-scores a rewritten chunk and, if it still reads as AI, asks the model
  /// for one more rewrite targeted at the flagged sentences. The retry is kept
  /// only if it preserves protected content and facts and scores lower.
  Future<String> _refineWithDetector({
    required HumanizerModel model,
    required ChunkRewriteContext context,
    required String firstPass,
    required Map<String, ProtectedItem> chunkProtected,
    required Map<String, ProtectedItem> tokenMap,
    required WritingToneProfile tone,
    String style = 'balanced',
    int intensity = 85,
    required Future<PlagiarismReport> Function(String text) scorer,
  }) async {
    String restore(String t) => _protectedManager.restore(text: t, tokenMap: tokenMap).restoredText;
    try {
      final firstReport = await scorer(restore(firstPass));
      if (firstReport.overallScore < chunkRetryThreshold) return firstPass;

      final feedback = detectorFeedback(firstReport);
      if (feedback.isEmpty) return firstPass;

      final retryRaw = await model.rewriteChunk(context.withDetectorFeedback(feedback));
      if (retryRaw.trim().isEmpty) return firstPass;
      final candidate = await _lauviraHumanize.humanizeLlmOutput(
        retryRaw,
        tone: tone,
        style: style,
        originalText: context.targetChunk,
        intensity: intensity,
      );

      final placeholdersSurvive = chunkProtected.keys
          .every((k) => candidate.contains(k.replaceAll(RegExp(r'\s+'), '')));
      if (!placeholdersSurvive) return firstPass;
      final preservation = _verifier.verify(originalText: context.targetChunk, humanizedText: candidate);
      if (preservation.verdict == SemanticPreservationVerdict.factualDriftAlert) return firstPass;

      final retryReport = await scorer(restore(candidate));
      var bestText = retryReport.overallScore < firstReport.overallScore ? candidate : firstPass;
      var bestScore = min(retryReport.overallScore, firstReport.overallScore);

      // If improved and still >= chunkRetryThreshold (15%), allow an escalated adversarial pass for cloud LLMs
      if (model is CloudLlmHumanizerModel && retryReport.overallScore < firstReport.overallScore && bestScore >= chunkRetryThreshold) {
        final secondFeedback = detectorFeedback(retryReport);
        if (secondFeedback.isNotEmpty) {
          final secondRaw = await model.rewriteChunk(context.withDetectorFeedback(
            'ADVERSARIAL REFINEMENT PASS (STILL FLAGGED AT ${bestScore.toStringAsFixed(0)}% AI):\n$secondFeedback\n'
            'Aggressively invert clause syntax, alternate punchy 4-word assertions with longer analytical clauses (CV > 0.55), and eradicate passive copulas.',
          ));
          if (secondRaw.trim().isNotEmpty) {
            final secondCandidate = await _lauviraHumanize.humanizeLlmOutput(
              secondRaw,
              tone: tone,
              style: style,
              originalText: context.targetChunk,
              intensity: intensity,
            );
            final placeholdersOk = chunkProtected.keys
                .every((k) => secondCandidate.contains(k.replaceAll(RegExp(r'\s+'), '')));
            if (placeholdersOk) {
              final secondPres = _verifier.verify(originalText: context.targetChunk, humanizedText: secondCandidate);
              if (secondPres.verdict != SemanticPreservationVerdict.factualDriftAlert) {
                final thirdReport = await scorer(restore(secondCandidate));
                if (thirdReport.overallScore < bestScore) {
                  bestText = secondCandidate;
                }
              }
            }
          }
        }
      }

      return bestText;
    } catch (e) {
      debugPrint('[HumanizerChunkEngine] Detector-guided refinement skipped: $e');
      return firstPass;
    }
  }

  /// Computes word-level Jaccard overlap between [source] and [candidate].
  /// Identifies lazy LLM echoes that merely repeat the input without structural humanization.
  static double computeWordOverlap(String source, String candidate) {
    final cleanReg = RegExp(r'[^\w\s]');
    final srcWords = source.toLowerCase().replaceAll(cleanReg, '').split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final candWords = candidate.toLowerCase().replaceAll(cleanReg, '').split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (srcWords.isEmpty || candWords.isEmpty) return 0.0;
    final intersection = srcWords.intersection(candWords).length;
    final union = srcWords.union(candWords).length;
    return union == 0 ? 0.0 : (intersection / union);
  }

  /// Formats the most AI-like sentences of [report] (and their tells) as
  /// rewrite feedback; falls back to document-level tells.
  @visibleForTesting
  static String detectorFeedback(PlagiarismReport report) {
    final flagged = report.sentences.where((s) => s.aiProbability >= chunkRetryThreshold).toList()
      ..sort((a, b) => b.aiProbability.compareTo(a.aiProbability));
    if (flagged.isNotEmpty) {
      return flagged.take(3).map((s) {
        final tells = s.detectedTells.take(3).join(', ');
        return '- "${s.text.trim()}"${tells.isEmpty ? '' : ' (flags: $tells)'}';
      }).join('\n');
    }
    final tells = report.detectedTells.take(4).toList();
    return tells.isEmpty ? '' : '- Document-level patterns: ${tells.join(', ')}';
  }

  PlagiarismReport _buildPlagiarismReport(String text, AiForensicResult audit) {
    final sentences = TextForensicsLexicons.splitSentences(text);
    final sentenceAudits = <SentenceAudit>[];

    for (int i = 0; i < sentences.length; i++) {
      final s = sentences[i];
      final sAudit = _forensicService.auditText(s);
      sentenceAudits.add(
        SentenceAudit(
          index: i,
          text: s,
          aiProbability: sAudit.aiProbability,
          riskLevel: PlagiarismRiskLevel.fromScore(sAudit.aiProbability),
          detectedTells: sAudit.detectedSignals.map((sig) => sig.name).toList(),
          wordCount: max(TextForensicsLexicons.extractWords(s).length, 1),
        ),
      );
    }

    final overall = audit.aiProbability.clamp(0.0, 100.0);
    return PlagiarismReport(
      overallScore: overall,
      riskLevel: PlagiarismRiskLevel.fromScore(overall),
      humanScore: (100.0 - overall).clamp(0.0, 100.0),
      burstinessScore: 0.65,
      predictabilityScore: overall * 0.8,
      lexicalRichness: 72.0,
      ngramOverlapScore: 0.0,
      repeatedNgrams: const [],
      detectedTells: audit.detectedSignals.map((sig) => sig.name).toList(),
      sentences: sentenceAudits,
      analyzedAt: DateTime.now(),
      modelSource: 'Lauvira On-Device Neural Engine',
      plagiarismRiskScore: 0.0,
      flaggedBoilerplates: const [],
      uncertaintyScore: audit.uncertainty,
      confidenceLevel: audit.confidenceLevel.label,
      authorshipBadge: audit.authorshipClass.badge,
      defensibleSummary: audit.defensibleSummary,
    );
  }
}

class _RawChunkInfo {
  final int paragraphIndex;
  final String text;
  final String paragraphTopic;

  const _RawChunkInfo({
    required this.paragraphIndex,
    required this.text,
    required this.paragraphTopic,
  });
}
