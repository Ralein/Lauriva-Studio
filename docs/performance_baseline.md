# Lauriva Forensic Intelligence Engine — Performance Baseline & Latency Budgets

## Executive Summary

The Lauriva Forensic Content Intelligence Engine 3.5 executes multi-dimensional forensic analysis across:
1. Canonical text normalization & homoglyph defense
2. Structural document & sentence segmentation
3. Multi-family stylometric feature extraction (perplexity, burstiness, syntax, vocabulary, POS n-grams)
4. Sliding-window segmentation with CUSUM style-shift detection
5. Exact 5-gram shingle matching & longest common subsequence (LCS) against literature corpora
6. Internal repetition & formulaic boilerplate pattern auditing
7. Evidential Bayesian fusion with multi-factor uncertainty quantification

This document establishes the empirical performance baseline and strict latency budgets for release gating.

---

## Empirical Benchmark Results (Apple Silicon / Dart 3.13)

| Document Size | Word Count | Sentence Count | Execution Latency | Throughput | Status |
|---------------|------------|----------------|-------------------|------------|--------|
| **Small** | ~500 words | ~25 sentences | **37 ms** | ~13,700 wps | ✅ Exceeds target (< 250ms) |
| **Medium** | ~1,000 words | ~50 sentences | **52 ms** | ~19,200 wps | ✅ Exceeds target (< 500ms) |
| **Large** | ~3,000 words | ~150 sentences | **193 ms** | ~15,500 wps | ✅ Exceeds target (< 2,500ms) |

*wps = words per second processing throughput*

---

## Latency Budgets & SLA Thresholds

To prevent UI frame drops and maintain a 60/120 FPS fluid mobile experience:

1. **Synchronous Execution Threshold (< 1,200 characters)**:
   - Evaluated directly on the main UI thread via `_safeAnalyzeSync()`.
   - Latency budget: **< 50 ms**.
   - Frame impact: Zero jank (within typical animation budget).

2. **Background Isolate Offloading (> 1,200 characters)**:
   - Offloaded to a dedicated background isolate via Flutter `compute()` inside `ForensicCoordinatorService`.
   - Latency budget: **p95 < 300 ms** for standard passages (< 2,000 words).
   - Frame impact: Strictly 0 ms UI thread blockage; main thread only deserializes result and updates UI.

3. **Self-Healing Fallback SLA**:
   - If an isolate crashes, encounters out-of-memory, or throws a serialization exception, `ForensicCoordinatorService` falls back to `_safeAnalyzeSync` within **< 10 ms**.
   - If synchronous evaluation encounters an unexpected runtime fault, `ForensicReport.empty()` returns within **< 1 ms**, preventing application crash.

---

## Continuous Regression Testing

Run the automated performance baseline suite with:

```bash
flutter test test/forensic/forensic_engine_benchmark_test.dart --no-pub
```
