import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_calibration.dart';
import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';

void main() {
  group('Frontier LLM Superior Accuracy Benchmark Suite', () {
    late ForensicEngine engine;

    setUp(() {
      engine = ForensicEngine();
    });

    test('Benchmark 1: GPT-4o / GPT-5 Academic Synthesis Essay (Subtle, No Buzzwords)', () {
      const gpt4oText = '''
Artificial intelligence is rapidly reshaping the landscape of modern higher education by introducing sophisticated digital platforms for instruction, research, and administration. Contemporary universities utilize machine learning algorithms to personalize course delivery, analyze student performance metrics, and provide automated diagnostic feedback in real time. These adaptive learning systems help learners master challenging concepts at an individualized pace while allowing faculty to identify specific academic challenges earlier in the semester. Data analytics and intelligent tutoring environments also offer scalable pathways to improve educational accessibility and optimize institutional resource allocation.

At the same time, integrating automated intelligence systems into university curricula introduces complex ethical and pedagogical questions. Key concerns include algorithmic transparency, data security, unequal technological access, and the potential diminution of independent analytical reasoning. University leadership and faculty governance must develop comprehensive policies around privacy, academic integrity, bias, and responsible AI use. If these challenges are addressed carefully, AI could complement educators and create a more flexible and individualized higher-education experience.
''';

      final report = engine.analyze(gpt4oText);
      expect(report.aiAuthorship.aiProbability, greaterThanOrEqualTo(65.0),
          reason: 'Frontier GPT-4o essay must score >= 75% AI probability');
      expect(report.aiAuthorship.authorshipClass, equals(AuthorshipClass.likelyAi));
      expect(report.tokenPredictability!.predictabilityScore, greaterThan(50.0));
      expect(report.tokenPredictability!.rareTailPercentage, lessThan(8.0));
    });

    test('Benchmark 2: Claude 3.5 Sonnet Technical Policy Analysis', () {
      const claudeSonnetText = '''
Decentralized autonomous organizations represent a fundamental shift in corporate governance and algorithmic decision-making. By replacing traditional hierarchical management with immutable smart contract architectures, these systems ensure transparent voting protocols and verifiable treasury distributions. However, several operational constraints must be addressed to guarantee long-term economic stability. Smart contract vulnerabilities, voter apathy, and legal jurisdictional ambiguities present ongoing hurdles for widespread adoption. Incorporating formal verification methods and adaptive governance mechanisms allows distributed communities to safeguard asset reserves while preserving decentralized autonomy.
''';

      final report = engine.analyze(claudeSonnetText);
      expect(report.aiAuthorship.aiProbability, greaterThanOrEqualTo(65.0),
          reason: 'Claude 3.5 Sonnet technical analysis should be flagged as likely AI');
      expect(report.aiAuthorship.authorshipClass, equals(AuthorshipClass.likelyAi));
    });

    test('Benchmark 3: Llama 3.3 70B Medical Health Summary', () {
      const llamaText = '''
Chronic metabolic disorders require multifaceted clinical interventions to mitigate systemic cardiovascular risks and improve patient outcomes. Integrating continuous glucose monitoring with personalized dietary adjustments enables clinicians to track glycemic variability with unprecedented precision. Furthermore, predictive risk algorithms assist healthcare practitioners in identifying microvascular complications prior to clinical onset. Establishing robust patient education programs and individualized follow-up protocols ensures long-term therapeutic adherence across diverse demographic populations.
''';

      final report = engine.analyze(llamaText);
      expect(report.aiAuthorship.aiProbability, greaterThanOrEqualTo(68.0),
          reason: 'Llama 3.3 medical overview must trigger high AI detection');
    });

    test('Benchmark 4: Adversarial Homoglyph & Evasion Cloaked Sample', () {
      // Homoglyphs in key keywords (Cyrillic a, e, o)
      const obfuscatedText = '''
Artifici\u0430l int\u0435llig\u0435nce is r\u0430pidly r\u0435sh\u0430ping high\u0435r \u0435duc\u0430ti\u043En by intr\u043Educing digit\u0430l pl\u0430tf\u043Erms.
Univ\u0435rsiti\u0435s utiliz\u0435 m\u0430chin\u0435 l\u0435\u0430rning t\u043E p\u0435rs\u043En\u0430liz\u0435 c\u043Eurse d\u0435liv\u0435ry.
''';

      final report = engine.analyze(obfuscatedText);
      expect(report.aiAuthorship.detectedSignals.any((s) => s.family == 'Adversarial'), isTrue,
          reason: 'Adversarial homoglyph substitution must be unmasked and flagged');
      expect(report.aiAuthorship.aiProbability, greaterThanOrEqualTo(70.0));
    });

    test('Benchmark 5: Authentic Human Memoir & Personal Narrative (False Positive Protection)', () {
      const humanMemoir = '''
When I first stepped into my grandfather's workshop, the smell of aged cedar and sawdust hit me like a memory I hadn't known I lost. He didn't look up right away; he was focused entirely on beveling the edge of a mahogany table leg. "Patience, kid," he mumbled, wiping his brow with a grease-stained handkerchief. I remember wondering how someone could spend six hours sanding a piece of wood that most people would never even look at closely. But to him, every curve told a story. It wasn't about speed or efficiency. It was about creating something that outlived the hands that made it. That afternoon changed how I look at craftsmanship forever.
''';

      final report = engine.analyze(humanMemoir);
      expect(report.aiAuthorship.aiProbability, lessThan(ForensicCalibrationConfig.calibrated().aiModerateThreshold),
          reason: 'Authentic human memoir must score very low AI (< 15%)');
      expect(report.aiAuthorship.authorshipClass, isNot(AuthorshipClass.likelyAi));
      expect(report.tokenPredictability!.rareTailPercentage, greaterThan(12.0));
    });

    test('Benchmark 6: Authentic Human Technical & Analytical Writing (Zero False Positives)', () {
      const humanTech = '''
I ran our benchmarks on the new ARM64 cluster yesterday and hit an annoying bottleneck with Redis connection pooling. We were spinning up roughly four thousand concurrent client goroutines, but the kernel ran out of file descriptors almost immediately because ulimit was stuck at the default 1024. Once we bumped the system limit to 65535 and enabled TCP keepalive recycling, latency dropped from 84ms down to barely 3.2ms. If you run into similar drops during load tests, check your socket reuse flags first before messing with mutexes.
''';

      final report = engine.analyze(humanTech);
      expect(report.aiAuthorship.aiProbability, lessThan(ForensicCalibrationConfig.calibrated().aiModerateThreshold),
          reason: 'Authentic human engineering report must not trigger false positive AI alerts');
      expect(report.aiAuthorship.authorshipClass, isNot(AuthorshipClass.likelyAi));
    });

    test('Benchmark 7: Paraphrased Literature Plagiarism Matching with Subword Vectors', () {
      final matcher = DenseSemanticMatcher();
      // Original reference: "Attention mechanisms allow neural networks to dynamically focus on relevant input tokens."
      const original = 'Attention mechanisms allow neural networks to dynamically focus on relevant input tokens.';
      const spunParaphrase = 'By utilizing dynamic attention layers, deep learning architectures selectively concentrate on significant tokens.';

      final sim = matcher.similarity(spunParaphrase, original);
      expect(sim, greaterThanOrEqualTo(0.55),
          reason: 'Dense subword semantic vector projection must capture structural and synonym paraphrasing');
    });
  });
}
