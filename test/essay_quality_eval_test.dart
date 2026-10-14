// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/humanizer/lauvira_humanize_service.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/plagiarism_detector_service.dart';

/// End-to-end essay evaluation of the humanizer and plagiarism engines.
/// Essays are full-length (150-250 words) so length gating does not apply.
const _aiEssays = <String, String>{
  'ai_education': '''
Artificial intelligence is rapidly reshaping the landscape of modern higher education by introducing sophisticated digital platforms for instruction, research, and administration. Furthermore, universities leverage machine learning algorithms to personalize course delivery, analyze student performance metrics, and provide automated feedback in real time. These adaptive systems help learners master challenging concepts at an individualized pace while allowing faculty to identify academic difficulties earlier in the semester.

Moreover, integrating intelligent systems into curricula introduces complex ethical and pedagogical questions. Key concerns include algorithmic transparency, data security, unequal access, and the potential erosion of independent critical thinking. It is important to note that institutions must develop comprehensive policies around privacy, academic integrity, and responsible use. In conclusion, if these challenges are addressed carefully, AI can complement educators and foster a more flexible, inclusive, and effective learning experience for all students.
''',
  'ai_climate': '''
Climate change represents one of the most pressing challenges of our time, demanding a multifaceted and collaborative response. In today's rapidly evolving world, rising global temperatures have intensified extreme weather events, disrupted ecosystems, and threatened food security across the globe. According to the 2023 IPCC synthesis, global surface temperature has already risen by roughly 1.1 degrees Celsius above pre-industrial levels.

Additionally, transitioning to renewable energy is not only crucial but also pivotal for sustainable development. Governments, businesses, and individuals all play a vital role in reducing emissions through innovative technologies and responsible consumption. Ultimately, addressing climate change requires a holistic approach that balances economic growth with environmental stewardship, ensuring a resilient future for generations to come.
''',
  'ai_remote_work': '''
Remote work has fundamentally transformed the modern workplace, offering both significant opportunities and notable challenges. On the one hand, employees benefit from greater flexibility, reduced commuting time, and improved work-life balance. On the other hand, organizations must navigate issues related to communication, collaboration, and company culture in a distributed environment.

Delving deeper, research suggests that productivity often remains stable or even increases when employees are given autonomy. However, isolation and blurred boundaries between professional and personal life can negatively impact well-being. Therefore, leaders should foster trust, establish clear expectations, and leverage digital tools to cultivate meaningful connections. In summary, the future of work is likely to be a hybrid model that harnesses the strengths of both in-person and remote collaboration.
''',
};

const _humanEssays = <String, String>{
  'human_workshop': '''
When I first stepped into my grandfather's workshop, the smell of aged cedar and sawdust hit me like a memory I hadn't known I lost. He didn't look up right away; he was focused entirely on beveling the edge of a mahogany table leg. "Patience, kid," he mumbled, wiping his brow with a grease-stained handkerchief. I remember wondering how someone could spend six hours sanding a piece of wood that most people would never even look at closely. But to him, every curve told a story. It wasn't about speed or efficiency. It was about creating something that outlived the hands that made it. That afternoon changed how I look at craftsmanship forever. Years later I still keep one of his chisels on my desk, nicked and dull, and I never sharpen it.
''',
  'human_commute': '''
I missed the 7:42 again. Third time this week, and honestly it's my own fault, because I keep hitting snooze like the alarm is negotiable. So there I was on the platform, coffee going cold, watching a pigeon steal half a bagel from a guy who didn't even notice. Funny how the small stuff sticks. By the time the 8:10 rolled in, packed like a sardine tin, I'd already decided to quit pretending I'm a morning person. My manager says I should "own my schedule," whatever that means. I'd settle for a seat. Maybe next month I'll try the bike, though the last time I did that a dog chased me for two blocks and I ended up in somebody's hedge.
''',
};

int _count(RegExp r, String s) => r.allMatches(s).length;
final _numbers = RegExp(r'\b\d+(?:\.\d+)?\b');
final _stockPhrases = RegExp(
  r'\b(furthermore|moreover|additionally|in conclusion|in summary|ultimately|it is important to note|delving|delve|multifaceted|pivotal|holistic|foster|leverage|crucial|rapidly evolving|rapidly reshaping|in today\x27s)\b',
  caseSensitive: false,
);

void main() {
  final engine = ForensicEngine();
  final detector = PlagiarismDetectorService();
  final humanizer = LauviraHumanizeService();

  group('Detector on essays', () {
    for (final e in _aiEssays.entries) {
      test('${e.key} is not rated clean human', () {
        final r = engine.analyze(e.value, enableOnlineSearch: false);
        print('${e.key}: AI ${r.aiAuthorship.aiProbability.toStringAsFixed(1)}% (${r.aiAuthorship.authorshipClass.badge})');
        expect(r.aiAuthorship.aiProbability, greaterThan(30));
      });
    }
    for (final e in _humanEssays.entries) {
      test('${e.key} is not flagged as AI', () {
        final r = engine.analyze(e.value, enableOnlineSearch: false);
        print('${e.key}: AI ${r.aiAuthorship.aiProbability.toStringAsFixed(1)}% (${r.aiAuthorship.authorshipClass.badge})');
        expect(r.aiAuthorship.aiProbability, lessThan(45));
      });
    }
  });

  group('Humanizer on AI essays', () {
    for (final e in _aiEssays.entries) {
      test('${e.key}: strips AI tells, keeps facts, stays clean', () async {
        final before = e.value.trim();
        final after = await humanizer.humanizeLlmOutput(before, tone: 'academic');
        final scoreBefore = engine.analyze(before, enableOnlineSearch: false).aiAuthorship.aiProbability;
        final scoreAfter = engine.analyze(after, enableOnlineSearch: false).aiAuthorship.aiProbability;
        print('--- ${e.key}: AI ${scoreBefore.toStringAsFixed(1)}% -> ${scoreAfter.toStringAsFixed(1)}%, '
            'stock phrases ${_count(_stockPhrases, before)} -> ${_count(_stockPhrases, after)}');
        print(after);

        // Facts preserved.
        expect(_numbers.allMatches(after).map((m) => m.group(0)).toSet(),
            containsAll(_numbers.allMatches(before).map((m) => m.group(0)).toSet()));
        // Tells reduced and detector score not worse.
        expect(_count(_stockPhrases, after), lessThan(_count(_stockPhrases, before)));
        expect(scoreAfter, lessThanOrEqualTo(scoreBefore + 1));
        // Length drift bounded.
        final ratio = after.split(RegExp(r'\s+')).length / before.split(RegExp(r'\s+')).length;
        expect(ratio, inInclusiveRange(0.7, 1.3));
        // No formatting damage.
        expect(after, isNot(contains('  ')));
        expect(after, isNot(matches(RegExp(r'[.!?]\s+[a-z]'))), reason: 'sentence starts must stay capitalized');
        expect(after, isNot(contains(' ,')));
        expect(after, isNot(contains('..')));
      });
    }

    test('human essays are left essentially intact', () async {
      for (final e in _humanEssays.entries) {
        final before = e.value.trim();
        final after = await humanizer.humanizeLlmOutput(before);
        final b = before.split(RegExp(r'\s+')).toSet();
        final a = after.split(RegExp(r'\s+')).toSet();
        final overlap = a.intersection(b).length / b.length;
        print('${e.key}: word overlap after humanize ${(overlap * 100).toStringAsFixed(0)}%');
        expect(overlap, greaterThan(0.85));
      }
    });
  });

  group('Plagiarism on essays', () {
    final turing = SourceRepository().getDocument('wiki_turing_test')!.content.trim();

    test('verbatim copy of a known source is flagged high', () {
      final essay = 'Machine intelligence has fascinated scholars for decades, and one of the earliest framings is worth quoting at length. '
          '$turing '
          'This framing still shapes how researchers discuss evaluation of intelligent systems today.';
      final r = engine.analyze(essay, enableOnlineSearch: false);
      print('verbatim: similarity ${r.sourceSimilarity.overallSimilarityScore.toStringAsFixed(1)}% '
          'coverage ${r.sourceSimilarity.documentCoveragePercent.toStringAsFixed(1)}% sources ${r.sourceSimilarity.uniqueSourceCount}');
      expect(r.sourceSimilarity.overallSimilarityScore, greaterThan(40));
      expect(r.sourceSimilarity.uniqueSourceCount, greaterThanOrEqualTo(1));
    });

    test('light paraphrase scores below verbatim', () {
      const para = 'Alan Turing opens by asking whether machines are capable of thought, and says we should first define what we mean by "machine" and "think". '
          'He then recasts the problem as a game, the so-called imitation game, played by three people: a man, a woman, and an interrogator of either sex. '
          'The interrogator sits alone in a separate room and has to work out which of the other two players is the man and which is the woman.';
      final r = engine.analyze(para, enableOnlineSearch: false);
      final v = engine.analyze(turing, enableOnlineSearch: false);
      print('paraphrase: ${r.sourceSimilarity.overallSimilarityScore.toStringAsFixed(1)}% vs verbatim ${v.sourceSimilarity.overallSimilarityScore.toStringAsFixed(1)}%');
      expect(r.sourceSimilarity.overallSimilarityScore, lessThan(v.sourceSimilarity.overallSimilarityScore));
    });

    test('original human essay has no source match', () {
      for (final e in _humanEssays.entries) {
        final r = engine.analyze(e.value, enableOnlineSearch: false);
        print('${e.key}: similarity ${r.sourceSimilarity.overallSimilarityScore.toStringAsFixed(1)}%');
        expect(r.sourceSimilarity.overallSimilarityScore, lessThan(15));
      }
    });

    test('PlagiarismDetectorService rule engine reports essays consistently', () {
      for (final e in {..._aiEssays, ..._humanEssays}.entries) {
        final r = detector.analyze(e.value);
        print('${e.key}: overall ${r.overallScore.toStringAsFixed(0)} human ${r.humanScore.toStringAsFixed(0)} tells ${r.detectedTells.length}');
      }
      final ai = detector.analyze(_aiEssays['ai_climate']!).overallScore;
      final human = detector.analyze(_humanEssays['human_commute']!).overallScore;
      expect(ai, greaterThan(human));
    });
  });
}
