import 'semantic_preservation_verifier.dart';

/// Per-chunk safety checks for T5 output (verified policy, see
/// tool/humanizer_release/README.md): length 0.80-1.30x, exact negation-count
/// parity, numbers and citations preserved. A chunk that fails keeps its source.
class T5GuardResult {
  final double lengthRatio;
  final bool lengthOk;
  final bool negationOk;
  final bool numbersOk;
  final bool citationsOk;
  final bool repetitionOk;

  const T5GuardResult({
    required this.lengthRatio,
    required this.lengthOk,
    required this.negationOk,
    required this.numbersOk,
    required this.citationsOk,
    this.repetitionOk = true,
  });

  bool get passed => lengthOk && negationOk && numbersOk && citationsOk && repetitionOk;

  /// First failing guard, for logging/tests.
  String? get failure {
    if (!lengthOk) return 'length';
    if (!negationOk) return 'negation';
    if (!numbersOk) return 'numbers';
    if (!citationsOk) return 'citations';
    if (!repetitionOk) return 'repetition';
    return null;
  }
}

class T5Guards {
  static const double minLengthRatio = 0.80;
  static const double maxLengthRatio = 1.30;

  // No trailing \b: it would stop "5%" from matching (both sides non-word), so
  // "5 percent" -> "5%" reformatting must compare equal after canonicalization.
  static final RegExp _number = RegExp(r'[\$€£¥₹]?\b\d+(?:[,\.]\d+)*(?:%|\s*per\s?cent\b)?', caseSensitive: false);
  static final RegExp _bracketCitation = RegExp(r'\[\d+(?:\s*[,–-]\s*\d+)*\]');
  static final RegExp _authorYear = RegExp(r'\([A-Z][A-Za-z\-]+(?:\s+(?:et al\.?|and|&)\s*[A-Z]?[A-Za-z\-]*)?,?\s+\d{4}[a-z]?\)');

  static T5GuardResult check(String source, String output) {
    final srcWords = _words(source);
    final outWords = _words(output);
    final ratio = srcWords == 0 ? 1.0 : outWords / srcWords;
    return T5GuardResult(
      lengthRatio: ratio,
      lengthOk: ratio >= minLengthRatio && ratio <= maxLengthRatio,
      negationOk: SemanticPreservationVerifier.countNegations(source) == SemanticPreservationVerifier.countNegations(output),
      numbersOk: numbers(source).difference(numbers(output)).isEmpty,
      citationsOk: _citations(source).difference(_citations(output)).isEmpty,
      repetitionOk: !degenerates(source, output),
    );
  }

  /// Degeneration check (added after the first on-device goldens produced
  /// "The tumour was found in the tumour in the early stages of the tumour."):
  /// rejects an output that repeats a word-trigram, or uses a content word
  /// (>= 5 letters) three or more times when the source used it at most once.
  /// Not part of the 60-chunk policy evaluation; it can only make output safer.
  static bool degenerates(String source, String output) {
    final out = _tokens(output);
    final seen = <String>{};
    for (var i = 0; i + 3 <= out.length; i++) {
      if (!seen.add('${out[i]} ${out[i + 1]} ${out[i + 2]}')) return true;
    }
    final src = <String, int>{};
    for (final w in _tokens(source)) {
      src.update(w, (v) => v + 1, ifAbsent: () => 1);
    }
    final counts = <String, int>{};
    for (final w in out) {
      if (w.length >= 5) counts.update(w, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts.entries.any((e) => e.value >= 3 && (src[e.key] ?? 0) <= 1);
  }

  static List<String> _tokens(String s) => RegExp(r"[A-Za-z']+").allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

  static int _words(String s) {
    final t = s.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  /// Canonical number tokens ("1,200" == "1200", "5 percent" == "5%").
  static Set<String> numbers(String text) {
    // Citation spans are compared separately (and "[1,2]" must not parse as the number "1,2").
    final bare = text.replaceAll(_bracketCitation, ' ').replaceAll(_authorYear, ' ');
    return {
      for (final m in _number.allMatches(bare)) _canon(m.group(0)!),
    };
  }

  static String _canon(String raw) {
    var k = raw.toLowerCase().replaceAll(RegExp(r'\s'), '').replaceAll(RegExp(r'[\$€£]'), '');
    k = k.replaceAll(RegExp(r'percent|per\s?cent'), '%');
    if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?').hasMatch(k)) k = k.replaceAll(',', '');
    return k;
  }

  static Set<String> _citations(String text) => {
        for (final m in _bracketCitation.allMatches(text)) m.group(0)!.replaceAll(RegExp(r'\s'), ''),
        for (final m in _authorYear.allMatches(text)) m.group(0)!.replaceAll(RegExp(r'\s+'), ' '),
      };
}
