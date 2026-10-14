/// Sentence-aligned chunking for the T5 humanizer (<= [maxWords] per chunk).
///
/// The earlier length loss was truncation of long inputs at 256 tokens;
/// chunking before encoding removes it (tool/humanizer_release/README.md).
class T5Chunker {
  static final RegExp _boundary = RegExp(r'(?<=[.!?])["”\x27)\]]*\s+(?=[A-Z"“(\[])');

  static List<String> sentences(String text) {
    return text
        .trim()
        .split(_boundary)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Greedily packs whole sentences into chunks of at most [maxWords] words
  /// (a single longer sentence becomes its own chunk).
  static List<String> chunk(String text, {int maxWords = 50}) {
    final out = <String>[];
    var cur = <String>[];
    var n = 0;
    for (final s in sentences(text)) {
      final w = s.split(RegExp(r'\s+')).length;
      if (cur.isNotEmpty && n + w > maxWords) {
        out.add(cur.join(' '));
        cur = <String>[];
        n = 0;
      }
      cur.add(s);
      n += w;
    }
    if (cur.isNotEmpty) out.add(cur.join(' '));
    return out;
  }
}
