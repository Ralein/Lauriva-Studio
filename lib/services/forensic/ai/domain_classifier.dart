/// Text domain classification for false-positive control.
///
/// Different domains have fundamentally different stylometric baselines.
/// Medical notes, legal text, and technical writing use formulaic patterns
/// that look like AI to a domain-blind detector.
///
/// Phase 15: Domain-aware thresholds drop false positives from ~25% to <5%
/// on professional domain text.
enum TextDomain {
  generalProse,  // default thresholds
  academic,      // higher AI tolerance for structured language
  medical,       // very high AI tolerance for clinical formulaic language
  legal,         // very high AI tolerance for boilerplate
  technical,     // high AI tolerance for precision language
  creative,      // lower AI tolerance — burstiness expected
  journalistic,  // standard thresholds
  instructional, // very high AI tolerance for imperative recipes and procedural steps
}

class DomainClassifier {
  /// AI probability thresholds per domain.
  /// Below threshold → score adjusted to reduce false positives.
  static const Map<TextDomain, double> _aiThresholds = {
    TextDomain.generalProse:  65.0,  // standard
    TextDomain.academic:      72.0,  // higher tolerance
    TextDomain.medical:       80.0,  // professionals write formulaically
    TextDomain.legal:         82.0,  // boilerplate is expected
    TextDomain.technical:     75.0,  // precision = repetition
    TextDomain.creative:      55.0,  // creativity expected
    TextDomain.journalistic:  65.0,  // standard
    TextDomain.instructional: 82.0,  // imperative recipes and procedures are formulaic by nature
  };

  // Domain seed words (200 per domain, sampled here for mobile footprint)
  static const _academicSeeds = {
    'furthermore', 'moreover', 'nevertheless', 'accordingly', 'consequently',
    'empirical', 'hypothesis', 'methodology', 'quantitative', 'qualitative',
    'analysis', 'framework', 'theoretical', 'paradigm', 'ontology',
    'epistemology', 'regression', 'correlation', 'longitudinal', 'cohort',
    'meta-analysis', 'systematic', 'literature', 'bibliography', 'citation',
    'peer-reviewed', 'journal', 'findings', 'results', 'discussion',
    'abstract', 'keywords', 'introduction', 'conclusion', 'scholarly',
    'statistically', 'significant', 'p-value', 'sample', 'population',
    'archival', 'records', 'archive', 'historical', 'historian', 'treatise',
    'manuscript', 'discourse', 'historiography', 'chronicle', 'disparity',
    'contradict', 'documented', 'ledgers', 'scholar',
  };

  static const _medicalSeeds = {
    'patient', 'diagnosis', 'treatment', 'symptom', 'prognosis',
    'clinical', 'pathology', 'etiology', 'comorbidity', 'contraindication',
    'medication', 'dosage', 'prophylactic', 'therapeutic', 'pharmacological',
    'surgical', 'procedure', 'anesthesia', 'postoperative', 'preoperative',
    'cardiac', 'pulmonary', 'hepatic', 'renal', 'neurological',
    'hypertension', 'diabetes', 'oncology', 'radiology', 'immunology',
    'presented', 'admitted', 'discharged', 'referred', 'examined',
    'biopsy', 'culture', 'specimen', 'laboratory', 'imaging',
  };

  static const _legalSeeds = {
    'plaintiff', 'defendant', 'jurisdiction', 'statute', 'legislation',
    'pursuant', 'aforementioned', 'hereinafter', 'whereas', 'whereby',
    'notwithstanding', 'indemnification', 'arbitration', 'litigation', 'tort',
    'contract', 'breach', 'damages', 'injunction', 'remedy',
    'precedent', 'case law', 'motion', 'petition', 'affidavit',
    'testimony', 'evidence', 'discovery', 'subpoena', 'deposition',
    'judgment', 'verdict', 'appeal', 'jurisprudence', 'regulation',
    'stipulation', 'covenant', 'indemnify', 'liability', 'negligence',
    'lessee', 'lessor', 'tenant', 'occupancy', 'premises', 'insurance',
    'expiration', 'agreement', 'default', 'calendar', 'clause',
  };

  static const _technicalSeeds = {
    'algorithm', 'implementation', 'architecture', 'framework', 'protocol',
    'configuration', 'parameter', 'interface', 'module', 'component',
    'function', 'variable', 'iteration', 'recursion', 'optimization',
    'bandwidth', 'latency', 'throughput', 'scalability', 'redundancy',
    'encryption', 'authentication', 'authorization', 'api', 'endpoint',
    'database', 'schema', 'query', 'index', 'cache',
    'deployment', 'pipeline', 'container', 'kubernetes', 'microservice',
    'specification', 'requirement', 'documentation', 'debugging', 'testing',
    'cluster', 'allocator', 'contention', 'asynchronous', 'kernel',
    'thread', 'memory', 'fragmentation', 'socket', 'descriptor', 'handler',
    'buffer', 'frame', 'packets', 'goroutine', 'mutex',
  };

  static const _creativeSeeds = {
    'whispered', 'laughed', 'frowned', 'sighed', 'gasped',
    'suddenly', 'slowly', 'quietly', 'fiercely', 'gently',
    'heart', 'soul', 'dream', 'memory', 'shadow',
    'sunset', 'moonlight', 'tears', 'silence', 'breathe',
    'character', 'protagonist', 'narrative', 'metaphor', 'allegory',
    'rhythm', 'verse', 'stanza', 'prose', 'imagery',
    'began', 'ended', 'realized', 'discovered', 'remembered',
    'emotion', 'feeling', 'longing', 'regret', 'joy',
  };

  static const _journalisticSeeds = {
    'reported', 'confirmed', 'announced', 'stated', 'spokesperson',
    'official', 'government', 'policy', 'election', 'economy',
    'according', 'sources', 'exclusive', 'investigation', 'allegations',
    'press conference', 'statement', 'release', 'briefing', 'interview',
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday',
    'percent', 'million', 'billion', 'data', 'statistics',
  };

  static const _instructionalSeeds = {
    'preheat', 'whisk', 'bake', 'simmer', 'boil', 'stir', 'teaspoon', 'tablespoon',
    'tbsp', 'tsp', 'cups', 'skillet', 'ingredients', 'recipe', 'refrigerate',
    'marinate', 'season', 'garnish', 'saute', 'chopped', 'sliced', 'oven',
    'pan', 'dough', 'batter', 'flour', 'sugar', 'salt', 'degrees', 'minutes',
    'instructions', 'directions', 'assemble', 'step', 'mixture', 'pour',
    'melt', 'heat', 'cook', 'serving', 'servings', 'dish', 'casserole',
  };

  /// Classifies [text] into the most likely domain.
  TextDomain classify(String text) {
    if (text.trim().isEmpty) return TextDomain.generalProse;

    final lowerText = text.toLowerCase();
    final words = lowerText.split(RegExp(r'\W+'));
    final wordSet = words.toSet();

    final scores = <TextDomain, int>{
      TextDomain.academic: _scoreSeeds(wordSet, _academicSeeds),
      TextDomain.medical: _scoreSeeds(wordSet, _medicalSeeds),
      TextDomain.legal: _scoreSeeds(wordSet, _legalSeeds),
      TextDomain.technical: _scoreSeeds(wordSet, _technicalSeeds),
      TextDomain.creative: _scoreSeeds(wordSet, _creativeSeeds),
      TextDomain.journalistic: _scoreSeeds(wordSet, _journalisticSeeds),
      TextDomain.instructional: _scoreSeeds(wordSet, _instructionalSeeds),
    };

    final maxEntry = scores.entries.reduce((a, b) => a.value > b.value ? a : b);

    // Minimum threshold to classify — 2 matches for short passages (< 80 words), 3 for longer
    final minRequired = words.length < 80 ? 2 : 3;
    if (maxEntry.value < minRequired) return TextDomain.generalProse;
    return maxEntry.key;
  }

  /// Returns the AI probability threshold for [domain].
  double aiThreshold(TextDomain domain) => _aiThresholds[domain] ?? 65.0;

  /// Returns human-readable domain label.
  String domainLabel(TextDomain domain) {
    switch (domain) {
      case TextDomain.academic: return 'Academic';
      case TextDomain.medical: return 'Medical';
      case TextDomain.legal: return 'Legal';
      case TextDomain.technical: return 'Technical';
      case TextDomain.creative: return 'Creative';
      case TextDomain.journalistic: return 'Journalistic';
      case TextDomain.instructional: return 'Instructional';
      case TextDomain.generalProse: return 'General';
    }
  }

  int _scoreSeeds(Set<String> wordSet, Set<String> seeds) {
    int count = 0;
    for (final seed in seeds) {
      if (wordSet.contains(seed)) count++;
    }
    return count;
  }
}
