/// Maps character offsets bidirectionally between raw original text and normalized text.
///
/// Ensures that highlights, sentence heatmaps, and evidence spans computed over
/// normalized tokens/characters always highlight the exact corresponding range
/// in the user's raw input canvas.
class PositionMapper {
  /// `_rawToNorm[i]` contains the normalized index corresponding to raw character `i`.
  /// Value is -1 if raw character `i` was dropped (e.g., zero-width space stripped).
  final List<int> _rawToNorm;

  /// `_normToRaw[j]` contains the raw index corresponding to normalized character `j`.
  final List<int> _normToRaw;

  final int rawLength;
  final int normalizedLength;

  const PositionMapper._({
    required List<int> rawToNorm,
    required List<int> normToRaw,
    required this.rawLength,
    required this.normalizedLength,
  })  : _rawToNorm = rawToNorm,
        _normToRaw = normToRaw;

  /// Builds a position mapper by tracking character-by-character transformations.
  factory PositionMapper.build({
    required String rawText,
    required String normalizedText,
    required List<int> normToRawIndices,
  }) {
    final rawLen = rawText.length;
    final normLen = normalizedText.length;

    final rawToNorm = List<int>.filled(rawLen, -1);
    for (int normIdx = 0; normIdx < normToRawIndices.length; normIdx++) {
      final rawIdx = normToRawIndices[normIdx];
      if (rawIdx >= 0 && rawIdx < rawLen) {
        if (rawToNorm[rawIdx] == -1) {
          rawToNorm[rawIdx] = normIdx;
        }
      }
    }

    // Fill in dropped indices with nearest valid normalized index
    int lastValidNorm = 0;
    for (int rawIdx = 0; rawIdx < rawLen; rawIdx++) {
      if (rawToNorm[rawIdx] != -1) {
        lastValidNorm = rawToNorm[rawIdx];
      } else {
        rawToNorm[rawIdx] = lastValidNorm;
      }
    }

    return PositionMapper._(
      rawToNorm: rawToNorm,
      normToRaw: normToRawIndices,
      rawLength: rawLen,
      normalizedLength: normLen,
    );
  }

  /// Identity mapper when normalized text matches raw text identically.
  factory PositionMapper.identity(int length) {
    final list = List<int>.generate(length, (i) => i);
    return PositionMapper._(
      rawToNorm: List<int>.from(list),
      normToRaw: List<int>.from(list),
      rawLength: length,
      normalizedLength: length,
    );
  }

  /// Converts a character index from normalized text space to raw source space.
  int toRawOffset(int normalizedOffset) {
    if (_normToRaw.isEmpty) return 0;
    if (normalizedOffset <= 0) return 0;
    if (normalizedOffset >= _normToRaw.length) return rawLength;
    return _normToRaw[normalizedOffset];
  }

  /// Converts a character index from raw source space to normalized text space.
  int toNormalizedOffset(int rawOffset) {
    if (_rawToNorm.isEmpty) return 0;
    if (rawOffset <= 0) return 0;
    if (rawOffset >= _rawToNorm.length) return normalizedLength;
    return _rawToNorm[rawOffset];
  }

  /// Converts a normalized character span `[normStart, normEnd)` into raw character offsets.
  (int rawStart, int rawEnd) mapSpan(int normStart, int normEnd) {
    final safeStart = normStart.clamp(0, normalizedLength);
    final safeEnd = normEnd.clamp(safeStart, normalizedLength);

    final rawStart = toRawOffset(safeStart);
    final rawEnd = safeEnd >= normalizedLength
        ? rawLength
        : toRawOffset(safeEnd).clamp(rawStart, rawLength);

    return (rawStart, rawEnd);
  }
}
