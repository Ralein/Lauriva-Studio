// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

void main() {
  test('Evaluate Full Forensic Engine on User ChatGPT Essay and Authentic Human Essay', () {
    final engine = ForensicEngine();

    // 1. User's modern ChatGPT higher education essay (subtle, no "Moreover", 199 words)
    const chatGptEssay = '''
Artificial intelligence is rapidly reshaping the landscape of modern higher education by introducing sophisticated digital platforms for instruction, research, and administration. Contemporary universities utilize machine learning algorithms to personalize course delivery, analyze student performance metrics, and provide automated diagnostic feedback in real time. These adaptive learning systems help learners master challenging concepts at an individualized pace while allowing faculty to identify specific academic challenges earlier in the semester. Data analytics and intelligent tutoring environments also offer scalable pathways to improve educational accessibility and optimize institutional resource allocation.

At the same time, integrating automated intelligence systems into university curricula introduces complex ethical and pedagogical questions. Key concerns include algorithmic transparency, data security, unequal technological access, and the potential diminution of independent analytical reasoning. University leadership and faculty governance must develop comprehensive policies around privacy, academic integrity, bias, and responsible AI use. If these challenges are addressed carefully, AI could complement educators and create a more flexible and individualized higher-education experience.
''';

    final reportAi = engine.analyze(chatGptEssay);
    print('\n========================================');
    print('🔬 USER CHATGPT ESSAY FORENSIC SCAN');
    print('========================================');
    print('AI Probability: ${reportAi.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
    print('Human Probability: ${reportAi.humanScore.toStringAsFixed(1)}%');
    print('Classification: ${reportAi.aiAuthorship.authorshipClass.badge}');
    print('Confidence: ${reportAi.confidence.level.badge} (${(reportAi.confidence.score * 100).toStringAsFixed(0)}%)');
    print('Detected Signals:');
    for (final s in reportAi.aiAuthorship.detectedSignals) {
      print('  - [${s.family}] ${s.name}: ${s.score.toStringAsFixed(1)}');
    }

    // 2. Authentic human essay
    const humanEssay = '''
When I first stepped into my grandfather's workshop, the smell of aged cedar and sawdust hit me like a memory I hadn't known I lost. He didn't look up right away; he was focused entirely on beveling the edge of a mahogany table leg. "Patience, kid," he mumbled, wiping his brow with a grease-stained handkerchief. I remember wondering how someone could spend six hours sanding a piece of wood that most people would never even look at closely. But to him, every curve told a story. It wasn't about speed or efficiency. It was about creating something that outlived the hands that made it. That afternoon changed how I look at craftsmanship forever.
''';

    final reportHuman = engine.analyze(humanEssay);
    print('\n========================================');
    print('👤 AUTHENTIC HUMAN ESSAY FORENSIC SCAN');
    print('========================================');
    print('AI Probability: ${reportHuman.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
    print('Human Probability: ${reportHuman.humanScore.toStringAsFixed(1)}%');
    print('Classification: ${reportHuman.aiAuthorship.authorshipClass.badge}');

    // Verdict scale follows the refit stylometric calibration (see ForensicCalibrationConfig.defaultPlatt):
    // >= aiModerateThreshold (68) is LIKELY AI; a clean human essay must stay well below it.
    expect(reportAi.aiAuthorship.aiProbability, greaterThanOrEqualTo(65.0));
    expect(reportHuman.aiAuthorship.aiProbability, lessThanOrEqualTo(45.0));
    expect(reportHuman.aiAuthorship.aiProbability, lessThan(reportAi.aiAuthorship.aiProbability - 20));
  });
}
