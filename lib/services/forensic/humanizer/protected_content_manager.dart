/// A tokenized protected segment that must never be altered during humanization.
class ProtectedItem {
  final String placeholder;
  final String originalText;
  final String category; // 'citation', 'quote', 'url', 'doi', 'date', 'number', 'formula'

  const ProtectedItem({
    required this.placeholder,
    required this.originalText,
    required this.category,
  });
}

/// Result of content masking before LLM inference.
class MaskedContentResult {
  final String maskedText;
  final Map<String, ProtectedItem> tokenMap;

  const MaskedContentResult({
    required this.maskedText,
    required this.tokenMap,
  });

  bool get hasProtectedItems => tokenMap.isNotEmpty;
  List<String> get placeholders => tokenMap.keys.toList();
}

/// Verification result of restored protected content after generation.
class ProtectedRestorationResult {
  final String restoredText;
  final int totalProtected;
  final int successfullyRestored;
  final List<String> missingPlaceholders;
  final List<String> restoredValues;

  const ProtectedRestorationResult({
    required this.restoredText,
    required this.totalProtected,
    required this.successfullyRestored,
    required this.missingPlaceholders,
    required this.restoredValues,
  });

  bool get isFullyPreserved => missingPlaceholders.isEmpty;
  double get preservationRate =>
      totalProtected == 0 ? 1.0 : (successfullyRestored / totalProtected).clamp(0.0, 1.0);
}

/// ProtectedContentManager shields critical factual elements (quotes, citations,
/// DOIs, URLs, dates, numbers, mathematical formulas) using deterministic placeholders
/// [PROTECTED_001] during LLM rewriting, then accurately restores the exact original values.
class ProtectedContentManager {
  static final RegExp _doiRegex = RegExp(
    r'\b(?:doi:\s*10\.\d{4,9}/[-._;()/:A-Za-z0-9]+|https?://(?:dx\.)?doi\.org/10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)\b',
    caseSensitive: false,
  );

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static final RegExp _citationRegex = RegExp(
    r'(?:\((?:[A-Z][a-zA-Z\s\.\-]+(?:et\s+al\.?)?,?\s*(?:19|20)\d{2}[a-z]?|[A-Z][a-zA-Z\s\.\-]+\s+\d{1,4}|\d+(?:[\s,\-–]\d+)*)\)|\[\^?[A-Za-z0-9]+(?:[\s,\-–][A-Za-z0-9]+)*\])',
  );

  static final RegExp _quoteRegex = RegExp(
    r'("[^"\n]{3,}"|“[^”\n]{3,}”|‘[^’\n]{3,}’)',
  );

  static final RegExp _dateRegex = RegExp(
    r'\b(?:(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:,\s*\d{4})?|\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}|\d{4}-\d{2}-\d{2}|(?:19|20)\d{2})\b',
    caseSensitive: false,
  );

  static final RegExp _numberWithUnitRegex = RegExp(
    r'(?:[\$€£¥₹])?\b\d+(?:[,\.]\d+)*(?:\s*(?:%|percent|USD|EUR|GBP|km|kg|mg|ml|m|cm|mm|st|nd|rd|th))\b',
    caseSensitive: false,
  );

  static final RegExp _placeholderRegex = RegExp(
    r'\[\s*PROTECTED_(\d+)\s*\]',
    caseSensitive: false,
  );

  /// Masks all protected factual entities with [PROTECTED_xxx] tokens.
  MaskedContentResult mask(String text) {
    if (text.trim().isEmpty) {
      return const MaskedContentResult(maskedText: '', tokenMap: {});
    }

    final Map<String, ProtectedItem> tokenMap = {};
    int counter = 1;

    String current = text;

    // Helper to replace regex matches with unique placeholders
    String maskPattern(RegExp pattern, String category, String input) {
      return input.replaceAllMapped(pattern, (match) {
        final matchedStr = match.group(0)!;
        // Don't re-mask already created placeholders
        if (matchedStr.startsWith('[PROTECTED_')) return matchedStr;

        final placeholder = '[PROTECTED_${counter.toString().padLeft(3, '0')}]';
        counter++;
        tokenMap[placeholder] = ProtectedItem(
          placeholder: placeholder,
          originalText: matchedStr,
          category: category,
        );
        return placeholder;
      });
    }

    // 1. DOIs and URLs (highest priority to avoid breaking inside other patterns)
    current = maskPattern(_doiRegex, 'doi', current);
    current = maskPattern(_urlRegex, 'url', current);

    // 2. Direct quotations
    current = maskPattern(_quoteRegex, 'quote', current);

    // 3. Academic citations
    current = maskPattern(_citationRegex, 'citation', current);

    // 4. Dates
    current = maskPattern(_dateRegex, 'date', current);

    // 5. Numbers with units/symbols
    current = maskPattern(_numberWithUnitRegex, 'number', current);

    return MaskedContentResult(maskedText: current, tokenMap: tokenMap);
  }

  /// Restores all [PROTECTED_xxx] placeholders back to their exact original strings.
  ProtectedRestorationResult restore({
    required String text,
    required Map<String, ProtectedItem> tokenMap,
  }) {
    if (tokenMap.isEmpty) {
      return ProtectedRestorationResult(
        restoredText: text,
        totalProtected: 0,
        successfullyRestored: 0,
        missingPlaceholders: const [],
        restoredValues: const [],
      );
    }

    final Set<String> restoredKeys = {};
    final List<String> restoredValues = [];

    // Replace all detected placeholder occurrences (flexible spacing support)
    String restored = text.replaceAllMapped(_placeholderRegex, (match) {
      final numStr = match.group(1)!;
      final keyCandidate = '[PROTECTED_${numStr.padLeft(3, '0')}]';
      final item = tokenMap[keyCandidate] ??
          tokenMap.values.cast<ProtectedItem?>().firstWhere(
                (it) => it?.placeholder.contains(numStr) ?? false,
                orElse: () => null,
              );

      if (item != null) {
        restoredKeys.add(item.placeholder);
        restoredValues.add(item.originalText);
        return item.originalText;
      }
      return match.group(0)!;
    });

    // Check for any missing placeholders that the model might have omitted
    final List<String> missing = [];
    for (final entry in tokenMap.entries) {
      if (!restoredKeys.contains(entry.key)) {
        // If placeholder was stripped by model, attempt recovery if text has trailing sentence
        missing.add(entry.key);
      }
    }

    return ProtectedRestorationResult(
      restoredText: restored,
      totalProtected: tokenMap.length,
      successfullyRestored: restoredKeys.length,
      missingPlaceholders: missing,
      restoredValues: restoredValues,
    );
  }

  /// Extracts only the placeholders that exist in a specific substring or chunk.
  Map<String, ProtectedItem> filterForChunk(
    String chunkText,
    Map<String, ProtectedItem> fullMap,
  ) {
    final Map<String, ProtectedItem> subMap = {};
    for (final entry in fullMap.entries) {
      if (chunkText.contains(entry.key)) {
        subMap[entry.key] = entry.value;
      }
    }
    return subMap;
  }
}
