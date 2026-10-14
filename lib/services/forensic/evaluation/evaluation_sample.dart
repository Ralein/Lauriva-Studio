/// Represents a single labeled sample in the Lauriva empirical evaluation benchmark.
class EvaluationSample {
  final String id;
  final String text;
  final bool isAi; // Ground truth: true = AI-generated, false = Human-authored
  final String domain; // academic, technical, journalism, esl, fiction, legal, informal
  final String generator; // human, gpt4o, claude35, gemini20, deepseek_r1, llama33, mistral, command_r, qwen
  final String transformation; // raw, human_edited, paraphrased, humanized, back_translated, mixed_paragraph
  final int wordCount;
  final String sourceType; // human, ai, transformed, mixed
  final String authorType; // academic, informal, technical, esl, personal, llm, mixed
  final String generationModel; // none, gpt4o, claude35, gemini20, deepseek_r1, llama33, mistral, command_r, qwen
  final String documentLength; // short, medium, long
  final String language; // en, etc.
  final String split; // train, validation, test, hard_test
  final Map<String, dynamic> metadata;

  const EvaluationSample({
    required this.id,
    required this.text,
    required this.isAi,
    required this.domain,
    required this.generator,
    this.transformation = 'raw',
    this.wordCount = 0,
    String? sourceType,
    String? authorType,
    String? generationModel,
    String? documentLength,
    this.language = 'en',
    this.split = 'validation',
    this.metadata = const {},
  })  : sourceType = sourceType ?? (isAi ? 'ai' : 'human'),
        authorType = authorType ?? (isAi ? 'llm' : domain),
        generationModel = generationModel ?? (isAi ? generator : 'none'),
        documentLength = documentLength ?? (wordCount < 150 ? 'short' : (wordCount < 600 ? 'medium' : 'long'));

  factory EvaluationSample.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    final calculatedWordCount = (json['wordCount'] as int?) ??
        (json['word_count'] as int?) ??
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final isAi = json['isAi'] as bool? ??
        (json['label'] == 'ai' || json['label'] == 1 || json['is_ai'] == true);
    final domain = json['domain'] as String? ?? 'general';
    final generator = json['generator'] as String? ??
        (isAi ? 'ai_unknown' : 'human');

    return EvaluationSample(
      id: json['id'] as String? ?? 'sample_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      isAi: isAi,
      domain: domain,
      generator: generator,
      transformation: json['transformation'] as String? ??
          json['transform'] as String? ??
          'raw',
      wordCount: calculatedWordCount,
      sourceType: json['source_type'] as String? ??
          json['sourceType'] as String?,
      authorType: json['author_type'] as String? ??
          json['authorType'] as String?,
      generationModel: json['generation_model'] as String? ??
          json['generationModel'] as String?,
      documentLength: json['document_length'] as String? ??
          json['documentLength'] as String?,
      language: json['language'] as String? ?? 'en',
      split: json['split'] as String? ?? 'validation',
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isAi': isAi,
        'domain': domain,
        'generator': generator,
        'transformation': transformation,
        'wordCount': wordCount,
        'source_type': sourceType,
        'author_type': authorType,
        'generation_model': generationModel,
        'document_length': documentLength,
        'language': language,
        'split': split,
        'metadata': metadata,
      };
}
