/// A repeated n-gram or word sequence inside the same document.
class RepeatedSequenceItem {
  final String sequence;
  final int occurrenceCount;
  final int tokenLength;
  final List<int> startOffsets;

  const RepeatedSequenceItem({
    required this.sequence,
    required this.occurrenceCount,
    required this.tokenLength,
    this.startOffsets = const [],
  });

  factory RepeatedSequenceItem.fromJson(Map<String, dynamic> json) =>
      RepeatedSequenceItem(
        sequence: json['sequence'] as String,
        occurrenceCount: (json['occurrenceCount'] as num).toInt(),
        tokenLength: (json['tokenLength'] as num).toInt(),
        startOffsets: (json['startOffsets'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'sequence': sequence,
        'occurrenceCount': occurrenceCount,
        'tokenLength': tokenLength,
        'startOffsets': startOffsets,
      };
}

/// A recurring syntactic or rhetorical sentence template.
class RepeatedTemplateItem {
  final String templatePattern;
  final int occurrenceCount;
  final List<String> matchingSentences;

  const RepeatedTemplateItem({
    required this.templatePattern,
    required this.occurrenceCount,
    required this.matchingSentences,
  });

  factory RepeatedTemplateItem.fromJson(Map<String, dynamic> json) =>
      RepeatedTemplateItem(
        templatePattern: json['templatePattern'] as String,
        occurrenceCount: (json['occurrenceCount'] as num).toInt(),
        matchingSentences: (json['matchingSentences'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'templatePattern': templatePattern,
        'occurrenceCount': occurrenceCount,
        'matchingSentences': matchingSentences,
      };
}

/// Independent forensic evidence measuring internal phrase repetition,
/// formulaic looping, and structural boilerplate within the document.
class InternalRepetitionEvidence {
  final double repetitionScore; // 0.0 to 100.0
  final double lexicalRichness; // 0.0 to 100.0
  final List<String> repeatedNgrams;
  final List<RepeatedSequenceItem> repeatedSequences;
  final List<RepeatedTemplateItem> repeatedTemplates;
  final List<String> flaggedBoilerplates;
  final String defensibleSummary;

  const InternalRepetitionEvidence({
    required this.repetitionScore,
    required this.lexicalRichness,
    this.repeatedNgrams = const [],
    this.repeatedSequences = const [],
    this.repeatedTemplates = const [],
    this.flaggedBoilerplates = const [],
    required this.defensibleSummary,
  });

  const InternalRepetitionEvidence.clean()
      : repetitionScore = 0.0,
        lexicalRichness = 100.0,
        repeatedNgrams = const [],
        repeatedSequences = const [],
        repeatedTemplates = const [],
        flaggedBoilerplates = const [],
        defensibleSummary = 'Natural vocabulary distribution with healthy syntactic variety.';

  factory InternalRepetitionEvidence.fromJson(Map<String, dynamic> json) =>
      InternalRepetitionEvidence(
        repetitionScore: (json['repetitionScore'] as num).toDouble(),
        lexicalRichness: (json['lexicalRichness'] as num).toDouble(),
        repeatedNgrams: (json['repeatedNgrams'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        repeatedSequences: (json['repeatedSequences'] as List<dynamic>? ?? [])
            .map((s) => RepeatedSequenceItem.fromJson(s as Map<String, dynamic>))
            .toList(),
        repeatedTemplates: (json['repeatedTemplates'] as List<dynamic>? ?? [])
            .map((t) => RepeatedTemplateItem.fromJson(t as Map<String, dynamic>))
            .toList(),
        flaggedBoilerplates: (json['flaggedBoilerplates'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        defensibleSummary: json['defensibleSummary'] as String,
      );

  Map<String, dynamic> toJson() => {
        'repetitionScore': repetitionScore,
        'lexicalRichness': lexicalRichness,
        'repeatedNgrams': repeatedNgrams,
        'repeatedSequences': repeatedSequences.map((s) => s.toJson()).toList(),
        'repeatedTemplates': repeatedTemplates.map((t) => t.toJson()).toList(),
        'flaggedBoilerplates': flaggedBoilerplates,
        'defensibleSummary': defensibleSummary,
      };
}
