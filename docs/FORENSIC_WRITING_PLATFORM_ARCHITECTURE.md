# Lauriva Forensic Writing Platform: System Architecture

## Executive Summary
Lauriva is architected as an executive-grade **Forensic Writing Platform** rather than a naive, binary "AI %" classifier. The system is built around two decoupled, evidence-backed engines:
1. **Originality / Plagiarism Engine** ("Where did this text come from?") — Deterministic and semantic source attribution across exact, near-duplicate, and vector-level similarity.
2. **Writing Analysis + Humanizer Engine** ("How does this text read, and how can we make it clearer and more natural while preserving the author's meaning and voice?") — Deep linguistic feature analysis coupled with user-controlled writing profiles and an automated **Meaning Guard**.

### Core Platform Promise
> **"Understand your document, identify source overlap, analyze writing patterns, and improve writing without changing its intended meaning."**
> 
> *The system provides explainable signals and verifiable evidence rather than claiming absolute proof of machine authorship.*

---

## 1. High-Level Architecture

```text
                         ┌─────────────────────────┐
                         │        CLIENT APP       │
                         │                         │
                         │  Editor / Paste / File  │
                         │  Humanizer / Reports    │
                         │  History / Settings     │
                         └────────────┬────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────┐
                    │          API / ORCHESTRATOR     │
                    │                                 │
                    │ Auth • Jobs • Rate Limits       │
                    │ Pipeline Coordination           │
                    └───────────────┬─────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
     ┌────────────────┐    ┌────────────────┐    ┌─────────────────┐
     │ TEXT ANALYSIS  │    │ ORIGINALITY    │    │ HUMANIZER       │
     │ ENGINE         │    │ ENGINE         │    │ ENGINE          │
     └───────┬────────┘    └───────┬────────┘    └────────┬────────┘
             │                     │                       │
             ▼                     ▼                       ▼
      ┌─────────────┐       ┌─────────────┐       ┌──────────────┐
      │ Linguistic  │       │ Fingerprint │       │ Rewrite      │
      │ Features    │       │ Extraction  │       │ Planner      │
      ├─────────────┤       ├─────────────┤       ├──────────────┤
      │ Sentence    │       │ Exact Match │       │ Meaning      │
      │ Vocabulary  │       │ N-gram      │       │ Preservation │
      │ Structure   │       │ Semantic    │       │ Voice        │
      │ Repetition  │       │ Similarity  │       │ Grammar      │
      │ Readability │       │ Source Map  │       │ Clarity      │
      └──────┬──────┘       └──────┬──────┘       └──────┬───────┘
             │                     │                       │
             └─────────────────────┼───────────────────────┘
                                   ▼
                         ┌────────────────────┐
                         │ EVIDENCE / REPORT  │
                         │ ENGINE             │
                         ├────────────────────┤
                         │ Findings           │
                         │ Confidence         │
                         │ Sources            │
                         │ Highlighted spans  │
                         │ Explanations       │
                         └──────────┬─────────┘
                                    ▼
                         ┌────────────────────┐
                         │ REPORT / UI LAYER  │
                         └────────────────────┘
```

---

## 2. Text Preprocessing Layer & Canonical Document Model

All documents pass through a unified normalization pipeline before processing. The original character offsets are preserved end-to-end to enable precise span highlighting across all analytical passes.

```text
Input
 │
 ├── Normalize Unicode (NFKC) & Homoglyph de-cloaking
 ├── Detect language
 ├── Remove/identify zero-width artifacts & evasion tokens
 ├── Sentence segmentation with boundary preservation
 ├── Paragraph segmentation
 ├── Tokenization
 └── Preserve original character offsets [startOffset, endOffset]
          │
          ▼
     Canonical Document Model
```

By preserving exact token and sentence offsets, the downstream UI maps high-level findings directly back to specific document segments:
- `Paragraph 2` → Potential source overlap detected
- `Sentence 5` → Elevated syntactic repetition
- `Sentence 12` → Suggested clarity rewrite

---

## 3. Originality / Plagiarism Engine

The Originality Engine avoids opaque, unverified percentage claims. It operates across three distinct tiers of similarity:

```text
                 DOCUMENT
                     │
                     ▼
             ┌───────────────┐
             │ Fingerprinter │
             └───────┬───────┘
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
       Exact       N-gram    Semantic
       Match       Match     Embedding
          │          │          │
          └──────────┼──────────┘
                     ▼
             Candidate Sources
                     │
                     ▼
              Source Verification
                     │
                     ▼
              Similarity Analysis
                     │
                     ▼
                 Evidence
```

### Multi-Tier Similarity Verification
1. **Level 1 — Exact Match**: Cryptographic / rolling token hashes matching verbatim passages.
2. **Level 2 — Near Duplicate**: N-gram shingling, Jaccard distance, and MinHash index detecting minor word substitutions and re-orderings.
3. **Level 3 — Semantic Similarity**: Dense vector embeddings identifying identical claims expressed with alternative vocabulary.

### Defensible Presentation
Never report:
> `73% Plagiarism` (without verifiable proof)

Instead report:
> **Potentially matching content: 18%**  
> Supported by structured match cards detailing:
> - User passage
> - Source citation / domain
> - Match type (`Exact`, `Near duplicate`, `Semantic`)
> - Similarity percentage

---

## 4. Writing Analysis Engine

Rather than reducing human communication to a binary classifier (`AI 11% / Human 89%`), Lauriva analyzes empirical stylometric and statistical properties:

```text
                    TEXT
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
   Linguistic Analysis     Statistical Analysis
          │                     │
     ┌────┼────┐          ┌─────┼─────┐
     ▼    ▼    ▼          ▼     ▼     ▼
 Sentence Vocabulary   Repetition Variation Rhythm
 Structure             Density     Patterns
     │    │    │          │     │     │
     └────┴────┴──────────┴─────┴─────┘
                       │
                       ▼
                Evidence Vector
                       │
                       ▼
                Analysis Model
                       │
                       ▼
                 Explanation
```

### Writing-Pattern Analysis Finding
> *"The document contains several characteristics commonly associated with automated drafting, but these signals are not proof of AI authorship."*

Key dimensions reported to the user:
- **Clarity**: Structural directness and syntactic coherence (`Good`, `Fair`, `Needs Focus`).
- **Repetition**: Lexical richness and n-gram reuse (`Low`, `Moderate`, `Elevated`).
- **Readability**: Flesch-Kincaid grade level and cognitive load (`Accessible`, `Standard`, `Advanced`).
- **Sentence Variation**: Burstiness coefficient of variation across clause lengths (`Diverse`, `Moderate`, `Uniform`).

---

## 5. Humanizer Architecture & Meaning Guard

The Humanizer is structured as a user-directed editorial assistant designed to cultivate authentic voice rather than an adversarial detector evasion tool.

```text
                    ORIGINAL
                       │
                       ▼
                ┌──────────────┐
                │ ANALYZER     │
                └──────┬───────┘
                       │
              Writing Profile
                       │
                       ▼
                ┌──────────────┐
                │ EDIT PLANNER │
                └──────┬───────┘
                       │
       ┌───────────────┼────────────────┐
       ▼               ▼                ▼
    Clarity          Flow            Voice
    Issues           Issues          Issues
       │               │                │
       └───────────────┼────────────────┘
                       ▼
                 Rewrite Model
                       │
                       ▼
                Meaning Checker
                       │
                       ▼
                Diff / Validator
                       │
                       ▼
                 FINAL VERSION
```

### The Meaning Guard
Before accepting any suggested rewrite, the Meaning Guard runs strict semantic and entity validation:
- **Entity Invariance**: Strict preservation of proper names, numerical values, dates, percentages, citations, and quotations.
- **Semantic Distance**: Vector similarity check ensuring the underlying premise has not drifted.
- **Terminology Protection**: Retention of domain-specific jargon and technical vocabulary.

```text
Original
   ↓
Rewrite
   ↓
Semantic & Entity Check
   ↓
Did meaning or factual assertions change?
   │
 ┌─┴─────────────┐
 NO              YES
 │                │
Accept       Reject / revise
```

---

## 6. User-Controlled Writing Profiles

Users control their editorial outcomes through distinct multidimensional parameters:

```text
Writing Profile

Tone
 ├── Professional
 ├── Academic
 ├── Casual
 ├── Conversational
 └── Direct

Style
 ├── Concise
 ├── Detailed
 ├── Simple
 ├── Technical
 └── Balanced

Preserve (Meaning Guard)
 ├── Vocabulary & technical terms
 ├── Sentence structure
 ├── Personal voice
 ├── Citations & quotations
 └── Numbers & dates
```

---

## 7. Document Intelligence & Evidence Graph

```text
                 DOCUMENT INTELLIGENCE
                         │
        ┌────────────────┼─────────────────┐
        ▼                ▼                 ▼
   Document Model   Writing Profile    Evidence Graph
        │                │                 │
        ▼                ▼                 ▼
 Original text      User preferences    Sources
 Sentences          Style features      Matches
 Paragraphs         Tone                Claims
 Metadata            Vocabulary         Confidence
```

### Minimalist Document Health Dashboard
```text
DOCUMENT HEALTH

Originality          94%
Source matches        2
Unmatched content    81%
Potential overlap    19%

WRITING ANALYSIS

Clarity              Good
Repetition           Low
Readability          Moderate
Sentence variation   Moderate

SOURCES

2 potential matches
0 confirmed duplicates
```

---

## 8. Scalable Backend Orchestration

```text
                    Client
                      │
                      ▼
                API Gateway
                      │
                ┌─────┴─────┐
                ▼           ▼
             FastAPI      Auth
                │
                ▼
          Job Orchestrator
                │
      ┌─────────┼─────────┐
      ▼         ▼         ▼
   Analysis  Originality Humanizer
   Worker     Worker      Worker
      │         │         │
      └─────────┼─────────┘
                ▼
          PostgreSQL
                │
        ┌───────┴────────┐
        ▼                ▼
     Results           Cache
```

For intensive operations (web indexing, dense embedding calculations), requests are queued asynchronously with WebSocket/SSE event streaming to keep client interaction instantaneous.

---

## 9. Model Routing Strategy

Lauriva leverages specialized models tailored to each stage of execution:
- **Local/On-Device Engine**: Token segmentation, regex filtering, homoglyph cleaning, n-gram shingle extraction, trigram language modeling.
- **Dense Embedding Model**: High-efficiency vector representation for semantic source similarity and Meaning Guard semantic divergence checks.
- **Curated LLM (Groq / OpenRouter / Anthropic / OpenAI)**: Multi-pass rewrite planning, tone matching, and natural prose generation.
- **Deterministic Rules Engine**: Punctuation cadence, entity extraction, and structural invariant validation.

---

## 10. Summary of Architectural Shifts
| Legacy Approach | Lauriva Forensic Writing Platform |
| :--- | :--- |
| Single binary "AI 11% / Human 89%" gauge | Two independent engines: Originality & Writing Analysis |
| "Bypass AI Detectors" adversarial angle | User-controlled natural writing & voice improvement |
| Unsubstantiated percentage scores | Defensible match cards with exact & semantic source citations |
| Overwhelming 38-dimension UI tables | Minimalist, executive-grade Document Health & Writing metrics |
| Fragile single LLM prompt | Decoupled pipeline with automated Meaning Guard verification |
