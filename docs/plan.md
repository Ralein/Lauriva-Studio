# Lauriva Plagiarism & AI-Writing Detection Engine v2: Master Architectural Plan

## 1. Executive Summary & Problem Diagnosis

Lauriva currently features an on-device stylometric classifier (`lib/services/plagiarism_detector_service.dart`) trained via `tool/train_stylometric_classifier.dart`. While innovative in operating completely offline with zero app-size bloat, the current system has fundamental bottlenecks:

```
Current Reality:
  54 Human + 30 AI Hand-curated Samples
               │
               ▼
   13 Feature Extraction Vector
               │
               ▼
       Z-Score Normalization
               │
               ▼
   Single Logistic Regression Model
               │
               ▼
   Binary-Biased Score (0.0 to 100.0)
```

### Critical Vulnerabilities of Engine v1
1. **Distant Weak Supervision & Narrow Corpus:** 84 samples cannot capture linguistic variance across human writing genres.
2. **Shortcut Learning:** Hand-crafted AI examples rely heavily on stereotyped tells (`"Furthermore"`, `"Moreover"`, em dashes, markdown headers, `"As an AI language model"`), causing the model to equate **formal prose with AI generation**.
3. **No Defense Against Adversarial Prompts:** Fails against AI explicitly instructed to omit em dashes, write casually, inject grammar slip-ups, or mimic human rhythm.
4. **Vulnerability to Human-Edited AI:** Fails to detect hybrid writing (AI draft + human polishing), which is the dominant real-world use case.
5. **No Sample-Length Gating:** Evaluating a 15-word sentence with stylometry is statistically invalid and yields high false-positive rates.
6. **Conflation of AI Detection & Plagiarism:** AI-writing detection (stylometry) is fundamentally distinct from true plagiarism (source attribution and verbatim copying).

---

## 2. Lauriva Forensics Engine v2: Target Architecture

```
                                 INPUT TEXT
                                     │
                                     ▼
                      ┌─────────────────────────────┐
                      │    Text Normalizer & San    │
                      │ (Unicode, Whitespace, Quotes)│
                      └──────────────┬──────────────┘
                                     │
                                     ▼
                      ┌─────────────────────────────┐
                      │    Length & Quality Gate    │
                      │  (<50 words = Inconclusive) │
                      └──────────────┬──────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 ▼                                       ▼
    ┌──────────────────────────┐           ┌──────────────────────────┐
    │  Document-Level Extract  │           │  Hierarchical Sentences  │
    │  (38 Stylometric Feats)  │           │   (Rolling Local Audit)  │
    └────────────┬─────────────┘           └─────────────┬────────────┘
                 │                                       │
                 ▼                                       ▼
    ┌──────────────────────────┐           ┌──────────────────────────┐
    │ On-Device Model Ensemble │           │ Local Tell Annotation    │
    │  • ElasticNet LogReg     │           │  • Regex Micro-Tells     │
    │  • Transpiled GBDT (x20) │           │  • Dynamic Lexical Shift │
    │  • Mahalanobis Anomaly   │           └─────────────┬────────────┘
    └────────────┬─────────────┘                         │
                 │                                       │
                 ▼                                       │
    ┌──────────────────────────┐                         │
    │ Score Fusion & Stacking  │                         │
    └────────────┬─────────────┘                         │
                 │                                       │
                 ▼                                       │
    ┌──────────────────────────┐                         │
    │ Isotonic Probability     │                         │
    │ Calibration & Uncertainty│                         │
    └────────────┬─────────────┘                         │
                 │                                       │
                 ▼                                       │
    ┌──────────────────────────┐                         │
    │ Ternary Decision Logic   │                         │
    │ [Human / Mixed / AI]     │                         │
    └────────────┬─────────────┘                         │
                 │                                       │
                 └───────────────────┬───────────────────┘
                                     ▼
                      ┌─────────────────────────────┐
                      │ Forensics Report Generator  │
                      │  • Overall Probability      │
                      │  • Uncertainty Interval     │
                      │  • Explainability Vector    │
                      │  • Sentence Audit Heatmap   │
                      └─────────────────────────────┘
```

---

## 3. Dataset Engineering: 40,000+ Sample Multi-Register Corpus

We scale from 84 static strings to a stratified, author-partitioned JSONL corpus under `tool/data/`:

```
tool/data/
├── human/                           (20,000+ samples across 12 distinct registers)
│   ├── casual_messaging.jsonl       (SMS, chats, personal forum threads)
│   ├── academic_papers.jsonl        (JSTOR open, arXiv abstracts, dissertations)
│   ├── technical_docs.jsonl         (GitHub markdown, RFCs, release notes)
│   ├── essays_arguments.jsonl       (High school and university essays)
│   ├── emails_business.jsonl        (Professional correspondence, inquiries)
│   ├── reviews_opinions.jsonl       (Yelp, Amazon, Goodreads reviews)
│   ├── journalism_news.jsonl        (AP, Reuters, investigative reporting)
│   ├── instructions_howtos.jsonl    (Recipes, repair manuals, workflows)
│   ├── creative_narratives.jsonl    (Fiction, memoirs, personal essays)
│   ├── speeches_transcripts.jsonl   (Spoken word transcripts, interviews)
│   ├── reddit_discussions.jsonl     (Casual debate, stream of consciousness)
│   └── student_drafts.jsonl         (Handwritten/unedited student work)
│
├── ai_raw/                          (10,000+ samples from leading foundation models)
│   ├── chatgpt_gpt4o.jsonl
│   ├── claude_3_5_sonnet.jsonl
│   ├── gemini_1_5_pro.jsonl
│   ├── llama_3_70b.jsonl
│   ├── qwen_2_5_72b.jsonl
│   └── mistral_large.jsonl
│
├── ai_adversarial/                  (5,000+ attack samples breaking known heuristics)
│   ├── tell_suppression.jsonl       (Prompted: "Avoid em dashes, formal transitions, and lists")
│   ├── informal_persona.jsonl       (Prompted: "Sound like a tired 19yo student or angry dev")
│   ├── flawed_grammar.jsonl         (Prompted: "Use comma splices, minor typos, casual syntax")
│   ├── varied_burstiness.jsonl      (Prompted: "Intermix 3-word sentences with 45-word sentences")
│   └── fragment_injections.jsonl    (Prompted: "Use incomplete sentences and casual thoughts")
│
└── ai_humanized_hybrids/            (5,000+ human-AI collaborative texts)
    ├── lightly_edited.jsonl         (Human adjusted connectors and sentence openings)
    ├── heavily_paraphrased.jsonl    (Substantially reworded but retaining AI logic/rhythm)
    ├── humanized_via_Lauriva.jsonl  (Passed through Lauriva's humanizer pipeline)
    └── interleaved_paragraphs.jsonl (Alternating human and AI paragraphs)
```

### Partitioning & Integrity Rules
- **Stratification:** 70% Train, 15% Validation, 15% Test.
- **Author/Topic Clustered Split:** Documents from the same author or source are held together in one split to prevent data contamination.
- **Cross-Model Evaluation:** Train on GPT-4o, Claude 3.5, and Gemini 1.5; benchmark generalization on Llama 3 and Qwen 2.5.
- **Asymmetric Cost Function:** Optimize loss such that false positives on human text cost $4\times$ more than false negatives on AI text:
  $$\mathcal{L} = -\frac{1}{N}\sum_{i} \left[ y_i \log(\hat{y}_i) + 4.0 \cdot (1 - y_i) \log(1 - \hat{y}_i) \right]$$

---

## 4. The 38-Feature Stylometric Engine

The 13-feature vector is expanded to **38 features across 6 families**, computed deterministically in `PlagiarismDetectorService.extractFeatureVectorV2()`:

### Family A: Surface & Length Statistics (10 Features)
- $f_0$: `sentence_count` — Total sentence count.
- $f_1$: `word_count` — Total words.
- $f_2$: `char_per_word_mean` — Mean word length in characters.
- $f_3$: `char_per_word_var` — Variance of word lengths.
- $f_4$: `sentence_len_mean` — Mean sentence length in words ($\mu_L$).
- $f_5$: `sentence_len_std` — Standard deviation of sentence length ($\sigma_L$).
- $f_6$: `burstiness_cv` — Coefficient of variation: $CV = \frac{\sigma_L}{\mu_L}$. (Human: $>0.50$, AI: $0.15–0.35$).
- $f_7$: `sentence_len_skew` — Skewness: $\frac{E[(L - \mu_L)^3]}{\sigma_L^3}$. (Human writing has positive skew).
- $f_8$: `sentence_len_entropy` — Shannon entropy over length bins.
- $f_9$: `paragraph_len_var` — Variance in sentences per paragraph.

### Family B: Punctuation & Orthographic Fingerprint (8 Features)
- $f_{10}$: `comma_rate` — Commas per sentence.
- $f_{11}$: `semicolon_colon_rate` — $(Count(;) + Count(:)) / S$.
- $f_{12}$: `em_dash_rate` — Em dashes and double hyphens per sentence.
- $f_{13}$: `parentheses_rate` — Parentheses pairs per 100 words.
- $f_{14}$: `hyphen_compound_rate` — Intra-word hyphens per 100 words.
- $f_{15}$: `quote_dialogue_rate` — Quotation marks per 100 words.
- $f_{16}$: `punctuation_diversity` — Unique punctuation marks / Total punctuation marks.
- $f_{17}$: `terminal_punct_skew` — Ratio of `!` and `?` to `.`.

### Family C: Lexical & Vocabulary Dynamics (8 Features)
- $f_{18}$: `ttr_standard` — Type-Token Ratio ($\frac{V}{N}$).
- $f_{19}$: `mattr_50` — Moving-Average TTR (window $W=50$, length-independent).
- $f_{20}$: `guiraud_r` — Guiraud's R Index ($\frac{V}{\sqrt{N}}$).
- $f_{21}$: `hapax_legomena_ratio` — Single-occurrence words / $V$.
- $f_{22}$: `function_word_ratio` — Stop-word frequency (scaffolding ratio).
- $f_{23}$: `pronoun_distribution` — 1st person (`I`, `we`) vs 3rd person (`it`, `they`).
- $f_{24}$: `modal_hedging_density` — Epistemic hedges (`might`, `could`, `arguably`).
- $f_{25}$: `ai_stock_word_density` — Density of 60 overused AI buzzwords (`delve`, `tapestry`, `pivotal`, etc.).

### Family D: Syntactic & Structural Complexity (6 Features)
- $f_{26}$: `transition_opener_ratio` — Sentences starting with formal connectors (`Moreover`, `Furthermore`).
- $f_{27}$: `opener_diversity` — Unique 2-word openers / $S$.
- $f_{28}$: `triad_structure_rate` — Forced tricolon groups per sentence.
- $f_{29}$: `contrast_formula_rate` — "Not X but Y" rhetorical structures.
- $f_{30}$: `subordinating_conj_rate` — Clause subordinators (`although`, `because`, `whereas`).
- $f_{31}$: `fragment_frequency` — Verbless fragments or sentences $< 4$ words.

### Family E: Cohesion & Repetition (4 Features)
- $f_{32}$: `trigram_overlap_ratio` — Repeated 3-grams / $N$.
- $f_{33}$: `fourgram_overlap_ratio` — Repeated 4-grams / $N$.
- $f_{34}$: `markdown_syntax_density` — Markdown tokens per 100 words.
- $f_{35}$: `wrapper_phrase_score` — Chatbot greeting/closing residue.

### Family F: Semantic Cohesion & Dispersion (2 Features)
- $f_{36}$: `academic_boilerplate_rate` — Formulaic academic cliches per $S$.
- $f_{37}$: `mahalanobis_human_dist` — Distance from the human writing centroid in compressed feature space.

---

## 5. On-Device Pure-Dart Ensemble & Calibration

To maintain zero native bloat and respect mobile CPU/RAM limits, we implement a **pure-Dart native compiled ensemble**:

```
                              38-Feature Vector
                                      │
               ┌──────────────────────┼──────────────────────┐
               ▼                      ▼                      ▼
      ElasticNet LogReg        Transpiled GBDT        Mahalanobis Centroid
      (Global Linear prior)     (20 Shallow Trees)     (Anomaly from Human)
               │                      │                      │
               └──────────────────────┼──────────────────────┘
                                      ▼
                             Calibrated Stacking
                                      │
                                      ▼
                        Isotonic Probability Lookup
                                      │
                        ┌─────────────┼─────────────┐
                        ▼             ▼             ▼
                      HUMAN         MIXED          AI
```

### Component Details
1. **Regularized Logistic Regression:** Standardized linear baseline with 38 learned weights + bias.
2. **Transpiled GBDT (Gradient Boosted Decision Trees):** 20 shallow trees (depth $\le 3$, max 8 leaves) transpiled into pure Dart `if-else` branching logic. Evaluates in under **0.5 milliseconds** with zero object allocations.
3. **Mahalanobis Anomaly Scorer:** Flags text whose multivariate variance is unnaturally compressed even when individual words seem natural.
4. **Isotonic Calibration Layer:** Maps raw ensemble scores into calibrated posterior probabilities:
   - $P(\text{AI}) < 0.30 \implies$ **Likely Human Written**
   - $0.30 \le P(\text{AI}) \le 0.65 \implies$ **Mixed / Human-Edited AI / Uncertain**
   - $P(\text{AI}) > 0.65 \implies$ **Likely AI-Generated**

---

## 6. Length Gating & Uncertainty Propagation

| Word Count ($N$) | Usable Features | Uncertainty Interval | UI Behavior & Badge |
| :--- | :--- | :--- | :--- |
| **$N < 50$** | Chatbot residue only | $\pm 45\%$ (High) | Amber notice: *"Text too short for stylometric analysis (< 50 words). Statistical evidence inconclusive."* |
| **$50 \le N < 150$** | Surface stats, stock words, punctuation | $\pm 25\%$ (Moderate) | *"Short sample. Preliminary indicators only."* |
| **$150 \le N < 500$** | Full 38-feature vector | $\pm 12\%$ (Low) | Standard confidence display with complete signal breakdown. |
| **$N \ge 500$** | Full vector + paragraph variance | $\pm 5\%$ (Very Low) | High-confidence statistical evidence. |

---

## 7. Decoupling AI-Forensics from True Plagiarism

Lauriva's current engine is split into two specialized sub-systems under a unified facade:

1. **`AiForensicService`**:
   - Analyzes authorship, syntactic uniformity, burstiness, and AI tells.
   - Evaluates on-device ML ensemble + remote Hugging Face neural classifier.
2. **`SourcePlagiarismService`**:
   - Performs 4-gram and 5-gram token shingling.
   - Measures internal paragraph duplication and Jaccard similarity.
   - Provides hooks for external search APIs (e.g. SerpApi, CrossRef) for true literature citation matching.
3. **`PlagiarismDetectorService`**:
   - Preserved as a facade coordinating both services for zero-breaking-change integration with existing views.

---

## 8. UI Modernization & Defensible Explainability

Update `PlagiarismAuditCard` to adhere to Lauriva's dark glassmorphism design system (`AppColors`, `GoogleFonts.outfit`, Lucide icons):

1. **Defensible Scientific Framing:**
   - Replace absolute statements (*"This text was written by AI"*) with defensible probabilistic assessments:
     > *"AI-Writing Likelihood: 82% (Moderate Confidence). The text exhibits uniform sentence cadence, elevated transition openers, and compressed syntactic variance."*
2. **Signal Attribution Drawer:**
   - Collapsible panel displaying the top contributory feature families with graphical contribution bars.
3. **Sentence Heatmap Enhancement:**
   - Per-sentence highlighting showing specific reasons (e.g. "Low Burstiness Delta", "Stock Word Density", "Em Dash Overuse").
4. **Ternary Badge System:**
   - `HUMAN WRITTEN` (Emerald `#10B981`)
   - `MIXED / EDITED` (Amber `#F59E0B`)
   - `LIKELY AI` (Orange/Red `#EF4444`)
   - `INSUFFICIENT DATA` (Sky Blue `#38BDF8`)

---

## 9. Implementation Phases & Milestones

### Phase 1: Feature Engine Expansion (38 Features)
- Implement `extractFeatureVectorV2(text)` in `lib/services/ai_forensic_service.dart`.
- Ensure all 38 features are strictly finite, bounded, and tested with edge cases.

### Phase 2: Data Pipeline & Training Tooling
- Implement JSONL corpus loader and synthetic generator in `tool/data_pipeline/`.
- Upgrade `tool/train_stylometric_classifier.dart` to support the 38-feature vector, stratified train/val/test split, and GBDT transpilation.

### Phase 3: Calibrated Ensemble & Isolate Performance
- Transpile GBDT trees into Dart code.
- Implement length gating and uncertainty intervals.
- Integrate into background isolate via `compute()` for long documents ($>500$ chars).

### Phase 4: UI Updates & Plagiarism Decoupling
- Update `PlagiarismReport` and `PlagiarismRiskLevel` models.
- Enhance `PlagiarismAuditCard` with uncertainty badges and defensible signal explanations.
- Preserve backward compatibility across `PlagiarismProvider` and `StudioProvider`.

### Phase 5: Verification, Benchmarking & Regression Testing
- Verify all unit tests pass with `flutter test`.
- Benchmark false positive rate on human test set ($< 3.0\%$).
- Verify zero UI frame drops and $< 150\text{MB}$ total binary budget.
