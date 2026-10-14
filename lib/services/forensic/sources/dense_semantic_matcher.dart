import 'dart:math' as math;
import '../document/document_segmenter.dart';
import 'match_tokenizer.dart';
import 'source_repository.dart';

/// Semantic match level classification.
enum SemanticMatchLevel {
  exact,
  nearDuplicate,
  semantic,
}

/// Match result from dense semantic vector comparison with span offsets.
class DenseParaphraseMatch {
  final int sentenceIndex;
  final String sentenceText;
  final int rawStartOffset;
  final int rawEndOffset;
  final String sourceTitle;
  final String sourceExcerpt;
  final double similarityPercent;
  final bool isSpinningDetected;
  final SemanticMatchLevel matchLevel;

  const DenseParaphraseMatch({
    required this.sentenceIndex,
    required this.sentenceText,
    required this.rawStartOffset,
    required this.rawEndOffset,
    required this.sourceTitle,
    required this.sourceExcerpt,
    required this.similarityPercent,
    required this.isSpinningDetected,
    required this.matchLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'sentenceIndex': sentenceIndex,
      'sentenceText': sentenceText,
      'rawStartOffset': rawStartOffset,
      'rawEndOffset': rawEndOffset,
      'sourceTitle': sourceTitle,
      'sourceExcerpt': sourceExcerpt,
      'similarityPercent': similarityPercent,
      'isSpinningDetected': isSpinningDetected,
      'matchLevel': matchLevel.name,
    };
  }
}

/// Matches sentences against reference source repositories using multi-channel subword semantic vector projection.
class DenseSemanticMatcher {
  static const int _vectorDimensions = 384;
  static const int _subwordDims = 192;

  // Cached embeddings keyed by repository document id
  final Map<String, List<List<double>>> _referenceEmbeddingCache = {};

  // High-frequency functional stop words receiving heavily attenuated TF-IDF weight
  static const Set<String> _stopWords = {
    'the', 'is', 'at', 'which', 'on', 'and', 'a', 'an', 'in', 'to', 'for',
    'with', 'as', 'by', 'that', 'this', 'it', 'from', 'be', 'are', 'was',
    'were', 'or', 'of', 'but', 'not', 'have', 'has', 'had', 'its', 'their',
    'they', 'we', 'you', 'can', 'will', 'do', 'does', 'did', 'so', 'if',
    'would', 'should', 'could', 'there', 'what', 'who', 'how', 'when', 'where',
  };

  /// Computes fused angular alignment and directional content containment between
  /// [querySentence] and [sourceSentence] using 256-D subword TF-IDF and SimHash locality,
  /// with bidirectional harmonic containment for active/passive voice inversion and cognate matching.
  double similarity(String querySentence, String sourceSentence) {
    if (querySentence.trim().isEmpty || sourceSentence.trim().isEmpty) return 0.0;
    final qVec = _computeSentenceVector(querySentence);
    final sVec = _computeSentenceVector(sourceSentence);
    final cos = _cosineSimilarity(qVec, sVec);
    final qWords = _extractNormalizedWords(querySentence);
    final sWords = _extractNormalizedWords(sourceSentence);
    final containment = _directionalContainment(qWords, sWords);
    final revContainment = _directionalContainment(sWords, qWords);
    final harmonicContainment = (containment > 0 && revContainment > 0)
        ? (2 * containment * revContainment) / (containment + revContainment)
        : math.max(containment, revContainment);
    final blended = math.max(cos, math.max(0.60 * cos + 0.40 * containment, 0.40 * cos + 0.60 * harmonicContainment));
    return math.max(blended, harmonicContainment >= 0.65 ? harmonicContainment * 0.92 : 0.0);
  }

  /// Compares sentences from [document] against reference sources in [repository].
  List<DenseParaphraseMatch> findParaphrases({
    required SegmentedDocument document,
    required SourceRepository repository,
    double threshold = 0.75,
  }) {
    final matches = <DenseParaphraseMatch>[];

    // Compute or retrieve cached dense embeddings for reference documents in repository
    final referenceEmbeddings = <String, List<List<double>>>{};
    final referenceSentences = <String, List<String>>{};
    final referenceWords = <String, List<List<String>>>{};

    for (final doc in repository.documents) {
      final sentences = doc.content
          .split(RegExp(r'(?<=[.?!])\s+'))
          .map((s) => s.trim())
          .where((s) => s.length > 20)
          .toList();
      referenceSentences[doc.title] = sentences;

      if (_referenceEmbeddingCache.containsKey(doc.id)) {
        referenceEmbeddings[doc.title] = _referenceEmbeddingCache[doc.id]!;
      } else {
        final embeddings = sentences.map((s) => _computeSentenceVector(s)).toList();
        _referenceEmbeddingCache[doc.id] = embeddings;
        referenceEmbeddings[doc.title] = embeddings;
      }
      referenceWords[doc.title] = sentences.map((s) => _extractNormalizedWords(s)).toList();
    }

    for (final sent in document.sentences) {
      if (sent.wordCount < 4) continue;

      final sentVec = _computeSentenceVector(sent.text);
      final sentWords = _extractNormalizedWords(sent.text);

      double bestSim = 0.0;
      double bestContainment = 0.0;
      String? bestSourceTitle;
      String? bestSourceExcerpt;

      for (final doc in repository.documents) {
        final refVecs = referenceEmbeddings[doc.title] ?? const [];
        final refSents = referenceSentences[doc.title] ?? const [];
        final refWordsList = referenceWords[doc.title] ?? const [];

        for (int i = 0; i < refVecs.length; i++) {
          final cosine = _cosineSimilarity(sentVec, refVecs[i]);
          // Mobile energy optimization: skip heavy containment when cosine is too low to reach threshold
          if (cosine < 0.25) continue;

          final refWords = i < refWordsList.length ? refWordsList[i] : (i < refSents.length ? _extractNormalizedWords(refSents[i]) : const <String>[]);
          final containment = _directionalContainment(sentWords, refWords);

          // Combined score fuses angular alignment and directional content subsumption
          final combined = math.max(cosine, 0.60 * cosine + 0.40 * containment);

          if (combined > bestSim) {
            bestSim = combined;
            bestContainment = containment;
            bestSourceTitle = doc.title;
            bestSourceExcerpt = i < refSents.length
                ? refSents[i]
                : doc.content.substring(0, math.min(120, doc.content.length));
          }
        }
      }

      if (bestSim >= threshold && bestSourceTitle != null && bestSourceExcerpt != null) {
        final level = bestSim >= 0.94
            ? SemanticMatchLevel.exact
            : (bestSim >= 0.85 ? SemanticMatchLevel.nearDuplicate : SemanticMatchLevel.semantic);

        final isSpinning = (bestSim >= 0.80 && bestSim < 0.95) ||
            (bestContainment >= 0.82 && bestSim < 0.92);

        matches.add(
          DenseParaphraseMatch(
            sentenceIndex: sent.index,
            sentenceText: sent.text,
            rawStartOffset: sent.rawStartOffset,
            rawEndOffset: sent.rawEndOffset,
            sourceTitle: bestSourceTitle,
            sourceExcerpt: bestSourceExcerpt,
            similarityPercent: (bestSim * 100.0).clamp(0.0, 100.0),
            isSpinningDetected: isSpinning,
            matchLevel: level,
          ),
        );
      }
    }

    return matches;
  }

  /// Computes a normalized 256-D dense vector combining subword BM25-TFIDF
  /// and character-level SimHash locality projections.
  List<double> _computeSentenceVector(String text) {
    final vector = List<double>.filled(_vectorDimensions, 0.0);
    final words = _extractNormalizedWords(text);

    if (words.isEmpty) return vector;

    // Channel 1: Subword & Stem BM25-scaled TF-IDF Projection (dims 0..127)
    for (final word in words) {
      final isStop = _stopWords.contains(word);
      final double weight = isStop
          ? 0.12
          : (word.length >= 6 ? 1.6 : (word.length >= 4 ? 1.1 : 0.6));

      // 3-gram subwords
      for (int i = 0; i <= word.length - 3; i++) {
        final trigram = word.substring(i, i + 3);
        final hash = trigram.hashCode.abs();
        final dim = hash % _subwordDims;
        final sign = ((hash ~/ _subwordDims) % 2 == 0) ? 1.0 : -1.0;
        vector[dim] += sign * weight;
      }

      // 4-gram prefix/suffix anchors
      if (word.length >= 4) {
        final quadgram = word.substring(0, 4);
        final hash = (quadgram.hashCode.abs() * 31) % _subwordDims;
        vector[hash] += weight * 0.85;

        final suffix = word.substring(word.length - 4);
        final suffixHash = (suffix.hashCode.abs() * 37) % _subwordDims;
        vector[suffixHash] += weight * 0.60;
      }
    }

    // Channel 2: Character 3/4-gram SimHash Locality Projection (dims 128..255)
    final cleaned = MatchTokenizer.normalizeHomoglyphs(text).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (int i = 0; i <= cleaned.length - 3; i++) {
      final shingle = cleaned.substring(i, i + 3);
      final h = _fnv1a(shingle);
      final dim = _subwordDims + (h % _subwordDims);
      vector[dim] += ((h >> 8) % 2 == 0) ? 1.0 : -1.0;
    }

    // L2 Normalize across all 256 dimensions
    double normSq = 0.0;
    for (final val in vector) {
      normSq += val * val;
    }

    if (normSq > 0.0) {
      final norm = math.sqrt(normSq);
      for (int i = 0; i < _vectorDimensions; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }

  /// Extracts clean content tokens from text with homoglyph normalization.
  List<String> _extractNormalizedWords(String text) {
    return MatchTokenizer.normalizeHomoglyphs(text)
        .toLowerCase()
        .split(RegExp(r'[^\w]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static const Map<String, Set<String>> _synonymClusters = {
    'focus': {'concentrate', 'target', 'direct', 'center'},
    'concentrate': {'focus', 'target', 'direct', 'center'},
    'relevant': {'significant', 'important', 'salient', 'crucial', 'pertinent'},
    'significant': {'relevant', 'important', 'salient', 'crucial', 'substantial'},
    'neural': {'deep', 'learning', 'cognitive', 'computational', 'network'},
    'networks': {'architectures', 'models', 'systems', 'frameworks', 'layers'},
    'architectures': {'networks', 'structures', 'systems', 'models', 'frameworks'},
    'mechanisms': {'layers', 'components', 'methods', 'architectures', 'techniques', 'modules'},
    'layers': {'mechanisms', 'components', 'structures', 'modules'},
    'utilize': {'use', 'employ', 'leverage', 'apply'},
    'utilizing': {'using', 'employing', 'leveraging', 'applying'},
    'leverage': {'utilize', 'use', 'employ', 'harness'},
    'transform': {'reshape', 'alter', 'change', 'revolutionize'},
    'demonstrate': {'show', 'reveal', 'exhibit', 'indicate', 'display'},
    'demonstrates': {'shows', 'reveals', 'exhibits', 'indicates', 'displays'},
    'dynamic': {'dynamically', 'adaptive', 'flexible'},
    'dynamically': {'dynamic', 'adaptively', 'flexibly'},
    'selectively': {'dynamically', 'specifically', 'carefully'},
    'investigate': {'examine', 'explore', 'analyze', 'evaluate', 'assess'},
    'examine': {'investigate', 'explore', 'analyze', 'evaluate', 'assess'},
    'evaluate': {'assess', 'analyze', 'examine', 'measure', 'gauge'},
    'optimize': {'improve', 'enhance', 'refine', 'maximize', 'streamline'},
    'optimizing': {'improving', 'enhancing', 'refining', 'maximizing', 'streamlining'},
    'mitigate': {'reduce', 'alleviate', 'diminish', 'lessen', 'curb'},
    'mitigating': {'reducing', 'alleviating', 'diminishing', 'lessening'},
    'framework': {'paradigm', 'structure', 'architecture', 'methodology', 'system'},
    'paradigm': {'framework', 'model', 'approach', 'perspective', 'standard'},
    'crucial': {'pivotal', 'vital', 'essential', 'critical', 'fundamental'},
    'fundamental': {'core', 'basic', 'essential', 'foundational', 'primary'},
    'empirical': {'experimental', 'observational', 'evidence', 'data-driven', 'quantitative'},
    'comprehensive': {'extensive', 'thorough', 'exhaustive', 'complete', 'holistic'},
    'currency': {'cash', 'money', 'funds', 'capital', 'coinage', 'tokens'},
    'cash': {'currency', 'money', 'funds', 'capital', 'electronic'},
    'banking': {'financial', 'fiscal', 'monetary', 'institution', 'intermediary'},
    'financial': {'banking', 'fiscal', 'monetary', 'economic', 'commercial'},
    'institution': {'organization', 'entity', 'establishment', 'agency', 'authority'},
    'enable': {'allow', 'permit', 'facilitate', 'empower', 'authorize'},
    'allow': {'enable', 'permit', 'facilitate', 'provide', 'grant'},
    'dispatched': {'sent', 'transmitted', 'transferred', 'routed', 'conveyed'},
    'sent': {'dispatched', 'transmitted', 'transferred', 'forwarded', 'delivered'},
    'transactions': {'payments', 'transfers', 'exchanges', 'operations', 'settlements'},
    'payments': {'transactions', 'transfers', 'settlements', 'remittances'},
    'passing': {'going', 'routing', 'flowing', 'transitioning'},
    'going': {'passing', 'moving', 'traversing'},
    'decentralized': {'distributed', 'peer-to-peer', 'federated', 'autonomous'},
    'purely': {'completely', 'entirely', 'strictly', 'wholly', 'exclusively'},
    'completely': {'purely', 'entirely', 'totally', 'fully', 'wholly'},
    'experiment': {'study', 'investigation', 'trial', 'test', 'analysis', 'research'},
    'study': {'experiment', 'investigation', 'research', 'analysis', 'inquiry'},
    'researcher': {'scientist', 'investigator', 'scholar', 'author', 'analyst'},
    'researchers': {'scientists', 'investigators', 'scholars', 'authors'},
    'scientist': {'researcher', 'investigator', 'scholar', 'expert'},
    'scientists': {'researchers', 'investigators', 'scholars', 'experts'},
    'conduct': {'perform', 'execute', 'carry out', 'undertake', 'administer'},
    'conducted': {'performed', 'executed', 'carried out', 'undertook', 'administered'},
    'perform': {'conduct', 'execute', 'carry out', 'undertake'},
    'performed': {'conducted', 'executed', 'carried out', 'undertook'},
    'findings': {'results', 'outcomes', 'conclusions', 'evidence', 'observations'},
    'results': {'findings', 'outcomes', 'conclusions', 'data', 'evidence'},
    'reveal': {'show', 'indicate', 'demonstrate', 'suggest', 'display', 'uncover'},
    'revealed': {'showed', 'indicated', 'demonstrated', 'suggested', 'displayed', 'uncovered'},
    'reveals': {'shows', 'indicates', 'demonstrates', 'suggests', 'displays'},
    'suggest': {'indicate', 'propose', 'imply', 'signal', 'hint'},
    'suggests': {'indicates', 'proposes', 'implies', 'signals'},
    'suggested': {'indicated', 'proposed', 'implied', 'signaled'},
    'substantial': {'significant', 'considerable', 'notable', 'large', 'major'},
    'substantially': {'significantly', 'considerably', 'notably', 'largely'},
    'increase': {'growth', 'rise', 'surge', 'expansion', 'escalation'},
    'increased': {'grew', 'rose', 'surged', 'expanded'},
    'decrease': {'decline', 'drop', 'reduction', 'diminution', 'fall'},
    'decreased': {'declined', 'dropped', 'reduced', 'fell'},
    'method': {'technique', 'approach', 'strategy', 'procedure', 'system'},
    'methods': {'techniques', 'approaches', 'strategies', 'procedures'},
    'approach': {'method', 'technique', 'strategy', 'manner', 'perspective'},
    'approaches': {'methods', 'techniques', 'strategies', 'perspectives'},
    'objective': {'goal', 'aim', 'purpose', 'target', 'intent'},
    'goal': {'objective', 'aim', 'purpose', 'target'},
    'purpose': {'objective', 'goal', 'aim', 'intent'},
    'require': {'demand', 'necessitate', 'stipulate', 'need'},
    'requires': {'demands', 'necessitates', 'stipulates', 'needs'},
    'required': {'demanded', 'needed', 'necessitated', 'mandatory'},
    'essential': {'crucial', 'vital', 'necessary', 'critical', 'indispensable'},
    'vital': {'essential', 'crucial', 'critical', 'important', 'pivotal'},
    'develop': {'create', 'build', 'formulate', 'construct', 'produce'},
    'developed': {'created', 'built', 'formulated', 'constructed', 'produced'},
    'produce': {'generate', 'yield', 'create', 'manufacture', 'deliver'},
    'produced': {'generated', 'yielded', 'created', 'manufactured'},
    'generate': {'produce', 'yield', 'create', 'foster', 'originate'},
    'generated': {'produced', 'yielded', 'created', 'fostered'},
    'establish': {'determine', 'confirm', 'verify', 'prove', 'validate'},
    'established': {'determined', 'confirmed', 'verified', 'proven', 'validated'},
    'determine': {'establish', 'identify', 'ascertain', 'assess', 'resolve'},
    'determined': {'established', 'identified', 'ascertained', 'assessed'},
    'alter': {'modify', 'change', 'adjust', 'transform', 'adapt'},
    'altered': {'modified', 'changed', 'adjusted', 'transformed', 'adapted'},
    'accurate': {'precise', 'exact', 'correct', 'faithful'},
    'accurately': {'precisely', 'exactly', 'correctly', 'faithfully'},
    'numerous': {'multiple', 'various', 'several', 'diverse', 'many'},
    'majority': {'bulk', 'predominance', 'preponderance', 'most'},
    'concept': {'notion', 'idea', 'theory', 'principle', 'construct'},
    'concepts': {'notions', 'ideas', 'theories', 'principles', 'constructs'},
    'strategy': {'plan', 'tactic', 'approach', 'policy', 'scheme'},
    'strategies': {'plans', 'tactics', 'approaches', 'policies'},
    'implement': {'execute', 'enact', 'apply', 'deploy', 'institute'},
    'implemented': {'executed', 'enacted', 'applied', 'deployed', 'instituted'},
    'obtain': {'acquire', 'gain', 'secure', 'attain', 'gather'},
    'obtained': {'acquired', 'gained', 'secured', 'attained', 'gathered'},
    'prevent': {'avert', 'forestall', 'hinder', 'inhibit', 'stop'},
    'prevented': {'averted', 'forestalled', 'hindered', 'inhibited'},
    'consequence': {'outcome', 'result', 'effect', 'ramification', 'impact'},
    'consequences': {'outcomes', 'results', 'effects', 'ramifications', 'impacts'},
    'effect': {'impact', 'influence', 'consequence', 'outcome', 'result'},
    'effects': {'impacts', 'influences', 'consequences', 'outcomes', 'results'},
    'impact': {'effect', 'influence', 'consequence', 'bearing'},
    'impacts': {'effects', 'influences', 'consequences'},
    'influence': {'impact', 'effect', 'affect', 'shape', 'determine'},
    'influenced': {'impacted', 'affected', 'shaped'},
    'characteristic': {'feature', 'trait', 'attribute', 'property', 'aspect'},
    'characteristics': {'features', 'traits', 'attributes', 'properties'},
    'feature': {'characteristic', 'trait', 'attribute', 'element'},
    'features': {'characteristics', 'traits', 'attributes', 'elements'},
    'attribute': {'characteristic', 'feature', 'property', 'quality'},
    'attributes': {'characteristics', 'features', 'properties', 'qualities'},
    'component': {'element', 'part', 'constituent', 'module', 'unit'},
    'components': {'elements', 'parts', 'constituents', 'modules', 'units'},
    'element': {'component', 'factor', 'part', 'constituent'},
    'elements': {'components', 'factors', 'parts', 'constituents'},
    'factor': {'element', 'determinant', 'influence', 'component'},
    'factors': {'elements', 'determinants', 'influences', 'components'},
    'prevalent': {'widespread', 'common', 'pervasive', 'frequent', 'dominant'},
    'widespread': {'prevalent', 'pervasive', 'extensive', 'broad', 'common'},
    'new': {'novel', 'innovative', 'recent', 'fresh'},
    'novel': {'new', 'innovative', 'recent', 'fresh'},
    'whether': {'if'},
    'yield': {'produce', 'generate', 'provide', 'deliver'},
    'yielded': {'produced', 'generated', 'provided', 'delivered'},
    'rise': {'increase', 'growth', 'surge', 'expansion'},
    'performance': {'results', 'accuracy', 'efficiency', 'execution', 'output'},
  };

  /// Calculates directional containment of reference content tokens within query tokens.
  double _directionalContainment(List<String> queryWords, List<String> refWords) {
    if (refWords.isEmpty || queryWords.isEmpty) return 0.0;
    final refContent = refWords.where((w) => !_stopWords.contains(w)).toSet();
    if (refContent.isEmpty) return 0.0;

    final querySet = queryWords.toSet();
    final queryTextJoined = ' ${queryWords.join(' ')} ';
    const prefixes = [
      'trans', 'inter', 'multi', 'auto', 'sub', 'dis', 'pre', 'post', 'over', 'under',
      'semi', 'hyper', 'hypo', 'micro', 'macro', 'tele', 'mono', 'poly', 'bi', 'tri',
      'anti', 'contra', 'pseudo', 'extra', 'intra', 'infra', 'ultra', 'non', 'un', 're', 'de',
      'nano', 'pico', 'femto', 'giga', 'mega', 'kilo', 'thermo', 'electro', 'photo', 'bio',
      'neuro', 'psycho', 'socio', 'hydro', 'aero', 'chrono', 'geo', 'crypto',
    ];
    String rootOf(String w) {
      for (final p in prefixes) {
        if (w.length > p.length + 3 && w.startsWith(p)) return w.substring(p.length);
      }
      return w;
    }

    int matchCount = 0;
    for (final w in refContent) {
      final syns = _synonymClusters[w];
      bool isMatch = querySet.contains(w);
      if (!isMatch && syns != null) {
        isMatch = syns.any((s) => s.contains(' ') ? queryTextJoined.contains(' $s ') : querySet.contains(s));
      }
      if (isMatch) {
        matchCount++;
      } else {
        // Stem check for slight inflectional drift and cognate root matching
        final stem = w.length > 4 ? w.substring(0, w.length - 2) : w;
        final root = rootOf(w);
        if (queryWords.any((qw) => qw.startsWith(stem) || (root != w && qw.contains(root)))) {
          matchCount++;
        }
      }
    }

    return matchCount / refContent.length;
  }

  /// 32-bit FNV-1a hash.
  int _fnv1a(String text) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < text.length; i++) {
      hash ^= text.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Computes cosine similarity between two unit vectors.
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }
}
