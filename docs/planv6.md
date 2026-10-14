# Lauriva Studio — On-Device ML Forensic & Humanizer Intelligence Plan v6

> **Executive Summary:** This plan specifies the complete transition of Lauriva to a **100% offline, zero-cloud, privacy-first, on-device Machine Learning architecture**. By combining quantized dense semantic embeddings (`all-MiniLM-L6-v2` space), an embedded 50-tree Gradient-Boosted Decision Tree (GBDT) ensemble, a Kneser-Ney smoothed trigram language model, an inverted shingle corpus, and a Low-Rank Adapter (LoRA) syntactic transformation matrix, Lauriva delivers enterprise-grade detection and humanization within an ultra-lean **~44 MB on-device footprint** with sub-15ms execution.

---

## 1. System Architecture & Model Footprint Matrix

```mermaid
flowchart TD
    subgraph Input["Input Document"]
        Doc[User Document / Essay / Article] --> Seg[Document Segmenter & Text Normalizer]
    end

    subgraph PlagiarismEngine["⚡ Tier-1: Semantic Plagiarism Engine (~36 MB)"]
        Seg --> Shingle[1. Inverted Shingle Index <br/> Exact & Near-Verbatim (O(1))]
        Seg --> DenseProj[2. Dense Semantic Vector Matcher <br/> 384-D Sentence Embeddings]
        
        Shingle --> Corpus[(assets/source_corpus.bin <br/> Compressed Wiki/arXiv/Books Index)]
        DenseProj --> Corpus
        Corpus --> SimEngine[Dense Similarity & Paraphrase Matcher <br/> Cosine + Bidirectional Harmonic Containment]
        SimEngine --> PlagReport[Plagiarism & Paraphrase Audit Report]
    end

    subgraph AIEngine["🧠 Tier-2: AI Forensic Scanner (~4 MB)"]
        Seg --> FeatExt[38-Dimensional Stylometric Extractor]
        Seg --> TrigramLM[Kneser-Ney Trigram LM <br/> Quantized Binary Trie (assets/ngram_lm_kn.bin)]
        
        FeatExt --> GBDT[50-Tree GBDT Classifier <br/> Bit-Packed Native Dart Tree Engine]
        TrigramLM --> GBDT
        
        GBDT --> Platt[Platt Sigmoid Calibrator]
        Platt --> EnsembleFusion[4-Way Forensic Fusion: <br/> 40% GBDT + 30% LogReg + 20% Perplexity + 10% Anomaly]
        EnsembleFusion --> AIReport[Sentence-Level AI Probability Heatmap]
    end

    subgraph HumanizerEngine["✨ Tier-3: LoRA-Guided Surgical Humanizer (~4 MB)"]
        AIReport --> Flagged[Flagged AI Sentences]
        Flagged --> LoRA[Low-Rank Stylistic Adapter Matrix <br/> LoRA Rank-8 Tensor Weights]
        LoRA --> AlgoRewrite[Algorithmic Syntax Perturbation: <br/> Burstiness Injection + Transition Stripping + Voice Inversion]
        AlgoRewrite --> PresCheck[Semantic Preservation Verifier <br/> Embedding Cosine Check >= 0.94]
        PresCheck --> CleanText[100% Humanized & Verified Output]
    end
```

### Storage & Runtime Budget

| Component | Asset / File | Maximum Compressed Size | RAM Footprint | Inference Latency |
|---|---|---|---|---|
| **Dense Semantic Vector Engine** | `dense_semantic_matcher.dart` | Embedded Projection Matrix | ~12 MB | ~8 ms / doc |
| **Inverted Shingle Corpus** | `assets/source_corpus.bin` | **18.2 MB** (Deflate / MinHash) | ~28 MB | < 2 ms ($O(1)$) |
| **Kneser-Ney Trigram LM** | `assets/ngram_lm_kn.bin` | **1.8 MB** (8-bit Quantized Trie) | ~6 MB | ~1 ms / sentence |
| **LoRA Humanizer Adapter** | `humanizer_lora.bin` | **1.7 MB** ($A_{384 \times 8} \times B_{8 \times 384}$) | ~3 MB | < 0.5 ms |
| **GBDT 50-Tree Classifier** | `gbdt_classifier.dart` | **40 KB** (Direct Dart Nodes) | < 0.2 MB | < 0.1 ms |
| **Total All-Inclusive Suite** | **Assets + Code** | **~42.8 MB** | **~50 MB** | **< 15 ms total** |

---

## 2. Phase-by-Phase Execution Plan

### Phase 1: High-Density Binary Asset Formats & Deserializers
* **1.1** Implement `CorpusLoader` binary decoder with MinHash 64-bit fingerprinting and Deflate decompression.
* **1.2** Implement `NgramLanguageModel` binary trie parser with 8-bit quantized log-probability lookup.
* **1.3** Implement `LoraStylisticAdapter` for low-rank syntactic transformation scoring.

### Phase 2: Dense Semantic Plagiarism & Deep Paraphrase Matcher
* **2.1** Upgrade `DenseSemanticMatcher` to support 384-D dense embedding projections, directional containment, and harmonic active/passive voice inversion.
* **2.2** Upgrade `InvertedShingleIndex` for sub-millisecond multi-gram candidate retrieval.
* **2.3** Connect `SourceSimilarityService` to fuse verbatim, shingle, and dense semantic matches into cohesive evidence with citation generation.

### Phase 3: AI Forensic Scanner & GBDT Ensemble Integration
* **3.1** Deepen `GbdtClassifier` to full 50-tree depth-4 ensemble over 38 stylometric dimensions.
* **3.2** Calibrate `PlattCalibrator` with empirical sigmoid constants fitted on HC3 and RAID benchmarks.
* **3.3** Upgrade `EvidenceFusionEngine` to dynamically weigh GBDT, Logistic Regression, Kneser-Ney Perplexity, and Anomaly signals.

### Phase 4: LoRA-Guided Algorithmic Humanizer
* **4.1** Integrate `LoraStylisticAdapter` into `AlgorithmicHumanizerService`.
* **4.2** Implement multi-pass sentence perturbation:
  - Burstiness variance injection (alternating lengths 8–32 words).
  - Transition word desaturation (stripping formulaic discourse markers).
  - Perplexity perturbation (substituting predictable n-grams with natural human idioms).
* **4.3** Enforce `SemanticPreservationVerifier` ensuring semantic cosine similarity $\ge 0.94$.

### Phase 5: Verification, Benchmark Testing & Regression Guard
* **5.1** Add comprehensive test suites covering all on-device ML subsystems.
* **5.2** Verify zero regressions across the existing 341 automated tests.
* **5.3** Benchmark execution latency and verify clean memory limits on mobile targets.
