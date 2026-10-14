/// Shared word lists, regex patterns, and tokenization helpers used by every
/// text-forensics service (`PlagiarismDetectorService`'s v1 classifier,
/// `AiForensicService`'s v2 ensemble, and `SourcePlagiarismService`).
///
/// These used to be independently copy-pasted into all three files, which
/// meant updating one signal (e.g. adding a stock AI word) silently missed
/// the other two — a real drift risk with no compiler warning. Single source
/// of truth now; update here and every service picks it up.
class TextForensicsLexicons {
  TextForensicsLexicons._();

  /// Common academic & web boilerplate phrases indicating unoriginal /
  /// formulaic writing.
  static const List<String> academicBoilerplates = [
    "in today's fast-paced world",
    "in today's digital era",
    "it is widely acknowledged that",
    "plays a crucial role in",
    "plays a pivotal role in",
    "plays an instrumental role in",
    "in light of the recent",
    "since the dawn of time",
    "it is important to note that",
    "it is worth noting that",
    "it is crucial to recognize that",
    "it is essential to recognize that",
    "on the other hand",
    "as mentioned earlier",
    "sheds light on the",
    "has a significant impact on",
    "at the end of the day",
    "taking everything into account",
    "in conclusion, it can be said that",
    "a wide array of",
    "a diverse range of",
    "it is crucial to understand",
    "when it comes to",
    "in the realm of",
    "in the world of",
    "navigating the complexities of",
    "cannot be overstated",
    "serves as a",
    "stands as a testament to",
    "serves as a testament to",
    "in the ever-evolving landscape",
    "paving the way for",
    "paves the way for",
    "setting the stage for",
    "a multifaceted approach",
    "delves into the complexities",
    "at the forefront of",
    "at this point in time",
    "taking into consideration",
    "it is important to remember that",
    "serves as a stark reminder",
    "lies at the intersection of",
    "bears witness to",
    "in stark contrast to",
    "plays an active role in",
    "plays an integral part in",
    "with that being said",
    "at its core",
    "a testament to the fact that",
    "unlocks new possibilities",
    "stands poised to",
    "catalyst for change",
    "groundbreaking innovation",
    "pave the way for a brighter future",
    "paves the way for a brighter future",
    "paving the way for a brighter future",
    "stands at the forefront of innovation",
    "an integral part of the equation",
    "serves as a cornerstone for",
    "lies at the heart of",
    "lies at the core of",
    "poised to revolutionize",
    "poised to reshape",
    "garnered significant attention",
    "unravel the complexities",
    "embark on this journey",
    "foster meaningful connections",
    "indelible mark",
    "testament to the enduring power",
    "at the nexus of",
    "a crucial dimension of",
    "from a broader perspective",
    "fundamentally speaking",
    "serves as a catalyst for",
    "plays an indispensable role",
    "a holistic understanding of",
    "navigating the delicate balance between",
    "it is crucial to emphasize that",
    "a profound transformation in",
    "it stands to reason that",
    // ── Empirical Kaggle DAIGT Overrepresented AI Bigrams & Trigrams ──────
    "important to consider",
    "to ensure that",
    "it is essential to",
    "is essential for",
    "in the face of",
    "has the potential to",
    "when faced with",
    "benefits and drawbacks",
    "research has shown that",
    "can be incredibly",
    "potential drawbacks",
    "mindful of the fact",
    "pros and cons of",
    "foster a sense of",
    "a variety of advantages and disadvantages",
    "on the one hand",
    "vital to recognize that",
    "an invaluable tool",
    "informed decisions",
    "personal growth",
    "academic performance",
    "can lead to a",
    "can help to",
    "this can lead to",
    "this can help",
    "this means that",
    "in this essay",
    "one of the primary reasons",
    "one of the main reasons",
    "while some may argue",
    "while it is true that",
    "another advantage of",
    "a wide range of benefits",
    "create an environment conducive to",
  ];

  /// Formal connector/transition words LLMs default to far more often than
  /// natural human prose does when opening a sentence — human writers vary
  /// sentence openers; models lean on a small, formal connector vocabulary.
  static const List<String> transitionOpeners = [
    'however',
    'moreover',
    'furthermore',
    'additionally',
    'in addition',
    'nevertheless',
    'nonetheless',
    'consequently',
    'therefore',
    'hence',
    'notably',
    'importantly',
    'crucially',
    'fundamentally',
    'ultimately',
    'overall',
    'conversely',
    'meanwhile',
    'in summary',
    'in conclusion',
    'as a result',
    'firstly',
    'secondly',
    'thirdly',
    'in particular',
    'on the other hand',
    'on the one hand',
    'this means that',
    'this can lead',
    'this can help',
  ];

  /// Stock AI vocabulary (curated from Wikipedia's "Signs of AI Writing",
  /// Kaggle DAIGT competition corpora & LLM evaluations).
  static const Set<String> aiStockWords = {
    'delve', 'delves', 'delved', 'delving', 'tapestry', 'tapestries', 'pivotal',
    'testament', 'interplay', 'intricate', 'intricacies', 'vibrant', 'foster',
    'fosters', 'fostered', 'fostering', 'crucial', 'crucially', 'robust', 'bolster',
    'bolsters', 'bolstered', 'bolstering', 'meticulous', 'meticulously',
    'showcase', 'showcases', 'showcased', 'showcasing', 'underscore',
    'underscores', 'underscored', 'underscoring', 'multifaceted', 'paramount',
    'beacon', 'enduring', 'seamlessly', 'seamless', 'groundbreaking',
    'plethora', 'navigate', 'navigates', 'navigated', 'navigating', 'unpack',
    'unpacks', 'unpacked', 'unpacking', 'holistic', 'underpin', 'underpins',
    'underpinned', 'unlock', 'unlocks', 'unlocked', 'unlocking', 'unleash',
    'unleashes', 'unleashed', 'elevate', 'elevates', 'elevated', 'elevating',
    'empower', 'empowers', 'empowered', 'empowering', 'streamline',
    'streamlines', 'streamlined', 'streamlining', 'landscape', 'realm',
    'invaluable', 'indelible', 'garner', 'garnered', 'garnering', 'harness',
    'harnesses', 'harnessed', 'harnessing', 'unravel', 'unravels', 'unraveled',
    'unraveling', 'embark', 'embarks', 'embarked', 'embarking', 'cornerstone',
    'cornerstones', 'transformative', 'nuanced', 'paradigm', 'paradigms',
    'synergy', 'synergies', 'spearhead', 'spearheads', 'spearheaded',
    'spearheading', 'myriad', 'burgeoning', 'actionable', 'demystify',
    'demystifies', 'demystifying', 'resonate', 'resonates', 'resonating',
    'poised', 'utilize', 'utilizes', 'utilized', 'utilizing', 'utilization',
    'leverage', 'leverages', 'leveraged', 'leveraging', 'catalyst', 'catalysts',
    'epitome', 'quintessential', 'commendable', 'bustling', 'nestled',
    'nexus', 'bedrock', 'linchpin', 'overarching', 'profoundly', 'instrumental',
    // Kaggle DAIGT empirical overrepresented markers
    'detrimental', 'wellbeing', 'autonomy', 'resilient', 'adversity',
    'mindful', 'drawbacks', 'increasingly', 'mitigate',
    'mitigates', 'mitigating', 'substantial', 'substantially', 'contemporary',
    'thereby',
  };

  /// Common function words — their relative frequency is a classic
  /// authorship/style signal independent of topic.
  static const Set<String> functionWords = {
    'the', 'a', 'an', 'of', 'to', 'in', 'and', 'is', 'are', 'was', 'were',
    'it', 'that', 'this', 'as', 'on', 'for', 'with', 'at', 'by', 'be',
    'have', 'has', 'had', 'but', 'or', 'not', 'from', 'we', 'you', 'they',
    'which', 'would', 'there', 'their', 'what', 'so', 'up', 'out', 'if',
  };

  /// Em dash (or double-hyphen standing in for one) between word characters —
  /// the single most-cited modern LLM stylistic tic (interruptive/appositive
  /// dashes standing in for commas or parentheses).
  static final RegExp emDashPattern = RegExp(r'—|(?<=[a-zA-Z])--(?=[a-zA-Z])');

  /// Markdown syntax (bullets, numbered lists, headers) bleeding into plain
  /// prose — a tell that raw model output was pasted without cleanup.
  static final RegExp markdownBlockPattern = RegExp(
    r'(^|\n)\s*(?:[-*•]\s+|\d+\.\s+|#{1,6}\s+)',
    multiLine: true,
  );

  /// Bold markdown asterisks bleeding into plain prose.
  static final RegExp markdownBoldPattern = RegExp(r'\*\*[^*\n]+\*\*');

  /// Splits [text] into sentences, avoiding common abbreviations, and
  /// recognizing both straight and curly opening quotes.
  ///
  /// Besides Latin terminators it recognises the Devanagari/Bengali danda
  /// (।, ॥), Arabic/Urdu question mark and full stop (؟, ۔) and the CJK
  /// full-width terminators (。！？), which need no following space. The next
  /// sentence may start with any uppercase letter or with a letter of a
  /// caseless script (Arabic, Indic, CJK, Hangul), so non-Latin text splits too.
  static List<String> splitSentences(String text) {
    final rawSplits = text.split(_sentenceBoundary);
    final results = <String>[];
    for (final s in rawSplits) {
      final trimmed = s.trim();
      if (trimmed.isNotEmpty) {
        results.add(trimmed);
      }
    }
    return results;
  }

  /// Extracts alphanumeric word tokens (including internal apostrophes,
  /// e.g. "don't") from [text].
  ///
  /// Tokens are Unicode letters (with combining marks, needed by Indic
  /// scripts) and decimal digits, so every Studio language yields words, not
  /// only ASCII text. Han and kana are written without spaces and have no
  /// cheap word segmentation, so each such character is its own unit
  /// (a morpheme-sized token; Chinese words average ~1.5 characters). Pure
  /// ASCII input tokenises exactly as before.
  static List<String> extractWords(String text) {
    final words = <String>[];
    for (final m in _wordPattern.allMatches(text)) {
      final w = m.group(0)!;
      if (!_hasSpacelessScript(w)) {
        words.add(w);
        continue;
      }
      final run = StringBuffer();
      for (final rune in w.runes) {
        if (isSpacelessScriptRune(rune)) {
          if (run.isNotEmpty) {
            words.add(run.toString());
            run.clear();
          }
          words.add(String.fromCharCode(rune));
        } else {
          run.writeCharCode(rune);
        }
      }
      if (run.isNotEmpty) words.add(run.toString());
    }
    return words;
  }

  /// Number of word units in [text]: whitespace-separated tokens, except that
  /// inside tokens written in a space-less script (Han, kana) every character
  /// counts as one unit, consistent with [extractWords].
  static int countWordUnits(String text) {
    var count = 0;
    for (final token in text.split(_whitespace)) {
      if (token.isEmpty) continue;
      if (!_hasSpacelessScript(token)) {
        count++;
        continue;
      }
      var inRun = false;
      for (final rune in token.runes) {
        if (isSpacelessScriptRune(rune)) {
          count++;
          inRun = false;
        } else if (_isWordChar(rune)) {
          if (!inRun) count++;
          inRun = true;
        } else {
          inRun = false;
        }
      }
    }
    return count;
  }

  /// True for Han ideographs and Japanese kana: scripts written without
  /// spaces between words.
  static bool isSpacelessScriptRune(int rune) =>
      (rune >= 0x3040 && rune <= 0x30FF) || // Hiragana, Katakana
      (rune >= 0x31F0 && rune <= 0x31FF) || // Katakana phonetic extensions
      (rune >= 0x3400 && rune <= 0x4DBF) || // CJK extension A
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified ideographs
      (rune >= 0xF900 && rune <= 0xFAFF) || // CJK compatibility ideographs
      (rune >= 0xFF66 && rune <= 0xFF9F) || // Half-width katakana
      (rune >= 0x20000 && rune <= 0x2FA1F); // CJK extensions B+

  static bool _hasSpacelessScript(String s) {
    for (final unit in s.codeUnits) {
      // Everything space-less lives at or above U+3040 (or in surrogates).
      if (unit >= 0x3040) return s.runes.any(isSpacelessScriptRune);
    }
    return false;
  }

  static bool _isWordChar(int rune) => _wordChar.hasMatch(String.fromCharCode(rune));

  static final RegExp _wordPattern =
      RegExp(r"[\p{L}\p{M}\p{Nd}]+(?:'[\p{L}\p{M}\p{Nd}]+)?", unicode: true);
  static final RegExp _wordChar = RegExp(r'[\p{L}\p{M}\p{Nd}]', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _sentenceBoundary = RegExp(
    r'(?<=[.!?।॥؟۔])\s+(?=[\p{Lu}\p{Lo}0-9"\x27“‘«])|(?<=[。！？])\s*(?=\S)|\n+',
    unicode: true,
  );

  /// Extracts lowercase [n]-word sliding-window n-grams from [words].
  static List<String> extractNgrams(List<String> words, int n) {
    if (words.length < n) return const [];
    final ngrams = <String>[];
    for (int i = 0; i <= words.length - n; i++) {
      ngrams.add(words.sublist(i, i + n).join(' ').toLowerCase());
    }
    return ngrams;
  }

  /// Returns a display-ready `"$ngram ($count times)"` entry for every
  /// n-gram in [ngrams] that occurs more than once.
  static List<String> findRepeatedNgrams(List<String> ngrams) {
    final counts = <String, int>{};
    for (final ng in ngrams) {
      counts[ng] = (counts[ng] ?? 0) + 1;
    }
    final repeated = <String>[];
    counts.forEach((ngram, count) {
      if (count > 1) {
        repeated.add('$ngram ($count times)');
      }
    });
    return repeated;
  }
}
