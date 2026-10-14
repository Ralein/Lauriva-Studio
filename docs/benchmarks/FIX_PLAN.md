# Plan: fix the weaknesses found by the plagiarism benchmark

Source of truth for the numbers: `docs/benchmarks/plagiarism.md`. Read it first.
Project rules: `AGENTS.md`. No UI changes. Free tier only: no API keys, no paid services, no new servers.

## Ground rules (do not skip)

1. **Split the data before touching code.** `tool/eval/plagiarism_bench/dataset.jsonl` has 396 items (the CSV export has 436 rows incl. the 40 heavy paraphrases).
   Randomly split by id (seed 42) into `dev` (50%) and `heldout` (50%), stratified by family and label. Save the id lists.
   Tune and debug ONLY on `dev`. Run `heldout` once at the end and report that number. Never adjust anything after seeing heldout.
2. **No threshold tuning for a target number.** The red-flag threshold (overall >= 20) and `CompactDecision` (gap 10, minRunFps 5, minSpan 14, minCoverage 0.20, strongTokens 60) are validated. Do not change them.
3. **Do not weaken the benchmark.** Same "correct source" rules (lenient, strict, URL-only), same negatives. Report all three.
4. Offline tier must keep 0 false positives on the originals. Any change that adds one is rejected.
5. Keep per-scan privacy bounds and the 5 s `overallDeadline` (must stay below the coordinator timeouts 8 s / 10 s). Bound every regex quantifier. Respect the circuit breakers and throttles.
6. Add a unit test (MockClient, no live network) for every change. Full suite must stay green (`flutter test`, currently 1176 passed).
7. Update `docs/privacy.md` and `docs/privacy.html` if a new third-party host is contacted.

## Fixes (in order)

### 1. Stack Exchange, 0/20
File: `lib/services/forensic/sources/online/community_retrievers.dart` (`StackExchangeRetriever`).
Problem: queries one site chosen from a small keyword map; the positives came from cooking, gardening, travel, etc.
Fix: query the unauthenticated `/search/excerpts` endpoint across a small set of sites (e.g. 3 to 4 chosen by keyword, fallback to stackoverflow + one general), in parallel, within the retriever's own timeout. Respect the API `backoff` field. Max 300 requests/day/IP unkeyed, so keep it to 1 to 2 requests per scan.

### 2. OpenStax, 0/55
Files: `keyless_web_retrievers.dart` (Bing/Brave HTML retrievers), `online_source_search_service.dart`.
Problem: matches came from doi.org/Wikipedia, never openstax.org. There is no OpenStax API.
Fix: when the text looks textbook-like (long expository paragraph, no first person), add one extra query using a quoted distinctive phrase plus `site:openstax.org` through the existing HTML retrievers. Budget: one extra query, same deadline. Measure that it does not hurt other families.

### 3. News (Wikinews 0 to 8%)
File: new retriever next to `web_search_retrievers.dart`, modelled on `WikipediaRetriever` (exact phrase quoted, MediaWiki API) against `en.wikinews.org`. Register it in `OnlineSourceSearchService.withDefaults`.

### 4. Dead and failing retrievers (Brave, Semantic Scholar: mostly HTTP 429)
File: `online_source_search_service.dart`.
Fix: after N consecutive failures, open the circuit breaker for a longer cooldown and skip that retriever for the rest of the session instead of spending deadline on it. Do not retry on 429 within the same scan. Verify with a test using a MockClient that returns 429.

### 5. Short-match false positives (~4% of originals scored >= 20)
Evidence: false matches are 5 to 26 tokens, against Wikipedia lead sentences and Hacker News titles, mostly on definition-style text.
Fix: in the online path only (never offline), do not count a match toward the score when it is shorter than a minimum run length and the source is one of those two kinds, unless the same source has a second independent run. Pick the minimum from the `dev` split only. Offline behaviour must stay byte-identical (add a regression test).

### 6. Page enrichment fires on ~3% of scans
File: `source_page_enricher.dart` (`minSnippetOverlap` = 2 content 4-grams).
Measured gain was +1 hit of 210, so this is LOW priority. Only change it if the dev split shows a gain, and keep p95 latency under the coordinator timeout.

## Not fixable for free (do not attempt, do not claim)

- Full-web / publisher / student-paper coverage (Turnitin's database).
- Heavy paraphrase detection (1 of 40 found). Needs a semantic model or an LLM. Optional future work using the user's own key, off by default, and must be measured on the 40 heavy items before any claim.

## Measuring

- Runner: `test/benchmark_live/plagiarism_bench_test.dart` (skipped unless `PLAG_BENCH_OUT` is set; also `PLAG_BENCH_PIPELINES`, `PLAG_BENCH_IDFILE`). Report script: `tool/eval/plagiarism_bench/report.py`.
- Run on plugged-in power, lid open. A full paired run took ~70 min.
- Live web varies run to run (hybrid recall was 36% then 30% from rate limits). Run heldout twice, report both, and report a range. Wilson 95% CIs cover item sampling only.
- Rate limits are partly an artifact of one IP sending ~700 scans. Space requests out.

## Honest targets (heldout)

| Metric | Target |
|---|---|
| Originals not flagged red (overall < 20) | >= 95% (report the CI lower bound too) |
| Offline: copy found when source is in the index | >= 95% (already 96 to 98%) |
| Hybrid: correct source, any source | report as measured; expect improvement, not 95% |
| Heavy paraphrase | report as measured; do not expect 95% |

If a target is missed, publish the miss. Do not tune on heldout to hide it.

## Done when

- All changes have tests, `flutter test` is green, `flutter analyze` is clean on touched files.
- `docs/benchmarks/plagiarism.md` has a new section with before/after on heldout, all three rules, CIs, and the run-to-run range.
- Nothing committed that changes the validated thresholds.
