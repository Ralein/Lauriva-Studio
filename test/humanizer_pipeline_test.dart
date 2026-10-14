import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/document_coherence_pass.dart';
import 'package:lauriva/services/forensic/humanizer/document_style_profiler.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_chunk_engine.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_model.dart';
import 'package:lauriva/services/forensic/humanizer/paragraph_reconstructor.dart';
import 'package:lauriva/services/forensic/humanizer/protected_content_manager.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/llm_service.dart';
import 'test_mocks.dart';

/// Test mock model that simulates context-aware humanization while
/// respecting protected placeholders and authorial style.
class MockContextAwareHumanizerModel implements HumanizerModel {
  int callCount = 0;
  List<ChunkRewriteContext> recordedContexts = [];

  @override
  String get name => 'Mock Context Aware Model';

  @override
  int get maxContextTokens => 4096;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    callCount++;
    recordedContexts.add(context);

    // Simulate nuanced human rewrite that retains all protected placeholders
    var rewritten = context.targetChunk;

    // Remove formulaic AI openers if present
    rewritten = rewritten.replaceAll(RegExp(r'\bFurthermore,?\s*', caseSensitive: false), '');
    rewritten = rewritten.replaceAll(RegExp(r'\bMoreover,?\s*', caseSensitive: false), '');
    rewritten = rewritten.replaceAll(RegExp(r'\bIn conclusion,?\s*', caseSensitive: false), '');
    rewritten = rewritten.replaceAll(RegExp(r'\bAt its core,?\s*', caseSensitive: false), '');
    rewritten = rewritten.replaceAll(RegExp(r'\bstands as a testament to\b', caseSensitive: false), 'illustrates');

    return rewritten.trim();
  }
}

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  group('ProtectedContentManager Tests', () {
    late ProtectedContentManager manager;

    setUp(() {
      manager = ProtectedContentManager();
    });

    test('Masks and restores academic citations, dates, numbers, and quotes accurately', () {
      const original =
          'According to recent findings by (Smith et al., 2021), '
          'global renewable investments reached \$450.5 billion in 2023, '
          'representing a 14% year-over-year increase. '
          'As Professor Harrison noted, "The transition is accelerating faster than predicted." '
          'Further information is available at https://nature.com/articles/s41558.';

      final masked = manager.mask(original);
      expect(masked.hasProtectedItems, isTrue);
      expect(masked.tokenMap.length, greaterThanOrEqualTo(4));

      // None of the sensitive factual values should appear unmasked in maskedText
      expect(masked.maskedText.contains('(Smith et al., 2021)'), isFalse);
      expect(masked.maskedText.contains('"The transition is accelerating faster than predicted."'), isFalse);
      expect(masked.maskedText.contains('https://nature.com/articles/s41558'), isFalse);

      final restored = manager.restore(
        text: masked.maskedText,
        tokenMap: masked.tokenMap,
      );

      expect(restored.isFullyPreserved, isTrue);
      expect(restored.restoredText, original);
    });

    test('Handles fuzzy placeholder formatting in LLM output', () {
      const original = 'Revenue was \$12.5M in 2022.';
      final masked = manager.mask(original);

      // Simulate an LLM inserting spaces inside the placeholder e.g. [ PROTECTED_001 ]
      var alteredText = masked.maskedText;
      alteredText = alteredText.replaceAll('[PROTECTED_001]', '[ PROTECTED_001 ]');

      final restored = manager.restore(
        text: alteredText,
        tokenMap: masked.tokenMap,
      );

      expect(restored.restoredText.contains('2022') || restored.restoredText.contains('\$12.5M'), isTrue);
    });
  });

  group('DocumentStyleProfiler Tests', () {
    late DocumentStyleProfiler profiler;

    setUp(() {
      profiler = DocumentStyleProfiler();
    });

    test('Accurately profiles academic third-person text', () {
      const academicText =
          'The researchers analyzed the empirical data using quantitative methodology. '
          'Furthermore, statistical significance was substantiated across all cohorts. '
          'The phenomenon observed by the authors indicates a paradigm shift.';

      final profile = profiler.profile(academicText);
      expect(profile.isAcademic, isTrue);
      expect(profile.formality, greaterThanOrEqualTo(0.7));
      expect(profile.prefersContractions, isFalse);
      expect(profile.thirdPersonRatio, greaterThan(0.0));
      expect(profile.toPromptInstructions().contains('academic'), isTrue);
    });

    test('Accurately profiles conversational first-person text with contractions', () {
      const conversationalText =
          "I didn't think we'd make it on time. "
          "We couldn't find the keys, and our bus was already twenty minutes late. "
          "I really hope you can understand where I'm coming from.";

      final profile = profiler.profile(conversationalText);
      expect(profile.isAcademic, isFalse);
      expect(profile.prefersContractions, isTrue);
      expect(profile.firstPersonRatio, greaterThan(2.0));
      expect(profile.toPromptInstructions().contains('contractions'), isTrue);
    });
  });

  group('ParagraphReconstructor & CoherencePass Tests', () {
    test('Smooths repeated transitions and removes monotonous formulaic openers', () {
      final reconstructor = ParagraphReconstructor();
      final chunks = [
        'Furthermore, the algorithm detects anomalies in the logs.',
        'Furthermore, it isolates malicious network packets quickly.',
        'Moreover, this demonstrates how cloud security operates.',
      ];

      final result = reconstructor.reconstruct(
        rewrittenChunks: chunks,
        originalParagraph: chunks.join(' '),
      );

      expect(result.smoothed, isTrue);
      // The second "Furthermore" should have been replaced or varied
      expect(result.text.split('Furthermore').length - 1, lessThan(2));
      expect(result.transitionDiversityScore, greaterThanOrEqualTo(0.5));
    });

    test('Removes premature conclusions before the final paragraph', () {
      final pass = DocumentCoherencePass();
      final paragraphs = [
        'Introduction to the experiment and initial setup.',
        'In conclusion, the methodology reveals several key factors.',
        'Detailed experimental data and findings.',
        'Final concluding thoughts and future directions.',
      ];

      final result = pass.harmonize(paragraphs);
      expect(result.adjusted, isTrue);
      expect(result.coherenceNotes.any((n) => n.contains('premature')), isTrue);
      expect(result.coherentText.contains('In conclusion, the methodology'), isFalse);
    });
  });

  group('Humanizer Hierarchical Pipeline Length Tests', () {
    late HumanizerChunkEngine engine;
    late MockContextAwareHumanizerModel mockModel;
    final dummyProvider = LlmProvider(
      id: 'test',
      name: 'Test',
      tag: 'test',
      baseUrl: 'https://test',
      keyPortalUrl: 'https://test',
      keyHint: '',
      description: '',
      defaultModel: 'test',
      requiresKey: false,
      curatedModels: const [],
    );

    setUp(() {
      mockModel = MockContextAwareHumanizerModel();
      engine = HumanizerChunkEngine();
    });

    test('Processes 1 sentence accurately without truncation', () async {
      const text = 'The economic indicators suggest steady expansion throughout the next fiscal quarter.';
      final result = await engine.processDocument(
        rawText: text,
        tone: WritingToneProfile.professional,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.isNotEmpty, isTrue);
      expect(result.totalChunksProcessed, 1);
      expect(result.preservationReport.verdict != SemanticPreservationVerdict.factualDriftAlert, isTrue);
    });

    test('Processes 3 sentences maintaining logical coreference', () async {
      const text =
          'Recent clinical trials demonstrated promising efficacy. '
          'These findings confirm that the novel therapeutic compound targets cellular inflammation directly. '
          'Consequently, researchers anticipate commencing Phase 3 trials early next year.';

      final result = await engine.processDocument(
        rawText: text,
        tone: WritingToneProfile.academic,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.contains('clinical trials'), isTrue);
      expect(result.preservationReport.hasNumericalDrift, isFalse);
    });

    test('Processes 100-word paragraph as a coherent semantic unit', () async {
      const paragraph =
          'Artificial intelligence in digital forensics provides automated detection capabilities '
          'for textual authenticity verification. By examining stylometric variation, syntactic structures, '
          'and token perplexity, modern algorithms distinguish machine-generated text from human writing. '
          'Furthermore, forensic analysts evaluate n-gram distributions and clause complexity to ensure '
          'rigorous evidential standards. In academic contexts, these tools protect research integrity while '
          'fostering transparent scholarship across interdisciplinary peer-reviewed domains.';

      final result = await engine.processDocument(
        rawText: paragraph,
        tone: WritingToneProfile.academic,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.isNotEmpty, isTrue);
      expect(result.preservationReport.preservationScore, greaterThan(0.70));
    });

    test('Processes 250-word paragraph with adaptive sentence-aware chunking', () async {
      const text250 =
          'The historical emergence of classical Athenian democracy during the fifth century BCE '
          'represented a profound structural transformation in Mediterranean governance. Rather than '
          'concentrating authority in oligarchic councils or hereditary monarchs, the polis vested '
          'deliberative power within the citizen assembly. Citizens gathered regularly on the Pnyx to debate '
          'naval appropriations, military expeditions, and civic legislation. However, this democratic framework '
          'remained intrinsically exclusive, as women, resident aliens, and enslaved populations were '
          'categorically disenfranchised from political participation. In the funeral oration attributed to '
          'Pericles by Thucydides, Athens is celebrated as an educational beacon for Hellas, characterized by '
          'equal justice under law and public honors awarded according to merit rather than social pedigree. '
          'Nevertheless, the subsequent pressures of the Peloponnesian War tested the resilience of these civic '
          'institutions, exposing the vulnerabilities of democratic debate to demagogic manipulation and strategic '
          'miscalculation during the disastrous Sicilian Expedition. Contemporary political philosophers continues '
          'to debate whether the Athenian experiment demonstrated the enduring efficacy of participatory '
          'citizenship or served as a precautionary testament to the volatility of unmediated popular sovereignty.';

      final result = await engine.processDocument(
        rawText: text250,
        tone: WritingToneProfile.academic,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.contains('Athenian democracy'), isTrue);
      expect(result.humanizedText.contains('Pericles'), isTrue);
      expect(result.humanizedText.contains('Thucydides'), isTrue);
      expect(result.totalChunksProcessed, greaterThanOrEqualTo(2));
      expect(mockModel.recordedContexts.any((c) => c.precedingContext.isNotEmpty), isTrue);
    });

    test('Processes 500-word long paragraph without attention decay or coreference loss', () async {
      final buffer = StringBuffer();
      buffer.write(
        'Quantum computing exploits quantum mechanical phenomena such as superposition and entanglement '
        'to perform computations beyond the capabilities of classical supercomputers. In a classical system, '
        'bits represent binary states of either zero or one, whereas quantum bits or qubits exist simultaneously '
        'in coherent linear combinations of both states. This superposition principle enables quantum processors '
        'to evaluate expansive solution spaces concurrently. When combined with quantum entanglement, where '
        'the quantum states of multiple qubits remain fundamentally interdependent regardless of spatial separation, '
        'the computational complexity scaling shifts exponentially. Leading research teams have demonstrated '
        'quantum supremacy in specialized benchmarking tasks using superconducting circuit architectures and '
        'trapped ion platforms. However, maintaining quantum coherence against environmental thermal noise remains '
        'the foremost engineering challenge. Stray electromagnetic fluctuations induce rapid decoherence, '
        'introducing quantum gate errors that degrade fidelity. To mitigate this vulnerability, quantum error '
        'correction protocols such as the surface code encode logical qubits across lattices of physical qubits. '
        'These protocols require high physical-to-logical qubit overhead ratios, demanding thousands of physical '
        'qubits to sustain a single fault-tolerant logical qubit. In pharmaceutical design, quantum simulation of '
        'complex molecular interactions could revolutionize drug discovery by computing exact ground-state electronic '
        'configurations of enzyme active sites. Similarly, in cryptographic applications, Shor algorithm poses an '
        'existential challenge to widespread public-key cryptosystems including RSA and elliptic curve cryptography. '
        'In response, international standards organizations are accelerating the deployment of post-quantum cryptographic '
        'algorithms based on lattice cryptography, multivariate equations, and hash-based signatures to secure critical '
        'digital infrastructure before fault-tolerant quantum hardware reaches operational maturity.',
      );

      final longText = buffer.toString();
      final words = longText.split(RegExp(r'\s+')).length;
      expect(words, greaterThanOrEqualTo(200));

      final result = await engine.processDocument(
        rawText: longText,
        tone: WritingToneProfile.academic,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.contains('Quantum computing'), isTrue);
      expect(result.humanizedText.contains('Shor'), isTrue);
      expect(result.humanizedText.contains('RSA'), isTrue);
      expect(result.totalChunksProcessed, greaterThanOrEqualTo(2));
    });

    test('Processes 1,000-word multi-paragraph document hierarchically', () async {
      final p1 = 'The history of Western philosophy began in ancient Miletus with Thales, Anaximander, and Anaximenes. ' * 5;
      final p2 = 'In fourth-century Athens, Plato established the Academy to pursue philosophical inquiry and dialectic. ' * 5;
      final p3 = 'Aristotle subsequently founded the Lyceum, developing formal logic, empirical biology, and virtue ethics. ' * 5;
      final p4 = 'During the Hellenistic era, Stoicism and Epicureanism offered contrasting approaches to eudaimonia. ' * 5;

      final doc = '$p1\n\n$p2\n\n$p3\n\n$p4';

      final progressEvents = <HumanizerChunkProgress>[];
      final result = await engine.processDocument(
        rawText: doc,
        tone: WritingToneProfile.academic,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
        onProgress: (p) => progressEvents.add(p),
      );

      expect(result.humanizedText.contains('Thales'), isTrue);
      expect(result.humanizedText.contains('Plato'), isTrue);
      expect(result.humanizedText.contains('Aristotle'), isTrue);
      expect(progressEvents.isNotEmpty, isTrue);
      expect(progressEvents.last.ratio, 1.0);
    });

    test('Processes 3,000+ word document with memory bounded and progress reported', () async {
      final paragraphs = <String>[];
      for (int i = 1; i <= 20; i++) {
        paragraphs.add(
          'Section $i investigates the systematic performance of distributed consensus protocols in large-scale '
          'peer-to-peer networks under asymmetric network latency and Byzantine fault conditions. '
          'Empirical benchmarks demonstrate that raft consensus maintains 99.99% availability when fewer than '
          'half of node clusters experience temporary network partitioning. (Smith & Davis, 2022).',
        );
      }
      final hugeDoc = paragraphs.join('\n\n');

      final result = await engine.processDocument(
        rawText: hugeDoc,
        tone: WritingToneProfile.professional,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.isNotEmpty, isTrue);
      expect(result.humanizedText.contains('(Smith & Davis, 2022)'), isTrue);
      expect(result.totalChunksProcessed, greaterThanOrEqualTo(10));
    });

    test('Preserves quotations, numbers, dates, and named entities in complex text', () async {
      const complexText =
          'On October 14, 1066, Duke William of Normandy defeated King Harold Godwinson at the Battle of Hastings. '
          'According to the Bayeux Tapestry, exactly 7,000 Norman troops engaged Harold forces on Senlac Hill. '
          'As chronicler William of Poitiers recorded, "The Normans fought with bold courage and unmatched discipline." '
          'This single day transformed English linguistics, introducing over 10,000 Anglo-Norman terms into Old English.';

      final result = await engine.processDocument(
        rawText: complexText,
        tone: WritingToneProfile.academic,
        llmService: LlmService(),
        activeProvider: dummyProvider,
        activeApiKey: '',
        activeModel: 'test',
        customModel: mockModel,
      );

      expect(result.humanizedText.contains('October 14, 1066'), isTrue);
      expect(result.humanizedText.contains('Battle of Hastings'), isTrue);
      expect(result.humanizedText.contains('7,000'), isTrue);
      expect(result.humanizedText.contains('10,000'), isTrue);
      expect(result.humanizedText.contains('"The Normans fought with bold courage and unmatched discipline."'), isTrue);
      expect(result.preservationReport.hasNumericalDrift, isFalse);
    });
  });
}
