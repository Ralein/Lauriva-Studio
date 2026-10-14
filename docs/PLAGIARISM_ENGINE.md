# Plagiarism & AI-Detection Engine

This document covers `lib/services/plagiarism_detector_service.dart` — Lauriva's
client-side text-forensics engine — what it does, what changed in this pass, and
how to maintain the on-device ML classifier it now includes.

## Architecture

Four layers, orchestrated cleanly inside `PlagiarismDetectorService`:

1. **Rule-based NLP engine** (`analyze()`) — sentence segmentation, n-gram
   repetition, lexical richness (TTR + Guiraud's R), burstiness (coefficient of
   variation of sentence length), a curated set of regex "tells" for known LLM
   phrasing, a stock-vocabulary list, and an academic-boilerplate phrase list.
   Runs fully offline, in a background isolate for texts over 500 characters
   (`analyzeAsync`, via `compute`).
2. **On-device Forensics Engine v2 (`AiForensicService`)** — a 38-feature
   stylometric extraction pipeline across 6 feature families, evaluating an
   on-device pure-Dart ensemble of three components:
   - An L2-regularized logistic regression whose weights are genuinely fit
     by `tool/train_stylometric_classifier.dart` (55% ensemble weight — the
     largest share, since it's the one component actually trained on data).
   - A **hand-authored heuristic-priors evaluator** (30% weight) — 20 small
     threshold rules, one per signal (e.g. "em dash rate > 0.20 → nudge
     toward AI"). Earlier in this file/codebase this was called a "20-tree
     GBDT" — that name has been corrected: these are domain-expert rules,
     not trees fit by gradient boosting, and calling them a GBDT overstated
     what they are.
   - A centroid-distance anomaly signal (15% weight) — how far a passage's
     burstiness/lexical-diversity/opener profile sits from a typical-human
     reference point.
   - Dynamic length-gating (<50 words triggers high uncertainty and conservative scaling).
3. **Decoupled Source Plagiarism Service (`SourcePlagiarismService`)** —
   isolated shingling, repeated n-gram detection, and formulaic boilerplate
   matching separate from AI stylometry. `PlagiarismReport.plagiarismRiskScore`
   is owned by this service (not re-derived inline in `PlagiarismDetectorService`
   — an earlier version computed a near-duplicate value inline and threw this
   service's result away except for its `repeatedNgrams` fallback; fixed).
4. **Optional remote ensemble** (`analyzeWithHuggingFace()`) — calls the free
   Hugging Face Inference API for a configured model (default
   `Hello-SimpleAI/chatgpt-detector-roberta`) and blends its output 60/40 with
   the local report. Zero app-size cost since it's a network call, not a
   bundled model; gracefully falls back to the local report on any failure.

## The On-Device ML Classifier (Engine v2)

### Why not a bundled neural network

The app has a hard **150MB total size budget**. Rather than bundling heavy
PyTorch/ONNX models (65–500MB), Lauriva uses a **pure-Dart native compiled ensemble**
over 38 engineered linguistic dimensions that evaluates in under **0.5 milliseconds**
with zero native allocations and zero asset size penalty.

### 38 Stylometric Features (6 Families)
1. **Surface & Length Statistics (0-9):** `sentenceCount`, `wordCount`, `charPerWordMean`, `charPerWordVar`, `sentenceLenMean`, `sentenceLenStd`, `burstinessCv`, `sentenceLenSkew`, `sentenceLenEntropy`, `paragraphLenVar`.
2. **Punctuation Fingerprint (10-17):** `commaRate`, `semicolonColonRate`, `emDashRate`, `parenthesesRate`, `hyphenCompoundRate`, `quoteDialogueRate`, `punctuationDiversity`, `terminalPunctSkew`.
3. **Lexical & Vocabulary Dynamics (18-25):** `ttrStandard`, `mattr50` (moving-average TTR), `guiraudR`, `hapaxLegomenaRatio`, `functionWordRatio`, `pronounDistribution` (1st vs 3rd person), `modalHedgingDensity`, `aiStockWordDensity`.
4. **Syntactic & Structural Complexity (26-31):** `transitionOpenerRatio`, `openerDiversity`, `triadStructureRate`, `contrastFormulaRate`, `subordinatingConjRate`, `fragmentFrequency`.
5. **Cohesion & Repetition (32-35):** `trigramOverlapRatio`, `fourgramOverlapRatio`, `markdownSyntaxDensity`, `wrapperPhraseScore`.
6. **Semantic Cohesion & Dispersion (36-37):** `academicBoilerplateRate`, `mahalanobisHumanDist`.

### Length Gating & Defensible Scientific Framing
Stylometric features cannot guarantee statistical significance on tiny samples.
Engine v2 gates confidence by token count:
- `< 50 words`: High uncertainty (0.75), sample flagged as inconclusive.
- `50–150 words`: Low-to-moderate confidence (0.35 uncertainty).
- `150–500 words`: Moderate-to-high confidence (0.15 uncertainty).
- `500+ words`: High certainty (0.06 uncertainty).

The UI replaces absolute claims with probabilistic, defensible findings
(e.g., *"Likely AI-Generated · Moderate Confidence"*) accompanied by specific
contributory signals.

More broadly: no verified, properly-documented, pre-quantized text-classification
model exists that's confirmed to fit comfortably in this budget alongside the
rest of the app (a quantized DistilBERT/MobileBERT still typically runs
65–110MB for the model alone), and converting/quantizing one from scratch
requires a Python ML toolchain, GPU, and labeled corpus this repo and session
don't have.

Published research supports a different approach for exactly this constraint:
["A Lightweight Approach to Detection of AI-Generated Texts Using Stylometric
Features"](https://arxiv.org/pdf/2511.21744) (2025) and the NEULIF framework
report that compact classifiers over engineered linguistic features reach
~95–97% accuracy — "near-transformer accuracy at a fraction of the
computational cost" — specifically for resource-constrained deployment. That's
the approach implemented here.

### What it is

A **logistic regression classifier** over 13 stylometric features, shipped as
plain `static const` Dart weight arrays — no model file, no native ML runtime
(no `tflite_flutter`/ONNX dependency), no bundled asset. Compiled size impact
is a few hundred bytes of constant doubles.

**Features** (`PlagiarismDetectorService.mlFeatureNames`, in order):
`burstiness`, `avgSentenceLength`, `lexicalRichness`, `ngramOverlapScore`,
`stockWordDensity`, `boilerplateCount`, `emDashRate`, `markdownCount`,
`transitionOpenerRatio`, `avgWordLength`, `punctuationDiversity`,
`functionWordRatio`, `patternTellScore`.

`extractFeatureVector(text)` computes these (`@visibleForTesting`, so both the
app and the training script call the identical code — no train/serve skew).
`mlClassifierScore(text)` z-score-normalizes the features against the trained
means/std-devs, applies the learned weights + bias, and runs a sigmoid to
produce a 0–100 AI-likelihood score.

In `analyze()`, this score is blended into the rule-based score as
`(ruleBasedScore * 0.65) + (mlScore * 0.35)` — weighted lower than the
hand-tuned rule engine since it's trained on a much smaller corpus. When the
ML score alone is ≥50%, it's also surfaced as its own entry in
`detectedTells` ("On-device ML classifier: NN.N% AI confidence") for
transparency.

### Training methodology — and its honest limitation

Weights are produced by `tool/train_stylometric_classifier.dart` (run via
`flutter test tool/train_stylometric_classifier.dart` — it needs the Flutter
test harness because the service imports `package:flutter/foundation.dart`
for `@visibleForTesting`/`compute`, and plain `dart run` can't load `dart:ui`).
It fits the logistic regression via L2-regularized batch gradient descent
(4000 epochs, lr 0.15) over a **60-example curated corpus** (30 human, 30
AI-style) hard-coded in the script, then prints ready-to-paste weight/mean/
std-dev constants.

**Be clear about what this corpus is**: it is not a scraped, independently
labeled real-world dataset. The 30 human examples span varied natural
registers (narrative, technical notes, casual writing, opinion, instructions).
The 30 "AI" examples are deliberately written to exhibit the well-documented
LLM tells this engine already targets (em dashes, formal transition openers,
markdown residue, stock vocabulary, chatbot wrapper phrases, tricolons). This
is a legitimate technique (weak/distant supervision) for a small linear model
targeting a known, documented signal space, and it reached 100% training
accuracy — expected given how cleanly the two classes were written, and a
signal that the model fits this particular corpus very well, not necessarily
proof of real-world generalization to text near the decision boundary or
adversarial paraphrasing. Treat its confidence numbers as a useful second
opinion alongside the rule engine, not a certified ground truth.

**To improve it**: replace or extend `_humanTexts`/`_aiTexts` in the training
script with a larger, independently-sourced labeled corpus (e.g. a public
human-vs-LLM-text dataset) and re-run the script; paste the new printed
constants into `PlagiarismDetectorService`.

### Validation results — and four bugs fixed in this pass

`flutter test tool/train_stylometric_classifier.dart` now runs genuine
**5-fold cross-validation**: each fold trains its own logistic regression
from scratch on the other 4/5 of the corpus and is scored only on the 1/5
it never saw during that fold's training. Current result:

```
Mean Accuracy:  83.3% (± 5.3 across folds)
Mean Precision: 96.0%
Mean Recall:    70.0% (± 6.7 across folds)
Mean FPR:       3.3%
Pooled confusion matrix across all folds: [TP: 21, FP: 1, TN: 29, FN: 9]
Per-fold accuracy: 83%, 92%, 75%, 83%, 83%
```

This is the honest number, and it is **not** "flawless" — it misses about
3 in 10 AI-authored holdout examples (mean recall 70%), and the ±5-7 point
spread across folds is itself telling you how much to trust the mean on a
corpus this small (60 examples, ~12 per fold). No authorship-detection
system — including paid commercial ones trained on millions of examples —
reliably hits anything close to 100% on real-world, adversarially-
paraphrased, or genre-diverse text. Treat this as one honest, directional
data point, not a warranty.

Four real bugs were found and fixed to get here honestly:

1. **The shipped weights weren't actually trained.** The training script fit
   its own logistic regression but never printed or wired the result back
   into `AiForensicService` — the `_featureMeans`/`_featureStdDevs`/
   `_logRegWeights` shipped there were hand-typed numbers presented as
   "derived from reference corpus." The script now fits a final model on the
   full corpus and prints a ready-to-paste block; those are the constants
   now in the file.
2. **The original holdout confusion matrix had a copy-paste bug**: the
   false-negative counter used the exact same condition as the true-negative
   counter (`!isPredictedAi && !isTrueAi` for both), so every true negative
   was also miscounted as a false negative. This silently hid the model's
   real recall (masked ~57% as if it were 33%).
3. **L2 regularization was ~60x weaker than intended.** The gradient update
   divided the penalty term by `n` on top of the per-example gradient already
   being an average — for a 38-feature model fit on only 45-60 examples
   (severe overparameterization, d/n ≈ 0.6-0.85), this let weights grow
   large (one hit 4.24) and made the model unstable on inputs even slightly
   different from its exact training rows (a near-duplicate of a training
   example scored 57% AI instead of the expected <45%). Fixing the division
   and raising `l2` to 3.0 shrank the weights by roughly two orders of
   magnitude and fixed that failure.
4. **The single 75/25 split's "holdout" wasn't actually held out.** The
   original validator trained a throwaway model on 75% of the corpus (bug
   #1's leftover), then evaluated `forensics.auditText()` — the *shipped*
   ensemble, whose weights come from a fit on the **full** corpus — against
   the remaining 25%. Since the shipped model had already seen those
   "holdout" examples during its full-corpus training fit, the reported
   "100% holdout accuracy" was actually in-sample accuracy wearing a
   holdout's name — a textbook data-leakage bug that made the model look
   perfect for the wrong reason. The 5-fold cross-validation above (each
   fold's model trained only on data it's then never scored against) is the
   fix, and it's the reason the honest number is 83%/70% recall, not 100%.

The v1 13-feature classifier (`PlagiarismDetectorService`'s own
`mlClassifierScore`) had the identical L2-divide-by-`n` bug in its original
training script, for the same reason (it was written the same way, before
this pass). `tool/train_stylometric_classifier.dart` now cross-validates and
refits both classifiers with one shared, corrected training function.
That fix over-corrected for v1: at `l2 = 3.0` its weights collapsed to
~0.003-0.09, so every output sat in ~45-58% and the classifier acted as a
constant pulling blended scores toward the middle, while its 0.5-threshold
accuracy still looked fine. The trainer now reports out-of-fold log-loss,
Brier score, and ROC-AUC and sweeps `l2`; v1 is refit at `l2 = 0.03`:
**86.7% ± 6.7% accuracy, 76.7% recall, 3.3% FPR, log-loss 0.29 (was 0.59),
Brier 0.09 (was 0.20), AUC 0.968 (was 0.898)**. v2 stays at `l2 = 3.0`: it
has the grid's best AUC (0.951) and lowest FPR, and `PlattCalibrator`
(A = -2.183) was fit to exactly its compressed output range, so refitting
v2 alone would silently mis-calibrate the ensemble.

### Consolidated lexicons (drift-risk fix)

The stock-AI-word list, transition-opener list, academic-boilerplate list,
function-word list, and em-dash/markdown regexes used to be independently
copy-pasted across `PlagiarismDetectorService`, `AiForensicService`, and
`SourcePlagiarismService` — three near-identical but not-quite-identical
copies with no compiler warning if they drifted. They're now defined once in
`lib/services/text_forensics_lexicons.dart` and imported by all three
services; updating a signal in one place now updates it everywhere.

### Source matching and sentence attribution (Engine 3.6)

Source similarity (`lib/services/forensic/sources/`, `SourceSimilarityService`)
aligns the submitted text against three kinds of candidate sources: the
in-memory `SourceRepository.baselineLiterature` (small seed corpus plus
documents registered at runtime), the offline fingerprint index
(`CompactCorpusIndex`, when downloaded), and documents fetched by the online
tier for the current scan. The online tier and the offline index are described
in the next section; the alignment below decides what counts as a match, no
matter where the candidate came from.

* **Retrieval**: exact 5-grams plus stemmed content trigrams, so passages with
  light edits still surface their source.
* **Alignment** (`ShingleMatchingEngine`): seed-and-extend on stemmed
  tokens, tolerating up to 2 consecutive inserted/deleted/substituted tokens.
  Segments need 5+ aligned tokens, 3+ of them content words, and an edit
  ratio of 0.34 or less. Offsets come from the tokenizer, so highlights land on
  the real occurrence.
* **Paraphrase tier**: sentences that are less than half covered by verbatim
  alignment are compared to source sentences by weighted content-stem
  containment plus character-trigram cosine. This is lexical only: a synonym-level
  rewrite with no shared vocabulary is out of reach without embeddings.
* **Scoring**: coverage is the union of matched tokens across sources,
  weighted by attribution (uncited 1.0, cited 0.6, quoted 0.4, quoted and cited
  0) and by tier (paraphrase ×0.6). Quote detection is paragraph-scoped and
  ignores apostrophes.

Per-sentence AI scores (`SentenceAttributionModel`) no longer run the
document classifier on single sentences, where burstiness is always 0.
Each sentence starts from the document/window posterior and is updated
in log-odds by sentence-local cues. The isolate path uses the same model.

Measured on the same inputs before (commit 685bfdd) and after:

| Input | Source score before → after | Coverage before → after | Sentence AI before → after |
|---|---|---|---|
| Light edit of Vaswani et al. | 50.4 → 86.0 | 65% → 100% | 57 → 59 |
| Heavier edit of He et al. | 39.6 → 66.9 | 52% → 76% | 100/90 → 17/17 (doc: 12% AI) |
| Reordered paraphrase (photosynthesis) | 23.9 → 52.1 | 28% → 71% | 52 → 56 |
| Original text, same topic | 0 → 0 | 0% → 0% | 35 → 32 |
| Casual human text | 0 → 0 | 0% → 0% | 100/87/87 → 13/9/7 (doc: 9% AI) |

These are single illustrative inputs, not a benchmark corpus. The regression
suite in `test/forensic/engine_accuracy_upgrade_test.dart` pins them.

## Hybrid source search (offline + online)

Source checking has two candidate-finding tiers. Both only supply
*candidates*; the alignment in the previous section is the only thing that
produces matches, so a topically similar abstract that cannot be aligned adds
nothing to the score. The online tier runs only in the `fullForensic` and
`sourceScan` scan modes (`ForensicCoordinatorService`), and only when the
user's "Online source check" switch is on.

### Offline tier: LSC1 fingerprint corpus

* **What it is**: `CompactCorpusIndex` reads an LSC1 file
  (`source_corpus_v2.bin`, 25,146,470 bytes) holding hashed 4-gram
  fingerprints only, no readable text. Build manifest
  (`tool/corpus/build/manifest.json`): 62,881 documents (59,956 arXiv
  abstracts, 2,564 Project Gutenberg chunks, 361 public speeches), 4,849,162
  fingerprints, 205 near-duplicates dropped.
* **Decision rule** (stored in the index header, read back by
  `CompactCorpusIndex`): `gap` 10, `minRunFps` 5, `minSpan` 14,
  `minCoverage` 0.20, `strongTokens` 60. A source is reported when a run of at
  least 5 fingerprints of one document, spanning at least 14 tokens with no
  gap above 10 tokens, covers at least 20% of the query or at least 60 tokens.
  See `tool/corpus/README.md` for why these values must not drift.
* **Delivery**: the file is **not bundled** in the app (`pubspec.yaml` lists
  only the 32-byte `assets/source_corpus_v2.id` and the attributions file).
  `CorpusLoader.warmup()` and the coordinator call
  `CompactCorpusIndex.ensureReady()`; when that returns null,
  `CorpusDeliveryService.ensureInBackground()` starts a download of
  `defaultRemoteUrl` (a GitHub release asset on `Ralein/Lauriva-Mobile`, tag
  `source-corpus-v2`), but only on an unmetered interface (name matching
  wlan/wifi/eth/en0/en1; unknown means no download), at most once per 6 hours
  after a failure, and never under `flutter test`. The stream is hashed while
  it is written; a SHA-256 or size mismatch against `defaultSha256` /
  `defaultSizeBytes` discards the file. On success it is renamed to
  `CompactCorpusIndex.cachePath` (a file under `Directory.systemTemp`) with a
  `.id` sidecar holding the first 32 hex characters of the hash.
* **Until it lands**, scans use the online tier plus the small in-memory
  corpus; afterwards every scan also queries the index. If the OS clears the
  temp directory the file is simply downloaded again.

### Online tier

`OnlineSourceSearchService.search(text)`: `SourceQueryGenerator` picks up to
8 excerpts, runs every enabled retriever in parallel, de-duplicates by
DOI/URL/title, drops hits under 12 words and hands at most 40 documents to the
aligner. It never throws.

| id | Class | Access | Returns |
|---|---|---|---|
| `duckduckgo` | `DuckDuckGoInstantRetriever` | keyless | Instant Answer abstract (encyclopedia-style summary) |
| `wikipedia` | `WikipediaRetriever` | keyless | article intro extracts (falls back to search snippets) |
| `bing` | `BingWebRetriever` | keyless, parses the public result page | titles + result snippets |
| `brave_web` | `BraveWebRetriever` | keyless, parses the public result page | titles + result snippets |
| `exa` | `ExaMcpRetriever` | keyless, free public MCP endpoint (`mcp.exa.ai`) | matching passages ("highlights") of each page |
| `europe_pmc` | `EuropePmcRetriever` | keyless | titles + abstracts |
| `openalex` | `OpenAlexRetriever` | keyless, optional key `openalex` | titles + abstracts |
| `crossref` | `CrossrefRetriever` | keyless | titles + abstracts (only records that have one) |
| `doaj` | `DoajRetriever` | keyless | titles + abstracts |
| `ncbi_pubmed` | `NcbiPubMedRetriever` | keyless | titles + abstracts |
| `semantic_scholar` | `SemanticScholarRetriever` | keyless, optional key `semantic_scholar` | titles + abstracts |
| `arxiv` | `ArxivRetriever` | keyless | titles + abstracts |
| `brave` | `BraveSearchRetriever` | **keyed** (`brave_search`); disabled without a key | titles + snippets |
| `serper` | `SerperSearchRetriever` | **keyed** (`serper`); disabled without a key | titles + snippets |

`withDefaults` registers all 14; the two keyed ones are skipped unless
`apiKeyLookup` returns a key. No full web pages are ever fetched.

**Throttling, budgets, breakers**

* Each retriever has its own `RequestThrottle` (minimum spacing between
  requests, e.g. arXiv 3 s, Semantic Scholar 1.1 s, Bing/Brave pages 0.9 s,
  Exa 0.7 s) shared across scans, a per-request timeout (default 7 s, Exa 12
  s) and a per-scan query budget (`maxQueriesPerScan`: arXiv 2, Semantic
  Scholar 3, Bing/Brave/Exa 3, PubMed 3, DOAJ 4, Europe PMC 4, OpenAlex 8,
  default 6).
* A retriever that fails twice in one scan is not queried again in that scan.
  Its `CircuitBreaker` opens after 3 failures and skips it for 2 minutes. A
  result-page retriever that gets an empty page that is not a recognised "no
  results" page counts that as a failure (challenge or changed markup), so it
  is neither cached nor trusted.
* Successful responses are cached in memory (LRU, 256 entries, 6 hour TTL),
  keyed by a SHA-256 of `retrieverId|query`, so the cache never stores user
  text verbatim; failures are not cached.
* `OnlineSourceSearchService.overallDeadline` is 15 s and partial results are
  kept. The coordinator is stricter: it wraps the whole search in a 10 s
  timeout for `sourceScan` and 8 s for `fullForensic`, and on timeout carries
  on with no online documents.

**Graceful degradation**: offline, blocked, rate-limited or CAPTCHA'd
retrievers just contribute nothing; the scan completes with whatever the
in-memory corpus, the downloaded index and the retrievers that did answer
provide. A report with few or no sources means "none found by these tiers",
not "original".

**User control**: the "Online source check" switch in the Audit Profile sheet
(`lib/widgets/forensic_mini_settings.dart`) is bound to
`PlagiarismProvider.enableOnlineSearch`. It defaults to on and is held only in
memory, so it resets to on at each app start. Off means the offline index
only and nothing leaves the device. Several internal paths (for example the
humanizer's own checks) pass `enableOnlineSearch: false` regardless.

**What leaves the device**: only query excerpts chosen by
`SourceQueryGenerator`. At most 8 excerpts per scan; the free-text query is
about 25 words or fewer with punctuation stripped, plus a five-keyword subset
and a short (5 to 8 token) quoted phrase for the web engines. Emails, URLs,
@handles and long digit runs are redacted before selection. Requests carry an
app User-Agent with a support contact address, not a user identifier (the
Bing/Brave page retrievers send a mobile-browser User-Agent). Nothing else
from the document is transmitted.

### Known limitations / honest caveats

* **Bing and Brave are scraped.** They are read from public result pages,
  best-effort. They may be CAPTCHA'd, blocked or silently break when the
  markup changes, and automated use of those pages may be outside the
  providers' terms of service. The circuit breaker hides failures; it does not
  make them reliable.
* **Exa uses a free public MCP endpoint.** No SLA, undocumented rate limits,
  and it can change or disappear.
* **Free scholarly APIs throttle.** Keyless Semantic Scholar in particular
  shares a pool that is often exhausted (HTTP 429), hence its tiny budget.
* **The offline index is narrow**: arXiv abstracts, Project Gutenberg works
  and public-domain speeches, 62,881 documents. Wikipedia and OpenStax fetch
  scripts exist in `tool/corpus/fetch/`, but neither family is in the shipped
  build. Anything else (paywalled papers, essays, news, blogs, student
  papers) is only reachable through the online tier, and only if a search
  engine surfaces it.
* **Paraphrase detection is lexical.** Both alignment and the paraphrase tier
  work on shared vocabulary; a synonym-level rewrite with no shared words is
  not detected, and the fingerprint index only finds near-verbatim runs.
* **Online recall depends on snippets.** Result-page and API snippets are
  short, so a copied passage may be found by title but not aligned.
* **The download needs the release to exist.** If the GitHub release is
  missing or its hash no longer matches the pinned one, the corpus never
  installs and the app silently stays online-only.
* A score is evidence to review, not an accusation: matches should be read
  against the cited source before anyone acts on them.

## Testing

`test/plagiarism_detector_test.dart` covers: the three rule-based tells (em
dash, markdown residue, transition openers), `extractFeatureVector`/
`extractFeatureVectorV2` shape/finiteness for both the 13-feature (v1) and
38-feature (v2) classifiers, human-vs-AI discrimination for both, length
gating on short passages, `SourcePlagiarismService`'s independent n-gram/
boilerplate detection, and that `analyze()` surfaces both classifiers' tells
at high confidence. Run the suite with `flutter test`.

Source search has its own tests under `test/forensic/`:
`compact_corpus_index_test.dart`, `compact_corpus_similarity_test.dart`,
`compact_corpus_asset_test.dart` (checks the real corpus file, including that
no human text is reported as a source), `corpus_delivery_service_test.dart`,
`corpus_loader_test.dart` and `keyless_web_retrievers_test.dart`.
