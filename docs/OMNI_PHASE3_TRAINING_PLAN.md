# Omni Phase 3 — Retraining Plan

Status: tooling and scripts written and CPU-smoke-tested, NOT yet run on Kaggle GPU or real data; updated 2026-10-05. Owner: detector. Applies to `scripts/ml_omni_v7_v10/`. Training target: **Kaggle** (see §11).

Already done in `train_omni_v7_v10.py` (compiles; split/dedup/fail-loud logic unit-tested on synthetic CSVs; the GPU run itself is untested): deterministic file order, per-source caps, text dedup, source-disjoint hold-out + separate calibration split (3,000 rows each max), Platt/threshold fit on calibration and reported on hold-out, 512-token benchmark window, attribution loss weight 0.85 -> 0.15 (`ATTR_LOSS_WEIGHT`), 2 full epochs (`EPOCHS`, `MAX_TRAIN_STEPS`), fp32 export kept, no synthetic fallback.
Still to add: random-length crops, hard-negative second epoch, verified-generator attribution masking, resume-from-checkpoint, frozen-benchmark gate (§4, §6, §11).

## 1. Why retrain (evidence, not opinion)

Measured on the repo's held-out splits (`tool/eval/data/*_test.jsonl`, 1,400 samples, full pipeline with the **correct** BPE tokenizer):

| Stream | AUC | Notes |
|---|---|---|
| Omni int4, 512-token window | 0.55–0.75 | modern_frontier 0.75, academic 0.61, diverse 0.55 |
| v6 L6 int8 (XLM-R tokenizer) | 0.59 | academic 0.66, modern_frontier 0.61 |
| Stylometry (no neural) | 0.64 | academic 0.54 |
| Fitted stack (Omni + stylometry) | 0.644 | ECE 0.042, human FPR 2% at the 65% verdict line |

Training logs claim AUC 0.964 (int4). Both can be true: the claim is in-distribution. What `train_omni_v7_v10.py` does that inflates it:

1. **Random 90/10 row split** (`rng.permutation`) over concatenated Kaggle CSVs: same prompts, near-duplicate essays and same generators land on both sides. No generator, source, prompt or domain holdout.
2. **Validation is 600 rows**, and the same 600 choose the threshold, choose int4 vs int8, and are reported. Optimistic by construction; ±2 pts of noise on AUC alone.
3. **Undertrained**: `min(2*len(loader), 4500)` steps at batch 16 is about 72k samples, roughly 0.4 epoch of 180k.
4. **Attribution head weighted 0.85** while its labels come from the *file path* (`classify_source_attribution`) and default to "GPT" for anything unmatched. A heavy, noisy auxiliary task competing with the main binary objective.
5. **Train/eval length mismatch**: trained at 512, benchmarked at 256 (`max_seq=256`), shipped at 512 (config) though the model is 8k.
6. **Silent synthetic fallback** (`_generate_synthetic_baseline`) trains on placeholder strings if no CSV is found.
7. **Stale generators**: corpus is mostly 2023–24 (DAIGT, Llama-70B/Falcon-180B, Gemini Pro, GPT-4 rephrase). Today's users paste frontier-model text (Claude 4.x/5, GPT-5, Gemini 3, o-series, DeepSeek-R).
8. No dedup, no length matching (length is a known confound), no adversarial/humanized training beyond one Kaggle set.

Before spending GPU hours, run the **diagnostic gate** (§3). If Omni reproduces 0.96 on its own split and ~0.6 on ours, the problem is coverage and the plan below is the fix.

## 2. Targets (on a frozen, generator-disjoint benchmark)

| Metric | Today | Phase 3 target |
|---|---|---|
| AUC, unseen generators | 0.55–0.75 | >= 0.95 |
| TPR at 1% human FPR | ~10% | >= 70% |
| Human FPR on ESL / student essays at verdict line | not measured | <= 1% |
| ECE after calibration | 0.04 (stack), 0.12–0.16 on modern splits | <= 0.03 per split |
| Robustness: light paraphrase / our own humanizer output | not measured | TPR >= 50% at 1% FPR |
| On-device latency (S24 Ultra, 512 window) | ~390 ms | <= 450 ms |

No claim of "99%": AI detection has a hard ceiling and every number ships with its uncertainty interval.

## 3. Phase 0 — Diagnostic gate (1 day, no training)

- Score Omni on its own held-out split (re-derive from the Kaggle sources) vs. our `*_test` splits: confirms distribution shift.
- Compare fp32 vs int4 vs int8 on identical rows (fp32 export is deleted after training today; keep it).
- ~~Sweep window length~~ DONE (106 held-out texts, median 295 words): AUC 0.670 / 0.681 / 0.688 / 0.690 at 128 / 256 / 512 / 1024 tokens. Longer context barely helps, so windowing is not the bottleneck; keep 512 on device.
- Compare ORT-CPU int4 against on-device ORT output for 50 samples (numeric parity).
- Decision: proceed only if shift (not quantization or windowing) explains the gap.

## 4. Phase 1 — Frozen benchmark (before any new data touches training)

Build `tool/eval/data/bench_v1/` once, version it, never tune on it:

- **Disjoint axes**: held-out generators, held-out prompts/topics, held-out human sources, held-out languages-of-writer (ESL).
- **Strata**: length (60–150 / 150–400 / 400+ words), domain (academic, creative, technical, casual, news), human origin (student, professional, ESL, forum).
- **Adversarial slices**: light paraphrase, heavy paraphrase, mixed human+AI (sentence-level labels), our humanizer output, typo/homoglyph injection.
- Report AUC, TPR@1%FPR, TPR@5%FPR, per-stratum ECE, with bootstrap 95% CIs. n >= 500 per cell that gates a release.
- A `tool/eval/run_benchmark.py` that takes any ONNX + tokenizer and emits one JSON; CI fails a model that regresses on any gated slice.

## 5. Phase 2 — Data (the main lever)

Constraint (standing user rule): **AI text comes from frontier-quality generators only.** If a generation quota runs out, stop, keep the cache, and record the exact resume state in `check.md`; do not fall back to small local models and do not create extra accounts for fresh quotas. Options when blocked: buy credits, wait for the next quota period, FreeLLMAPI with the user's own keys.

- **AI**: current frontier families (Claude, GPT, Gemini, o-series/R1-style reasoning, DeepSeek, Qwen, Llama-4+). 15+ distinct prompts per topic, mixed system styles (neutral, "write like a student", "avoid AI tells"), temperatures 0.3–1.2, lengths matched to humans per stratum.
- **Human**: pre-2022 or verified. Student essays, ESL (TOEFL/ICNALE-style), professional prose, forum/casual, technical. Dedup against all AI text and across splits (MinHash).
- **Adversarial / paraphrased**: LLM paraphrase of AI text, human-edited AI, our own humanizer v6 output, translated-and-back text, as *labelled AI*.
- **Mixed authorship**: spliced documents with sentence-level labels to train the window head.
- **Hygiene**: split by `(generator, prompt, source)` group, never by row; hash-based dedup; per-source caps (no source > 8%); length-balance classes; drop the synthetic-baseline fallback (hard error instead).
- Target size: 300–500k docs; quality over volume, because the current weakness is coverage, not scale.

## 6. Phase 3 — Training changes to `train_omni_v7_v10.py`

1. Group-aware split (§5) plus a generator-held-out validation set of >= 3,000 rows, separate from the calibration set (>= 3,000) and the frozen benchmark.
2. Train >= 2 full epochs; log validation per 500 steps; early-stop on held-out-generator TPR@1%FPR, not loss.
3. Objective: binary head primary. Attribution head weight 0.85 -> 0.15, and only on rows with *verified* generator labels (from our own generation metadata, not file paths); mask the loss elsewhere.
4. Replace the fixed 1.8/1.0 focal alpha with an explicit FPR-constrained loss or post-hoc threshold at 1% FPR on the calibration split.
5. Context: train with random-length crops 128–1024 tokens (not always 512) so the model is stable across window sizes; at inference score overlapping windows and aggregate (mean of logits plus max-window feature) in the app.
6. Hard-negative mining: after epoch 1, add the highest-scoring human and lowest-scoring AI rows to epoch 2 with 2x weight.
7. Keep AWP, but ablate it; keep it only if it helps held-out-generator metrics.
8. Quantization: export fp32, int8 and int4, evaluate all three on the **benchmark** (not 600 val rows). Ship int4 only if its TPR@1%FPR is within 1.5 pts of fp32. Keep the fp32 artifact in `tool/checkpoints/`.
9. Seeds: 3 runs; report mean and spread. A gain smaller than the spread is not a gain.

## 7. Phase 4 — Calibration, fusion, abstention

- Platt/temperature on the calibration split only; per-domain offsets only if ECE improves on the benchmark.
- Refit the stack with `tool/fit_fusion_stack.py` against the new model (features: window-aggregated Omni logit, stylometric logit). Drop stylometry's weight if it adds < 0.01 AUC.
- Keep the uncertainty zone: abstain below a confidence floor rather than guess; surface "insufficient evidence" in the UI that already exists.
- Conformal or bootstrap interval per document if latency permits.

## 8. Phase 5 — Humanizer loop (v6)

- Evaluate humanizer output against the *new* detector and against **held-out** generators/detectors, so it does not overfit one scorer.
- Add detector-guided retry (already in `HumanizerChunkEngine`) only as an inference-time feature; do not train the detector on its own humanizer's output without keeping that slice in the benchmark as a separate, reported row.
- Gate: semantic preservation (numbers, citations, polarity) unchanged; reading-quality checks (capitalization, agreement, duplicated synonyms) from `test/essay_quality_eval_test.dart` stay green.

## 9. Phase 6 — Ship & monitor

- On-device parity test: ORT mobile vs Python ONNX on 50 fixed texts (tolerance 1e-2 on logits).
- Replace `assets/models/lauvira_omni_detector.onnx.gz`, keep `assets/models/omni_tokenizer.json` in lockstep, bump `modelVersion`, rerun `tool/fit_fusion_stack.py`, update `FusionConfig` and `ForensicCalibrationConfig`.
- Opt-in, privacy-preserving feedback ("this verdict was wrong") stored locally and exportable, to grow the benchmark.
- Release gate = every gated benchmark slice meets §2; otherwise do not ship.

## 10. Order of work and rough cost

| Step | Effort | Blocks |
|---|---|---|
| Phase 0 diagnostic | 1 day | everything |
| Phase 1 benchmark | 2–3 days | training |
| Phase 2 data | 1–2 weeks (generation quota is the bottleneck) | training |
| Phase 3 training (2x T4 or better, 3 seeds) | 2–3 days | calibration |
| Phase 4–6 | 3–4 days | release |

Risks: generation quota stalls Phase 2 (mitigation: checkpoint and resume, §5); in-distribution gains that do not transfer (mitigation: only the frozen benchmark gates a release); int4 loses accuracy (mitigation: ship int8 or fp32-distilled student).

## 11. Kaggle execution plan (2026+)

**Environment facts to plan around** (verify current limits in the Kaggle UI before each run; they change): 2x T4 (16 GB each) or 1x P100, roughly 30 GPU-hours/week per account, sessions capped near 9–12 h, `/kaggle/working` about 20 GB, internet is opt-in per notebook (`enable_internet` is already true in `kernel-metadata.json`). Do not plan around extra accounts for more quota (standing rule).

**Split the work by where it can run:**

| Stage | Where | Why |
|---|---|---|
| Frontier-text generation (§5) | Local/API with the user's own keys, resumable cache | Needs paid/frontier APIs; keep quota state in `check.md` |
| Dataset build, dedup, group split, benchmark build | Local | CPU work; no GPU hours burned |
| Upload as **private Kaggle datasets** `lauriva-omni-p3-train`, `-cal`, `-bench` (versioned) | Kaggle | Reproducible inputs; benchmark dataset is read-only and never mounted in the train notebook except for final scoring |
| Training + export + quantization | Kaggle GPU notebook | 2 epochs of ~300k docs at 512 tokens with bf16/fp16 autocast |
| Frozen-benchmark scoring, calibration, fusion refit | Local with the downloaded ONNX | Free; matches on-device ORT |

**Notebook design (fits one 9 h session, resumable across several):**
- `kernel-metadata.json` `dataset_sources` replaced with only the Phase 3 private datasets plus any public sets that pass the §5 hygiene rules; drop sets we cannot attribute or that are pre-2023 generators unless used as a labelled "legacy generators" slice.
- Checkpoint every 500 steps to `/kaggle/working/ckpt/` (model, optimizer, scheduler, scaler, RNG, step, sample order seed); on start, resume if a checkpoint dataset is attached (`kernel_sources` / output of the previous version). Env knobs already in script: `EPOCHS`, `MAX_TRAIN_STEPS`, `MAX_SAMPLES`, `ATTR_LOSS_WEIGHT`.
- Throughput levers: bf16 where available (T4 lacks bf16: use fp16 + GradScaler as the script already does), length-bucketed batching (sort by length within a shuffled mega-batch) instead of `padding="max_length"`, gradient checkpointing if OOM at 1024-token crops, `torch.compile` only if stable on the Kaggle image.
- Evaluate on the hold-out every 500 steps (3k rows, CPU-cheap relative to training); log TPR@1%FPR, AUC, ECE per source; save the best-by-TPR@1%FPR checkpoint, not last.
- Seeds: 3 runs are expensive; run seed A fully, seeds B and C on a 50% budget only if A passes §2 on the benchmark. Report spread honestly.
- Export fp32 -> int8 -> int4 in the same session; keep all three plus `v7_forensic_calibration.json` in outputs. Do not delete fp32.
- Failure mode guards already in place: no data -> hard error; silently skipped CSVs -> printed warnings.

**2026+ specifics:**
- **Generators**: refresh the generator list each retrain (current Claude, GPT, Gemini, reasoning models, DeepSeek, Qwen, Llama families). Store `generator`, `model_version`, `prompt_id`, `temperature`, `date` per row; this metadata drives group splits and verified attribution labels.
- **Agentic / long-form / multi-turn outputs** and **"write like a human" prompts** are first-class AI slices; so are text from chat UIs with markdown stripped.
- **Human text**: keep pre-2022 or verified-human; assume contamination of web human text after 2023 and never source "human" labels from scraped recent web text.
- **Context**: training crops 128–1024 tokens; keep the 8k architecture so a later app release can score longer windows without retraining.
- **Backbone**: ModernBERT-base stays the default (Dec-2024 architecture, 8k context, ONNX-exportable). Treat any backbone swap (e.g. a larger ModernBERT or a newer encoder) as an ablation to run only after the data is fixed, on the same benchmark; do not change data and backbone in one run.
- **Release gate** (unchanged): all §2 targets on the frozen benchmark, int4 within 1.5 pts of fp32, on-device parity, fusion/calibration refit committed together with the model.

**Runbook (each retrain):** (1) refresh generators and regenerate/append data with checkpointed cache; (2) rebuild datasets, dedup, group-split, push private datasets; (3) bump benchmark only via a new versioned dataset, never edit; (4) run the Kaggle notebook; (5) download outputs, score the benchmark locally; (6) refit calibration and fusion; (7) run on-device parity and the app test suite; (8) ship only if the gate passes, else record results in `check.md` and iterate on data first.

## 12. Three tracks (detector, plagiarism embedding, humanizer)

Status honesty: only Track A has a training script (`scripts/ml_omni_v7_v10/train_omni_v7_v10.py`). Track B has no script yet. Track C has the older `scripts/ml_humanizer_v6/train_humanizer_sota_v6.py` (T5-small), not yet updated for this plan.

| Track | Model | Depends on | Script |
|---|---|---|---|
| A. Omni detector (teacher) | ModernBERT-base, binary + attribution heads | frozen benchmark, new data | exists, patched |
| A2. Omni student (small) | distilled 6-8 layer student of A | A finished | to write (`train_omni_student.py`) |
| B. Plagiarism / semantic embedding | embedding head on the A2 student, contrastive (paraphrase pairs, source-vs-copy pairs, hard negatives) | A2 | to write (`train_omni_embed.py`) |
| C. Humanizer | T5-class seq2seq (separate decoder; cannot share the encoder) | benchmark + final detector for evaluation only | exists (v6), needs data/eval update |

**Parallelism, honestly:** A and C training are independent and could run in separate Kaggle notebooks, but they draw from the same weekly GPU quota (about 30 h per account), so running them in parallel saves wall-clock, not GPU hours. A2 and B must wait for A, since A is their teacher and their data/benchmark. So the practical order is: benchmark and data (A, C datasets) -> A and C notebooks -> evaluate C against A's final detector -> A2 distill -> B embedding head -> fusion refit and ship.

**Track C requirements (humanizer):** train on (AI text -> human-written paraphrase) pairs from frontier generators with the same group-split hygiene as A; loss includes a semantic-preservation term; evaluate on held-out detectors and generators (not only Omni); keep the numbers/citations/polarity guard and the quality tests in `test/essay_quality_eval_test.dart` as release gates.

**Track B requirements (plagiarism):** two layers stay: exact/shingle matching (no training) and semantic matching (embedding). Gate on a plagiarism benchmark with verbatim, light/heavy paraphrase and original slices at fixed FPR, built alongside the detector benchmark.

## 13. Implementation status and ship checklist (2026-10-05)

**Where everything is:** `scripts/kaggle_omni_p3/` (copy bundle, run order `01_data` -> `02_teacher` -> `03_student` -> `04_embed` -> `05_humanizer`, README runbook; originals live in `tool/omni_data/`, `scripts/ml_omni_v7_v10/`, `scripts/ml_omni_student/`, `scripts/ml_omni_embed/`, `scripts/ml_humanizer_v6/`; rebuild the bundle with `scripts/kaggle_omni_p3/build_bundle.sh`).

**Verified (CPU / synthetic):** all scripts compile; 94 `tool/omni_data` tests pass; each training script's SMOKE path ran train -> eval -> export -> quantize -> resume; humanizer ONNX decode matches PyTorch; data tool ran on real legacy data and scored the real Omni model (AUC 0.746 on unseen generators, matching earlier measurements).

**Not verified:** any Kaggle GPU run (fp16/bf16, DataParallel, memory at `TOKEN_BUDGET=12288`), real-data accuracy of any new model, live frontier-API generation (adapters tested against fakes only), `kaggle_push.sh` against the real CLI, on-device latency/parity of new models.

**Findings that change the ship format:**
1. App ONNX runtime is **ORT 1.15.1** (Dart `onnxruntime` 1.4.1). The currently shipped Omni model loads and runs on it (verified). True int4 (`MatMulNBits`) does **not** load on 1.15.1, so the teacher script ships **int8** by default; int4 only with a runtime upgrade and `ALLOW_INT4_SHIP=1`. The old "int4" artifact was an int8 fallback (identical 150 MB).
2. The distilled student prunes the vocabulary: the app must apply `student_vocab_remap.tsv` to tokenizer ids (BPE tokenizer change in Dart) before shipping the student.
3. Humanizer int8 is lossy on T5 (per-channel quantization default raises top-1 agreement with fp32 from 0.87 to ~0.92; the run fails below 0.85). Real size ~94 MB, not 28 MB.
4. Scoring a full benchmark on CPU is slow (383 rows took 8.5 min): use `--chunk-words`.

**User actions before the first run:**
- Create private Kaggle datasets (`lauriva-omni-p3-train`, `-cal` including `holdout.jsonl`, `-bench`; humanizer `lauriva-humanizer-p3`; `lauriva-omni-p3-detector`) and replace placeholder owner slugs in every `kernel-metadata.json`.
- Generate AI text with `01_data/generate_frontier.py` using your own keys (frontier-only policy enforced; stops and writes resume state to `check.md` when quota ends).
- First GPU run: `MAX_TRAIN_STEPS=200 EVAL_EVERY=100` to check memory; set `KEEP_CKPT=1`; attach `-train` and `-cal`, never `-bench`.
- After training: score the frozen benchmark locally (`run_benchmark.py`), refit calibration and fusion (`tool/fit_fusion_stack.py`), run `tool/eval/check_onnx_runtime_compat.py` on the exported model, then the app test suite and an on-device check. Ship only if every §2 gate passes.

## 14. Production-readiness status (2026-10-06)

| Component | State | Evidence |
|---|---|---|
| Detector (Omni P3) | Integrated in app (`omni_p3_int8`), verified on phone | Frozen-bench AUC 0.984 (fp32, 1,200 rows); shipped int8 AUC 0.966 vs fp32 0.968 (100 rows), 170 MB, loads on ORT 1.15.1; Kaggle essays (PERSUADE + DAIGT v2, 320 rows): AUC 0.996, ELL humans flagged 0% at p>=0.90, AI caught 91% |
| Fusion/calibration | Refit: neural-only stack (coef 1.5043, bias 0.9102), verdict p>=0.90 AI / <=0.20 human | ECE 0.018; old coefficients gave ECE 0.257 on the new model |
| Plagiarism embedding | int8 verified (170 MB, `tool/embed_release/`), NOT yet wired into the app | parity vs fp32 on 4 sets; calibration covers near-duplicates only |
| Humanizer | Do not ship raw T5. Ship guarded hybrid (`tool/humanizer_release/`); int8 94.5 MB (top-1 agreement 0.98, exact match 10/20) | 60 chunks: flagged 92% -> 67% (hybrid), negation parity 98-100% |

**Known gaps (not fixed):**
1. Claude-family text is the weakest slice (47% caught at p>=0.90, n=15). Collect >= 200 Claude-family essays, then run the leave-one-family-out retrain.
2. Calibration split's humans differ from the benchmark's (cal-split threshold gives 3.3% human FPR on the bench). Needs a larger, more varied calibration set.
3. Frozen benchmark: legacy generators only, no ESL / humanized / frontier-held-out slices. PERSUADE (ELL flag) can seed the ESL slice.
4. Bundle size: detector asset is 141 MB gz (debug APK 245 MB). Decide bundle vs on-demand (`ModelDeliveryService`), and confirm Play size limits with a release AAB.
5. On-device latency/memory of the 170 MB int8 detector not measured (needs a profiling run); neural-path debug log added (`[ForensicCoordinator] Neural stream ok ...`) but the scan path through the isolate worker did not emit it: instrument the isolate worker.
6. Embedding calibration is near-duplicate only; heavy-paraphrase set needed. Hard-negative detection ~41% at 1% FPR.
7. Humanizer: entity swaps ("We're building" -> "I'm taking") are not caught by any guard; retrain needs frontier paraphrase pairs, sentence-sized pairs, length/negation/entity penalties.
8. `ModelDeliveryService` default download URL (`v7.0.0-models`) is a placeholder: point it at your real release.

## 15. Results added 2026-10-06 (Kaggle account relein) and open items

**Leave-Claude-family-out (LOCO)**, `relein/lauriva-omni-p3-loco-claude` (720 steps, 0.57 h): Claude Opus/Sonnet/Haiku 4.5 rows
(n=415) removed from train and calibration. AUC 0.991 vs holdout humans; TPR 91.3% (Wilson 95% 88.2-93.7%) at the 1%-FPR
calibration-split threshold, human FPR 1.9% at that threshold; per model: Opus 4.5 83%, Sonnet 4.5 95%, Haiku 4.5 97%.
Caveat: held-out rows come from our own generation pipeline (same prompts/domains as training), so this isolates the
model family, not prompt/format shift. DAIGT Claude essays (different prompts, 15 essays) were caught only 47% at p>=0.90:
the weakness is likely prompt/format shift. Retest with a larger set of externally prompted Claude text.

**Student distillation FAILED its gate**, `relein/lauriva-omni-student-p3` (6 layers, hidden 768, 61M params, vocab 40,302,
3 epochs / 1,032 steps, ~10 min): holdout (n=9,989) student AUC 0.964 / TPR@1%FPR 74.2% vs teacher 0.984 / 90.8%
(gate: <= 3 pts drop). int8 66.8 MB (cap 60 MB) with AUC 0.961, TPR@1%FPR 61%. Not shippable. To retry: distil on a large
UNLABELED transfer set (the soft labels come from the teacher: arXiv/OpenStax/Gutenberg/Wikipedia text from tool/corpus/raw,
RAID sample, PERSUADE) with hidden-state distillation (distill_hidden=1), 8 layers, longer training. Until then the app
keeps the bundled teacher (release arm64 APK 156.9 MB).

**RAID** (see docs/RAID_EVAL.md): pooled AUC 0.879; 71.7% of AI caught at p>=0.90 (no attack), strong on chat models
(chatgpt/gpt4/llama-chat/mistral-chat 98-100%), weak on base models (gpt2 47%, mistral 45%, mpt 32%) and attacks
(paraphrase 42%; homoglyph/zero-width not representative: scored without the app's normaliser). Not competitive with top
RAID entries. Plan: add base-model/older-model text and attack augmentation to training and re-evaluate on held-out RAID rows.

**Unfinished agent work (stopped by API limits, 2026-10-06):** corpus fetch (Wikipedia not written yet; arXiv 84 MB,
OpenStax 26 MB, Gutenberg 24 MB, speeches 6 MB done) and the compact corpus index (asset v2 is 5.6 MB from partial data; final
configuration/accuracy report not produced).
