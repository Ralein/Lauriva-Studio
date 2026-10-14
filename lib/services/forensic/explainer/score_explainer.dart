import '../../../models/forensic/ai_authorship_evidence.dart';
import '../../../models/forensic/forensic_report.dart';
import '../../../models/plagiarism_report.dart';

/// Translates technical stylometric metrics, token predictability statistics,
/// and source similarities into human-centered, defensible explanations.
class ScoreExplainer {
  const ScoreExplainer();

  /// Returns the single primary human-readable driver behind the report's verdict.
  String primaryReason(ForensicReport report) {
    if (report.confidence.uncertainty > 0.35 && report.rawText.split(RegExp(r'\s+')).length < 40) {
      return 'The passage is too short (${report.wordCount} words) for a definitive conclusion; '
          'more text is required for statistical stability.';
    }

    if (report.sourceSimilarity.overallSimilarityScore >= 50.0) {
      final match = report.sourceSimilarity.matches.isNotEmpty
          ? report.sourceSimilarity.matches.first
          : null;
      if (match != null) {
        return 'Substantial text overlap (${match.similarityPercent.toStringAsFixed(0)}%) '
            'detected against external literature ("${match.sourceTitle}").';
      }
    }

    if (report.adversarialEvidence?.evasionAttemptDetected == true) {
      return 'Adversarial evasion detected — text was obfuscated using hidden characters or cross-alphabet homoglyphs.';
    }

    final ai = report.aiAuthorship;
    if (ai.authorshipClass == AuthorshipClass.likelyAi || ai.aiProbability >= 65.0) {
      // Find top non-trivial signal
      for (final signal in ai.detectedSignals) {
        if (signal.name.toLowerCase().contains('burstiness')) {
          return 'Sentences exhibit uniform cadence and length with minimal natural variance — characteristic of synthetic generation.';
        }
        if (signal.name.toLowerCase().contains('transition')) {
          return 'Frequent formulaic discourse connectives (e.g., "Moreover", "Furthermore") are overrepresented relative to human writing.';
        }
        if (signal.name.toLowerCase().contains('triad')) {
          return 'Repetitive three-item rhythmic patterns (e.g., "X, Y, and Z") create an artificial, formulaic cadence.';
        }
      }
      return 'Multiple statistical and lexical markers align closely with large language model generation patterns.';
    }

    if (ai.authorshipClass == AuthorshipClass.mixedOrEdited) {
      return 'The document displays sharp stylistic discontinuities, indicating human-authored sections blended with machine-generated prose.';
    }

    return 'Natural sentence length diversity, dynamic vocabulary distribution, and organic stylistic flow suggest authentic human authorship.';
  }

  /// Converts top forensic signals into structured, plain-English bullet points.
  List<({String title, String explanation, bool isRisk})> explainSignals(ForensicReport report) {
    final results = <({String title, String explanation, bool isRisk})>[];

    // Source matching signals
    if (report.sourceSimilarity.overallSimilarityScore >= 20.0) {
      final top = report.sourceSimilarity.matches.isNotEmpty ? report.sourceSimilarity.matches.first : null;
      results.add((
        title: 'Literature Overlap',
        explanation: top != null
            ? 'Matched ${top.similarityPercent.toStringAsFixed(0)}% with "${top.sourceTitle}".'
            : 'Detected matching passages against indexed references.',
        isRisk: report.sourceSimilarity.overallSimilarityScore >= 45.0,
      ));
    }

    // Adversarial signals
    if (report.adversarialEvidence?.evasionAttemptDetected == true) {
      results.add((
        title: 'Adversarial Evasion',
        explanation: 'Contained Unicode confusables or hidden control characters intended to bypass automated filters.',
        isRisk: true,
      ));
    }

    // Stylometric signals
    for (final signal in report.aiAuthorship.detectedSignals.take(4)) {
      final name = signal.name.toLowerCase();
      if (name.contains('burstiness')) {
        results.add((
          title: 'Sentence Length Uniformity',
          explanation: 'Sentences are almost the same length throughout; human prose naturally exhibits high variability.',
          isRisk: signal.score > 60.0,
        ));
      } else if (name.contains('transition')) {
        results.add((
          title: 'Transition Openers',
          explanation: 'Sentences frequently begin with formal transitional words like "Moreover" or "In conclusion".',
          isRisk: signal.score > 60.0,
        ));
      } else if (name.contains('triad')) {
        results.add((
          title: 'Three-Item Rhythm',
          explanation: 'Repetitive use of three-part lists ("innovation, efficiency, and scalability") typical of AI summaries.',
          isRisk: signal.score > 60.0,
        ));
      } else if (name.contains('predictab') || name.contains('token')) {
        results.add((
          title: 'Sequence Predictability',
          explanation: 'Token sequence choices closely mirror autoregressive next-token probabilities of leading LLMs.',
          isRisk: signal.score > 60.0,
        ));
      } else if (name.contains('domain')) {
        results.add((
          title: 'Domain Context',
          explanation: signal.description,
          isRisk: false,
        ));
      }
    }

    if (results.isEmpty) {
      results.add((
        title: 'Cadence & Flow',
        explanation: 'Sentence structures and vocabulary demonstrate organic human variability with natural pacing.',
        isRisk: false,
      ));
    }

    return results;
  }

  /// Generates a bulleted plain-English diagnostic for a specific tapped sentence.
  List<String> explainSentence(SentenceAudit audit, {int averageDocWords = 18}) {
    final points = <String>[];
    final text = audit.text.trim();
    final lower = text.toLowerCase();

    // 1. Length analysis
    final delta = (audit.wordCount - averageDocWords).abs();
    if (delta <= 2) {
      points.add('Length (${audit.wordCount} words) matches document average almost exactly (uniform pacing).');
    } else if (audit.wordCount > 35) {
      points.add('Extended complex compound structure (${audit.wordCount} words).');
    } else if (audit.wordCount < 8) {
      points.add('Short punchy fragment (${audit.wordCount} words).');
    }

    // 2. Openers
    final commonTransitions = [
      'moreover', 'furthermore', 'additionally', 'consequently', 'therefore',
      'in conclusion', 'in summary', 'notably', 'it is important', 'however'
    ];
    for (final tr in commonTransitions) {
      if (lower.startsWith(tr)) {
        points.add('Opens with "$tr" — a high-frequency discourse connective commonly overused by AI models.');
        break;
      }
    }

    // 3. Stock phrases
    final aiStock = [
      'it is worth noting', 'plays a crucial role', 'delve into', 'rich tapestry',
      'ever-evolving landscape', 'beacon of hope', 'multifaceted nature', 'holistic approach'
    ];
    for (final stock in aiStock) {
      if (lower.contains(stock)) {
        points.add('Contains signature AI idiom: "$stock".');
      }
    }

    // 4. Triads
    final triadRegex = RegExp(r'\b[a-zA-Z]+,\s+[a-zA-Z]+,\s+and\s+[a-zA-Z]+\b');
    if (triadRegex.hasMatch(text)) {
      points.add('Uses a three-part parallel list rhythm (triad structure).');
    }

    // 5. Detected tells from audit
    for (final tell in audit.detectedTells) {
      if (!points.any((p) => p.toLowerCase().contains(tell.toLowerCase()))) {
        points.add('Flagged marker: $tell.');
      }
    }

    if (points.isEmpty) {
      points.add('Sentence exhibits balanced structure and organic lexical distribution.');
    }

    return points;
  }
}
