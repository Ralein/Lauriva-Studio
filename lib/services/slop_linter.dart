// Dart port of the AI-writing-pattern checker from SlopMonster (tools/deslop.py).
//
// SlopMonster: https://github.com/ItsssssJack/SlopMonster
// MIT License, Copyright (c) 2026 Jack Roberts. Full licence text is in
// THIRD_PARTY_NOTICES.md at the repository root.
//
// The catalogue, regexes, thresholds and scoring follow upstream. Differences:
//  * Offsets: upstream collapses whitespace and deletes markdown markup, so its
//    positions are meaningless against the input. Here every transformation is
//    length-preserving (skipped spans become spaces), so [SlopFinding.start] and
//    [SlopFinding.end] index the string that was passed to [SlopLinter.check].
//  * Dart's `\w` and `\b` are ASCII-only, so accented letters count as non-word.
//  * HTML input (upstream `visible_text`) is not ported; pass plain text or Markdown.

import 'dart:math' as math;

enum SlopCategory {
  vocabulary,
  sentencePatterns,
  punctuation,
  threeItemLists,
  unsupportedProof,
}

class SlopFinding {
  final SlopCategory category;
  final String label;

  /// Matched text, always equal to `text.substring(start, end)` of the checked string.
  final String match;
  final int start;
  final int end;

  const SlopFinding({
    required this.category,
    required this.label,
    required this.match,
    required this.start,
    required this.end,
  });

  @override
  String toString() => '${category.name}: $label [$start,$end) "$match"';
}

class SlopReport {
  /// 0..5. Each category with at least one scored finding costs one point.
  final int score;
  final List<SlopFinding> findings;

  /// True when proof findings are reported but were not scored (`allowProof`).
  final bool proofAdvisory;

  const SlopReport({
    required this.score,
    required this.findings,
    this.proofAdvisory = false,
  });

  /// Only categories that have at least one finding appear as keys.
  Map<SlopCategory, List<SlopFinding>> get byCategory {
    final out = <SlopCategory, List<SlopFinding>>{};
    for (final f in findings) {
      (out[f.category] ??= <SlopFinding>[]).add(f);
    }
    return out;
  }

  bool get isClean => score == 5;

  /// Short human-readable list for logs and prompts.
  String summary() {
    if (findings.isEmpty) {
      return score == 0 ? 'slop score 0/5: no text to score' : 'slop score $score/5 (clean)';
    }
    const order = [
      SlopCategory.unsupportedProof,
      SlopCategory.sentencePatterns,
      SlopCategory.vocabulary,
      SlopCategory.punctuation,
      SlopCategory.threeItemLists,
    ];
    const titles = {
      SlopCategory.vocabulary: 'AI vocabulary',
      SlopCategory.sentencePatterns: 'AI constructions',
      SlopCategory.punctuation: 'punctuation cadence',
      SlopCategory.threeItemLists: 'rule-of-three rhythm',
      SlopCategory.unsupportedProof: 'possible invented proof',
    };
    final groups = byCategory;
    final parts = <String>[];
    for (final c in order) {
      final list = groups[c];
      if (list == null) continue;
      final counts = <String, int>{};
      for (final f in list) {
        counts[f.label] = (counts[f.label] ?? 0) + 1;
      }
      final items = counts.entries.map((e) => e.value > 1 ? '${e.key} x${e.value}' : e.key).toList();
      final shown = items.take(6).join(', ');
      final more = items.length > 6 ? ', +${items.length - 6} more' : '';
      final advisory = c == SlopCategory.unsupportedProof && proofAdvisory ? ' (unscored)' : '';
      parts.add('${titles[c]}$advisory: $shown$more');
    }
    return 'slop score $score/5 - ${parts.join('; ')}';
  }
}

class SlopLinter {
  const SlopLinter();

  /// Scores [text] out of 5. With [markdown] (default) fenced code, inline code,
  /// images and struck-through text are ignored. With [allowProof] the proof rule
  /// is still reported but costs no point.
  SlopReport check(String text, {bool markdown = true, bool allowProof = false}) {
    if (text.trim().isEmpty) return const SlopReport(score: 0, findings: []);

    final normalised = _normalise(text);
    var work = normalised;
    var breaks = const <int>[];
    if (markdown) {
      final m = _maskMarkdown(normalised);
      work = m.text;
      breaks = m.breaks;
    }
    // Nothing left to read (for example a code-only snippet): same as empty upstream.
    if (work.trim().isEmpty) return const SlopReport(score: 0, findings: []);

    final findings = <SlopFinding>[];
    void add(SlopCategory c, String label, int s, int e) {
      findings.add(SlopFinding(category: c, label: label, match: text.substring(s, e), start: s, end: e));
    }

    for (final v in _vocab) {
      for (final m in v.pattern.allMatches(work)) {
        add(SlopCategory.vocabulary, v.word, m.start, m.end);
      }
    }

    for (final p in _phrases) {
      for (final m in p.pattern.allMatches(work)) {
        add(SlopCategory.sentencePatterns, p.label, m.start, m.end);
      }
    }

    // Em-dash and compound density, in 220-char windows per sentence (see upstream).
    final segments = _segments(work, breaks);
    for (final seg in segments) {
      for (final w in _windows(seg)) {
        final slice = work.substring(w.$1, w.$2);
        final first = slice.indexOf('—');
        final last = slice.lastIndexOf('—');
        if (first != last) {
          add(SlopCategory.punctuation, 'two or more em-dashes in one sentence', w.$1 + first, w.$1 + last + 1);
          break;
        }
      }
    }
    for (final seg in segments) {
      for (final w in _windows(seg)) {
        final found = _compound.allMatches(work.substring(w.$1, w.$2)).toList();
        if (found.length >= _compoundFloor) {
          final names = found.take(4).map((m) => m.group(0)).join(', ');
          add(SlopCategory.punctuation, '${found.length} hyphenated compounds stacked in one sentence ($names)',
              w.$1 + found.first.start, w.$1 + found.last.end);
          break;
        }
      }
    }

    // Floor of 3: two semicolons in a long technical page is a style, not a tell.
    final semis = ';'.allMatches(work).toList();
    if (semis.length > math.max(3, work.length ~/ 1200)) {
      add(SlopCategory.punctuation, 'semicolon-heavy for web copy (${semis.length} found)', semis.first.start,
          semis.first.end);
    }

    for (final pat in _tricolons) {
      for (final m in pat.allMatches(work)) {
        add(SlopCategory.threeItemLists, 'rule-of-three list', m.start, m.end);
      }
    }

    for (final m in _proof.allMatches(work)) {
      add(SlopCategory.unsupportedProof, 'possible invented proof', m.start, m.end);
    }

    findings.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));

    final failed = <SlopCategory>{
      for (final f in findings)
        if (!(allowProof && f.category == SlopCategory.unsupportedProof)) f.category,
    };
    final score = math.max(0, 5 - failed.length);
    return SlopReport(
      score: score,
      findings: List.unmodifiable(findings),
      proofAdvisory: allowProof && findings.any((f) => f.category == SlopCategory.unsupportedProof),
    );
  }
}

// ── the catalogue ────────────────────────────────────────────────────────────

// Matched by root, so every inflection fires: `elevate` also catches elevates,
// elevated, elevating, elevation.
const _vocabWords = <String>[
  'delve', 'leverage', 'seamless', 'elevate', 'robust', 'unlock', 'unleash',
  'empower', 'streamline', 'cutting-edge', 'state-of-the-art', 'game-changer',
  'game-changing', 'revolutionize', 'revolutionise', 'transformative',
  'transformation', 'innovate', 'holistic', 'synergy', 'synergies', 'paradigm', 'bespoke',
  'meticulous', 'tapestry', 'testament', 'beacon', 'unparalleled', 'supercharge',
  'turbocharge', 'effortless', 'next-level',
  // second tier: fine once in a long page, damning in every section
  'pivotal', 'foster', 'showcase', 'compelling', 'intuitive', 'world-class',
  'best-in-class',
];

// Words with an ordinary literal sense ("we craft furniture", "harness the horse").
// Matched exactly, never by root, so only the marketing inflection is caught.
const _vocabExactWords = <String>[
  'crafted', 'curated', 'harnessing', 'harness the power', 'journey', 'realm', 'landscape',
  'navigate the', 'in the world of', "in today's", 'ever-evolving', 'fast-paced',
  'look no further', 'dive in', "let's dive", 'deep dive', 'embark',
  'unlock the power', 'buckle up', 'the secret sauce', 'level up',
];

class _Vocab {
  final String word;
  final RegExp pattern;
  const _Vocab(this.word, this.pattern);
}

class _Phrase {
  final RegExp pattern;
  final String label;
  const _Phrase(this.pattern, this.label);
}

/// A regex matching [word] and its inflections. Strip a trailing ed/ing/ly/e to get
/// the root, then allow the suffixes back; the bare `e?` keeps the base form matching.
RegExp slopRootPattern(String word) {
  final root = word.replaceFirst(RegExp(r'(ed|ing|ly|e)$'), '');
  if (root.length < 4) {
    return RegExp('(?<!\\w)${RegExp.escape(word)}(?!\\w)', caseSensitive: false);
  }
  return RegExp(
    '(?<!\\w)${RegExp.escape(root)}(?:e|es|ed|ing|ion|ions|ional|ive|al|ally|s|ly|ness)?(?!\\w)',
    caseSensitive: false,
  );
}

final List<_Vocab> _vocab = [
  for (final w in _vocabWords) _Vocab(w, slopRootPattern(w)),
  for (final w in _vocabExactWords)
    _Vocab(w, RegExp('(?<!\\w)${RegExp.escape(w)}(?!\\w)', caseSensitive: false)),
];

// Negated "just/only/merely/simply", contracted or not, straight or curly apostrophe.
const _negJust = r"(?:\bnot|n['’]t)\s+(?:just|only|merely|simply)\b";

// The Y clause of the swap, reached across a comma or a single full stop.
const _xyTail = r'[^!?]{0,80}?[,.]\s*(?:it|this|that|they|we|you|he|she|i)\b';

RegExp _ci(String p) => RegExp(p, caseSensitive: false);

final List<_Phrase> _phrases = [
  _Phrase(_ci(_negJust + r'[^.!?]{0,80}\bbut\b'), "the 'not just X, but Y' construction"),
  _Phrase(_ci(_negJust + _xyTail), "the 'not just X, it's Y' construction"),
  _Phrase(_ci(r"\bwhether you(?:'?re| are)\b[^.!?]{0,40}\bor\b"), "the 'whether you're X or Y' opener"),
  _Phrase(_ci(r'\bmore than just\b'), "'more than just'"),
  _Phrase(_ci(r"\b(that|this)(?:'?s| is) where\b[^.!?]{0,30}\bcomes? in\b"), "'that's where X comes in'"),
  _Phrase(_ci(r'\bsay goodbye to\b'), "'say goodbye to'"),
  _Phrase(_ci(r'\bimagine (a|an|the)\b'), "the 'imagine a...' opener"),
  _Phrase(_ci(r'\bin conclusion\b|\bto sum up\b'), 'essay-summary phrasing'),
  _Phrase(_ci(r'\bwhen it comes to\b'), "'when it comes to' filler"),
  _Phrase(_ci(r'\bat the end of the day\b'), "'at the end of the day'"),
  _Phrase(_ci(r'\bthe key is\b|\bthe truth is\b'), 'throat-clearing opener'),
  _Phrase(_ci(r'\bhelps? you to\b|\bcan help you\b'), "hedged benefit ('helps you to...')"),
  _Phrase(_ci(r'\bmay potentially\b|\bcould potentially\b|\bmight possibly\b'), 'stacked hedging'),
  _Phrase(_ci(r'\bvery unique\b|\bquite literally\b'), 'intensifier padding'),
  _Phrase(_ci(r"\bhere'?s the thing\b|\blet'?s break (it|this) down\b|\bthe best part\b"), 'throat-clearing opener'),
  _Phrase(_ci(r"\bready to get started\b|\blet'?s get started\b"), 'boilerplate CTA'),
  _Phrase(_ci(r'\bthe (result|answer|catch|kicker|upshot)\?\s'), 'self-answering question'),
];

// Four hyphenated compounds in a sentence is a model reaching for authority.
final RegExp _compound = RegExp(r'\b[a-z]{2,}-[a-z]{2,}(?:-[a-z]{2,})*\b', caseSensitive: false);
const int _compoundFloor = 4;

// Tricolon, two narrow shapes: Oxford-comma single words, or a no-Oxford list whose
// third item is a 2-3 word phrase ending the clause.
final List<RegExp> _tricolons = [
  RegExp(r'\b(\w{4,}),\s+(\w{4,}),\s+and\s+(\w{4,})\b'),
  RegExp(r'\b(\w{4,}),\s+(\w{4,})\s+and\s+((?:\w+\s+){1,2}\w+)\s*[.!?,;:]'),
];

// Invented social proof. Every gap is bounded so pathological input (10k spaces after a digit)
// cannot make matching quadratic. Never absorbs a trailing full stop, and the noun is closed
// with a word boundary so "sitemaps" and "teamsters" do not match.
final RegExp _proof = RegExp(
  r'([\d][\d,]{0,15}(?:\.\d{1,6})?)\s{0,3}\+?\s{0,3}'
  r'((?:happy|early|active|satisfied|verified|trusted|delighted)\s{1,3})?'
  r'(?:\w{1,40}\s{1,3}){0,1}'
  r'(users?|customers?|learners?|students?|teams?|members?|companies|businesses'
  r'|homeowners?|subscribers?|clients?|patients?|readers?|sites?|projects?)'
  r'(?!\w)',
  caseSensitive: false,
);

final RegExp _sentenceSplit = RegExp(r'(?<=[.!?])\s+');

// ── helpers ──────────────────────────────────────────────────────────────────

/// Fold typographic variants back to the plain ones the rules match. Every
/// replacement is one UTF-16 unit for one UTF-16 unit, so offsets stay valid.
String _normalise(String t) => t.replaceAll('‑', '-').replaceAll(' ', ' ').replaceAll('’', "'");

/// Same-length blank of [orig]: newlines survive (so `^` anchors still work),
/// everything else becomes a space, optionally with [lead] written at the start.
String _blank(String orig, [String lead = '']) {
  final b = orig.replaceAll(RegExp(r'[^\n]'), ' ');
  if (lead.isEmpty || b.length < lead.length || orig.substring(0, lead.length).contains('\n')) return b;
  return lead + b.substring(lead.length);
}

/// A stand-in for a removed span. Deleting `[needs number]` outright would weld the
/// clause into a false rule-of-three, so a short word keeps it intact.
String _standIn(String orig) => _blank(orig, orig.length >= 3 ? ' it' : '');

/// Length-preserving port of upstream `markdown_prose`. [breaks] are offsets where
/// a heading line ends and the next copy begins.
({String text, List<int> breaks}) _maskMarkdown(String md) {
  final breaks = <int>[];
  md = md.replaceAllMapped(RegExp(r'```.*?```', dotAll: true), (m) => _blank(m.group(0)!));
  md = md.replaceAllMapped(RegExp(r'!\[[^\]]{0,300}\]\([^)]{0,500}\)'), (m) => _blank(m.group(0)!, '.'));
  // Link text stays, because it is read as part of the sentence.
  md = md.replaceAllMapped(RegExp(r'\[([^\]]{0,300})\]\([^)]{0,500}\)'), (m) {
    final inner = m.group(1)!;
    return ' $inner${' ' * (m.group(0)!.length - inner.length - 1)}';
  });
  md = md.replaceAllMapped(RegExp(r'`[^`]*`'), (m) => _standIn(m.group(0)!));
  md = md.replaceAllMapped(RegExp(r'~~.*?~~', dotAll: true), (m) => _standIn(m.group(0)!));
  // Headings, table cells and bullets are separate copy, not one long sentence.
  md = md.replaceAllMapped(RegExp(r'^([ \t]{0,3})(#{1,6})[ \t]*(.*)$', multiLine: true), (m) {
    breaks.add(m.end);
    final g1 = m.group(1)!;
    final g2 = m.group(2)!;
    return '$g1.${' ' * (g2.length - 1)}${m.group(0)!.substring(g1.length + g2.length)}';
  });
  md = md.replaceAll('|', '.');
  md = md.replaceAllMapped(RegExp(r'^([ \t]*)([-*+]|\d+\.)([ \t]+)', multiLine: true),
      (m) => '${m.group(1)}.${' ' * (m.group(2)!.length - 1)}${m.group(3)}');
  md = md.replaceAllMapped(RegExp(r'^([ \t]*)>[ \t]?', multiLine: true),
      (m) => '${m.group(1)}.${m.group(0)!.substring(m.group(1)!.length + 1)}');
  md = md.replaceAll(RegExp(r'[*_>]'), ' ');
  return (text: md, breaks: breaks);
}

/// Sentence spans: split after [.!?] plus whitespace, and additionally at [breaks].
List<(int, int)> _segments(String t, List<int> breaks) {
  final out = <(int, int)>[];
  void addSeg(int start, int end) {
    var s = start;
    for (final h in breaks) {
      if (h > s && h < end) {
        out.add((s, h));
        s = h;
      }
    }
    out.add((s, end));
  }

  var start = 0;
  for (final m in _sentenceSplit.allMatches(t)) {
    addSeg(start, m.start);
    start = m.end;
  }
  addSeg(start, t.length);
  return out;
}

/// 220-char windows over a sentence; bounded on purpose so unpunctuated UI strings
/// do not merge into one giant "sentence".
Iterable<(int, int)> _windows((int, int) seg) sync* {
  final len = seg.$2 - seg.$1;
  for (var i = 0; i < math.max(1, len); i += 220) {
    yield (seg.$1 + i, math.min(seg.$2, seg.$1 + i + 220));
  }
}
