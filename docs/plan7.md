Yes. Based strictly on the architecture you provided, I’d implement it as a **dual-stream forensic pipeline**, but with a few implementation safeguards so the code does not bake in assumptions that the current design has not actually validated.

The source already establishes the major structure: neural detection + the existing 38-feature forensic engine → evidence fusion → `ForensicReport`, all running off the UI isolate. 

# Lauriva — Implementation Specification

## 0. Target architecture

Implement this exact runtime flow:

```text
USER TEXT
   │
   ▼
ForensicCoordinatorService
   │
   ├── Normalize document
   ├── Sentence segmentation
   ├── Token/chunk segmentation
   ├── Progress reporting
   │
   ▼
┌─────────────────────────────────────────────┐
│          BACKGROUND FORENSIC JOB            │
│                                             │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Neural Stream    │  │ Forensic Stream │  │
│  │                  │  │                 │  │
│  │ Tokenizer        │  │ 38 features     │  │
│  │       ↓          │  │       ↓         │  │
│  │ ONNX model       │  │ GBDT            │  │
│  │       ↓          │  │ Stylometry      │  │
│  │ Neural evidence  │  │ Predictability  │  │
│  │                  │  │ Structure       │  │
│  └────────┬─────────┘  └────────┬────────┘  │
│           │                     │           │
│           └──────────┬──────────┘           │
│                      ▼                      │
│             EvidenceFusionEngine            │
│                      │                      │
│                      ▼                      │
│              Calibrated Result              │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
                 ForensicReport
                       │
                       ▼
                 Flutter Provider
                       │
                       ▼
              Detector / Studio UI
```

The important architectural principle is:

> **The neural model becomes the primary learned detector, while the existing forensic engine becomes independent supporting evidence and explainability.**

Your existing forensic engine should **not be deleted**.

---

# 1. Directory structure

Create/modify the project into:

```text
lib/
├── models/
│   └── forensic/
│       ├── neural_detection_result.dart
│       ├── ai_authorship_evidence.dart
│       ├── forensic_report.dart
│       ├── forensic_sentence.dart
│       ├── forensic_evidence.dart
│       └── forensic_scan_metadata.dart
│
├── services/
│   └── forensic/
│       │
│       ├── forensic_coordinator_service.dart
│       ├── forensic_engine.dart
│       │
│       ├── ai/
│       │   ├── gbdt_classifier.dart
│       │   ├── stylometric_feature_extractor.dart
│       │   ├── sentence_attribution_model.dart
│       │   ├── token_predictability_analyzer.dart
│       │   │
│       │   └── neural/
│       │       ├── neural_detector_service.dart
│       │       ├── onnx_neural_runner.dart
│       │       ├── pure_dart_tokenizer.dart
│       │       ├── neural_model_config.dart
│       │       ├── neural_model_registry.dart
│       │       └── neural_isolate_worker.dart
│       │
│       ├── fusion/
│       │   ├── evidence_fusion_engine.dart
│       │   ├── probability_calibrator.dart
│       │   ├── confidence_calculator.dart
│       │   └── fusion_config.dart
│       │
│       └── segmentation/
│           ├── document_segmenter.dart
│           ├── sentence_segmenter.dart
│           └── text_window.dart
│
└── assets/
    └── models/
        ├── lauriva_student_v1_int8.onnx
        ├── vocab.txt
        └── model_config.json
```

The source architecture already specifies the neural model, tokenizer, ONNX runner and vocabulary assets. 

---

# 2. First important change: don't hard-code 35 MB

Your source currently describes:

```text
lauriva_student_v1_int8.onnx
(~35MB)
```

but that should be treated as a **target candidate**, not an architectural constraint. 

Implement:

```dart
class NeuralModelConfig {
  final String modelVersion;
  final String modelAsset;
  final String vocabularyAsset;

  final int maxSequenceLength;
  final int expectedVocabularySize;

  final String architecture;
  final String quantization;

  const NeuralModelConfig({
    required this.modelVersion,
    required this.modelAsset,
    required this.vocabularyAsset,
    required this.maxSequenceLength,
    required this.expectedVocabularySize,
    required this.architecture,
    required this.quantization,
  });
}
```

Then:

```json
{
  "modelVersion": "student_v1",
  "architecture": "distilled-transformer",
  "quantization": "int8",
  "maxSequenceLength": 512
}
```

This allows you to eventually replace:

```text
student_v1
```

with:

```text
student_v2
student_v3
student_large_v1
```

without rewriting the Flutter architecture.

---

# 3. `NeuralDetectionResult`

Create:

```dart
class NeuralDetectionResult {
  final double aiProbability;

  final double uncertainty;

  final List<SentenceNeuralEvidence> sentences;

  final List<TokenEvidence> tokens;

  final bool isFallback;

  final String modelVersion;

  final Duration inferenceTime;

  final String? error;

  const NeuralDetectionResult({
    required this.aiProbability,
    required this.uncertainty,
    required this.sentences,
    required this.tokens,
    required this.isFallback,
    required this.modelVersion,
    required this.inferenceTime,
    this.error,
  });

  factory NeuralDetectionResult.fallback({
    String? error,
  }) {
    return NeuralDetectionResult(
      aiProbability: 50.0,
      uncertainty: 1.0,
      sentences: const [],
      tokens: const [],
      isFallback: true,
      modelVersion: 'fallback',
      inferenceTime: Duration.zero,
      error: error,
    );
  }
}
```

### Important

The current source calls the output:

```text
documentAiProbability
neuralUncertainty
sentenceLogits
tokenPerplexities
```

but **do not implement genuine perplexity unless the student is actually a language model with an LM head**.

A classification model's logits are not perplexity.

Therefore replace:

```dart
List<double> tokenPerplexities
```

with:

```dart
List<TokenEvidence>
```

unless your eventual student architecture genuinely produces token-level likelihoods.

---

# 4. Sentence evidence

Create:

```dart
class SentenceNeuralEvidence {
  final int sentenceIndex;

  final int startOffset;
  final int endOffset;

  final double aiProbability;

  final double confidence;

  const SentenceNeuralEvidence({
    required this.sentenceIndex,
    required this.startOffset,
    required this.endOffset,
    required this.aiProbability,
    required this.confidence,
  });
}
```

This gives the UI enough information to highlight:

```text
Sentence 0 → 17%
Sentence 1 → 82%
Sentence 2 → 91%
Sentence 3 → 34%
```

instead of merely returning a document-level score.

---

# 5. Token evidence

Create:

```dart
class TokenEvidence {
  final int tokenId;

  final int startOffset;
  final int endOffset;

  final double score;

  const TokenEvidence({
    required this.tokenId,
    required this.startOffset,
    required this.endOffset,
    required this.score,
  });
}
```

This can later support:

```text
word-level forensic visualization
```

without forcing the first version of the detector to expose it.

---

# 6. Document segmentation

Do **not** immediately implement only:

```text
300 words → model
300 words → model
300 words → model
```

Your source currently specifies 300-word chunking. 

Instead create an abstraction:

```dart
class TextWindow {
  final int index;

  final int startOffset;
  final int endOffset;

  final String text;

  final List<int> sentenceIndices;

  const TextWindow({
    required this.index,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required this.sentenceIndices,
  });
}
```

Then:

```dart
abstract class DocumentSegmenter {
  List<TextWindow> segment(String text);
}
```

Initial implementation:

```text
target tokens: 384–512
overlap: 64–128 tokens
```

Why?

Because transformer models operate on **tokens**, not words.

A 300-word chunk can easily exceed 512 subword tokens.

So the segmentation layer should be token-aware.

---

# 7. Sentence segmentation

Create:

```dart
class SentenceBoundary {
  final int index;
  final int start;
  final int end;
  final String text;

  const SentenceBoundary({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });
}
```

Then:

```dart
abstract class SentenceSegmenter {
  List<SentenceBoundary> segment(String text);
}
```

The same sentence must retain its original character offsets.

That is critical for your UI.

---

# 8. Tokenizer

Your architecture specifies a pure-Dart WordPiece tokenizer with:

```text
inputIds
attentionMask
tokenTypeIds
tokenSpans
```

and maximum sequence length 512. 

Implement it as:

```dart
class PureDartTokenizer {
  final Map<String, int> vocab;

  final int clsTokenId;
  final int sepTokenId;
  final int padTokenId;
  final int unkTokenId;

  final int maxSequenceLength;

  const PureDartTokenizer({
    required this.vocab,
    required this.clsTokenId,
    required this.sepTokenId,
    required this.padTokenId,
    required this.unkTokenId,
    this.maxSequenceLength = 512,
  });

  TokenizedInput tokenize({
    required String text,
    required List<SentenceBoundary> sentences,
  }) {
    // implementation
  }
}
```

---

# 9. Do NOT assume token IDs

Your current source has:

```dart
unkTokenId = 100
clsTokenId = 101
sepTokenId = 102
padTokenId = 0
```

Those IDs correspond to a particular BERT-style vocabulary.

That is fine **only if your student model actually uses that vocabulary**. 

Instead load these from model configuration:

```json
{
  "unk_token": "[UNK]",
  "cls_token": "[CLS]",
  "sep_token": "[SEP]",
  "pad_token": "[PAD]"
}
```

Resolve IDs from `vocab.txt`.

This prevents an extremely nasty bug where:

```text
tokenizer vocabulary
        ≠
model vocabulary
```

---

# 10. Tokenizer output

```dart
class TokenizedInput {
  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> tokenTypeIds;
  final List<TokenSpan> tokenSpans;

  const TokenizedInput({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.tokenSpans,
  });
}
```

Each `TokenSpan`:

```dart
class TokenSpan {
  final int tokenIndex;

  final int startOffset;
  final int endOffset;

  final int sentenceIndex;

  const TokenSpan({
    required this.tokenIndex,
    required this.startOffset,
    required this.endOffset,
    required this.sentenceIndex,
  });
}
```

---

# 11. WordPiece algorithm

Implement:

```text
normalize
   ↓
whitespace tokenize
   ↓
punctuation split
   ↓
WordPiece
   ↓
special tokens
   ↓
truncate
   ↓
padding
```

For each word:

```text
playing
```

try:

```text
playing
```

then:

```text
play
##ing
```

If no valid decomposition exists:

```text
[UNK]
```

Each produced token must preserve its original character span.

---

# 12. ONNX runner

The source defines:

```dart
abstract class NeuralInferenceRunner {
  Future<void> initialize();

  NeuralDetectionResult runInference(
    TokenizedInput input,
    int sentenceCount,
  );

  void dispose();
}
```

Keep this interface. 

But implement it around a model-specific contract.

```dart
abstract class NeuralInferenceRunner {
  Future<void> initialize();

  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
  });

  void dispose();
}
```

---

# 13. Model output contract

Before writing the Dart ONNX code, establish the exact ONNX graph.

For example:

```text
INPUTS

input_ids
attention_mask
token_type_ids
```

and:

```text
OUTPUTS

logits
```

Potentially:

```text
sentence_logits
```

if the model was explicitly trained for that.

Do **not** make Flutter guess output names.

Put them in:

```json
{
  "inputs": {
    "input_ids": "input_ids",
    "attention_mask": "attention_mask",
    "token_type_ids": "token_type_ids"
  },
  "outputs": {
    "document_logits": "logits"
  }
}
```

---

# 14. Document probability

For binary classification:

```text
logits = [humanLogit, aiLogit]
```

calculate:

```dart
double softmaxAiProbability(
  double humanLogit,
  double aiLogit,
) {
  final maxLogit = max(humanLogit, aiLogit);

  final humanExp = exp(humanLogit - maxLogit);
  final aiExp = exp(aiLogit - maxLogit);

  return aiExp / (humanExp + aiExp);
}
```

Then:

```dart
final probability = softmaxAiProbability(
  logits[0],
  logits[1],
);
```

Return:

```text
0.0–1.0
```

internally.

Only convert to:

```text
0–100
```

at the presentation/report layer.

---

# 15. Never store percentages internally

Use:

```dart
double probability;
```

with:

```text
0.0 → 1.0
```

throughout the engine.

Then:

```dart
double get percentage => probability * 100;
```

This avoids:

```text
72.3
+
0.83
```

type mistakes.

---

# 16. Neural uncertainty

For binary output, calculate entropy:

```dart
double binaryEntropy(double p) {
  final clamped = p.clamp(1e-7, 1 - 1e-7);

  return -(
    clamped * log(clamped) +
    (1 - clamped) * log(1 - clamped)
  ) / log(2);
}
```

Result:

```text
0 = very certain
1 = maximally uncertain
```

So:

```dart
final uncertainty = binaryEntropy(aiProbability);
```

This matches the architecture's concept of entropy-based neural uncertainty. 

---

# 17. Neural detector service

Create:

```dart
class NeuralDetectorService {
  final NeuralInferenceRunner runner;
  final PureDartTokenizer tokenizer;

  bool _initialized = false;

  NeuralDetectorService({
    required this.runner,
    required this.tokenizer,
  });

  Future<void> initialize() async {
    if (_initialized) return;

    await runner.initialize();
    _initialized = true;
  }

  Future<NeuralDetectionResult> analyze({
    required String text,
    required List<SentenceBoundary> sentences,
  }) async {
    await initialize();

    final windows = _segment(text);

    // Run all windows.
    // Aggregate probabilities.
  }

  void dispose() {
    runner.dispose();
  }
}
```

---

# 18. Window aggregation

Suppose:

```text
window 1 = 0.91
window 2 = 0.87
window 3 = 0.42
window 4 = 0.76
```

Do not simply average blindly.

Initially implement:

```text
weighted mean
```

where central/full windows get higher weight and overlap duplicates are handled.

For example:

```dart
double aggregateWindowScores(
  List<WindowPrediction> predictions,
) {
  var weightedSum = 0.0;
  var totalWeight = 0.0;

  for (final prediction in predictions) {
    weightedSum +=
        prediction.aiProbability * prediction.weight;

    totalWeight += prediction.weight;
  }

  return weightedSum / totalWeight;
}
```

Later, this aggregation can be learned.

---

# 19. Sentence-level detection

This is one of the most important changes.

Your source proposes sentence logits/attention spans. 

But:

> **Attention weights are not automatically sentence AI probabilities.**

Do not do:

```text
attention = 0.82
therefore sentence AI probability = 82%
```

Instead, use one of:

### Option A — model trained with sentence labels

Best architecture:

```text
Transformer
    ↓
sentence representation
    ↓
sentence classification head
```

### Option B — sliding sentence inference

Run the same document classifier over individual sentences or small sentence groups.

### Option C — sentence attribution layer

Use the existing `SentenceAttributionModel` to provide supporting evidence while the neural model remains document-level.

For the first production implementation, **Option B/C is safer if your student has only a document classification head**.

---

# 20. Existing forensic stream

Do not modify the semantics of the existing 38-feature system unnecessarily.

Keep:

```text
StylometricFeatureExtractor
        ↓
38-dimensional feature vector
        ↓
GBDT classifier
        ↓
forensic probability
```

Your new architecture should call it as an independent service:

```dart
class ForensicStreamResult {
  final double aiProbability;

  final List<double> features;

  final List<ForensicEvidence> evidence;

  final StructuralEvidence structural;

  final PredictabilityEvidence predictability;

  const ForensicStreamResult({
    required this.aiProbability,
    required this.features,
    required this.evidence,
    required this.structural,
    required this.predictability,
  });
}
```

---

# 21. Existing hardcoded AI tells

The current design explicitly proposes repurposing hardcoded AI tells as explainability badges. 

That is the correct role.

Don't do:

```dart
if (contains("plays a crucial role")) {
  aiProbability += 0.15;
}
```

Instead:

```dart
ForensicEvidence(
  type: EvidenceType.lexicalPattern,
  label: 'Formulaic transitional phrase',
  description: 'Detected a phrase associated with the configured lexical evidence set.',
  strength: 0.42,
  source: EvidenceSource.lexicalPattern,
)
```

Then the fusion engine can decide whether that evidence matters.

---

# 22. Evidence model

Create:

```dart
enum EvidenceType {
  neural,
  stylometric,
  structural,
  lexical,
  predictability,
  authorshipDrift,
  sourceSimilarity,
  repetition,
}
```

Then:

```dart
class ForensicEvidence {
  final EvidenceType type;

  final String label;

  final String description;

  final double strength;

  final double confidence;

  final int? startOffset;

  final int? endOffset;

  const ForensicEvidence({
    required this.type,
    required this.label,
    required this.description,
    required this.strength,
    required this.confidence,
    this.startOffset,
    this.endOffset,
  });
}
```

This becomes the common evidence format.

---

# 23. Fusion engine

Your current source proposes:

```text
neural weight
+
forensic weight
=
fused probability
```

and currently gives the neural stream a maximum weighting around 0.75. 

For the **first engineering version**, you can implement the documented formula.

But architect the code so the coefficients are replaceable:

```dart
class FusionConfig {
  final double neuralBaseWeight;

  final double minimumNeuralWeight;

  final double maximumNeuralWeight;

  final int fullContextWordCount;

  const FusionConfig({
    this.neuralBaseWeight = 0.75,
    this.minimumNeuralWeight = 0.15,
    this.maximumNeuralWeight = 0.85,
    this.fullContextWordCount = 150,
  });
}
```

---

# 24. Initial fusion

Implement:

```dart
double calculateNeuralWeight({
  required int wordCount,
  required double uncertainty,
  required FusionConfig config,
}) {
  final lengthFactor =
      (wordCount / config.fullContextWordCount)
          .clamp(0.2, 1.0);

  final certaintyFactor =
      (1.0 - uncertainty)
          .clamp(0.3, 1.0);

  return (
    config.neuralBaseWeight *
    lengthFactor *
    certaintyFactor
  ).clamp(
    config.minimumNeuralWeight,
    config.maximumNeuralWeight,
  );
}
```

This is directly aligned with the mathematical fusion design in your document. 

---

# 25. But don't calibrate with arbitrary Platt parameters

The source specifies:

```text
raw fused probability
       ↓
Platt scaling
       ↓
calibrated probability
```

That structure is good. 

But the coefficients must come from validation data.

Implement:

```dart
class ProbabilityCalibrator {
  final double a;
  final double b;

  const ProbabilityCalibrator({
    required this.a,
    required this.b,
  });

  double calibrate(double probability) {
    final p = probability.clamp(1e-6, 1 - 1e-6);

    final logit = log(p / (1 - p));

    final calibratedLogit = a * logit + b;

    return 1.0 / (1.0 + exp(-calibratedLogit));
  }
}
```

Store:

```json
{
  "version": "calibration_v1",
  "a": 1.12,
  "b": -0.08
}
```

But **do not invent those numbers**.

Generate them from your validation set.

---

# 26. Better long-term fusion

Once you have enough validation data, replace manually chosen fusion weights with a small meta-classifier:

```text
Neural probability
Neural uncertainty
Forensic probability
Stylometric score
Predictability score
Structural score
Document length
Source similarity
Mixed-authorship score
       ↓
small logistic regression
       ↓
calibrated AI probability
```

This is preferable to permanently assuming:

```text
75% neural
25% forensic
```

because your validation data can tell you whether that weighting is actually appropriate.

---

# 27. Plagiarism conflict

Your architecture specifically calls for reconciliation between plagiarism and AI detection. 

Do not interpret:

```text
source match = AI
```

Those are different signals.

Represent:

```dart
class AuthorshipAssessment {
  final double aiProbability;

  final double sourceMatchProbability;

  final bool mixedAuthorship;

  final bool sourceConflict;

  const AuthorshipAssessment({
    required this.aiProbability,
    required this.sourceMatchProbability,
    required this.mixedAuthorship,
    required this.sourceConflict,
  });
}
```

Example:

```text
AI likelihood: 87%
Source similarity: 93%
```

should be presented as:

```text
High AI-like signal
+
High source overlap
```

rather than automatically claiming:

```text
93% plagiarism caused by AI
```

---

# 28. Mixed-authorship detection

Your existing `CUSUM Authorship Drift` is particularly useful here.

Pipeline:

```text
document
   ↓
sliding windows
   ↓
neural score per window
   +
forensic score per window
   ↓
style drift
   ↓
CUSUM
   ↓
mixed-authorship regions
```

Example:

```text
0–120 words      18%
120–240 words    23%
240–360 words    88%
360–480 words    92%
480–600 words    21%
```

The report can identify:

```text
Potential authorship transition
```

instead of treating the entire document as homogeneous.

---

# 29. Coordinator

The coordinator should become the orchestration layer.

```dart
class ForensicCoordinatorService {
  Future<ForensicReport> analyze(
    String text, {
    void Function(ForensicProgress)? onProgress,
  }) async {
    _validateInput(text);

    onProgress?.call(
      const ForensicProgress(
        stage: ForensicStage.preparing,
        progress: 0.05,
      ),
    );

    final document = _prepareDocument(text);

    onProgress?.call(
      const ForensicProgress(
        stage: ForensicStage.analyzing,
        progress: 0.15,
      ),
    );

    final result = await compute(
      _backgroundAnalyze,
      document.toPayload(),
    );

    onProgress?.call(
      const ForensicProgress(
        stage: ForensicStage.complete,
        progress: 1.0,
      ),
    );

    return result;
  }
}
```

---

# 30. Don't use `compute()` for every tiny operation

Your source says to use background isolates and cache heavy model weights. 

Do not do:

```text
compute(tokenize)
compute(forensic)
compute(neural)
compute(fusion)
compute(report)
```

That creates isolate overhead.

Instead:

```text
UI isolate
   │
   ▼
one forensic worker isolate
   │
   ├── tokenizer
   ├── model
   ├── forensic engine
   ├── fusion
   └── report
   │
   ▼
serialized report
```

Keep the heavy objects alive inside that worker.

---

# 31. Model lifecycle

Implement:

```text
UNINITIALIZED
      ↓
LOADING
      ↓
READY
      ↓
RUNNING
      ↓
READY
      ↓
DISPOSED
```

Enum:

```dart
enum NeuralModelState {
  uninitialized,
  loading,
  ready,
  running,
  failed,
  disposed,
}
```

---

# 32. Lazy model loading

Do not load the ONNX model when Lauriva launches.

Instead:

```text
App launch
    ↓
normal UI
    ↓
user opens detector
    ↓
first scan
    ↓
load tokenizer
    ↓
load ONNX model
    ↓
run
```

This prevents unnecessary startup RAM consumption.

---

# 33. Model cache

Inside the worker:

```dart
class NeuralModelCache {
  static OrtSession? _session;

  static Future<OrtSession> getOrCreate() async {
    if (_session != null) {
      return _session!;
    }

    _session = await _loadModel();

    return _session!;
  }
}
```

The exact API depends on the ONNX Flutter package you select.

Your source currently proposes `onnxruntime` or C-FFI bindings, so the implementation should keep that boundary isolated behind `NeuralInferenceRunner`. 

---

# 34. Fallback behavior

Never crash the detector because the model failed.

Flow:

```text
ONNX initialization
       │
       ├── SUCCESS
       │      ↓
       │   neural stream
       │
       └── FAILURE
              ↓
        forensic stream
              ↓
       report marked:
       neural unavailable
```

Do **not** silently return:

```text
AI = 50%
```

and present that as a real prediction.

Instead:

```dart
NeuralDetectionResult.fallback(
  error: 'Neural model unavailable',
);
```

Then the report explicitly says:

```text
Neural detector unavailable.
Assessment based on forensic evidence only.
```

---

# 35. Parallel execution

The ideal pipeline:

```text
             document
                │
          ┌─────┴─────┐
          │            │
          ▼            ▼
       neural       forensic
          │            │
          └─────┬──────┘
                ▼
              fusion
```

Do not run:

```text
neural
  ↓
forensic
  ↓
fusion
```

unless resource limitations require it.

---

# 36. Progress model

Create:

```dart
enum ForensicStage {
  preparing,
  tokenizing,
  neuralAnalysis,
  forensicAnalysis,
  fusing,
  generatingReport,
  complete,
  failed,
}
```

And:

```dart
class ForensicProgress {
  final ForensicStage stage;
  final double progress;

  const ForensicProgress({
    required this.stage,
    required this.progress,
  });
}
```

Suggested progression:

```text
Preparing       0.00–0.10
Segmentation    0.10–0.15
Neural          0.15–0.55
Forensic        0.15–0.55
Fusion          0.55–0.80
Report          0.80–0.95
Complete        1.00
```

---

# 37. ForensicReport

Expand the report to:

```dart
class ForensicReport {
  final double aiProbability;

  final double confidence;

  final AuthorshipClass authorshipClass;

  final NeuralDetectionResult neural;

  final ForensicStreamResult forensic;

  final List<ForensicSentence> sentences;

  final List<ForensicEvidence> evidence;

  final ForensicScanMetadata metadata;

  final String executiveSummary;
}
```

---

# 38. Authorship class

Use descriptive categories rather than pretending the score proves authorship.

For example:

```dart
enum AuthorshipClass {
  predominantlyHumanLike,
  mixedSignals,
  predominantlyAiLike,
  insufficientEvidence,
}
```

Thresholds should be configuration-driven:

```json
{
  "humanUpper": 0.30,
  "mixedUpper": 0.70
}
```

Do not hard-code them throughout UI/business logic.

---

# 39. Sentence report

```dart
class ForensicSentence {
  final int index;

  final String text;

  final double aiProbability;

  final double confidence;

  final List<ForensicEvidence> evidence;

  const ForensicSentence({
    required this.index,
    required this.text,
    required this.aiProbability,
    required this.confidence,
    required this.evidence,
  });
}
```

Now your UI can directly consume:

```text
Sentence
AI probability
Evidence
Offsets
```

---

# 40. UI

Your current architecture already identifies:

```text
visual_diff_viewer.dart
detector_screen.dart
```

for sentence heatmaps and evidence. 

The UI should show three distinct things:

### Document level

```text
AI-like signal

78%
```

### Evidence confidence

```text
Confidence
Moderate
```

### Explanation

```text
Neural evidence
Stylometric evidence
Structural evidence
Predictability evidence
Authorship drift
```

Never make the UI imply:

```text
78% = 78% certainty that AI wrote it
```

It is a model probability/score after calibration.

---

# 41. Sentence heatmap

Use:

```dart
final intensity =
    sentence.aiProbability.clamp(0.0, 1.0);
```

But render uncertainty separately.

For example:

```text
AI signal     ████████░░ 82%
Confidence    ██████░░░░ 61%
```

A sentence with:

```text
82% probability
35% confidence
```

should not look equivalent to:

```text
82% probability
94% confidence
```

---

# 42. Evidence bottom sheet

When tapping a sentence:

```text
Sentence 14

AI-like signal
82%

Evidence

• Neural detector
  Strong AI-like signal

• Stylometric
  Low lexical variation

• Structural
  Uniform clause structure

• Predictability
  Elevated regularity

• Authorship drift
  Consistent with neighboring AI-like region
```

The source's UI concept of forensic badges can be preserved here. 

---

# 43. Model version metadata

Every result should include:

```dart
class ForensicScanMetadata {
  final String engineVersion;

  final String neuralModelVersion;

  final String calibrationVersion;

  final DateTime timestamp;

  final int wordCount;

  final int sentenceCount;

  final Duration processingTime;
}
```

Example:

```text
Lauriva Engine: 4.0.0
Neural Model: student_v1
Calibration: calibration_v1
Words: 842
Sentences: 47
Processing: 1.82s
```

This will be extremely useful when you update models later.

---

# 44. Testing structure

Create:

```text
test/
├── forensic/
│   ├── tokenizer_test.dart
│   ├── segmentation_test.dart
│   ├── neural_runner_test.dart
│   ├── neural_detector_test.dart
│   ├── fusion_test.dart
│   ├── calibration_test.dart
│   ├── mixed_authorship_test.dart
│   ├── fallback_test.dart
│   └── report_test.dart
│
├── fixtures/
│   ├── human/
│   ├── ai/
│   ├── mixed/
│   ├── edited_ai/
│   └── edge_cases/
│
└── golden/
    └── forensic_reports/
```

---

# 45. Tokenizer tests

Test:

```text
empty string
one word
normal paragraph
punctuation
Unicode
Tamil
emoji
URLs
numbers
contractions
hyphenated words
unknown words
very long document
exact 512 tokens
511 tokens
512 tokens
513 tokens
```

Especially verify:

```text
character offset
→ token offset
→ sentence index
```

because the heatmap depends on this.

---

# 46. ONNX tests

Before integrating into Flutter UI, create a known fixture:

```text
input text
      ↓
tokenizer
      ↓
input_ids
      ↓
ONNX
      ↓
expected logits
```

Test that the Flutter output is within tolerance:

```text
absolute error < 1e-4
```

or whatever tolerance is appropriate for the quantized runtime.

---

# 47. Fusion tests

Test:

### Human-like neural + human-like forensic

```text
neural = 0.12
forensic = 0.19
```

Expected:

```text
low fused signal
```

### AI-like both

```text
neural = 0.92
forensic = 0.81
```

Expected:

```text
high fused signal
```

### Disagreement

```text
neural = 0.92
forensic = 0.21
```

Expected:

```text
lower confidence
```

not simply:

```text
92%
```

---

# 48. Short-text tests

Your source specifically recognizes that short text should reduce reliance on the neural stream. 

Test:

```text
5 words
20 words
50 words
99 words
100 words
150 words
300 words
1000 words
5000 words
```

Verify the neural weighting changes smoothly.

No discontinuous:

```text
99 → weight 0.32
100 → weight 0.75
```

type behavior.

---

# 49. Mixed-authorship tests

Create fixtures such as:

```text
Human
Human
Human
AI
AI
AI
Human
Human
```

Expected behavior:

```text
window-level variation
+
CUSUM transition
+
sentence evidence
```

rather than a single document score hiding the transition.

---

# 50. Model benchmark suite

Before shipping `student_v1`, build:

```text
                  HUMAN
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
   academic      casual      technical

                    +

                    AI
                    │
 ┌────────┬─────────┼────────┬─────────┐
 ▼        ▼         ▼        ▼         ▼
GPT     Claude    Gemini   Qwen     DeepSeek
```

Then include:

```text
raw AI
edited AI
paraphrased AI
grammar-corrected AI
humanized AI
AI + human mixed
```

The most important benchmark is **unseen generators**, not merely the same generator used during training.

---

# 51. Student model training

The Flutter implementation assumes the ONNX model already exists.

Your training pipeline should therefore be separate:

```text
teacher
   ↓
dataset
   ↓
teacher inference
   ↓
soft labels
   +
ground truth
   ↓
student training
   ↓
validation
   ↓
quantization
   ↓
ONNX
   ↓
Flutter
```

Use the larger teacher for quality.

Use the smaller student for deployment.

---

# 52. Distillation target

Student loss can combine:

```text
classification loss
+
knowledge distillation loss
```

Conceptually:

```text
L =
α * CrossEntropy(student, groundTruth)
+
β * KL(studentTemperature, teacherTemperature)
```

Optionally:

```text
+
γ * representation loss
```

if your architecture supports it.

---

# 53. Dataset split

Do NOT randomly split individual paragraphs from the same document.

Use:

```text
TRAIN
VALIDATION
TEST
```

with generator/source separation where possible.

For example:

```text
GPT samples
→ train

Claude samples
→ validation

unseen generator
→ test
```

This better measures generalization.

---

# 54. Hard cases

Your dataset must deliberately contain:

```text
human academic writing
human ESL writing
human technical writing
human short writing
human highly polished writing

AI raw output
AI edited by human
AI paraphrased
AI translated
AI grammar corrected
AI shortened
AI expanded
AI humanized
AI + human paragraphs
```

Otherwise the model will learn superficial shortcuts.

---

# 55. Quantization

Your production pipeline should be:

```text
FP32 teacher/student
       ↓
FP16 benchmark
       ↓
INT8 benchmark
       ↓
optional INT4 experiment
       ↓
accuracy/size/latency comparison
```

Do not choose INT8 simply because the architecture document says INT8.

Choose it because it gives an acceptable:

```text
accuracy
+
latency
+
RAM
+
package size
```

tradeoff.

---

# 56. Model selection gate

Before placing a model into:

```text
assets/models/
```

require:

```text
[ ] validation performance acceptable
[ ] unseen-generator performance acceptable
[ ] edited-AI performance evaluated
[ ] mixed-authorship evaluated
[ ] calibration evaluated
[ ] INT8 degradation measured
[ ] mobile latency measured
[ ] memory measured
[ ] ONNX output verified
[ ] tokenizer verified
```

Only then call it:

```text
student_v1
```

---

# 57. Performance targets

Don't make the UI responsible for model optimization.

Measure:

```text
cold model load
warm model load
tokenization
ONNX inference
forensic engine
fusion
total scan
peak memory
```

Record:

```dart
class PerformanceMetrics {
  final Duration modelLoad;
  final Duration tokenization;
  final Duration neuralInference;
  final Duration forensicAnalysis;
  final Duration fusion;
  final Duration total;

  final int peakMemoryMb;
}
```

---

# 58. Caching

Cache:

```text
model session
tokenizer vocabulary
model configuration
calibration parameters
```

Do **not** cache every user's document indefinitely.

For repeated analysis of the same document, use a bounded in-memory cache keyed by a content hash if that fits Lauriva's privacy model.

---

# 59. Privacy

Because this architecture is intended to be on-device:

```text
USER TEXT
   ↓
Flutter memory
   ↓
isolate
   ↓
ONNX
   ↓
report
```

No network request should be necessary for the neural detector.

That should remain a hard architectural boundary.

---

# 60. Error boundaries

Wrap independently:

```text
Tokenizer
ONNX initialization
ONNX inference
Forensic engine
Fusion
Report generation
```

Example:

```dart
try {
  neuralResult = await neuralService.analyze(...);
} catch (e, stack) {
  neuralResult = NeuralDetectionResult.fallback(
    error: e.toString(),
  );
}
```

Then the forensic stream can still complete.

---

# 61. Critical failure policy

### Neural failure

```text
continue with forensic
```

### Forensic failure

```text
continue with neural
```

### Both fail

```text
return insufficient evidence
```

Do **not** manufacture:

```text
50%
```

as though it were an actual prediction.

---

# 62. Final fusion object

The fusion engine should return:

```dart
class FusionResult {
  final double aiProbability;

  final double confidence;

  final double neuralWeight;

  final double forensicWeight;

  final AuthorshipClass classification;

  final List<ForensicEvidence> evidence;

  final String summary;

  const FusionResult({
    required this.aiProbability,
    required this.confidence,
    required this.neuralWeight,
    required this.forensicWeight,
    required this.classification,
    required this.evidence,
    required this.summary,
  });
}
```

This makes the result auditable.

---

# 63. Example complete runtime

For:

```text
850-word essay
```

Lauriva does:

```text
1. Receive text

2. Normalize text

3. Detect 47 sentences

4. Generate token-aware windows

5. Start neural stream

6. Start forensic stream

7. Neural:
      tokenize
      ONNX
      window scores
      sentence evidence
      uncertainty

8. Forensic:
      38 features
      GBDT
      structural analysis
      predictability
      authorship drift
      lexical evidence

9. Normalize evidence

10. Calculate initial neural/forensic weights

11. Fuse

12. Apply calibration

13. Detect mixed-authorship regions

14. Generate sentence evidence

15. Generate report

16. Serialize result

17. Return to UI isolate

18. Render report
```

---

# 64. Final report example

Internally:

```json
{
  "engineVersion": "4.0.0",
  "neuralModelVersion": "student_v1",
  "calibrationVersion": "calibration_v1",

  "aiProbability": 0.81,
  "confidence": 0.76,

  "neuralWeight": 0.68,
  "forensicWeight": 0.32,

  "classification": "predominantlyAiLike",

  "mixedAuthorship": true,

  "sentences": [
    {
      "index": 0,
      "aiProbability": 0.21
    },
    {
      "index": 1,
      "aiProbability": 0.84
    }
  ]
}
```

The UI converts that into the human-readable forensic report.

---

# 65. Implementation order

This is the order I would actually give the developer.

### Phase 1 — Freeze existing system

```text
[ ] Commit current Lauriva
[ ] Existing forensic tests passing
[ ] Record current detector benchmark
```

Do **not** modify everything simultaneously.

### Phase 2 — Data contracts

```text
[ ] NeuralDetectionResult
[ ] TokenizedInput
[ ] TokenSpan
[ ] SentenceNeuralEvidence
[ ] ForensicStreamResult
[ ] ForensicEvidence
[ ] FusionResult
[ ] ForensicReport extensions
```

### Phase 3 — Segmentation

```text
[ ] SentenceSegmenter
[ ] DocumentSegmenter
[ ] TextWindow
[ ] offsets
[ ] overlap
```

### Phase 4 — Tokenizer

```text
[ ] vocab loader
[ ] normalization
[ ] WordPiece
[ ] special tokens
[ ] truncation
[ ] padding
[ ] offsets
[ ] unit tests
```

### Phase 5 — ONNX

```text
[ ] model config
[ ] asset loading
[ ] session initialization
[ ] input tensors
[ ] output tensors
[ ] softmax
[ ] uncertainty
[ ] error handling
```

### Phase 6 — Neural service

```text
[ ] model lifecycle
[ ] window inference
[ ] window aggregation
[ ] sentence mapping
[ ] result generation
```

### Phase 7 — Existing forensic integration

```text
[ ] preserve 38 features
[ ] expose forensic result
[ ] expose evidence
[ ] preserve structural signals
[ ] preserve CUSUM
```

### Phase 8 — Fusion

```text
[ ] normalize probabilities
[ ] uncertainty
[ ] length factor
[ ] initial weighting
[ ] calibration
[ ] confidence
[ ] disagreement handling
```

### Phase 9 — Isolate architecture

```text
[ ] worker
[ ] model cache
[ ] tokenizer cache
[ ] serialized payload
[ ] progress messages
[ ] cancellation
```

### Phase 10 — UI

```text
[ ] document score
[ ] confidence
[ ] sentence heatmap
[ ] evidence badges
[ ] mixed-authorship regions
[ ] forensic explanation
```

### Phase 11 — Validation

```text
[ ] human corpus
[ ] AI corpus
[ ] unseen generators
[ ] edited AI
[ ] paraphrased AI
[ ] mixed documents
[ ] short text
[ ] technical writing
[ ] academic writing
```

### Phase 12 — Model optimization

```text
[ ] FP32
[ ] FP16
[ ] INT8
[ ] optional INT4
[ ] latency
[ ] RAM
[ ] accuracy
[ ] package size
```

### Phase 13 — Production gate

```text
[ ] crash testing
[ ] model-missing testing
[ ] malformed-input testing
[ ] long-document testing
[ ] low-memory testing
[ ] Android testing
[ ] iOS testing
[ ] release build
```

---

# 66. The three things I would change from your original document

Your architecture is fundamentally sound, but these three points should **not** be implemented literally.

### 1. `tokenPerplexities`

Change:

```dart
List<double> tokenPerplexities
```

to genuine token evidence unless your model actually has a language-model probability head.

Otherwise Lauriva would be labeling classifier outputs as perplexity.

### 2. Sentence attention = sentence probability

Don't do this:

```text
attention weight → AI probability
```

Attention is not inherently an attribution probability.

Use a trained sentence head, sentence-window inference, or the existing attribution system.

### 3. Fixed 75/25 fusion forever

Your current design's dynamic weighting is a good **initial implementation**, but the production fusion parameters should eventually be learned/calibrated from held-out validation data rather than assumed.

The original document already gives the dynamic weighting design and calibration structure. 

---

## Final implementation target

The finished Lauriva architecture should therefore be:

```text
                    LAURIVA FORENSIC ENGINE
                           │
                           ▼
                ForensicCoordinatorService
                           │
                ┌──────────┴──────────┐
                │                     │
                ▼                     ▼
        NEURAL STREAM          FORENSIC STREAM
                │                     │
        Tokenizer              38 features
                │                     │
        ONNX Student                 GBDT
                │                     │
        AI probability        forensic probability
        uncertainty            structural evidence
        sentence evidence      predictability
                │                     │
                └──────────┬──────────┘
                           ▼
                 EvidenceFusionEngine
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
          Neural        Forensic      Context
         evidence       evidence      signals
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                     Calibration
                           │
                           ▼
                  Authorship Assessment
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
         Document       Sentence       Evidence
          score          scores         timeline
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                    ForensicReport
                           │
                           ▼
                     Flutter UI
```

That is the version I would implement **without ripping apart your existing 38-feature engine**. Your supplied architecture already has the right separation of responsibilities; the main job now is making the contracts, model interface, evidence semantics, calibration, and isolate lifecycle precise enough that the 38k-line app can absorb the neural detector without becoming fragile. 