import 'position_mapper.dart';

/// Metadata detailing transformations applied during canonical normalization.
class NormalizationMetadata {
  final int invisibleCharactersRemoved;
  final int homoglyphsReplaced;
  final int smartQuotesStandardized;
  final int whitespaceSequencesCollapsed;
  final bool containsMarkdownSyntax;
  final bool containsHtmlTags;
  final int emDashCount;
  final int enDashCount;

  const NormalizationMetadata({
    required this.invisibleCharactersRemoved,
    this.homoglyphsReplaced = 0,
    required this.smartQuotesStandardized,
    required this.whitespaceSequencesCollapsed,
    required this.containsMarkdownSyntax,
    required this.containsHtmlTags,
    required this.emDashCount,
    required this.enDashCount,
  });
}

/// Result of normalizing a document while preserving bidirectional position mapping.
class NormalizedDocument {
  final String rawText;
  final String normalizedText;
  final PositionMapper mapper;
  final NormalizationMetadata metadata;

  const NormalizedDocument({
    required this.rawText,
    required this.normalizedText,
    required this.mapper,
    required this.metadata,
  });
}

/// Canonical normalization pipeline for Lauriva Forensic Content Intelligence Engine 3.0.
///
/// Converts arbitrary user input (containing smart punctuation, Markdown/HTML,
/// invisible zero-width characters, or chaotic whitespace) into a standardized representation
/// while tracking exact character offsets back to the raw source text.
class TextNormalizer {
  // Common invisible / zero-width characters often used in copy-paste or steganography
  static final Set<int> _invisibleCharCodes = {
    0x200B, // Zero-width space
    0x200C, // Zero-width non-joiner
    0x200D, // Zero-width joiner
    0xFEFF, // Zero-width no-break space / BOM
    0x202A, // Left-to-right embedding
    0x202B, // Right-to-left embedding
    0x202C, // Pop directional formatting
    0x202D, // Left-to-right override
    0x202E, // Right-to-left override
    0x2060, // Word joiner
    0x00AD, // Soft hyphen
  };

  static const Map<int, String> _homoglyphs = {
    0x0430: 'a', 0x0441: 'c', 0x0435: 'e', 0x0456: 'i', 0x0458: 'j',
    0x043E: 'o', 0x0440: 'p', 0x0455: 's', 0x0443: 'y', 0x0445: 'x',
    0x0410: 'A', 0x0412: 'B', 0x0421: 'C', 0x0415: 'E', 0x041D: 'H',
    0x0406: 'I', 0x0408: 'J', 0x041A: 'K', 0x041C: 'M', 0x041E: 'O',
    0x0420: 'P', 0x0422: 'T', 0x0425: 'X', 0x0423: 'Y',
    0x03B1: 'a', 0x03B5: 'e', 0x03B9: 'i', 0x03BF: 'o', 0x03C1: 'p',
    0x03C5: 'u', 0x03BD: 'v',
    0x0391: 'A', 0x0392: 'B', 0x0395: 'E', 0x0397: 'H', 0x0399: 'I',
    0x039A: 'K', 0x039C: 'M', 0x039D: 'N', 0x039F: 'O', 0x03A1: 'P',
    0x03A4: 'T', 0x03A7: 'X', 0x03A5: 'Y', 0x0396: 'Z',
  };

  /// Normalizes [rawText] into canonical representation with original position mapping.
  NormalizedDocument normalize(String rawText) {
    if (rawText.isEmpty) {
      return NormalizedDocument(
        rawText: '',
        normalizedText: '',
        mapper: PositionMapper.identity(0),
        metadata: const NormalizationMetadata(
          invisibleCharactersRemoved: 0,
          smartQuotesStandardized: 0,
          whitespaceSequencesCollapsed: 0,
          containsMarkdownSyntax: false,
          containsHtmlTags: false,
          emDashCount: 0,
          enDashCount: 0,
        ),
      );
    }

    final normBuffer = StringBuffer();
    final normToRaw = <int>[];

    int invisibleCount = 0;
    int homoglyphsCount = 0;
    int smartQuotesCount = 0;
    int collapsedSpacesCount = 0;
    int emDashCount = 0;
    int enDashCount = 0;

    bool lastWasSpace = false;

    for (int rawIdx = 0; rawIdx < rawText.length; rawIdx++) {
      final code = rawText.codeUnitAt(rawIdx);
      final char = rawText[rawIdx];

      // 1. Strip invisible / zero-width characters
      if (_invisibleCharCodes.contains(code)) {
        invisibleCount++;
        continue;
      }

      // 2. Canonicalize Cyrillic/Greek homoglyphs
      String targetChar = char;
      if (_homoglyphs.containsKey(code)) {
        targetChar = _homoglyphs[code]!;
        homoglyphsCount++;
      } else if (char == '\u2018' || char == '\u2019' || char == '\u201A' || char == '\u201B') {
        // 3. Normalize smart quotes
        targetChar = "'";
        smartQuotesCount++;
      } else if (char == '\u201C' || char == '\u201D' || char == '\u201E' || char == '\u201F') {
        targetChar = '"';
        smartQuotesCount++;
      } else if (char == '\u2014') {
        // Em dash
        emDashCount++;
        targetChar = '—';
      } else if (char == '\u2013') {
        // En dash
        enDashCount++;
        targetChar = '–';
      } else if (char == '\u00A0') {
        // Non-breaking space
        targetChar = ' ';
      }

      // 4. Line break canonicalization (\r\n -> \n)
      if (char == '\r') {
        if (rawIdx + 1 < rawText.length && rawText[rawIdx + 1] == '\n') {
          continue; // Skip \r in \r\n pair
        }
        targetChar = '\n';
      }

      // 5. Horizontal whitespace collapsing (preserves newlines)
      if (targetChar == ' ' || targetChar == '\t') {
        if (lastWasSpace) {
          collapsedSpacesCount++;
          continue;
        }
        targetChar = ' ';
        lastWasSpace = true;
      } else {
        lastWasSpace = false;
      }

      normBuffer.write(targetChar);
      normToRaw.add(rawIdx);
    }

    final normalized = normBuffer.toString();

    // 6. Detect Markdown & HTML features
    final containsMarkdown = RegExp(r'(^#{1,6}\s|\*{1,2}[^*]+\*{1,2}|_{1,2}[^_]+_{1,2}|\[[^\]]+\]\([^)]+\))', multiLine: true).hasMatch(rawText);
    final containsHtml = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(rawText);

    final mapper = PositionMapper.build(
      rawText: rawText,
      normalizedText: normalized,
      normToRawIndices: normToRaw,
    );

    return NormalizedDocument(
      rawText: rawText,
      normalizedText: normalized,
      mapper: mapper,
      metadata: NormalizationMetadata(
        invisibleCharactersRemoved: invisibleCount,
        homoglyphsReplaced: homoglyphsCount,
        smartQuotesStandardized: smartQuotesCount,
        whitespaceSequencesCollapsed: collapsedSpacesCount,
        containsMarkdownSyntax: containsMarkdown,
        containsHtmlTags: containsHtml,
        emDashCount: emDashCount,
        enDashCount: enDashCount,
      ),
    );
  }
}
