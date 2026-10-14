# Studio Engine

Studio is the text-transformation surface of Lauriva: the user pastes or dictates
text, taps a feature chip (Humanize, Rephrase, Concise, Professional, Polite,
Grammar, Translate, a `Style:*` tone, or PlagiarismCheck) and receives streamed
output. This document covers the pieces that decide what the model is asked to
do and what happens to its answer.

| Piece | File |
|---|---|
| Orchestration and state | `lib/providers/studio_provider.dart` (`StudioProvider`) |
| Prompts | `lib/constants/app_prompts.dart` (`AppPrompts`) |
| AI-pattern linter | `lib/services/slop_linter.dart` (`SlopLinter`, `SlopReport`, `SlopFinding`) |
| Targeted repair | `lib/services/slop_repair_service.dart` (`SlopRepairService`, `SlopRepairResult`) |
| Report UI | `lib/widgets/studio/slop_report_chip.dart` (`SlopReportChip`), shown from `lib/widgets/zone3_output.dart`; auto-polish switch in `lib/widgets/zone2_action_chips.dart` |

## Request flow

1. `StudioProvider.handleFeatureClick(featureId)` rejects unknown feature ids
   (`FeatureType.fromId`), routes `PlagiarismCheck` to the plagiarism provider,
   and otherwise starts a streamed LLM call through
   `LlmService.transformTextStreamWithFailover`, so the configured provider
   chain can fail over. Streamed chunks are flushed to the UI on a 40 ms
   throttle, and a 5-minute guard timer ends a stuck generation.
2. The system prompt is built by `AppPrompts`. `globalSystemPrompt` states the
   global rules (no chatter, preserve names, numbers and dates, never invent
   facts, keep the input language, avoid metronomic AI cadence).
   `getFeatureInstruction` adds the per-feature instruction; for Humanize it
   layers a tone calibration (`_humanizeToneCalibration`, by persona) and an
   intensity calibration (`_intensityCalibration`, by the 0 to 100 intensity).
3. **`AppPrompts.editingPrinciples`**: a short block appended by
   `getFeatureInstruction` to the rewrite-style features only (`Humanize`,
   `Rephrase`, `Concise`, `Professional`, `Polite`, and the `Style:` Witty,
   Assertive, Empathetic, Direct and Storytelling variants). It is deliberately
   not added to Grammar, Translate or PlagiarismCheck, which must stay faithful
   to the input. Its rules: write for the stated reader and lead with what they
   need; every sentence must add information; keep claims exactly as
   conditional as the source (preserve hedges); avoid empty contrasts, repeated
   metaphors and mirrored sentence shapes; let sentence length follow the
   thought and do not manufacture personality (no invented opinions, deliberate
   mistakes or short-sentence quotas); never add statistics, testimonials,
   examples, causes or attributions; preserve facts, numbers, dates, names,
   links, citations and placeholders. The principles are distilled from the
   MIT-licensed SlopMonster editing guidance (see Credit).
4. After the stream ends and the output is sanitised, the optional slop repair
   pass runs (below). For Humanize, the algorithmic post-processing quality loop
   (`AlgorithmicHumanizerService.postProcessWithQualityLoop`) runs after the
   repair pass, so the loop sees the repaired text and cannot be undone by it.
5. The final text is shown, a lint report is computed for it (rewrite-style
   features only), and for Humanize a verification against the original is
   computed by the plagiarism provider.

## The AI-pattern linter (`SlopLinter`)

`SlopLinter.check(text, {markdown = true, allowProof = false})` is a Dart port
of the AI-writing-pattern checker `tools/deslop.py` from SlopMonster. It is
rule-based, offline, deterministic and fast; it does not call a model.

* **Five categories** (`SlopCategory`): `vocabulary` (AI-favoured words,
  matched by root so inflections count), `sentencePatterns` (stock AI
  constructions, such as "not just X but Y" shapes), `punctuation` (two or more
  em dashes in one sentence, stacked hyphenated compounds, semicolon-heavy
  copy), `threeItemLists` (rule-of-three rhythm), and `unsupportedProof`
  (possible invented social proof such as made-up testimonials or statistics).
* **Score** (`SlopReport.score`, 0 to 5): `5 - (categories with at least one
  finding)`. Each category costs at most one point however many times it
  fires. Empty or code-only input scores 0 with no findings; `isClean` means
  5/5. With `allowProof` the proof rule is reported but not scored
  (`proofAdvisory`).
* **Offsets**: every markdown-masking step is length-preserving, so
  `SlopFinding.start` and `end` index the exact string that was checked.
  Fenced code, inline code, images and struck-through text are ignored when
  `markdown` is true.
* **Differences from upstream**: Dart's `\w` and `\b` are ASCII-only, so
  accented letters count as non-word characters; HTML input is not ported (pass
  plain text or Markdown).

### What the score is, and what it is not

The score is a **lint**. It counts surface patterns that readers and many
detectors associate with machine-written text. It is useful for editing: it
points at specific phrases worth rewording.

* A high score is **not proof of human authorship**. Human writers use these
  words and rhythms constantly, and a model can avoid them.
* A low score is **not proof of AI authorship**, and a clean text can still be
  fully machine-generated.
* It is **not a detector-evasion guarantee**. Passing the lint says nothing
  about how any third-party or institutional AI detector will score the text,
  and Lauriva makes no such promise. Treat the product as an editing aid, and be
  honest about authorship wherever policy requires it.
* The `unsupportedProof` category is a heuristic for invented claims; it can
  misfire on legitimate quoted material and is never auto-repaired.

## Check, repair, verify (`SlopRepairService`)

Run by `StudioProvider` after a finished rewrite when the user's auto-polish
setting is on and `SlopRepairService.shouldCheck(featureId)` is true (Humanize,
Rephrase, Concise, Professional, Polite and `Style:*`; never Grammar or
Translate).

1. Lint the candidate. If there is nothing repairable (only
   `unsupportedProof` findings do not count as repairable), keep it as is.
2. One non-streaming LLM call (`featureId` `SlopRepair`, temperature 0.2, same
   provider chain with failover) is given the flagged spots, up to 40, each with
   its surrounding sentence, plus the full text, and told to fix only those.
3. The repair is **accepted only if every rule holds**, otherwise the original
   candidate is returned unchanged:
   * the number of repairable findings strictly dropped;
   * word count stays within 15% of the candidate;
   * all URLs, `@handles`, `{placeholders}` and numbers from the candidate are
     still present;
   * the negation count is unchanged;
   * `SemanticPreservationVerifier` against the **original source** reports no
     factual drift, numeric drift or citation loss.
4. It never throws; any error, cancellation, empty or unchanged reply keeps the
   candidate. `SlopRepairResult.reason` records why a repair was rejected.

The repair costs one extra model call per rewrite. The setting is
`StudioProvider.slopAutoPolish` (default on), persisted by
`StorageService.getSlopAutoPolish` / `setSlopAutoPolish`. The UI shows
"Polishing AI patterns..." during the pass and then a `SlopReportChip` ("n/5,
k flags"); tapping it lists the findings and whether a repair was applied.
`stopGeneration()` cancels the pass and keeps what is on screen.

## Credit

The AI-pattern catalogue, regexes, thresholds and scoring in
`lib/services/slop_linter.dart`, and the principles behind
`AppPrompts.editingPrinciples`, derive from
[SlopMonster](https://github.com/ItsssssJack/SlopMonster) by Jack Roberts,
licensed under the MIT License. The copyright notice and licence text are
reproduced in `THIRD_PARTY_NOTICES.md` at the repository root and must remain
with any redistribution.

## Tests

`test/slop_linter_test.dart`, `test/slop_repair_service_test.dart` and
`test/studio_slop_setting_test.dart`.
