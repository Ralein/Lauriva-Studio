/// Stylometric calibration parameters tailored to a specific human language.
class MultilingualFeatureProfile {
  final String languageCode;
  final String languageName;
  final double burstinessMean;
  final double transitionOpenerThreshold;
  final double vocabularyRichnessBaseline;
  final double functionWordRatio;
  final double expectedAiThreshold;

  const MultilingualFeatureProfile({
    required this.languageCode,
    required this.languageName,
    required this.burstinessMean,
    required this.transitionOpenerThreshold,
    required this.vocabularyRichnessBaseline,
    required this.functionWordRatio,
    this.expectedAiThreshold = 65.0,
  });
}

/// Baseline stylometric profiles for the 22 languages supported by Lauriva.
class MultilingualProfiles {
  static const MultilingualFeatureProfile english = MultilingualFeatureProfile(
    languageCode: 'en',
    languageName: 'English',
    burstinessMean: 0.65,
    transitionOpenerThreshold: 0.12,
    vocabularyRichnessBaseline: 0.72,
    functionWordRatio: 0.43,
    expectedAiThreshold: 65.0,
  );

  static const MultilingualFeatureProfile spanish = MultilingualFeatureProfile(
    languageCode: 'es',
    languageName: 'Spanish',
    burstinessMean: 0.58,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.68,
    functionWordRatio: 0.48,
    expectedAiThreshold: 68.0,
  );

  static const MultilingualFeatureProfile french = MultilingualFeatureProfile(
    languageCode: 'fr',
    languageName: 'French',
    burstinessMean: 0.61,
    transitionOpenerThreshold: 0.11,
    vocabularyRichnessBaseline: 0.70,
    functionWordRatio: 0.46,
    expectedAiThreshold: 67.0,
  );

  static const MultilingualFeatureProfile german = MultilingualFeatureProfile(
    languageCode: 'de',
    languageName: 'German',
    burstinessMean: 0.55,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.65,
    functionWordRatio: 0.41,
    expectedAiThreshold: 70.0,
  );

  static const MultilingualFeatureProfile arabic = MultilingualFeatureProfile(
    languageCode: 'ar',
    languageName: 'Arabic',
    burstinessMean: 0.50,
    transitionOpenerThreshold: 0.07,
    vocabularyRichnessBaseline: 0.60,
    functionWordRatio: 0.52,
    expectedAiThreshold: 72.0,
  );

  static const MultilingualFeatureProfile hindi = MultilingualFeatureProfile(
    languageCode: 'hi',
    languageName: 'Hindi',
    burstinessMean: 0.60,
    transitionOpenerThreshold: 0.10,
    vocabularyRichnessBaseline: 0.67,
    functionWordRatio: 0.45,
    expectedAiThreshold: 69.0,
  );

  // Profiles for the remaining Studio languages. Field semantics follow the
  // six above: burstinessMean = typical coefficient of variation of human
  // sentence lengths, transitionOpenerThreshold = share of sentences opening
  // with a discourse connective above which prose reads as templated,
  // vocabularyRichnessBaseline = expected human type-token ratio,
  // functionWordRatio = share of tokens that are closed-class words, and
  // expectedAiThreshold = score (0..100) at which the language profile flags
  // AI authorship. Only English has the neural detector, so languages whose
  // stylometry is least supported by the English-derived lexicons get a
  // higher (more conservative) threshold.

  static const MultilingualFeatureProfile portuguese = MultilingualFeatureProfile(
    languageCode: 'pt',
    languageName: 'Portuguese',
    burstinessMean: 0.59,
    transitionOpenerThreshold: 0.10,
    vocabularyRichnessBaseline: 0.68,
    functionWordRatio: 0.47, // Romance: articles fused with prepositions (do, na, pelo), close to Spanish.
    expectedAiThreshold: 67.0,
  );

  static const MultilingualFeatureProfile italian = MultilingualFeatureProfile(
    languageCode: 'it',
    languageName: 'Italian',
    burstinessMean: 0.60,
    transitionOpenerThreshold: 0.10,
    vocabularyRichnessBaseline: 0.69,
    functionWordRatio: 0.46, // Articulated prepositions (della, nel) keep it between Spanish and French.
    expectedAiThreshold: 67.0,
  );

  static const MultilingualFeatureProfile dutch = MultilingualFeatureProfile(
    languageCode: 'nl',
    languageName: 'Dutch',
    burstinessMean: 0.57,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.66, // Closed compounds like German inflate TTR slightly less than German.
    functionWordRatio: 0.44,
    expectedAiThreshold: 68.0,
  );

  static const MultilingualFeatureProfile swedish = MultilingualFeatureProfile(
    languageCode: 'sv',
    languageName: 'Swedish',
    burstinessMean: 0.58,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.67,
    functionWordRatio: 0.42, // Suffixed definite articles (huset) remove free article tokens.
    expectedAiThreshold: 68.0,
  );

  static const MultilingualFeatureProfile russian = MultilingualFeatureProfile(
    languageCode: 'ru',
    languageName: 'Russian',
    burstinessMean: 0.60,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.78, // Six-case inflection spreads one lemma over many word forms.
    functionWordRatio: 0.33, // No articles; case endings replace many prepositions.
    expectedAiThreshold: 69.0,
  );

  static const MultilingualFeatureProfile polish = MultilingualFeatureProfile(
    languageCode: 'pl',
    languageName: 'Polish',
    burstinessMean: 0.60,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.78, // Seven cases, same inflectional spread as Russian.
    functionWordRatio: 0.34, // No articles; short prepositions/conjunctions (w, z, i) still frequent.
    expectedAiThreshold: 70.0,
  );

  static const MultilingualFeatureProfile turkish = MultilingualFeatureProfile(
    languageCode: 'tr',
    languageName: 'Turkish',
    burstinessMean: 0.56,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.82, // Agglutinative: suffix chains make most tokens unique.
    functionWordRatio: 0.25, // Postpositions and case suffixes attach to the word.
    expectedAiThreshold: 71.0,
  );

  static const MultilingualFeatureProfile indonesian = MultilingualFeatureProfile(
    languageCode: 'id',
    languageName: 'Indonesian',
    burstinessMean: 0.55,
    transitionOpenerThreshold: 0.10,
    vocabularyRichnessBaseline: 0.62, // Little inflection; affixes are derivational, lemmas repeat.
    functionWordRatio: 0.40, // yang/dan/di/untuk are very frequent free particles.
    expectedAiThreshold: 69.0,
  );

  static const MultilingualFeatureProfile vietnamese = MultilingualFeatureProfile(
    languageCode: 'vi',
    languageName: 'Vietnamese',
    burstinessMean: 0.55,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.52, // Space-separated units are syllables; compounds reuse them.
    functionWordRatio: 0.50, // Isolating: grammar carried by free particles (của, các, được, đã).
    expectedAiThreshold: 71.0,
  );

  static const MultilingualFeatureProfile chinese = MultilingualFeatureProfile(
    languageCode: 'zh',
    languageName: 'Chinese',
    burstinessMean: 0.52,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.50, // Measured over single characters (no spaces): characters repeat across words.
    functionWordRatio: 0.30, // Particles (的, 了, 在, 是) as a share of characters.
    expectedAiThreshold: 71.0,
  );

  static const MultilingualFeatureProfile japanese = MultilingualFeatureProfile(
    languageCode: 'ja',
    languageName: 'Japanese',
    burstinessMean: 0.52,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.45, // Character units; kana syllables recur far more than Han.
    functionWordRatio: 0.35, // Case particles (は, が, の, を, に) are single kana units.
    expectedAiThreshold: 71.0,
  );

  static const MultilingualFeatureProfile korean = MultilingualFeatureProfile(
    languageCode: 'ko',
    languageName: 'Korean',
    burstinessMean: 0.55,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.80, // Space-separated eojeol carry attached particles, so forms rarely repeat.
    functionWordRatio: 0.22, // Particles are suffixed; few free function words.
    expectedAiThreshold: 71.0,
  );

  static const MultilingualFeatureProfile bengali = MultilingualFeatureProfile(
    languageCode: 'bn',
    languageName: 'Bengali',
    burstinessMean: 0.58,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.74, // Case markers and classifiers are suffixed.
    functionWordRatio: 0.32,
    expectedAiThreshold: 72.0,
  );

  static const MultilingualFeatureProfile marathi = MultilingualFeatureProfile(
    languageCode: 'mr',
    languageName: 'Marathi',
    burstinessMean: 0.58,
    transitionOpenerThreshold: 0.09,
    vocabularyRichnessBaseline: 0.76, // Unlike Hindi, postpositions fuse to the noun (-मध्ये, -च्या).
    functionWordRatio: 0.30,
    expectedAiThreshold: 72.0,
  );

  static const MultilingualFeatureProfile tamil = MultilingualFeatureProfile(
    languageCode: 'ta',
    languageName: 'Tamil',
    burstinessMean: 0.57,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.84, // Highly agglutinative Dravidian morphology and sandhi.
    functionWordRatio: 0.20,
    expectedAiThreshold: 72.0,
  );

  static const MultilingualFeatureProfile telugu = MultilingualFeatureProfile(
    languageCode: 'te',
    languageName: 'Telugu',
    burstinessMean: 0.57,
    transitionOpenerThreshold: 0.08,
    vocabularyRichnessBaseline: 0.83, // Agglutinative Dravidian, like Tamil.
    functionWordRatio: 0.21,
    expectedAiThreshold: 72.0,
  );

  /// All 22 Studio languages (see `TargetLanguage` in lib/models/feature_type.dart).
  static const Map<String, MultilingualFeatureProfile> profiles = {
    'en': english,
    'ta': tamil,
    'es': spanish,
    'fr': french,
    'de': german,
    'hi': hindi,
    'ja': japanese,
    'zh': chinese,
    'ar': arabic,
    'pt': portuguese,
    'ru': russian,
    'it': italian,
    'ko': korean,
    'nl': dutch,
    'tr': turkish,
    'bn': bengali,
    'vi': vietnamese,
    'id': indonesian,
    'pl': polish,
    'te': telugu,
    'mr': marathi,
    'sv': swedish,
  };

  /// Returns profile for language code, falling back to English.
  static MultilingualFeatureProfile forCode(String code) {
    return profiles[code.toLowerCase()] ?? english;
  }
}

/// Lightweight, deterministic on-device language detector based on Unicode scripts
/// and stop-word distribution profiles. Zero cloud calls, 0 ms latency.
class LanguageDetector {
  /// Function words that are frequent in English and rare as words in the
  /// Studio's other 21 languages ("is"/"was"/"of" are Dutch, "to" Polish,
  /// "die" German, "me"/"he" Spanish, ... so they are left out).
  static const Set<String> _enMarkers = {
    'the', 'and', 'that', 'with', 'for', 'this', 'are', 'from', 'have', 'has', 'had', 'which', 'were', 'not',
    'they', 'their', 'his', 'she', 'you', 'will', 'would', 'can', 'could', 'should', 'been', 'but', 'its',
    'there', 'these', 'those', 'what', 'when', 'where', 'who', 'how', 'than', 'then', 'also', 'into', 'about',
    'more', 'other', 'some', 'such', 'only', 'after', 'over', 'between', 'through', 'because', 'while',
    'however', 'our', 'your', 'them', 'does', 'did', 'just', 'like', 'very', 'my', 'it', 'be', 'by', 'at',
    'we', 'as', 'if', 'do', 'one', 'all', 'any', 'each', 'most', 'many', 'much', 'first', 'new', 'used',
    'during', 'within', 'without', 'under', 'against', 'being', 'both', 'same', 'may', 'must', 'shall',
  };

  /// Share of letters outside Latin script above which text is not English.
  static const double maxNonLatinShare = 0.2;

  /// Share of distinctive English function words at or above which Latin-script
  /// text is English. Calibrated on Wikipedia paragraphs in all 22 Studio
  /// languages and the English evaluation corpora (test/forensic/language_gate_test.dart).
  static const double minEnglishMarkerShare = 0.10;

  /// True only when [text] is confidently English -- the one language the
  /// neural detector is trained on. Unlike [detect], unknown languages are not
  /// assumed to be English.
  static bool isEnglish(String text) {
    var letters = 0, nonLatin = 0;
    for (final rune in text.runes) {
      final isLatin = (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A) || (rune >= 0xC0 && rune <= 0x24F);
      final isSymbol = (rune >= 0x2000 && rune <= 0x2BFF) || (rune >= 0x3000 && rune <= 0x303F) ||
          (rune >= 0xFE30 && rune <= 0xFE4F) || (rune >= 0xFF00 && rune <= 0xFF20) || rune >= 0x1F000;
      // Non-Latin letters: cased scripts (Greek, Cyrillic) and caseless ones
      // (Arabic, Indic, CJK, Hangul, ...); punctuation and symbols excluded.
      final isLetter = isLatin || (!isSymbol && rune >= 0x370 &&
          (rune >= 0x0590 || String.fromCharCode(rune).toLowerCase() != String.fromCharCode(rune).toUpperCase()));
      if (!isLetter) continue;
      letters++;
      if (!isLatin) nonLatin++;
    }
    if (letters == 0) return false;
    if (nonLatin / letters > maxNonLatinShare) return false;
    final words = text.toLowerCase().split(RegExp(r"[^a-z\u00c0-\u024f']+")).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;
    final markers = words.where(_enMarkers.contains).length;
    return markers / words.length >= minEnglishMarkerShare;
  }

  /// Distinctive high-frequency function words of each Latin-script Studio
  /// language. A word listed for k languages scores 1/k for each, so shared
  /// words (de, la, en, a) only break ties while distinctive ones decide.
  static const Map<String, Set<String>> _latinFunctionWords = {
    'en': {
      'the', 'and', 'of', 'to', 'is', 'was', 'that', 'with', 'for', 'this', 'are', 'from', 'have', 'has',
      'which', 'were', 'by', 'it', 'be', 'as', 'at', 'on', 'not', 'they', 'their', 'his', 'her', 'an',
      'or', 'but', 'been', 'its', 'also', 'into', 'there', 'these', 'would', 'will', 'can', 'more',
      'other', 'some', 'such', 'only', 'after', 'than', 'who', 'what', 'when', 'where', 'she', 'you', 'we',
    },
    'es': {
      'el', 'la', 'los', 'las', 'del', 'que', 'y', 'en', 'un', 'una', 'por', 'con', 'para', 'es', 'se', 'su',
      'sus', 'al', 'como', 'más', 'pero', 'también', 'fue', 'son', 'este', 'esta', 'entre', 'desde',
      'sobre', 'ya', 'muy', 'hay', 'sin', 'ha', 'han', 'cuando', 'donde', 'lo', 'les', 'según', 'está',
      'están', 'sido', 'o', 'de', 'le', 'era', 'otros', 'otras', 'puede', 'hasta',
    },
    'pt': {
      'o', 'os', 'a', 'as', 'do', 'da', 'dos', 'das', 'no', 'na', 'nos', 'nas', 'em', 'um', 'uma', 'de',
      'que', 'e', 'é', 'com', 'para', 'por', 'pelo', 'pela', 'ao', 'à', 'mais', 'não', 'foi', 'são', 'seu',
      'sua', 'também', 'como', 'ou', 'entre', 'ser', 'está', 'isso', 'este', 'esta', 'ela', 'ele', 'eles', 'muito', 'até', 'já', 'onde', 'quando', 'pelos', 'pelas',
    },
    'fr': {
      'le', 'la', 'les', 'des', 'du', 'de', 'et', 'est', 'un', 'une', 'en', 'dans', 'pour', 'qui', 'que',
      'sur', 'au', 'aux', 'par', 'pas', 'ne', 'ce', 'cette', 'ces', 'il', 'elle', 'sont', 'avec', 'plus',
      'ont', 'été', 'son', 'sa', 'ses', 'leur', 'mais', 'ou', 'où', 'comme', 'd', 'qu', 'n', 'j', 'c',
      'très', 'être', 'avoir', 'nous', 'vous', 'ils', 'aussi', 'peut', 'deux', 'entre',
    },
    'it': {
      'il', 'lo', 'la', 'gli', 'le', 'di', 'del', 'della', 'dei', 'delle', 'dello', 'degli', 'e', 'è',
      'che', 'un', 'una', 'uno', 'per', 'con', 'non', 'sono', 'nel', 'nella', 'nei', 'alla', 'al', 'ai',
      'alle', 'dal', 'dalla', 'da', 'come', 'anche', 'più', 'ma', 'questo', 'questa', 'essere', 'stato',
      'suo', 'sua', 'loro', 'tra', 'fra', 'dell', 'all', 'nell', 'dall', 'sull', 'quello', 'quella',
      'cioè', 'ha', 'hanno', 'ed', 'quindi', 'essa', 'esso',
    },
    'de': {
      'der', 'die', 'das', 'und', 'ist', 'von', 'zu', 'den', 'dem', 'des', 'mit', 'sich', 'auf', 'für',
      'im', 'nicht', 'ein', 'eine', 'einer', 'eines', 'einem', 'einen', 'als', 'auch', 'an', 'wird',
      'werden', 'wurde', 'sind', 'bei', 'aus', 'nach', 'oder', 'wie', 'über', 'dass', 'durch', 'sie',
      'er', 'bis', 'zum', 'zur', 'hat', 'kann', 'noch', 'nur', 'in', 'es', 'dieser', 'diese', 'können',
    },
    'nl': {
      'de', 'het', 'een', 'en', 'van', 'in', 'is', 'dat', 'op', 'te', 'zijn', 'voor', 'met', 'die', 'niet',
      'aan', 'er', 'om', 'ook', 'als', 'bij', 'door', 'of', 'worden', 'wordt', 'werd', 'naar', 'tot', 'uit',
      'maar', 'over', 'deze', 'dit', 'kan', 'heeft', 'zich', 'hun', 'geen', 'wel', 'meer', 'onder', 'men',
      'veel', 'ze', 'hij', 'zij', 'tussen', 'sinds', 'twee',
    },
    'sv': {
      'och', 'i', 'att', 'det', 'som', 'en', 'på', 'är', 'av', 'för', 'med', 'den', 'till', 'har', 'de',
      'inte', 'om', 'ett', 'var', 'jag', 'han', 'hon', 'men', 'så', 'vid', 'kan', 'från', 'sig', 'eller',
      'sin', 'sina', 'också', 'efter', 'under', 'när', 'andra', 'alla', 'detta', 'dessa', 'blev', 'finns',
      'skulle', 'hans', 'där', 'vad', 'mellan',
    },
    'pl': {
      'i', 'w', 'z', 'na', 'się', 'nie', 'do', 'to', 'że', 'jest', 'o', 'a', 'od', 'po', 'jak', 'ale',
      'przez', 'oraz', 'dla', 'jego', 'jej', 'ich', 'był', 'była', 'było', 'są', 'co', 'tak', 'lub', 'przy',
      'także', 'który', 'która', 'które', 'których', 'tym', 'tego', 'ze', 'we', 'pod', 'nad',
      'może', 'być', 'jako', 'został', 'została', 'tylko',
    },
    'tr': {
      've', 'bir', 'bu', 'da', 'de', 'ile', 'için', 'olarak', 'olan', 'çok', 'daha', 'gibi', 'sonra',
      'kadar', 'ise', 'ki', 'ne', 'her', 'veya', 'göre', 'ancak', 'tarafından', 'olduğu', 'şu', 'değil',
      'var', 'yok', 'arasında', 'ilk', 'en', 'o', 'büyük', 'olup', 'ya', 'ayrıca', 'yılında',
    },
    'vi': {
      'là', 'và', 'của', 'có', 'các', 'những', 'được', 'trong', 'cho', 'một', 'không', 'với', 'người',
      'này', 'đã', 'để', 'từ', 'đến', 'khi', 'như', 'cũng', 'về', 'theo', 'sự', 'thể', 'năm', 'ra', 'nhiều',
      'tại', 'do', 'hay', 'vào', 'nhưng', 'thì', 'rất', 'mà', 'lại', 'còn', 'chúng', 'thành',
    },
    'id': {
      'yang', 'dan', 'di', 'ini', 'itu', 'dengan', 'untuk', 'dari', 'dalam', 'tidak', 'ke', 'pada',
      'adalah', 'akan', 'oleh', 'juga', 'sebagai', 'atau', 'ada', 'karena', 'bahwa', 'mereka', 'kami',
      'telah', 'dapat', 'lebih', 'bisa', 'sudah', 'seperti', 'sebuah', 'para', 'antara', 'tersebut',
      'banyak', 'hanya', 'secara', 'menjadi', 'masih', 'saat',
    },
  };

  /// Letters that are (nearly) unique to one Latin-script Studio language.
  /// Each occurrence adds [_diacriticWeight] to that language's score.
  static const Map<int, String> _diacriticCues = {
    0x00F1: 'es', // ñ
    0x00BF: 'es', // ¿
    0x00A1: 'es', // ¡
    0x00E3: 'pt', // ã
    0x00F5: 'pt', // õ
    0x00DF: 'de', // ß
    0x0153: 'fr', // œ
    0x00EB: 'fr', // ë
    0x00EE: 'fr', // î
    0x00FB: 'fr', // û
    0x00E5: 'sv', // å
    0x0142: 'pl', // ł
    0x0105: 'pl', // ą
    0x0119: 'pl', // ę
    0x015B: 'pl', // ś
    0x017A: 'pl', // ź
    0x017C: 'pl', // ż
    0x0107: 'pl', // ć
    0x0144: 'pl', // ń
    0x0131: 'tr', // ı (dotless i)
    0x0130: 'tr', // İ
    0x015F: 'tr', // ş
    0x011F: 'tr', // ğ
    0x0111: 'vi', // đ
    0x0110: 'vi', // Đ
    0x01A1: 'vi', // ơ
    0x01B0: 'vi', // ư
    0x01A0: 'vi', // Ơ
    0x01AF: 'vi', // Ư
  };

  static const double _diacriticWeight = 0.5;

  static final Map<String, Map<String, double>> _wordWeights = () {
    final owners = <String, List<String>>{};
    _latinFunctionWords.forEach((lang, words) {
      for (final w in words) {
        (owners[w] ??= []).add(lang);
      }
    });
    return owners.map((w, langs) => MapEntry(w, {for (final l in langs) l: 1.0 / langs.length}));
  }();

  /// Words far more frequent in Hindi than Marathi (Hindi keeps postpositions
  /// and auxiliaries as separate words; Marathi fuses them).
  static const Set<String> _hiMarkers = {
    'है', 'हैं', 'का', 'की', 'के', 'में', 'से', 'और', 'को', 'था', 'थी', 'थे', 'पर', 'भी', 'यह', 'वह',
    'नहीं', 'लिए', 'कि', 'गया', 'गई', 'जो', 'ने', 'हो', 'किया', 'करने', 'इस', 'उस',
    'जाता', 'जाती', 'रहा', 'रही', 'होता', 'होती', 'कर', 'जिसे',
  };

  /// Words far more frequent in Marathi than Hindi.
  static const Set<String> _mrMarkers = {
    'आहे', 'आहेत', 'आणि', 'हा', 'हे', 'ते', 'तसेच', 'असे', 'असा', 'अशी', 'म्हणजे', 'होते', 'होता', 'होती',
    'आली', 'आले', 'आला', 'केले', 'केली', 'त्या', 'त्याच्या', 'त्यांच्या', 'मध्ये', 'नाही', 'पण', 'येथे',
    'असून', 'असलेले', 'असलेल्या', 'झाला', 'झाली', 'झाले', 'करून', 'आपल्या', 'तर', 'म्हणून',
    'यांच्या', 'व',
  };

  /// Detects the language of [text] among the 22 Studio languages and returns
  /// its ISO 639-1 code: en ta es fr de hi ja zh ar pt ru it ko nl tr bn vi id
  /// pl te mr sv.
  ///
  /// The dominant script decides first (Tamil, Telugu, Bengali, Devanagari,
  /// Arabic, Cyrillic, Hangul, Han/kana); Devanagari is split into Hindi and
  /// Marathi by marker words, Han into Japanese (any meaningful kana share) or
  /// Chinese. Latin-script text is scored on distinctive function words plus
  /// language-specific letters. Text with no evidence at all returns 'en'.
  /// Deterministic, dependency-free, single pass over the runes.
  static String detect(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return 'en';

    var latin = 0, cyrillic = 0, arabic = 0, devanagari = 0, bengali = 0, tamil = 0, telugu = 0;
    var hangul = 0, han = 0, kana = 0, vietTone = 0;
    for (final r in clean.runes) {
      if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) {
        latin++;
      } else if (r >= 0x1E00 && r <= 0x1EFF) {
        latin++;
        // Precomposed Vietnamese letters with tone marks (ạ ả ấ ... ỹ).
        if (r >= 0x1EA0 && r <= 0x1EF9) vietTone++;
      } else if (r >= 0x0400 && r <= 0x04FF) {
        cyrillic++;
      } else if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F) || (r >= 0x08A0 && r <= 0x08FF) ||
          (r >= 0xFB50 && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF)) {
        arabic++;
      } else if (r >= 0x0900 && r <= 0x097F) {
        devanagari++;
      } else if (r >= 0x0980 && r <= 0x09FF) {
        bengali++;
      } else if (r >= 0x0B80 && r <= 0x0BFF) {
        tamil++;
      } else if (r >= 0x0C00 && r <= 0x0C7F) {
        telugu++;
      } else if ((r >= 0xAC00 && r <= 0xD7AF) || (r >= 0x1100 && r <= 0x11FF) || (r >= 0x3130 && r <= 0x318F)) {
        hangul++;
      } else if ((r >= 0x3040 && r <= 0x30FF) || (r >= 0x31F0 && r <= 0x31FF) || (r >= 0xFF66 && r <= 0xFF9F)) {
        kana++;
      } else if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF) || (r >= 0xF900 && r <= 0xFAFF) ||
          (r >= 0x20000 && r <= 0x2FA1F)) {
        han++;
      }
    }

    // Dominant script; ties keep the earlier (non-Latin) entry since a few
    // Latin names inside non-Latin prose are common, the reverse is not.
    final scripts = <String, int>{
      'ta': tamil,
      'te': telugu,
      'bn': bengali,
      'deva': devanagari,
      'ar': arabic,
      'ru': cyrillic,
      'ko': hangul,
      'cjk': han + kana,
      'latin': latin,
    };
    var best = 'latin';
    var bestCount = 0;
    scripts.forEach((script, count) {
      if (count > bestCount) {
        best = script;
        bestCount = count;
      }
    });
    if (bestCount == 0) return 'en';

    switch (best) {
      case 'deva':
        return _hindiOrMarathi(clean);
      case 'cjk':
        // Japanese mixes kana into nearly every sentence; Chinese has none.
        // A 10% kana share tolerates a stray Japanese name in Chinese text.
        return kana > 0 && kana >= 0.1 * (han + kana) ? 'ja' : 'zh';
      case 'latin':
        return _latinLanguage(clean, vietTone);
      default:
        return best;
    }
  }

  static String _hindiOrMarathi(String text) {
    var hi = 0.0, mr = 0.0;
    for (final w in text.split(RegExp(r'[\s।॥.,;:!?()\[\]"\x27\-–—]+'))) {
      if (w.isEmpty) continue;
      if (_hiMarkers.contains(w)) hi++;
      if (_mrMarkers.contains(w)) mr++;
    }
    // ळ (LLA) is common in Marathi and rare in Hindi: a weak tie-breaker.
    mr += 0.25 * 'ळ'.allMatches(text).length;
    return mr > hi ? 'mr' : 'hi';
  }

  static String _latinLanguage(String text, int vietTone) {
    final scores = <String, double>{for (final l in _latinFunctionWords.keys) l: 0.0};
    final lower = text.toLowerCase();
    for (final w in lower.split(RegExp(r"[^a-zÀ-ɏḀ-ỿ]+"))) {
      final weights = _wordWeights[w];
      if (weights == null) continue;
      weights.forEach((lang, weight) => scores[lang] = scores[lang]! + weight);
    }
    for (final r in text.runes) {
      final lang = _diacriticCues[r];
      if (lang != null) scores[lang] = scores[lang]! + _diacriticWeight;
    }
    scores['vi'] = scores['vi']! + _diacriticWeight * vietTone;

    var best = 'en';
    var bestScore = 0.0;
    // Iterating in map order makes ties deterministic, with English first.
    scores.forEach((lang, score) {
      if (score > bestScore) {
        best = lang;
        bestScore = score;
      }
    });
    return best;
  }
}
