import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/models/plagiarism_report.dart';
import 'package:lauriva/models/toast_notification.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/source_plagiarism_service.dart';
import 'package:lauriva/services/plagiarism_detector_service.dart';
import 'package:lauriva/services/storage_service.dart';
import 'test_mocks.dart';

LlmProvider _testLlmProvider() => LlmProvider(
      id: 'test_provider',
      name: 'Test Provider',
      tag: 'test',
      baseUrl: 'https://example.test/v1',
      keyPortalUrl: 'https://example.test/keys',
      keyHint: 'test-...',
      description: 'Test provider',
      defaultModel: 'test-model',
      requiresKey: true,
      curatedModels: const [],
    );

http.Response _chatCompletion(String content, {int statusCode = 200}) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    }),
    statusCode,
  );
}

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });
  group('PlagiarismDetectorService Tests', () {
    late PlagiarismDetectorService detector;

    setUp(() {
      detector = PlagiarismDetectorService();
    });

    test('Empty text returns clean report with 0 score', () {
      final report = detector.analyze('');
      expect(report.overallScore, 0.0);
      expect(report.riskLevel, PlagiarismRiskLevel.clean);
      expect(report.humanScore, 100.0);
      expect(report.sentences, isEmpty);
      expect(report.detectedTells, isEmpty);
    });

    test('Detects heavily AI-generated text with known tells and stock vocabulary', () {
      const aiSample =
          'It is not only about innovation, but also about execution. '
          'At its core, this stands as a testament to the evolving landscape of digital transformation. '
          'Let us dive in to explore the multifaceted intricacies. '
          'The platform delivers innovation, inspiration, and insights, bolstering user confidence. '
          'As an AI, I hope this helps!';

      final report = detector.analyze(aiSample);

      expect(report.overallScore, greaterThan(65.0));
      expect(
        report.riskLevel == PlagiarismRiskLevel.high ||
            report.riskLevel == PlagiarismRiskLevel.critical,
        isTrue,
      );
      expect(report.detectedTells.isNotEmpty, isTrue);

      // Verify specific tell detection
      final tellsJoined = report.detectedTells.join(' ');
      expect(tellsJoined.contains('Not X but Y') || tellsJoined.contains('Chatbot') || tellsJoined.contains('testament'), isTrue);
      expect(report.sentences.length, greaterThanOrEqualTo(4));
    });

    test('Recognizes authentic human text with high burstiness and low tell density', () {
      const humanSample =
          'I left the apartment before sunrise. '
          'The morning air had that damp, cold bite that always reminds me of late November in Chicago, '
          'when the buses run twenty minutes late and nobody bothers to complain because everyone is already numb. '
          'Forgot my gloves again. '
          'I stopped at the corner diner, ordered black coffee, and watched steam rise from the grill while the cook prepped hash browns.';

      final report = detector.analyze(humanSample);

      expect(report.burstinessScore, greaterThanOrEqualTo(0.5));
      expect(report.overallScore, lessThan(40.0));
      expect(
        report.riskLevel == PlagiarismRiskLevel.clean ||
            report.riskLevel == PlagiarismRiskLevel.low,
        isTrue,
      );
      expect(report.humanScore, greaterThan(60.0));
    });

    test('Calculates n-gram repetition and formulaic overlap', () {
      const repetitiveSample =
          'The quick brown fox jumped over the lazy sleeping dog. '
          'The quick brown fox jumped over the lazy sleeping dog. '
          'Another unrelated sentence for balance. '
          'The quick brown fox jumped over the lazy sleeping dog.';

      final report = detector.analyze(repetitiveSample);

      expect(report.ngramOverlapScore, greaterThan(0.0));
      expect(report.repeatedNgrams.isNotEmpty, isTrue);
    });

    test('Generates structured audit summary export', () {
      const sample = 'This is a test sentence. Let us dive in to explore.';
      final report = detector.analyze(sample);
      final summary = report.toSummaryText();

      expect(summary.contains('Lauriva AI Plagiarism & Originality Report'), isTrue);
      expect(summary.contains('AI Likelihood:') || summary.contains('AI Plagiarism'), isTrue);
      expect(summary.contains('Burstiness Variance:'), isTrue);
    });

    test('Detects em dash overuse — a signature modern LLM stylistic tic', () {
      const emDashSample =
          'The results were surprising — not because of the data, but because of what it revealed. '
          'This was not a minor discovery — it was a breakthrough for the whole team. '
          'The implications are vast — spanning industries, disciplines, and geographies.';

      final report = detector.analyze(emDashSample);

      final tellsJoined = report.detectedTells.join(' ');
      expect(tellsJoined.contains('Em dash overuse'), isTrue);
      expect(report.sentences.any((s) => s.detectedTells.contains('Em dash usage')), isTrue);
    });

    test('Detects unstripped markdown formatting residue in prose', () {
      const markdownSample =
          "Here's what you need to know:\n"
          '**Key Point:** This matters more than people realize.\n'
          '- First consideration to weigh carefully\n'
          '- Second consideration worth noting\n'
          '## Summary\n'
          'This wraps up the analysis nicely.';

      final report = detector.analyze(markdownSample);

      final tellsJoined = report.detectedTells.join(' ');
      expect(tellsJoined.contains('Unstripped markdown formatting'), isTrue);
    });

    test('extractFeatureVector returns one value per named feature, all finite', () {
      final features = detector.extractFeatureVector(
        'Moreover, the results were compelling — a genuine breakthrough for the field.',
      );
      expect(features.length, PlagiarismDetectorService.mlFeatureNames.length);
      expect(features.every((f) => f.isFinite), isTrue);
    });

    test('mlClassifierScore returns a bounded 0-100 score for empty text', () {
      final score = detector.mlClassifierScore('');
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(100.0));
    });

    test('On-device ML classifier scores a clearly human sample low and a clearly AI-style sample high', () {
      const humanSample =
          'I left the apartment before sunrise. The morning air had that damp, cold bite that always '
          'reminds me of late November in Chicago, when the buses run twenty minutes late and nobody '
          'bothers to complain because everyone is already numb. Forgot my gloves again.';
      const aiSample =
          'Moreover, the intricate interplay between technology and society continues to shape our '
          'collective future. This is not to say that progress comes without challenges — nevertheless, '
          'the enduring impact of these innovations cannot be overstated.';

      final humanMlScore = detector.mlClassifierScore(humanSample);
      final aiMlScore = detector.mlClassifierScore(aiSample);

      expect(humanMlScore, lessThan(aiMlScore));
      expect(aiMlScore, greaterThan(50.0));
    });

    test('analyze() surfaces the ML classifier tell when its confidence is high', () {
      const aiSample =
          'It is not only about innovation, but also about execution. '
          'At its core, this stands as a testament to the evolving landscape of digital transformation. '
          'Let us dive in to explore the multifaceted intricacies. '
          'The platform delivers innovation, inspiration, and insights, bolstering user confidence. '
          'As an AI, I hope this helps!';

      final report = detector.analyze(aiSample);
      final tellsJoined = report.detectedTells.join(' ');
      expect(tellsJoined.contains('On-device ML classifier'), isTrue);
    });

    test('Detects overuse of formal transition-word sentence openers', () {
      const transitionSample =
          'Moreover, the data supports this claim clearly. '
          'Furthermore, additional analysis confirms the underlying trend. '
          'Additionally, stakeholders have expressed strong interest in the results. '
          'Consequently, the team moved forward with full implementation.';

      final report = detector.analyze(transitionSample);

      final tellsJoined = report.detectedTells.join(' ');
      expect(tellsJoined.contains('Formal transition-word openers') || tellsJoined.contains('Formal Connector Openers'), isTrue);
    });

    test('Engine v2: extractFeatureVectorV2 returns exactly 38 finite features', () {
      final features = detector.extractFeatureVectorV2(
        'Moreover, this approach underscores the importance of balance — a concept that resonates deeply.',
      );
      expect(features.length, 38);
      expect(features.length, PlagiarismDetectorService.mlFeatureNamesV2.length);
      expect(features.every((f) => f.isFinite), isTrue);
    });

    test('Engine v2: Length gating triggers high uncertainty on short passages (<50 words)', () {
      const shortText = 'This is just a quick two sentence note. It has very few words.';
      final forensic = detector.auditForensics(shortText);

      expect(forensic.confidenceLevel, AiConfidenceLevel.insufficient);
      expect(forensic.uncertainty, greaterThanOrEqualTo(0.70));
      expect(forensic.authorshipClass, AiAuthorshipClass.inconclusive);
    });

    test('Engine v2: Full passage discrimination with calibrated explainability', () {
      const humanLong =
          'I left the apartment before sunrise. The morning air had that damp, cold bite that always '
          'reminds me of late November in Chicago, when the buses run twenty minutes late and nobody '
          'bothers to complain because everyone is already numb. Forgot my gloves again. '
          'I stopped at the corner diner, ordered black coffee, and watched steam rise from the grill while the cook prepped hash browns. '
          'The coffee was scalding and bitter, but it was hot enough to wake me up before the morning rush.';

      final forensicHuman = detector.auditForensics(humanLong);
      expect(forensicHuman.aiProbability, lessThan(45.0));
      expect(forensicHuman.confidenceLevel != AiConfidenceLevel.insufficient, isTrue);

      const aiLong =
          'In today\'s rapidly evolving digital landscape, organizations must navigate a multitude of complex challenges. '
          'Furthermore, it is crucial to understand that fostering innovation requires a multifaceted approach. '
          'Moreover, this comprehensive methodology delivers efficiency, agility, and scalability across every department. '
          'At its core, it is not only about technology, but also about cultivating a sustainable culture of excellence. '
          'Consequently, adopting these principles stands as a testament to long-term operational resilience.';

      final forensicAi = detector.auditForensics(aiLong);
      expect(forensicAi.aiProbability, greaterThan(65.0));
      expect(forensicAi.authorshipClass, AiAuthorshipClass.likelyAi);
      expect(forensicAi.detectedSignals.isNotEmpty, isTrue);
    });

    test('Engine v2: SourcePlagiarismService detects repeated n-grams and boilerplates independently', () {
      final sourceService = SourcePlagiarismService();
      const sample =
          'In today\'s digital era, navigating the complexities of modern software is crucial. '
          'The quick brown fox jumps over the lazy sleeping dog. '
          'The quick brown fox jumps over the lazy sleeping dog. '
          'In today\'s fast-paced world, it cannot be overstated.';

      final result = sourceService.analyzeText(sample);
      expect(result.flaggedBoilerplates.isNotEmpty, isTrue);
      expect(result.repeatedNgrams.isNotEmpty, isTrue);
      expect(result.plagiarismRiskScore, greaterThan(20.0));
    });

    test('Report withFix attaches post-fix scores accurately', () {
      const sample = 'Let us explore the tapestry of possibilities.';
      final initialReport = detector.analyze(sample);

      final updatedReport = initialReport.withFix(
        fixedText: 'We checked our options.',
        fixedScore: 4.5,
        fixedRiskLevel: PlagiarismRiskLevel.clean,
      );

      expect(updatedReport.fixedText, 'We checked our options.');
      expect(updatedReport.fixedScore, 4.5);
      expect(updatedReport.fixedRiskLevel, PlagiarismRiskLevel.clean);
      expect(updatedReport.toSummaryText().contains('Lauriva Humanized Fix Result'), isTrue);
    });
  });

  group('PlagiarismProvider Integration Tests', () {
    late StorageService storage;
    late ToastProvider toast;
    late HistoryProvider history;
    late PlagiarismProvider plagiarism;
    late LlmSettingsProvider llmSettings;
    late SpeechProvider speech;
    late StudioProvider studio;

    late LlmService mockLlmService;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.init();
      await storage.setApiKey('groq', 'gsk_test_api_key_123');
      toast = ToastProvider();
      history = HistoryProvider(storage: storage, toast: toast);
      llmSettings = LlmSettingsProvider(storage: storage);
      final auditJson = jsonEncode({
        'overallScore': 85.0,
        'plagiarismRiskScore': 10.0,
        'burstinessScore': 0.3,
        'predictabilityScore': 0.8,
        'lexicalRichness': 65.0,
        'ngramOverlapScore': 12.0,
        'detectedTells': ['Formulaic structure'],
        'defensibleSummary': 'High AI writing likelihood detected by cloud model.',
        'sentences': [
          {
            'text': 'It is not only about innovation, but also about execution.',
            'aiProbability': 90.0,
            'detectedTells': ['Antithesis']
          }
        ]
      });
      mockLlmService = LlmService(
        client: MockClient((req) async => _chatCompletion(auditJson)),
      );
      plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
        llmSettings: llmSettings,
        llmService: mockLlmService,
      );
      speech = SpeechProvider(storage: storage, toast: toast);
      studio = StudioProvider(
        storage: storage,
        speech: speech,
        llmSettings: llmSettings,
        history: history,
        toast: toast,
        plagiarism: plagiarism,
      );
    });

    test('runPlagiarismCheck analyzes input and populates report', () async {
      studio.setInputText(
        'It is not only about innovation, but also about execution. '
        'At its core, this stands as a testament to the enduring legacy of modern technology. '
        'Let us dive in to explore the intricacies. '
        'As an AI, I hope this helps!',
      );

      await studio.runPlagiarismCheck();

      expect(plagiarism.plagiarismReport, isNotNull);
      expect(plagiarism.plagiarismReport!.overallScore, greaterThan(50.0));
      expect(studio.outputText.isNotEmpty, isTrue);
      expect(studio.activeFeatureId, 'PlagiarismCheck');
    });

    test('clearPlagiarismReport clears the stored report', () async {
      studio.setInputText('Old text. Just a sentence about nothing in particular.');
      await studio.runPlagiarismCheck();

      // Simulate a fix applied to the report
      final fixedReport = plagiarism.plagiarismReport!.withFix(
        fixedText: 'Clean humanized version of the prose.',
        fixedScore: 5.0,
        fixedRiskLevel: PlagiarismRiskLevel.clean,
      );
      expect(fixedReport.fixedText, 'Clean humanized version of the prose.');

      // Clear the report and verify
      plagiarism.clearPlagiarismReport();
      expect(plagiarism.plagiarismReport, isNull);
    });

    test('runPlagiarismCheck on blank text shows an error toast and sets no report', () async {
      final result = await plagiarism.runPlagiarismCheck('   ');

      expect(result, isNull);
      expect(plagiarism.plagiarismReport, isNull);
      expect(toast.toasts.any((t) => t.type == ToastType.error), isTrue);
    });

    test('runPlagiarismCheck with forOutput populates outputPlagiarismReport, not plagiarismReport', () async {
      final result = await plagiarism.runPlagiarismCheck(
        'Moreover, this stands as a testament to the evolving landscape of modern technology.',
        forOutput: true,
      );

      expect(result, isNotNull);
      expect(plagiarism.outputPlagiarismReport, isNotNull);
      expect(plagiarism.plagiarismReport, isNull);
    });

    test('setDetectorEngine and setHuggingFaceDetectorModel update provider state', () {
      expect(plagiarism.detectorEngine, 'llm');

      plagiarism.setDetectorEngine('huggingface');
      expect(plagiarism.detectorEngine, 'huggingface');

      plagiarism.setHuggingFaceDetectorModel('some/other-model');
      expect(plagiarism.huggingFaceDetectorModel, 'some/other-model');
    });

    test('analyzeOutputSilently populates outputPlagiarismReport and syncs an existing report\'s fix fields', () async {
      await plagiarism.runPlagiarismCheck('Just a plain sentence with nothing unusual about it at all.');
      expect(plagiarism.plagiarismReport, isNotNull);
      expect(plagiarism.plagiarismReport!.fixedText, isNull);

      await plagiarism.analyzeOutputSilently('A cleaner rewritten version of that same sentence.');

      expect(plagiarism.outputPlagiarismReport, isNotNull);
      expect(plagiarism.plagiarismReport!.fixedText, 'A cleaner rewritten version of that same sentence.');
    });

    test('analyzeOutputSilently is a silent no-op for blank text', () async {
      await plagiarism.analyzeOutputSilently('   ');
      expect(plagiarism.outputPlagiarismReport, isNull);
      expect(toast.toasts, isEmpty);
    });

    test('fixPlagiarismAndHumanize returns the humanized text, records history, and toggles isFixingPlagiarism', () async {
      final llmService = LlmService(
        client: MockClient((req) async => _chatCompletion('This is the humanized rewrite.')),
      );
      final plagiarismWithLlm = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
        llmService: llmService,
      );

      expect(plagiarismWithLlm.isFixingPlagiarism, isFalse);
      expect(history.structuredHistory, isEmpty);

      final future = plagiarismWithLlm.fixPlagiarismAndHumanize(
        text: 'Original draft text that needs humanizing.',
        provider: _testLlmProvider(),
        apiKey: 'test-key',
        model: 'test-model',
        inputWordCount: 6,
      );
      expect(plagiarismWithLlm.isFixingPlagiarism, isTrue);

      final humanized = await future;

      expect(humanized, 'This is the humanized rewrite.');
      expect(plagiarismWithLlm.isFixingPlagiarism, isFalse);
      expect(history.structuredHistory.length, 1);
      expect(history.structuredHistory.first.featureId, 'Humanize');
      expect(toast.toasts.any((t) => t.type == ToastType.success), isTrue);
    });

    test('fixPlagiarismAndHumanize shows an error toast and resets isFixingPlagiarism on LLM failure', () async {
      final llmService = LlmService(
        client: MockClient((req) async => http.Response('server error', 500)),
      );
      final plagiarismWithLlm = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
        llmService: llmService,
      );

      final humanized = await plagiarismWithLlm.fixPlagiarismAndHumanize(
        text: 'Original draft text that needs humanizing.',
        provider: _testLlmProvider(),
        apiKey: 'test-key',
        model: 'test-model',
        inputWordCount: 6,
      );

      expect(humanized, isNull);
      expect(plagiarismWithLlm.isFixingPlagiarism, isFalse);
      expect(history.structuredHistory, isEmpty);
      expect(toast.toasts.any((t) => t.type == ToastType.error), isTrue);
    });
  });
}
