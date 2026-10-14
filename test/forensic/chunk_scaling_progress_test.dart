import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/forensic_progress.dart';
import 'package:lauriva/services/forensic/document/document_segmenter.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/normalization/text_normalizer.dart';
import 'package:lauriva/widgets/forensic_chunk_progress_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chunk Partitioning & Arbitrary Word Count Scaling Tests', () {
    late TextNormalizer normalizer;
    late DocumentSegmenter segmenter;
    late ForensicEngine engine;
    late ForensicCoordinatorService coordinator;

    setUp(() {
      normalizer = TextNormalizer();
      segmenter = DocumentSegmenter();
      engine = ForensicEngine();
      coordinator = ForensicCoordinatorService(engine: engine);
    });

    test('1. Single chunk for short snippet (30 words)', () {
      const shortSnippet = 'Artificial intelligence systems generate fluent text by estimating conditional probability distributions over token vocabularies. These models optimize statistical cross-entropy loss across large textual training corpora.';
      final norm = normalizer.normalize(shortSnippet);
      final seg = segmenter.segment(norm);
      final chunks = segmenter.partitionIntoChunks(seg);

      expect(chunks.length, 1);
      expect(chunks.first.chunkIndex, 0);
      expect(chunks.first.totalChunks, 1);
      expect(chunks.first.wordCount, seg.totalWordCount);
      expect(chunks.first.sentences.length, seg.sentences.length);
    });

    test('2. Multi-chunk partitioning for medium essay (~700 words)', () {
      final paragraph = 'Artificial intelligence continues to transform modern knowledge workflows. Researchers utilize automated tools to summarize complex literature and synthesize experimental hypotheses. However, maintaining intellectual integrity requires meticulous source attribution and adversarial verification.\n\n';
      final mediumText = List.filled(15, paragraph).join();

      final norm = normalizer.normalize(mediumText);
      final seg = segmenter.segment(norm);
      final chunks = segmenter.partitionIntoChunks(seg, targetWordsPerChunk: 250);

      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first.chunkIndex, 0);
      expect(chunks.last.chunkIndex, chunks.length - 1);

      // Verify continuous sentence coverage
      int totalChunkSentences = 0;
      for (final chunk in chunks) {
        expect(chunk.wordCount, greaterThan(0));
        expect(chunk.sentences.isNotEmpty, isTrue);
        totalChunkSentences += chunk.sentences.length;
      }
      expect(totalChunkSentences, seg.sentences.length);
    });

    test('3. High-scale chunk partitioning for large manuscript (~3,500 words)', () {
      final paragraph = 'Enterprise cloud infrastructures rely on distributed consensus algorithms to maintain consistency across heterogeneous cluster nodes. Raft and Paxos protocols coordinate log replication and leader elections to ensure resilient state machine replication under network partition conditions. Observability pipelines ingest distributed traces to identify latency bottlenecks.\n\n';
      final largeText = List.filled(75, paragraph).join();

      final norm = normalizer.normalize(largeText);
      final seg = segmenter.segment(norm);
      final chunks = segmenter.partitionIntoChunks(seg, targetWordsPerChunk: 300);

      expect(chunks.length, greaterThanOrEqualTo(8));
      expect(chunks.every((c) => c.wordCount > 0), isTrue);

      // Verify exact raw offset alignment
      expect(chunks.first.rawStartOffset, seg.sentences.first.rawStartOffset);
      expect(chunks.last.rawEndOffset, seg.sentences.last.rawEndOffset);
    });

    test('4. ForensicEngine emits progressive chunk callbacks with dynamic load times', () {
      final paragraph = 'Adaptive educational platforms dynamically calibrate problem difficulty according to student response latencies. Machine learning algorithms identify conceptual bottlenecks and recommend targeted remedial exercises.\n\n';
      final multiChunkText = List.filled(12, paragraph).join();

      final progressEvents = <ForensicProgress>[];
      final report = engine.analyze(
        multiChunkText,
        onProgress: (progress) {
          progressEvents.add(progress);
        },
      );

      expect(report.wordCount, greaterThan(200));
      expect(progressEvents.isNotEmpty, isTrue);

      // Verify progress monotonicity
      expect(progressEvents.first.progressRatio, lessThanOrEqualTo(0.10));
      expect(progressEvents.last.progressRatio, 1.0);
      expect(progressEvents.last.estimatedRemaining, Duration.zero);

      for (final event in progressEvents) {
        expect(event.totalWords, report.wordCount);
        expect(event.stage.isNotEmpty, isTrue);
      }
    });

    test('5. ForensicCoordinator handles both small and massive inputs without crashing', () async {
      // Micro text
      final microReport = await coordinator.coordinate(text: 'Brief test note.');
      expect(microReport.wordCount, 3);

      // Multi-paragraph text
      final longText = List.filled(30, 'The distributed database replicates transactions across geographic regions. ').join();
      final longReport = await coordinator.coordinate(text: longText);
      expect(longReport.wordCount, greaterThan(200));
      expect(longReport.sentences.isNotEmpty, isTrue);
    });
  });

  group('ForensicChunkProgressCard Widget Tests', () {
    testWidgets('Renders active chunk counter, dynamic ETA, and glowing progress bar', (WidgetTester tester) async {
      const progress = ForensicProgress(
        currentChunk: 3,
        totalChunks: 8,
        progressRatio: 0.375,
        elapsed: Duration(milliseconds: 90),
        estimatedRemaining: Duration(milliseconds: 150),
        estimatedTotal: Duration(milliseconds: 240),
        stage: 'Analyzing chunk 3 of 8 (280 words)...',
        wordsProcessed: 840,
        totalWords: 2240,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ForensicChunkProgressCard(progress: progress),
              ),
            ),
          ),
        ),
      );

      expect(find.text('CHUNK 3 OF 8'), findsOneWidget);
      expect(find.text('Analyzing chunk 3 of 8 (280 words)...'), findsOneWidget);
      expect(find.text('840 / 2240 words'), findsOneWidget);
    });
  });
}
