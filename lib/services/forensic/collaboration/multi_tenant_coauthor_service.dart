import '../micro_authorship/micro_authorship_heatmap_service.dart';

/// Single contributor's authorship audit in a collaborative multi-tenant document.
class CoAuthorContribution {
  final String authorName;
  final String sectionTitle;
  final double personalQai; // 0.0 to 100.0%
  final int totalWords;
  final int humanWords;
  final int syntheticWords;

  const CoAuthorContribution({
    required this.authorName,
    required this.sectionTitle,
    required this.personalQai,
    required this.totalWords,
    required this.humanWords,
    required this.syntheticWords,
  });

  Map<String, dynamic> toJson() => {
        'authorName': authorName,
        'sectionTitle': sectionTitle,
        'personalQai': personalQai,
        'totalWords': totalWords,
        'humanWords': humanWords,
        'syntheticWords': syntheticWords,
      };
}

/// Service that decomposes multi-author collaborative enterprise/academic documents.
class MultiTenantCoAuthorService {
  final MicroAuthorshipHeatmapService _heatmapService = MicroAuthorshipHeatmapService();

  /// Decomposes [sections] mapped by author names into a collaborative provenance matrix.
  List<CoAuthorContribution> decompose({
    required Map<String, Map<String, String>> authorSections, // authorName -> { sectionTitle: text }
  }) {
    final results = <CoAuthorContribution>[];

    for (final authorEntry in authorSections.entries) {
      final authorName = authorEntry.key;
      for (final sectionEntry in authorEntry.value.entries) {
        final title = sectionEntry.key;
        final text = sectionEntry.value;

        final report = _heatmapService.analyze(text);
        final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final humanWords = (words * (report.quantifiedAuthorshipIndex / 100.0)).round();
        final syntheticWords = words - humanWords;

        results.add(
          CoAuthorContribution(
            authorName: authorName,
            sectionTitle: title,
            personalQai: report.quantifiedAuthorshipIndex,
            totalWords: words,
            humanWords: humanWords,
            syntheticWords: syntheticWords,
          ),
        );
      }
    }

    return results;
  }
}
