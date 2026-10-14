/// Vocabulary/segmentation algorithm a detector was trained with.
enum NeuralTokenizerType {
  /// BERT WordPiece (`vocab.txt`), the English detectors.
  wordpiece,

  /// SentencePiece Unigram (exported by tool/export_sentencepiece_vocab.py),
  /// the multilingual XLM-R-family detectors.
  sentencepiece,

  /// Byte-level BPE (HF `tokenizer.json`), the ModernBERT-based Omni detector.
  bpe;

  static NeuralTokenizerType fromName(String? name) => NeuralTokenizerType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => NeuralTokenizerType.wordpiece,
      );
}

/// Configuration parameters for on-device Neural Transformer Detectors.
class NeuralModelConfig {
  final String modelVersion;
  final String modelAsset;
  final String vocabularyAsset;
  final String? localFilePath;
  final int maxSequenceLength;
  final int expectedVocabularySize;
  final String architecture;
  final String quantization;
  final String unkToken;
  final String clsToken;
  final String sepToken;
  final String padToken;
  final Map<String, String> inputNames;
  final Map<String, String> outputNames;

  /// Whether the model was trained on typography-normalized text
  /// (TypographyNormalizer); inference must then normalize too.
  final bool normalizeTypography;

  /// Tokenizer that reads [vocabularyAsset].
  final NeuralTokenizerType tokenizerType;

  /// Language codes (as returned by `LanguageDetector.detect`) the model was
  /// trained and calibrated on; other languages skip the neural stream.
  final Set<String> supportedLanguages;

  /// Multilingual MiniLM-L6 detector (v6). Not bundled in the app: the ONNX
  /// (~108 MB) and its tokenizer vocab are delivered on demand through
  /// ModelDeliveryService, so neither asset is listed in pubspec.yaml and
  /// loading falls back to the fallback tokenizer / stylometry until installed.
  ///
  /// Tokenizer: XLM-R SentencePiece Unigram (250,002 ids, identical to HF
  /// `xlm-roberta-base`; vocab exported by tool/export_sentencepiece_vocab.py).
  /// The ONNX embedding has 250,037 rows, a superset of the tokenizer ids.
  static const NeuralModelConfig v6Sota = NeuralModelConfig(
    modelVersion: 'plagiarism_v6_sota',
    modelAsset: 'assets/models/lauvira_plagiarism_v6_l6_int8.onnx',
    vocabularyAsset: 'assets/models/sentencepiece_unigram.txt',
    maxSequenceLength: 256,
    expectedVocabularySize: 250002,
    architecture: 'multilingual-minilm-l6-dual-head',
    quantization: 'int8',
    tokenizerType: NeuralTokenizerType.sentencepiece,
    inputNames: {
      'input_ids': 'input_ids',
      'attention_mask': 'attention_mask',
    },
    outputNames: {
      'logits': 'logits',
      'attribution_logits': 'attribution_logits',
    },
    supportedLanguages: {
      'en', 'es', 'fr', 'de', 'zh', 'ar', 'ru', 'pt', 'ja', 'it',
    },
  );

  static const NeuralModelConfig v7Omni = NeuralModelConfig(
    modelVersion: 'omni_p3_int8',
    modelAsset: 'assets/models/lauvira_omni_detector.onnx',
    vocabularyAsset: 'assets/models/omni_tokenizer.json',
    tokenizerType: NeuralTokenizerType.bpe,
    maxSequenceLength: 512,
    expectedVocabularySize: 50368,
    architecture: 'modernbert-8k-dual-head',
    quantization: 'int4_awp_sota',
    inputNames: {
      'input_ids': 'input_ids',
      'attention_mask': 'attention_mask',
    },
    outputNames: {
      'logits': 'logits',
      'attribution_logits': 'attribution_logits',
    },
    // English-only: the held-out evaluation only covers English, so no wider
    // coverage is claimed even though the BPE vocabulary is multilingual-safe.
    supportedLanguages: {'en'},
  );

  const NeuralModelConfig({
    this.modelVersion = 'omni_p3_int8',
    this.modelAsset = 'assets/models/lauvira_omni_detector.onnx',
    this.vocabularyAsset = 'assets/models/vocab.txt',
    this.localFilePath,
    this.maxSequenceLength = 512,
    this.expectedVocabularySize = 30522,
    this.architecture = 'distilled-transformer',
    this.quantization = 'int8',
    this.unkToken = '[UNK]',
    this.clsToken = '[CLS]',
    this.sepToken = '[SEP]',
    this.padToken = '[PAD]',
    this.inputNames = const {
      'input_ids': 'input_ids',
      'attention_mask': 'attention_mask',
      'token_type_ids': 'token_type_ids',
    },
    this.outputNames = const {
      'logits': 'logits',
    },
    this.normalizeTypography = true,
    this.tokenizerType = NeuralTokenizerType.wordpiece,
    this.supportedLanguages = const {'en'},
  });

  NeuralModelConfig copyWith({
    String? modelVersion,
    String? modelAsset,
    String? vocabularyAsset,
    String? localFilePath,
    int? maxSequenceLength,
    int? expectedVocabularySize,
    String? architecture,
    String? quantization,
    String? unkToken,
    String? clsToken,
    String? sepToken,
    String? padToken,
    Map<String, String>? inputNames,
    Map<String, String>? outputNames,
    bool? normalizeTypography,
    NeuralTokenizerType? tokenizerType,
    Set<String>? supportedLanguages,
  }) {
    return NeuralModelConfig(
      modelVersion: modelVersion ?? this.modelVersion,
      modelAsset: modelAsset ?? this.modelAsset,
      vocabularyAsset: vocabularyAsset ?? this.vocabularyAsset,
      localFilePath: localFilePath ?? this.localFilePath,
      maxSequenceLength: maxSequenceLength ?? this.maxSequenceLength,
      expectedVocabularySize:
          expectedVocabularySize ?? this.expectedVocabularySize,
      architecture: architecture ?? this.architecture,
      quantization: quantization ?? this.quantization,
      unkToken: unkToken ?? this.unkToken,
      clsToken: clsToken ?? this.clsToken,
      sepToken: sepToken ?? this.sepToken,
      padToken: padToken ?? this.padToken,
      inputNames: inputNames ?? this.inputNames,
      outputNames: outputNames ?? this.outputNames,
      normalizeTypography: normalizeTypography ?? this.normalizeTypography,
      tokenizerType: tokenizerType ?? this.tokenizerType,
      supportedLanguages: supportedLanguages ?? this.supportedLanguages,
    );
  }

  factory NeuralModelConfig.fromJson(Map<String, dynamic> json) =>
      NeuralModelConfig(
        modelVersion: json['modelVersion'] as String? ?? 'omni_p3_int8',
        modelAsset: json['modelAsset'] as String? ??
            'assets/models/lauvira_omni_detector.onnx',
        vocabularyAsset: json['vocabularyAsset'] as String? ??
            'assets/models/vocab.txt',
        maxSequenceLength: json['maxSequenceLength'] as int? ?? 512,
        expectedVocabularySize:
            json['expectedVocabularySize'] as int? ?? 30522,
        architecture:
            json['architecture'] as String? ?? 'distilled-transformer',
        quantization: json['quantization'] as String? ?? 'int8',
        unkToken: json['unk_token'] as String? ?? '[UNK]',
        clsToken: json['cls_token'] as String? ?? '[CLS]',
        sepToken: json['sep_token'] as String? ?? '[SEP]',
        padToken: json['pad_token'] as String? ?? '[PAD]',
        inputNames: (json['inputs'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            const {
              'input_ids': 'input_ids',
              'attention_mask': 'attention_mask',
              'token_type_ids': 'token_type_ids',
            },
        outputNames: (json['outputs'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            const {
              'logits': 'logits',
            },
        normalizeTypography: json['normalizeTypography'] as bool? ?? true,
        tokenizerType: NeuralTokenizerType.fromName(json['tokenizerType'] as String?),
        supportedLanguages:
            (json['supportedLanguages'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? const {'en'},
      );

  Map<String, dynamic> toJson() => {
        'modelVersion': modelVersion,
        'modelAsset': modelAsset,
        'vocabularyAsset': vocabularyAsset,
        'maxSequenceLength': maxSequenceLength,
        'expectedVocabularySize': expectedVocabularySize,
        'architecture': architecture,
        'quantization': quantization,
        'unk_token': unkToken,
        'cls_token': clsToken,
        'sep_token': sepToken,
        'pad_token': padToken,
        'inputs': inputNames,
        'outputs': outputNames,
        'normalizeTypography': normalizeTypography,
        'tokenizerType': tokenizerType.name,
        'supportedLanguages': (supportedLanguages.toList()..sort()),
      };
}
