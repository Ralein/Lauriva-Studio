# RAID evaluation of the shipped detector (2026-10-06)

Independent public benchmark: RAID (Dugan et al., ACL 2024, `liamdugan/raid`). Protocol: threshold tuned to
5% false-positive rate on the pooled human texts. Test labels are hidden (leaderboard submission), so this uses
the LABELED train split, sampled by HTTP range requests at 120 offsets across the file (`tool/raid_eval/sample_raid.py`,
67,560 rows). English domains only (abstracts skipped: they overlap our legacy training data; code/czech/german skipped).
Evaluated: 1,220 docs = 300 human + 660 AI with no attack (60 per generator, 8 generators in the sample) + 440 AI with an
attack (40 per attack). Model: shipped int8 Omni P3 (`tool/release/omni_p3_int8`), first 512 tokens, ONNX only.
Script: `tool/raid_eval/eval_raid.py`, results: `tool/raid_eval/raid_report.json`.

## Result: clearly below top RAID entries; far below our own benchmark numbers

- Pooled AUC (all AI vs human): **0.879**. App operating point (p >= 0.90): human FPR 4.7%, AI caught 71.7% (no attack), 54.5% (attacked).
- Our own tests (AUC 0.977-0.996) were on different data: they flatter the model. RAID is the number to quote when comparing.

By generator (TPR at the 5%-FPR threshold, no attack):

| Generator | TPR | | Generator | TPR |
|---|---|---|---|---|
| chatgpt | 1.00 | | gpt2 | 0.47 |
| llama-chat | 1.00 | | mistral (base) | 0.45 |
| gpt4 | 0.98 | | mpt-chat | 0.60 |
| mistral-chat | 0.98 | | mpt (base) | 0.32 |

Strong on instruction-tuned chat models; weak on base (non-chat) models and older gpt2.

By attack (TPR at 5% FPR): paraphrase 0.42, whitespace 0.45, synonym 0.60, number 0.60, article_deletion 0.75,
upper_lower 0.75, insert_paragraphs 0.78, perplexity_misspelling 0.82, alternative_spelling 0.85,
**homoglyph 0.07, zero_width_space 0.05**.

CAVEAT on homoglyph / zero-width / whitespace: this script scores raw text through the ONNX model only. The app runs
`HomoglyphNormalizer` and `TextNormalizer` first, so these three numbers understate the app. Re-score the attacked slice
after the app's normalisation to get the real figure (TODO).

By domain (AI TPR at 5% FPR): reviews 0.95, news 0.72, books 0.67, recipes 0.61, wiki 0.52, reddit 0.50, poetry 0.38.
Human FPR by domain at the pooled threshold: news 0.00, wiki 0.00 (n=17), books 0.04, **recipes 0.15 (n=65)**.

## How to read this honestly

- Published RAID leaderboard entries report > 99% on non-adversarial text at 5% FPR; ours is 71.7%. We are NOT competitive on this benchmark.
- Our detector was not trained on RAID (except a few legacy abstracts); leaderboard entries trained on RAID have an advantage. The comparison is
  informative, not like-for-like.
- n is small per cell (40-60); differences of ~10 points are noise. Domains with n=17 (wiki humans) are not reliable.
- Higher base-model/older-generator failure suggests the training data is too chat-model-heavy: add base-model and older-generator text, plus
  attack-augmented training (homoglyph, whitespace, paraphrase, synonym, misspelling).

## Next steps
1. Re-score attacks after the app's normalisation (Dart): measure the true app numbers for homoglyph/zero-width/whitespace.
2. Add RAID-style training/augmentation (base models, older models, attacks) and re-evaluate on held-out RAID rows.
3. Add the recipes/poetry/reddit domains to the calibration set (human FPR is domain-dependent).
