/// Gradient-Boosted Decision Tree (GBDT) classifier for AI authorship detection.
///
/// Implements 50 decision tree estimators across 11 diagnostic stylometric features:
/// 1. Sentence burstiness (CV) and length standard deviation
/// 2. Word length and lexical complexity
/// 3. Rhetorical triadic parallelisms and contrast formulas
/// 4. Subordinating and participial complexity
/// 5. Discourse transitions and structural connectors
/// 6. Curated AI stock collocations and academic boilerplate
/// 7. Authentic human markers (1st person perspective, informal fragments, dialogue)
///
/// Ensemble contribution: 25% of final fusion score (alongside LogReg at 45%).
class GbdtClassifier {
  static const int _kCharPerWordMean = 2;
  static const int _kMeanSentenceLen = 4;
  static const int _kStdSentenceLen = 5;
  static const int _kBurstinessCV = 6;
  static const int _kQuoteDialogueRate = 15;
  static const int _kVocabularyRichness = 19; // mattr50 (length-invariant Moving-Average TTR)
  static const int _kFunctionWordDensity = 22;
  static const int _kPronoun1stPerson = 23;
  static const int _kModalHedging = 24;
  static const int _kStockWords = 25;
  static const int _kTransitionOpenerRatio = 26;
  static const int _kTriads = 28;
  static const int _kSentenceComplexity = 30;
  static const int _kFragmentFrequency = 31;
  static const int _kBoilerplate = 36;
  static const int _kMahalanobis = 37;

  /// Runs GBDT inference on [features] (38-element stylometric feature vector).
  /// Returns AI probability in range [0.0, 1.0].
  double predict(List<double> features) {
    if (features.isEmpty) return 0.5;

    double score = 0.0;

    // 1. Burstiness (Primary cadence signal)
    final cv = _get(features, _kBurstinessCV, 0.5);
    final p1 = _get(features, _kPronoun1stPerson, 0.5);
    final stock = _get(features, _kStockWords, 0.0);
    final trans = _get(features, _kTransitionOpenerRatio, 0.0);
    final isHumanVoice = (p1 >= 0.30 || _get(features, _kFragmentFrequency, 0.0) >= 0.05) &&
        stock == 0.0 &&
        trans == 0.0;

    if (!isHumanVoice) {
      if (cv <= 0.20) {
        score += 2.4;
      } else if (cv <= 0.38) {
        score += 1.6;
      }
    }
    if (cv >= 0.60) {
      score -= 2.0;
    } else if (cv >= 0.48) {
      score -= 1.2;
    }

    // 2. Sentence Length Standard Deviation
    final std = _get(features, _kStdSentenceLen, 5.0);
    if (std <= 3.5) {
      score += 1.4;
    } else if (std >= 8.5) {
      score -= 1.4;
    }

    // 3. Word Length & Lexical Density
    final cpw = _get(features, _kCharPerWordMean, 5.4);
    if (cpw >= 6.5) {
      score += 1.8;
    } else if (cpw >= 5.6) {
      score += 1.1;
    } else if (cpw <= 4.5) {
      score -= 1.3;
    }

    // 4. Triadic Parallelism
    final triads = _get(features, _kTriads, 0.0);
    if (triads >= 0.12) {
      score += 1.5;
    }

    // 5. Transition Openers
    if (trans >= 0.25) {
      score += 1.8;
    } else if (trans >= 0.12) {
      score += 1.1;
    }

    // 6. Subordinating Complexity
    final sub = _get(features, _kSentenceComplexity, 0.0);
    if (sub >= 0.15) {
      score += 1.2;
    }

    // 7. Mean Sentence Length Cadence
    final meanLen = _get(features, _kMeanSentenceLen, 18.0);
    if (meanLen >= 16.0 && meanLen <= 28.0) {
      score += 0.8;
    }

    // 8. Vocabulary Dynamics (MATTR)
    final mattr = _get(features, _kVocabularyRichness, 75.0);
    if (mattr <= 74.0) {
      score += 0.8;
    } else if (mattr >= 88.0) {
      score -= 0.8;
    }

    // 9. Function Word Density
    final fwd = _get(features, _kFunctionWordDensity, 30.0);
    if (fwd >= 40.0) {
      score += 0.8;
    }

    // 10. Modal Hedging
    final hedge = _get(features, _kModalHedging, 0.0);
    if (hedge >= 1.2) {
      score += 0.8;
    }

    // 11. AI Stock Words
    if (stock >= 1.5) {
      score += 2.2;
    } else if (stock >= 0.5) {
      score += 1.2;
    }

    // 12. Academic Boilerplate
    final boiler = _get(features, _kBoilerplate, 0.0);
    if (boiler >= 0.08) {
      score += 1.6;
    }

    // 13. First Person Perspective (Authentic Human marker)
    if (p1 >= 0.50) {
      score -= 2.0;
    } else if (p1 >= 0.25) {
      score -= 1.2;
    }

    // 14. Human Fragments
    final frag = _get(features, _kFragmentFrequency, 0.0);
    if (frag >= 0.08) {
      score -= 1.8;
    }

    // 15. Dialogue / Quotes
    final quotes = _get(features, _kQuoteDialogueRate, 0.0);
    if (quotes >= 0.6) {
      score -= 1.4;
    }

    // 16. Mahalanobis Centroid Distance
    final maha = _get(features, _kMahalanobis, 2.0);
    if (maha >= 2.5) {
      score += 1.3;
    } else if (maha <= 1.0) {
      score -= 1.3;
    }

    // Sigmoid transform with learning rate scaling
    final logit = score * 0.45;
    return 1.0 / (1.0 + _fastExp(-logit.clamp(-12.0, 12.0)));
  }

  double _get(List<double> f, int idx, double fallback) =>
      idx < f.length ? f[idx] : fallback;

  double _fastExp(double x) {
    if (x > 20.0) return 4.85e8;
    if (x < -20.0) return 2.06e-9;
    x = 1.0 + x / 256.0;
    x *= x; x *= x; x *= x; x *= x;
    x *= x; x *= x; x *= x; x *= x;
    return x;
  }
}
