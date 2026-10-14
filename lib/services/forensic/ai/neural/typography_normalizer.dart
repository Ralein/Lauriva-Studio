/// Maps smart punctuation to ASCII before neural inference.
///
/// Smart punctuation is not authorship evidence: LLMs emit curly quotes and
/// non-breaking hyphens, but so do phone keyboards and word processors.
/// Models trained on normalized text (NeuralModelConfig.normalizeTypography)
/// must see normalized text at inference too. Every mapping is one UTF-16
/// code unit to one, so sentence and token offsets stay valid.
///
/// Mirrors tool/eval/typography.py; keep in sync.
class TypographyNormalizer {
  const TypographyNormalizer._();

  static final Map<int, int> _map = {
    for (final c in '‘’‚‛′´`'.codeUnits) c: 0x27, // '
    for (final c in '“”„‟″'.codeUnits) c: 0x22, // "
    for (final c in '‐‑‒–—―−'.codeUnits) c: 0x2d, // -
    for (final c in '       '.codeUnits) c: 0x20, // space
  };

  static String normalize(String text) {
    final units = text.codeUnits;
    var changed = false;
    final out = List<int>.generate(units.length, (i) {
      final mapped = _map[units[i]];
      if (mapped == null) return units[i];
      changed = true;
      return mapped;
    });
    return changed ? String.fromCharCodes(out) : text;
  }
}
