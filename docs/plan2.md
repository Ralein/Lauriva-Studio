Yes son. Looking at the actual Lauriva engine you uploaded, I would **not just add more regexes**. You already have a decent v2 foundation: 38 stylometric features, an on-device logistic component, heuristic signals, anomaly distance, uncertainty, source-plagiarism separation, and a Hugging Face fallback. 

But the current system is still fundamentally a **heuristic/stylometric AI detector with a relatively small training corpus**, while the `SourcePlagiarismService` is not yet a true source-plagiarism engine. The latter currently measures repeated internal n-grams, lexical richness, and boilerplate rather than actually establishing that text came from an external source.

So I would redesign Lauriva into a **Forensic Content Intelligence Engine**, not merely make the existing score bigger.

# Lauriva Forensic Engine 3.0 — Principal/Senior Implementation Plan

# Lauriva Forensic Content Intelligence Engine 3.0
## Principal/Senior-Level Implementation & Enhancement Plan

### Objective

Transform Lauriva's current AI/plagiarism detector into a layered forensic system capable of:

1. Detecting likely AI-generated writing.
2. Detecting human-edited AI writing.
3. Detecting mixed-origin passages.
4. Detecting copied/verbatim content.
5. Detecting paraphrased copying.
6. Detecting semantic source similarity.
7. Detecting internally repeated/formulaic content.
8. Identifying suspicious passages at sentence/span level.
9. Quantifying uncertainty instead of pretending detection is certain.
10. Providing defensible evidence for every major score.

The system must **never equate "AI-like" with "plagiarized."**

These are separate forensic questions:

```text
QUESTION A
Was this writing likely generated or substantially assisted by AI?

QUESTION B
Does this writing appear to match another known source?

QUESTION C
Does this document contain internally repetitive/formulaic writing?

QUESTION D
How strong is the available evidence?
```

The final report combines these independent dimensions rather than collapsing them into one misleading number.

---

# 1. Target Architecture

Replace the current conceptual pipeline:

```text
Text
 ↓
Rule Engine
 ↓
ML Score
 ↓
Plagiarism Score
 ↓
Final Score
```

with:

```text
                         ┌──────────────────────────┐
                         │      INPUT DOCUMENT      │
                         └────────────┬─────────────┘
                                      │
                                      ▼
                         ┌──────────────────────────┐
                         │  NORMALIZATION LAYER     │
                         │                          │
                         │ Unicode                  │
                         │ whitespace               │
                         │ punctuation              │
                         │ casing                   │
                         │ sentence boundaries     │
                         │ paragraph boundaries     │
                         │ tokenization             │
                         └────────────┬─────────────┘
                                      │
              ┌───────────────────────┼────────────────────────┐
              │                       │                        │
              ▼                       ▼                        ▼
    ┌─────────────────┐    ┌──────────────────┐    ┌────────────────────┐
    │ AI FORENSICS    │    │ SOURCE FORENSICS │    │ DOCUMENT FORENSICS │
    │                 │    │                  │    │                    │
    │ Stylometry      │    │ Exact matching   │    │ Repetition         │
    │ Syntax          │    │ Shingles         │    │ Authorship shifts  │
    │ Vocabulary      │    │ Fuzzy matching   │    │ Section anomalies  │
    │ Structure       │    │ Semantic match   │    │ Style transitions  │
    │ Predictability  │    │ Source corpus    │    │ Span analysis      │
    │ AI patterns     │    │ Web sources      │    │ Consistency        │
    └────────┬────────┘    └─────────┬────────┘    └─────────┬──────────┘
             │                       │                       │
             └───────────────────────┼───────────────────────┘
                                     ▼
                         ┌──────────────────────────┐
                         │ EVIDENCE FUSION ENGINE   │
                         │                          │
                         │ Calibration              │
                         │ Confidence               │
                         │ Reliability weighting    │
                         │ Contradiction handling  │
                         └────────────┬─────────────┘
                                      │
                                      ▼
                         ┌──────────────────────────┐
                         │ DOCUMENT DECISION LAYER  │
                         │                          │
                         │ AI likelihood            │
                         │ Source similarity        │
                         │ Mixed/edited likelihood  │
                         │ Uncertainty               │
                         └────────────┬─────────────┘
                                      │
                                      ▼
                         ┌──────────────────────────┐
                         │ FORENSIC REPORT          │
                         │                          │
                         │ Score + evidence         │
                         │ Sentence heatmap         │
                         │ Source matches           │
                         │ Explanation              │
                         │ Confidence               │
                         └──────────────────────────┘
```

The crucial architectural change is:

> **Do not allow the AI detector and plagiarism detector to contaminate each other's evidence.**

---

# 2. Phase 1 — Establish a Proper Forensic Domain Model

## Current problem

The existing report combines:

- `overallScore`
- `humanScore`
- `plagiarismRiskScore`
- `ngramOverlapScore`
- AI tells
- lexical richness
- burstiness

into a UI that visually treats them as one "AI & Content Check."

The current provider also calls the result "AI Plagiarism," which is conceptually ambiguous.

The existing system already separates `SourcePlagiarismService` from `AiForensicService`, which is the correct direction.

Take this separation much further.

## New domain objects

Create:

```text
ForensicDocument
ForensicAnalysis
AiAuthorshipEvidence
SourceSimilarityEvidence
InternalRepetitionEvidence
ForensicSpan
SourceMatch
EvidenceSignal
ConfidenceAssessment
ForensicSummary
```

### Example conceptual model

```dart
class ForensicAnalysis {
  final AiAuthorshipEvidence ai;
  final SourceSimilarityEvidence source;
  final InternalRepetitionEvidence repetition;
  final List<ForensicSpan> suspiciousSpans;
  final ConfidenceAssessment confidence;
  final ForensicSummary summary;
}
```

Do not make `overallScore` the primary source of truth.

Instead:

```text
AI likelihood
Source similarity
Internal repetition
Uncertainty
```

become first-class independent dimensions.

---

# 3. Phase 2 — Build a High-Quality Normalization Pipeline

Before calculating any feature, create one canonical representation.

## Normalization stages

```text
Raw text
 ↓
Unicode normalization
 ↓
Invisible-character removal
 ↓
Whitespace normalization
 ↓
Quote normalization
 ↓
Dash normalization
 ↓
HTML/Markdown classification
 ↓
Sentence segmentation
 ↓
Paragraph segmentation
 ↓
Tokenization
 ↓
Normalized tokens
 ↓
Original-position mapping
```

### Important

Maintain BOTH:

```text
originalText
normalizedText
```

Never destroy the original.

You need position mappings so that:

```text
normalized token #842
```

can still map back to:

```text
original characters 4821–4874
```

This becomes essential for sentence heatmaps and plagiarism highlighting.

---

# 4. Phase 3 — Upgrade AI Forensics From 38 Features to a Multi-Family Feature System

The existing engine already has a strong foundation of 38 features across surface statistics, punctuation, lexical dynamics, syntax/structure, cohesion, and semantic/anomaly signals.

Do NOT simply jump from 38 → 200 random features.

Instead build hierarchical feature families.

## Family A — Surface statistics

Add:

```text
characterCount
wordCount
sentenceCount
paragraphCount

meanWordLength
medianWordLength
wordLengthVariance
wordLengthSkew

meanSentenceLength
medianSentenceLength
sentenceLengthVariance
sentenceLengthSkew
sentenceLengthKurtosis

burstiness
burstinessByParagraph
burstinessByWindow

paragraphLengthMean
paragraphLengthVariance
paragraphLengthSkew
```

---

# 5. Family B — Punctuation Fingerprint

Track:

```text
comma frequency
semicolon frequency
colon frequency
period frequency
question frequency
exclamation frequency
dash frequency
em dash frequency
en dash frequency
parentheses
brackets
quotes
apostrophes
ellipsis
slash
colon-semicolon ratio
comma-period ratio
punctuation entropy
punctuation transition probability
```

The important improvement:

## Don't say

```text
"em dash = AI"
```

Instead:

```text
emDashSignal
```

should be:

```text
weak evidence
```

because humans absolutely use em dashes.

The current engine has multiple hand-authored AI pattern weights such as 16–25 points for individual patterns.

Those weights should eventually be learned or calibrated from validation data rather than treated as universal truths.

---

# 6. Family C — Vocabulary Dynamics

Add:

```text
TTR
MATTR
MTLD
HD-D
Guiraud R
Hapax ratio
Dis legomena ratio
Rare-word ratio
Common-word ratio
Function-word ratio
Pronoun distribution
Verb/adjective/adverb ratios
Modal density
Hedging density
Contraction density
First-person density
Third-person density
Vocabulary repetition distance
Lexical novelty
```

## Critical addition: vocabulary burstiness

Measure vocabulary introduction over time.

Example:

```text
paragraph 1 → new vocabulary 35%
paragraph 2 → new vocabulary 18%
paragraph 3 → new vocabulary 8%
```

versus:

```text
35%
34%
31%
```

This can help identify unusually homogeneous generation patterns.

---

# 7. Family D — Sentence-Level Structural Fingerprint

Instead of only calculating average sentence length, calculate distributions.

For each sentence:

```text
word count
character count
clause estimate
comma count
subordinate conjunction count
coordinating conjunction count
question status
exclamation status
passive-like construction
first-person usage
transition opener
modal density
```

Then derive:

```text
sentence-to-sentence distance
structural variance
opening diversity
closing diversity
syntax repetition
sentence-template repetition
```

## Sentence template fingerprint

Convert:

```text
The platform improves workflow efficiency.

The application improves team productivity.

The system improves operational visibility.
```

into:

```text
DET NOUN VERB NOUN NOUN
DET NOUN VERB NOUN NOUN
DET NOUN VERB ADJ NOUN
```

Repeated templates become evidence of structural regularity.

---

# 8. Phase 4 — Add Stylometric Fingerprinting

This is one of the biggest upgrades.

Instead of only asking:

> "Does this text look like AI?"

ask:

> "How internally consistent is the author's writing fingerprint?"

Build:

```text
StyleFingerprint
```

containing:

```text
sentence-length distribution
punctuation distribution
function-word distribution
pronoun profile
contraction profile
paragraph cadence
vocabulary richness
opening patterns
closing patterns
syntactic complexity
```

Then divide the document into windows:

```text
Document
 ├── Window 1
 ├── Window 2
 ├── Window 3
 ├── Window 4
 └── Window 5
```

Compare fingerprints between windows.

This allows detection of:

```text
Human → AI
AI → Human
Human → AI → Human
```

style transitions.

This is much more valuable than simply returning:

```text
AI = 73%
```

---

# 9. Phase 5 — Mixed / Human-Edited AI Detection

The current engine already explicitly supports:

```text
likelyHuman
mixedOrEdited
likelyAi
inconclusive
```

which is a good foundation.

Now make this a genuine document-level segmentation problem.

## Window analysis

Split text into overlapping windows:

```text
100–150 words
```

with overlap:

```text
30–50 words
```

For each window calculate:

```text
AI probability
uncertainty
style fingerprint
feature vector
```

Example:

```text
Paragraph 1 → 18% AI
Paragraph 2 → 22% AI
Paragraph 3 → 78% AI
Paragraph 4 → 81% AI
Paragraph 5 → 25% AI
```

Instead of:

```text
Document = 53% AI
```

report:

```text
Potentially AI-like region detected
Paragraphs 3–4
```

This is far more useful.

---

# 10. Phase 6 — Replace the Current Source Plagiarism Logic

This is probably the **largest weakness in the current implementation**.

Your current source service calculates repeated n-grams, lexical richness, boilerplates and then creates a composite plagiarism risk. It does not actually prove an external source match.

The class itself says it handles external literature/web matching, but `sourceMatches` currently defaults to an empty list in the provided implementation.

## Build a real source similarity pipeline

```text
Input
 ↓
Exact matching
 ↓
Shingle matching
 ↓
Fuzzy matching
 ↓
Paraphrase matching
 ↓
Semantic similarity
 ↓
Source aggregation
 ↓
Evidence verification
```

---

# 11. Exact Match Engine

Create normalized shingles:

```text
3-grams
4-grams
5-grams
7-grams
9-grams
```

But don't simply count:

```dart
repeatedNgrams.length
```

because that number is not a reliable plagiarism percentage.

Instead calculate:

```text
matchedTokenCount
sourceCoverage
documentCoverage
longestContiguousMatch
matchedShingleCount
uniqueMatchedShingles
```

Example:

```text
Document = 1000 words

Source A:
matched words = 230
coverage = 23%

Source B:
matched words = 42
coverage = 4.2%
```

This is meaningful.

---

# 12. Longest Common Subsequence / Contiguous Match Detection

Add:

```text
LongestCommonSubstring
LongestCommonSubsequence
```

for candidate passages.

If:

```text
17 consecutive normalized tokens
```

match a source, that is much stronger evidence than:

```text
17 scattered matching tokens
```

Store:

```dart
SourceMatchSegment(
  documentStart,
  documentEnd,
  sourceStart,
  sourceEnd,
  tokenCount,
  similarity,
  matchType,
)
```

---

# 13. Fuzzy Matching

Exact copying is easy.

Paraphrased copying is harder.

Create a fuzzy matcher using:

```text
token edit distance
character n-gram similarity
Jaccard similarity
Cosine similarity over TF-IDF
```

Example:

Original:

```text
The company reduced operating costs by 18 percent.
```

Paraphrase:

```text
Operating expenses were lowered by eighteen percent.
```

Exact matching:

```text
low
```

Semantic/lexical matching:

```text
high
```

This is where Lauriva's source-plagiarism engine becomes substantially more useful.

---

# 14. Semantic Similarity Layer

For serious paraphrase detection, add embeddings.

Architecture:

```text
Sentence
 ↓
Embedding
 ↓
Vector index
 ↓
Nearest-neighbor search
 ↓
Candidate sources
 ↓
Cross-verification
```

Do not compare every sentence against every source.

Use:

```text
ANN / approximate nearest neighbor
```

candidate retrieval.

Pipeline:

```text
Embedding retrieval
      ↓
Top 20 candidates
      ↓
lexical verification
      ↓
semantic verification
      ↓
match threshold
```

This dramatically reduces false positives.

---

# 15. Source Corpus Architecture

Create:

```text
SourceRepository
```

with adapters:

```text
LocalCorpusSource
UploadedDocumentSource
LibrarySource
WebSource
AcademicSource
UserProvidedSource
```

The engine should be able to analyze:

```text
Document vs uploaded files
Document vs local corpus
Document vs indexed sources
Document vs web results
```

without changing the core forensic engine.

---

# 16. Source Match Confidence

Never report:

```text
93% plagiarism
```

without source evidence.

Instead:

```text
Source similarity: 93%

Evidence:
Source A
├── 3 matched passages
├── 184 matching tokens
├── 18.4% document coverage
├── longest match: 42 tokens
└── semantic similarity: 0.91
```

This is defensible.

---

# 17. Boilerplate Intelligence

The current implementation detects academic boilerplate.

Improve it by classifying boilerplates:

```text
Academic boilerplate
Legal boilerplate
Technical boilerplate
Marketing boilerplate
Documentation boilerplate
Citation boilerplate
AI conversational boilerplate
Common-language boilerplate
```

Then assign:

```text
commonness
specificity
sourceability
```

A phrase such as:

```text
"In conclusion..."
```

should have almost no plagiarism weight.

A highly distinctive 15-word phrase should have substantially more weight.

---

# 18. Phase 7 — Better ML Architecture

The current v2 training script uses an ElasticNet/logistic-style classifier and evaluates it using cross-validation. The training script itself correctly warns that its current corpus is only a 60-example directional signal.

That must change.

## Training corpus target

Minimum serious target:

```text
Human:        20,000+
AI:           20,000+
Hybrid:       10,000+
Adversarial:  10,000+
```

Better:

```text
100k+ passages
```

eventually.

---

# 19. Human Corpus Design

Human data must cover:

```text
personal writing
emails
forums
technical writing
academic writing
journalism
reviews
documentation
student writing
creative writing
business writing
casual chat
social posts
professional reports
non-native English
```

Do NOT create synthetic "human" examples.

The human corpus should represent genuine human variation.

---

# 20. AI Corpus Design

Use multiple generation conditions:

```text
GPT family
Claude family
Gemini family
Llama family
Qwen family
Mistral family
other open models
```

Also vary:

```text
temperature
system prompts
writing styles
length
domain
reasoning level
instruction complexity
```

Most importantly:

## Include adversarial AI.

Generate AI text specifically instructed to:

```text
avoid em dashes
avoid "furthermore"
avoid "moreover"
use contractions
use sentence fragments
make occasional grammatical errors
vary sentence lengths
use slang
avoid markdown
avoid stock vocabulary
imitate human writing
use personal anecdotes
```

Your existing corpus has already started doing this with "Adversarial AI" and "Human-Edited & Hybrid AI"; expand that idea dramatically.

---

# 21. Human-Edited Dataset

This should become a first-class training class.

Generate:

```text
AI → light human editing
AI → moderate human editing
AI → heavy human editing
AI → complete rewrite
Human → AI-assisted expansion
Human → AI grammar correction
Human → AI paraphrase
```

Labels:

```text
PURE_HUMAN
AI_GENERATED
AI_ASSISTED
AI_EDITED
MIXED
UNKNOWN
```

This is much more realistic than binary classification.

---

# 22. Avoid Data Leakage

Never randomly split near-duplicate passages.

Use:

```text
author-grouped split
source-grouped split
topic-grouped split
model-grouped split
time-based split
```

Example:

```text
TRAIN
GPT + human authors A–M

TEST
GPT + human authors N–Z
+
held-out model
```

Then perform:

```text
Cross-model evaluation
Cross-domain evaluation
Cross-author evaluation
Cross-time evaluation
```

---

# 23. Hard-Negative Mining

This is critical.

Every time the model produces:

```text
False Positive
```

save the example.

Every time it misses:

```text
AI generated text classified as human
```

save it.

Build:

```text
HardNegativeCorpus
```

Then retrain periodically.

The loop becomes:

```text
Model
 ↓
Evaluation
 ↓
False positives / negatives
 ↓
Hard-negative corpus
 ↓
Retraining
 ↓
Evaluation
 ↓
Deployment
```

This is how the detector improves rather than accumulating regexes.

---

# 24. ML Model Stack

For mobile deployment, keep the first-stage model lightweight.

Recommended architecture:

```text
Feature Extractor
       ↓
Logistic Regression
       +
Small Gradient-Boosted/Tree Model
       +
Anomaly Detector
       ↓
Calibrated Fusion
```

Do not immediately bundle a huge transformer.

Your current design's biggest advantage is that the 38-feature engine is cheap enough to run on-device.

Preserve that advantage.

---

# 25. Calibration Layer

Raw classifier output is not automatically a probability.

Implement:

```text
CalibrationModel
```

using:

```text
Platt scaling
or
Isotonic regression
```

Then evaluate:

```text
Brier score
ECE
reliability curve
```

A detector saying:

```text
AI probability = 80%
```

should actually correspond approximately to an 80% empirical frequency within the relevant evaluation population.

---

# 26. Uncertainty Engine

Current confidence levels are already length-gated at:

```text
<50
50–149
150–499
500+
```

as represented in the existing `AiConfidenceLevel`.

Upgrade this from simple word-count gating to:

```text
sample length
feature stability
model disagreement
domain shift
training coverage
source availability
sentence count
language confidence
```

For example:

```text
Confidence =
f(
  length,
  ensemble agreement,
  feature stability,
  domain similarity,
  calibration,
  source evidence
)
```

---

# 27. Ensemble Disagreement

Suppose:

```text
Logistic regression     72%
Tree model              69%
Anomaly model           61%
Neural model            45%
```

Do NOT simply average them.

This indicates disagreement.

Instead:

```text
AI estimate: ~62–72%
uncertainty: elevated
```

Whereas:

```text
72%
70%
74%
71%
```

means much stronger agreement.

This becomes an important confidence signal.

---

# 28. Phase 8 — Sentence/Span Forensics

Every sentence should receive:

```text
aiLikelihood
sourceSimilarity
repetitionScore
confidence
signals
```

Example:

```text
Sentence 14

AI likelihood:       82%
Source similarity:   4%
Confidence:          0.81

Signals:
• unusually uniform syntax
• repeated rhetorical structure
• high transition density
```

Another:

```text
Sentence 18

AI likelihood:       31%
Source similarity:   91%
Confidence:          0.94

Source:
Example.com / Source A

Matched tokens:
37
```

This is much more informative than a single document score.

---

# 29. Sentence Heatmap Upgrade

The existing UI already has an interactive sentence breakdown/heatmap concept.

Upgrade it to multiple forensic layers:

```text
AI likelihood
Source similarity
Style anomaly
Repeated phrase
Confidence
```

Allow:

```text
AI view
Plagiarism view
Style view
Combined view
```

---

# 30. Phase 9 — Evidence Fusion

Create an explicit:

```text
EvidenceFusionEngine
```

Inputs:

```text
AI stylometry
ML classifier
AI pattern detector
style-transition detector
source exact match
source fuzzy match
source semantic match
internal repetition
document consistency
external model
```

Each evidence source has:

```text
signal
direction
strength
reliability
coverage
confidence
```

Example:

```dart
EvidenceSignal(
  type: EvidenceType.aiStylometry,
  strength: 0.71,
  reliability: 0.82,
  coverage: 0.91,
)
```

Then calculate calibrated outputs.

---

# 31. Contradiction Handling

This is an advanced but important component.

Example:

```text
AI detector:       82%
Source plagiarism: 4%
Style consistency: 91%
```

Interpretation:

```text
Likely AI-generated
but no source-copy evidence
```

Another:

```text
AI detector:       29%
Source similarity: 93%
```

Interpretation:

```text
Strong source similarity
without strong AI-authorship evidence
```

These must not become:

```text
93% AI plagiarism
```

because those are different phenomena.

---

# 32. Phase 10 — Final Report Architecture

Replace the idea of one giant score with:

```text
FORENSIC REPORT

AI AUTHORSHIP
─────────────
Likelihood: 72%
Class: Mixed / AI-assisted
Confidence: Moderate

SOURCE SIMILARITY
─────────────────
Matched-source evidence: 81%
Sources: 3
Coverage: 22%

INTERNAL REPETITION
───────────────────
Risk: Low

UNCERTAINTY
───────────
Moderate

EVIDENCE
────────
7 AI-like signals
3 source matches
2 anomalous sections
```

Then:

```text
Overall interpretation
```

generated from evidence.

---

# 33. Report Model

Recommended:

```dart
class ForensicReport {
  final AiAuthorshipReport aiAuthorship;
  final SourceSimilarityReport sourceSimilarity;
  final InternalRepetitionReport repetition;
  final List<ForensicSpan> spans;
  final ConfidenceAssessment confidence;
  final List<EvidenceSignal> evidence;
  final String summary;
}
```

Do not let:

```dart
overallScore
```

be the master truth.

Keep it only as a compatibility field for the current UI if required.

---

# 34. Phase 11 — Provider Refactor

The current `PlagiarismProvider` owns:

```text
detector engine
HF model
analysis
humanization
history
toast
```

This is becoming too much responsibility.

Refactor:

```text
PlagiarismProvider
        ↓
ForensicAnalysisCoordinator
        ↓
 ┌───────────────┬────────────────┬────────────────┐
 │               │                │
AiForensics   SourceForensics   DocumentForensics
```

Provider should primarily handle:

```text
UI state
loading
result
errors
selection
```

Business logic belongs in services.

---

# 35. Analysis Modes

Add:

```text
Quick Scan
Deep Scan
Source Scan
AI Scan
Full Forensic Scan
```

### Quick Scan

```text
surface
stylometry
local classifier
```

### Deep Scan

```text
all features
window analysis
ensemble
calibration
```

### Source Scan

```text
exact
fuzzy
semantic
indexed sources
```

### Full Forensic

Everything.

This allows performance control.

---

# 36. Hugging Face Architecture

The current Hugging Face path truncates text to 1500 characters before inference and blends the external model result with the local score.

Do not treat that as a reliable document-level neural score.

For long documents:

```text
document
 ↓
chunks
 ↓
model inference per chunk
 ↓
aggregate
 ↓
confidence
```

Use:

```text
overlapping chunks
```

and aggregate using:

```text
length-weighted probability
```

rather than simply analyzing the first 1500 characters.

Also store:

```text
model name
model version
timestamp
chunk count
successful chunks
failed chunks
```

---

# 37. External Model Should Be an Independent Signal

Architecture:

```text
Local Engine
        +
HF Model
        +
Future Neural Model
        ↓
Calibration/Fusion
```

Do NOT allow:

```text
HF says 90%
```

to automatically override everything.

External model reliability should depend on:

```text
model validation
domain
text length
language
model version
```

---

# 38. Web/Source Search Layer

For true web plagiarism checking:

```text
Document
 ↓
Candidate phrase generation
 ↓
Search retrieval
 ↓
Candidate URLs
 ↓
Fetch content
 ↓
Normalize
 ↓
Exact/fuzzy/semantic comparison
 ↓
Source verification
```

Candidate phrases should be distinctive.

Do not search:

```text
"In conclusion, technology is important..."
```

Search:

```text
rare 8–12 word phrase
```

with high information content.

---

# 39. Source Deduplication

Web results will often contain the same content syndicated across:

```text
Source A
Source B
Source C
```

Cluster sources using:

```text
URL canonicalization
domain relationships
content similarity
```

Then report:

```text
1 underlying source
3 discovered URLs
```

rather than falsely presenting it as three independent matches.

---

# 40. Citation-Aware Detection

Add parsing for:

```text
APA
MLA
Chicago
IEEE
Harvard
URLs
DOIs
footnotes
quotes
blockquote
```

If a matching passage is explicitly quoted and cited:

```text
quoted + cited
```

should be distinguished from:

```text
uncited copied passage
```

The source engine should therefore classify matches:

```text
Quoted
Quoted + cited
Paraphrased + cited
Copied + uncited
Likely common phrase
Unknown
```

---

# 41. Common Phrase Suppression

Build a common-phrase database.

Examples:

```text
according to the study
in recent years
the results show
this study examines
```

These should not create major plagiarism evidence.

The system should focus on:

```text
distinctive phrase similarity
```

rather than generic language.

---

# 42. Source Match Scoring

A source match should combine:

```text
Exact token overlap
Longest contiguous match
Document coverage
Source coverage
Character similarity
Semantic similarity
Phrase distinctiveness
Citation state
```

Conceptually:

```text
matchStrength =
    exactOverlap
  + contiguousMatch
  + semanticSimilarity
  + distinctiveness
  + coverage
  - commonPhrasePenalty
```

Then calibrate this against known copied/paraphrased examples.

---

# 43. Internal Repetition Engine

Keep your current repeated n-gram functionality, but rename its meaning.

It is not:

```text
plagiarism
```

It is:

```text
internal repetition
```

Detect:

```text
repeated 3-grams
repeated 4-grams
repeated 5-grams
repeated sentence templates
repeated semantic propositions
```

This can detect:

```text
AI looping
bad paraphrasing
copy-paste duplication
template repetition
```

without incorrectly calling it external plagiarism.

---

# 44. Advanced AI Signal Families

Create:

```text
AI_SIGNAL
├── lexical
├── syntactic
├── rhetorical
├── structural
├── punctuation
├── semantic
├── discourse
├── repetition
├── predictability
└── style-transition
```

Each signal should have:

```text
name
value
direction
strength
confidence
explanation
```

This replaces hard-coded "AI tell = huge score" logic.

---

# 45. Remove Overreliance on Stock AI Words

Your current engine explicitly checks AI stock vocabulary.

Keep it.

But reduce its importance.

Why?

Because a human can naturally write:

```text
Furthermore
Moreover
crucial
landscape
```

and an AI can be instructed not to.

Therefore:

```text
stock word = weak signal
```

while:

```text
stock vocabulary + structural regularity
+ low stylistic variance
+ model agreement
```

becomes stronger evidence.

---

# 46. Adversarial Robustness Test Suite

Create a permanent test suite containing:

```text
normal human
normal AI
casual AI
edited AI
paraphrased AI
AI with slang
AI with typos
AI without punctuation
AI imitating a human
AI imitating academic writing
AI imitating technical writing
AI with contractions
AI with fragments
human formal writing
human academic writing
human non-native English
human ESL writing
human highly polished writing
```

The detector should be tested against all of them.

---

# 47. False Positive Protection

Create explicit "do not overclaim" tests.

Examples:

```text
formal academic paper → must not automatically become AI
technical documentation → must not automatically become AI
professional report → must not automatically become AI
ESL writing → must not automatically become AI
short text → inconclusive
quoted text → source evidence, not AI evidence
common phrase → low plagiarism evidence
```

---

# 48. Evaluation Dashboard

Every model version should produce:

```text
Accuracy
Precision
Recall
F1
ROC-AUC
PR-AUC
False Positive Rate
False Negative Rate
Calibration Error
Brier Score
```

But most importantly:

```text
False Positive Rate on Human Writing
```

and:

```text
Detection rate on held-out AI generators
```

---

# 49. Evaluation Matrix

Build:

```text
                 Human   GPT   Claude   Gemini   Qwen
Academic           ✓      ✓      ✓        ✓       ✓
Technical          ✓      ✓      ✓        ✓       ✓
Casual             ✓      ✓      ✓        ✓       ✓
Creative            ✓      ✓      ✓        ✓       ✓
Edited              ✓      ✓      ✓        ✓       ✓
Paraphrased         ✓      ✓      ✓        ✓       ✓
```

The final report should show model-family generalization.

---

# 50. Versioned Model Artifacts

Never overwrite weights manually.

Create:

```text
models/
  forensic-v3/
    manifest.json
    normalization.json
    feature-schema.json
    calibration.json
    logistic.bin
    tree.bin
```

Manifest:

```json
{
  "modelVersion": "3.0.0",
  "featureVersion": "3",
  "trainingCorpusVersion": "2026.09",
  "calibrationVersion": "1",
  "language": "en",
  "createdAt": "...",
  "evaluation": {
    "f1": 0.0,
    "falsePositiveRate": 0.0
  }
}
```

The actual values should only be populated from real evaluation.

---

# 51. Feature Versioning

This is critical.

Every report should know:

```text
featureSchemaVersion
modelVersion
calibrationVersion
```

Otherwise future model upgrades make historical reports impossible to interpret.

---

# 52. Deterministic Reproducibility

Given:

```text
same text
same model
same feature version
same configuration
```

the result should be deterministic.

Create:

```text
AnalysisConfig
```

containing:

```text
thresholds
enabled detectors
model version
source mode
chunk size
overlap
language
```

---

# 53. Performance Architecture

For Flutter:

```text
UI
 ↓
Provider
 ↓
Coordinator
 ↓
Isolate
 ↓
Feature extraction
 ↓
ML
```

Long documents should never execute expensive analysis on the UI isolate.

The current implementation already moves texts over 500 characters to an isolate.

Upgrade this to workload-based scheduling.

For example:

```text
< 1000 tokens
→ local synchronous/short isolate

1000–10000
→ isolate

10000+
→ chunked isolate pipeline
```

---

# 54. Streaming Analysis

For very large documents:

```text
Document
 ↓
Chunk 1 → analyze
Chunk 2 → analyze
Chunk 3 → analyze
...
 ↓
aggregate
```

Don't load every derived structure simultaneously.

Use:

```text
chunk → feature → result → release
```

where possible.

---

# 55. Caching

Cache:

```text
normalized text hash
feature vector
sentence segmentation
embeddings
source candidates
```

Key:

```text
SHA-256(text + modelVersion + featureVersion)
```

This makes repeated scans dramatically faster.

---

# 56. Analysis Hash

Every report should contain:

```text
analysisId
textHash
modelVersion
timestamp
```

This gives reproducibility.

---

# 57. Privacy Architecture

For the local engine:

```text
Raw text
 ↓
local processing
 ↓
local report
```

For external AI detection:

```text
explicit user-selected external analysis
 ↓
network
```

The UI should clearly distinguish:

```text
ON-DEVICE
```

from:

```text
CLOUD
```

Your current system already distinguishes the on-device engine and Hugging Face engine in the provider.

---

# 58. Phase 12 — Report UX

The current UI already exposes:

```text
likelihood
confidence
flow
patterns
vocabulary
AI tells
```

and an uncertainty banner.

Upgrade the UX to:

## Main card

```text
FORENSIC ANALYSIS

AI AUTHORSHIP
72% likely AI-assisted

Confidence
Moderate

SOURCE SIMILARITY
18%

INTERNAL REPETITION
Low
```

Then:

```text
WHY?
```

expands evidence.

---

# 59. Evidence Cards

Example:

```text
STYLE ANOMALY

High sentence uniformity

Observed:
18.4 words average
σ = 2.1

This is one signal among several.
```

Another:

```text
SOURCE MATCH

87% semantic similarity

Source:
example.com/article

Matched region:
"..."

Coverage:
14.2%
```

---

# 60. Don't Present AI Detection as Proven Fact

Avoid:

```text
AI GENERATED: YES
```

Prefer:

```text
Likely AI-generated
```

or:

```text
AI-like characteristics detected
```

And:

```text
Insufficient evidence
```

for weak cases.

This is particularly important because authorship attribution from text alone is probabilistic.

---

# 61. Phase 13 — Humanizer Integration

Your current provider immediately re-analyzes humanized text and stores the result.

Keep the comparison architecture, but expand it.

Compare:

```text
Original
 ↓
Humanized
```

with:

```text
AI score change
Source similarity change
Vocabulary change
Style fingerprint change
Meaning preservation
```

Do NOT optimize the humanizer simply to "beat the detector."

Instead:

```text
Preserve meaning
Preserve factual claims
Preserve citations
Improve naturalness
Reduce repetitive/formulaic structure
```

---

# 62. Semantic Preservation Test

After humanization:

```text
Original embedding
        ↕
Output embedding
```

Measure semantic similarity.

Also compare:

```text
entities
numbers
dates
technical terms
citations
```

to prevent the humanizer from silently changing facts.

---

# 63. Anti-Gaming Protection

The engine should not be defeated by:

```text
adding random punctuation
changing every adjective
introducing typos
adding slang
splitting sentences
```

because the classifier should use multiple independent signals.

Architecture:

```text
surface
+
lexical
+
syntax
+
structure
+
semantic
+
stylometry
+
model ensemble
```

not:

```text
AI words = AI
```

---

# 64. Source Plagiarism Confidence Levels

Use:

```text
No meaningful source evidence
Weak source similarity
Possible source similarity
Strong source similarity
Very strong source match
```

rather than mapping source similarity directly to AI likelihood.

---

# 65. Document-Level Aggregation

For source plagiarism:

```text
document coverage
```

matters more than number of matches.

Example:

```text
3 matches × 10 words = 30 words
```

in a:

```text
5000-word document
```

is very different from:

```text
3 matches × 300 words
```

Therefore calculate:

```text
matchedTokenCoverage
matchedSentenceCoverage
matchedParagraphCoverage
```

---

# 66. Source Match Deduplication

If five matching passages all originate from one source:

```text
Source A
 ├─ Match 1
 ├─ Match 2
 ├─ Match 3
 ├─ Match 4
 └─ Match 5
```

report one source with five segments.

Don't count them as five independent sources.

---

# 67. Citation Awareness

If the user has:

```text
quotation + citation
```

show:

```text
MATCH FOUND
CITED QUOTATION
```

rather than:

```text
PLAGIARISM
```

The detector identifies similarity; the interpretation of whether use is legitimate depends on context.

---

# 68. Test Architecture

Create:

```text
test/
 ├── forensic/
 │   ├── tokenizer_test.dart
 │   ├── sentence_segmentation_test.dart
 │   ├── feature_extractor_test.dart
 │   ├── stylometry_test.dart
 │   ├── calibration_test.dart
 │   └── fusion_test.dart
 │
 ├── plagiarism/
 │   ├── exact_match_test.dart
 │   ├── fuzzy_match_test.dart
 │   ├── semantic_match_test.dart
 │   ├── source_coverage_test.dart
 │   └── citation_test.dart
 │
 ├── adversarial/
 │   ├── edited_ai_test.dart
 │   ├── casual_ai_test.dart
 │   ├── paraphrase_test.dart
 │   └── human_false_positive_test.dart
 │
 └── regression/
     └── golden_reports_test.dart
```

---

# 69. Golden Test Corpus

Maintain a version-controlled benchmark:

```text
case_0001_human.txt
case_0002_ai.txt
case_0003_hybrid.txt
case_0004_copy.txt
case_0005_paraphrase.txt
...
```

Each case has:

```json
{
  "expectedClass": "...",
  "expectedSource": "...",
  "expectedConfidence": "...",
  "expectedSignals": [...]
}
```

Don't hardcode exact probabilities unless they are deliberately regression-tested.

---

# 70. Training Pipeline

Recommended:

```text
Raw datasets
 ↓
deduplication
 ↓
language filtering
 ↓
quality filtering
 ↓
source grouping
 ↓
author grouping
 ↓
feature extraction
 ↓
train/validation/test split
 ↓
model training
 ↓
calibration
 ↓
adversarial evaluation
 ↓
cross-model evaluation
 ↓
export
 ↓
mobile integration
```

---

# 71. Training Script Improvements

Your existing training script already validates the feature vector length and cross-validates the classifier.

Extend it to output:

```text
feature importance
confusion matrix
precision
recall
F1
ROC-AUC
PR-AUC
FPR
FNR
Brier score
ECE
per-domain metrics
per-model metrics
per-length metrics
```

And produce machine-readable:

```text
training_metrics.json
```

alongside the Dart constants/artifacts.

---

# 72. Feature Ablation Testing

This is essential.

Run:

```text
all features
```

then:

```text
without punctuation
without vocabulary
without AI stock words
without burstiness
without syntax
without semantic features
```

Measure what actually contributes.

If removing:

```text
AI stock vocabulary
```

barely changes performance, good.

If removing:

```text
style fingerprint
```

destroys performance, invest there.

This prevents building mythology around individual "AI tells."

---

# 73. Calibration by Text Length

Create separate calibration curves:

```text
50–150 words
150–500
500–1000
1000+
```

because confidence behaves differently across lengths.

---

# 74. Domain Calibration

Also calibrate by:

```text
academic
technical
casual
creative
business
journalistic
```

A technical document naturally has more regularity than a personal diary.

The detector should know this.

---

# 75. Language Gate

Your current engine is primarily English-oriented.

Explicitly detect:

```text
language
```

If the text is not sufficiently English:

```text
English detector confidence = low
```

Do not confidently classify another language using an English-trained model.

---

# 76. Robustness to Formatting

Normalize:

```text
Markdown
HTML
PDF extraction artifacts
smart quotes
Unicode punctuation
multiple spaces
line breaks
```

But retain the original formatting as a separate signal.

---

# 77. Phase 14 — Observability

Record anonymous aggregate telemetry if the product/privacy design allows it:

```text
analysis duration
text length bucket
model version
feature extraction failures
source lookup failures
model disagreement
```

Do not log raw user text unless explicitly justified and consented to.

---

# 78. Performance Targets

Target:

### Quick scan

```text
< 200 ms
```

for typical short text on modern devices.

### Medium document

```text
< 1 second
```

target for local stylometry.

### Large document

```text
progressive analysis
```

rather than freezing the UI.

### Network source scan

Show:

```text
Retrieving sources...
Analyzing matches...
Verifying evidence...
```

instead of a generic spinner.

---

# 79. Recommended Final Engine Modules

```text
lib/
└── services/
    └── forensic/
        ├── forensic_engine.dart
        ├── forensic_coordinator.dart
        │
        ├── ai/
        │   ├── ai_forensic_engine.dart
        │   ├── stylometric_engine.dart
        │   ├── syntax_engine.dart
        │   ├── lexical_engine.dart
        │   ├── discourse_engine.dart
        │   ├── style_transition_engine.dart
        │   └── ai_signal_engine.dart
        │
        ├── plagiarism/
        │   ├── source_engine.dart
        │   ├── exact_match_engine.dart
        │   ├── shingle_engine.dart
        │   ├── fuzzy_match_engine.dart
        │   ├── semantic_match_engine.dart
        │   ├── source_repository.dart
        │   └── source_deduplicator.dart
        │
        ├── document/
        │   ├── document_segmenter.dart
        │   ├── span_analyzer.dart
        │   ├── repetition_engine.dart
        │   └── authorship_transition_engine.dart
        │
        ├── ml/
        │   ├── classifier.dart
        │   ├── ensemble.dart
        │   ├── calibration.dart
        │   └── anomaly_detector.dart
        │
        ├── normalization/
        │   ├── text_normalizer.dart
        │   ├── tokenizer.dart
        │   └── position_mapper.dart
        │
        └── evidence/
            ├── evidence_fusion.dart
            ├── confidence_engine.dart
            └── explanation_engine.dart
```

---

# 80. Recommended Report Model

```text
ForensicReport
│
├── metadata
│   ├── analysisId
│   ├── textHash
│   ├── modelVersion
│   └── featureVersion
│
├── aiAuthorship
│   ├── probability
│   ├── class
│   ├── confidence
│   ├── signals
│   └── windows
│
├── sourceSimilarity
│   ├── risk
│   ├── documentCoverage
│   ├── matches
│   └── sources
│
├── internalRepetition
│   ├── score
│   ├── repeatedPhrases
│   └── repeatedStructures
│
├── spans
│
├── evidence
│
├── uncertainty
│
└── summary
```

---

# 81. Implementation Order

Do NOT implement everything simultaneously.

### Sprint 1

```text
Domain model
Normalization
Feature schema
Report schema
```

### Sprint 2

```text
AI feature engine
Window segmentation
Stylometric fingerprint
```

### Sprint 3

```text
ML training pipeline
Calibration
Ensemble
```

### Sprint 4

```text
Exact source matching
Shingling
Longest-match algorithm
```

### Sprint 5

```text
Fuzzy matching
Source coverage
Source deduplication
```

### Sprint 6

```text
Semantic retrieval
Embedding index
Candidate verification
```

### Sprint 7

```text
Hybrid/mixed authorship
Style transitions
Span-level analysis
```

### Sprint 8

```text
Evidence fusion
Confidence
Explanations
```

### Sprint 9

```text
Provider refactor
UI
Heatmaps
Source panels
```

### Sprint 10

```text
Adversarial testing
Performance
Regression tests
Production hardening
```

---

# 82. Production Acceptance Gates

Do not ship based on:

```text
"It works on my examples."
```

Require:

### Gate A — Data

```text
large diverse corpus
deduplicated
grouped splits
```

### Gate B — Generalization

```text
held-out authors
held-out domains
held-out AI models
```

### Gate C — Calibration

```text
probabilities calibrated
uncertainty validated
```

### Gate D — Source evidence

```text
exact/fuzzy/semantic matches independently tested
```

### Gate E — False positives

```text
human formal writing tested
ESL writing tested
technical writing tested
academic writing tested
```

### Gate F — Performance

```text
mobile benchmark passed
```

### Gate G — Regression

```text
golden corpus passed
```

---

# 83. Final Lauriva 3.0 Decision Architecture

The final engine should conceptually operate like this:

```text
                       DOCUMENT
                           │
                           ▼
                  ┌─────────────────┐
                  │ NORMALIZE       │
                  └────────┬────────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
        AI FORENSICS   SOURCE MATCH    DOCUMENT STYLE
            │              │              │
            │              │              │
       stylometry       exact            repetition
       syntax           fuzzy            transitions
       vocabulary       semantic         anomalies
       structure        source           consistency
       predictability   coverage
            │              │              │
            └──────────────┼──────────────┘
                           ▼
                  ┌─────────────────┐
                  │ EVIDENCE FUSION │
                  └────────┬────────┘
                           ▼
                  ┌─────────────────┐
                  │ CALIBRATION     │
                  │ + UNCERTAINTY   │
                  └────────┬────────┘
                           ▼
              ┌─────────────────────────┐
              │ FORENSIC REPORT        │
              │                         │
              │ AI likelihood           │
              │ Source similarity       │
              │ Mixed authorship        │
              │ Internal repetition     │
              │ Confidence              │
              │ Evidence spans          │
              └─────────────────────────┘
```

# 84. The Most Important Changes

If we have to prioritize, these are the **10 highest-value upgrades**:

1. **Separate AI detection from plagiarism completely.**
2. **Replace the current source-plagiarism score with actual source matching.**
3. **Add exact + fuzzy + semantic similarity.**
4. **Introduce document-window and sentence-level authorship analysis.**
5. **Build a real human/AI/hybrid training corpus instead of relying on tiny curated examples.**
6. **Add adversarial AI and hard-negative mining.**
7. **Calibrate model probabilities instead of treating classifier outputs as probabilities.**
8. **Use ensemble disagreement as uncertainty.**
9. **Make every major result evidence-backed and explainable.**
10. **Keep the lightweight feature-based architecture for mobile while allowing optional cloud/neural enhancement.**

# 85. Target End State

Lauriva should eventually answer four independent questions:

```text
┌─────────────────────────────────────────────┐
│ AI AUTHORSHIP                               │
│                                             │
│ Likely AI-assisted                          │
│ Confidence: Moderate                        │
│                                             │
│ Evidence:                                   │
│ • structural regularity                    │
│ • vocabulary distribution                   │
│ • sentence-template repetition             │
│ • ensemble agreement                       │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ SOURCE SIMILARITY                            │
│                                             │
│ Strong source match                         │
│                                             │
│ 3 source passages                           │
│ 18.4% document coverage                     │
│ Longest match: 42 tokens                    │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ MIXED AUTHORSHIP                             │
│                                             │
│ Possible AI-assisted section                │
│                                             │
│ Paragraphs 7–10 show a different            │
│ stylistic fingerprint.                      │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ CONFIDENCE                                   │
│                                             │
│ Moderate                                     │
│                                             │
│ Evidence is probabilistic; no single signal │
│ determines authorship.                      │
└─────────────────────────────────────────────┘
```

That is the direction I would take Lauriva if I were responsible for the architecture as the principal engineer.

The biggest conceptual upgrade is **not "more AI detection rules."**

It is turning Lauriva from:

```text
AI score + plagiarism score
```

into:

```text
FORENSIC EVIDENCE SYSTEM
```

where AI authorship, source similarity, internal repetition, mixed authorship, and uncertainty are independently measured and then fused.

Your existing 38-feature v2 is a good foundation for that architecture; the training script already validates the vector and performs cross-validation, so the next step is to make the underlying data, source matching, calibration, and evidence model production-grade rather than endlessly adding regex patterns.