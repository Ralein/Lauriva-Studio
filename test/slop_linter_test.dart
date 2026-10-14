// Ports the regression cases of SlopMonster's tools/test_deslop.py (MIT, Jack Roberts;
// see THIRD_PARTY_NOTICES.md). Inputs and expectations are upstream's; the Python
// suite could not be run here, so expectations were traced against the regexes by hand.
import 'package:lauriva/services/slop_linter.dart';
import 'package:flutter_test/flutter_test.dart';

const _linter = SlopLinter();

Set<SlopCategory> groups(String t, {bool markdown = false}) =>
    _linter.check(t, markdown: markdown).byCategory.keys.toSet();

Set<SlopCategory> mdGroups(String t) => groups(t, markdown: true);

const _vocab = SlopCategory.vocabulary;
const _phr = SlopCategory.sentencePatterns;
const _punct = SlopCategory.punctuation;
const _rhythm = SlopCategory.threeItemLists;
const _proof = SlopCategory.unsupportedProof;

void main() {
  group('vocabulary', () {
    const exact = [
      'crafted', 'curated', 'harnessing', 'harness the power', 'journey', 'realm', 'landscape',
      'navigate the', 'in the world of', "in today's", 'ever-evolving', 'fast-paced',
      'look no further', 'dive in', "let's dive", 'deep dive', 'embark',
      'unlock the power', 'buckle up', 'the secret sauce', 'level up',
    ];
    const base = [
      'delve', 'leverage', 'seamless', 'elevate', 'robust', 'unlock', 'unleash',
      'empower', 'streamline', 'cutting-edge', 'state-of-the-art', 'game-changer',
      'game-changing', 'revolutionize', 'revolutionise', 'transformative',
      'transformation', 'innovate', 'holistic', 'synergy', 'synergies', 'paradigm', 'bespoke',
      'meticulous', 'tapestry', 'testament', 'beacon', 'unparalleled', 'supercharge',
      'turbocharge', 'effortless', 'next-level', 'pivotal', 'foster', 'showcase',
      'compelling', 'intuitive', 'world-class', 'best-in-class',
    ];

    test('every catalogue word fires in its own base form', () {
      for (final w in base) {
        expect(groups('Acme is $w today.'), contains(_vocab), reason: w);
        expect(slopRootPattern(w).hasMatch(w), isTrue, reason: w);
      }
    });

    test('every exact phrase fires', () {
      for (final w in exact) {
        expect(groups('We $w things.'), contains(_vocab), reason: w);
      }
    });

    test('inflections fire', () {
      for (final w in ['elevates', 'unlocks', 'empowers', 'streamlines', 'leverages', 'harnessing',
        'revolutionizes', 'innovation', 'transformational']) {
        expect(groups('Acme $w your workflow.'), contains(_vocab), reason: w);
      }
    });

    test('literal senses stay clean', () {
      for (final ok in ['We craft furniture by hand in Leeds.', 'Harness the horse before you load the cart.',
        'They walked the length of the valley.']) {
        expect(groups(ok), isNot(contains(_vocab)), reason: ok);
      }
    });
  });

  group('constructions', () {
    test('caught', () {
      for (final bad in [
        "It's not just a tool, it's a platform.",
        'It is not just a tool, it is a platform.',
        'Whether you are a beginner or a pro, start here.',
        'This is where Acme comes in.',
        "Here's the thing. You need a plan.",
        'The result? Teams ship faster.',
        'Ready to get started?',
      ]) {
        expect(groups(bad), contains(_phr), reason: bad);
      }
    });

    test('plain "whether you are" is clean', () {
      expect(groups('Check whether you are on the latest version.'), isNot(contains(_phr)));
    });

    test('negated-just, contracted and not, both apostrophes', () {
      for (final hit in [
        "This isn't just a map, it's a plan.",
        'It is not just a map. It is a plan.',
        "SlopMonster isn't just a linter, it's a gate.",
        "These aren't just words, they're tells.",
        'This is not just a map, but a plan.',
        "It doesn't just score you, it fails the build.",
        'This isn’t just a map, it’s a plan.',
      ]) {
        expect(groups(hit), contains(_phr), reason: hit);
      }
    });

    test('negated-just stays clean without a Y clause', () {
      for (final clean in [
        "It's not just about money.",
        'Do not just take my word for it.',
        'We could not just sit there. The rain kept falling.',
        'The lot is not paved, it is grass.',
        'He said the price was not right, and we walked away.',
      ]) {
        expect(groups(clean), isNot(contains(_phr)), reason: clean);
      }
    });
  });

  group('rule of three', () {
    test('no-Oxford tricolon', () => expect(groups('Trusted, reliable and built to last.'), contains(_rhythm)));
    test('Oxford tricolon', () => expect(groups('It is faster, smarter, and better.'), contains(_rhythm)));
    test('short items are not a tricolon',
        () => expect(groups('We shipped red, white, and blue.'), isNot(contains(_rhythm))));
    test('fronted adverbial is not a tricolon',
        () => expect(groups('On Tuesday, we shipped the release and went home.'), isNot(contains(_rhythm))));
    test('service list is not a tricolon', () {
      expect(groups('Inspection, repair and replacement for homes and commercial buildings.'),
          isNot(contains(_rhythm)));
    });
    test('or-list is not a tricolon',
        () => expect(groups('We do not do gutters, siding, windows or conservatories.'), isNot(contains(_rhythm))));
  });

  group('proof', () {
    test('canonical invented proof', () {
      expect(groups('Loved by 10,000+ happy homeowners.'), contains(_proof));
      expect(groups('Trusted by 25 businesses.'), contains(_proof));
    });

    test('real claims caught', () {
      for (final hit in ['10,000+ happy users', '500 teams', '2,000 verified customers', '3.5 million customers',
        'Trusted by 10,000 teams.', 'We host 12 sites.', 'Over 300 clients served.']) {
        expect(groups(hit), contains(_proof), reason: hit);
      }
    });

    test('does not reach across a full stop', () {
      for (final clean in [
        '"Don\'t Make Me Think", 2000. The reader decides in seconds.',
        'Roofing, and only roofing, since 2001. Customers come back.',
        'Version 2.0. Readers can skip it.',
      ]) {
        expect(groups(clean), isNot(contains(_proof)), reason: clean);
      }
    });

    test('noun needs a closing boundary', () {
      for (final clean in ['We generated 12 sitemaps last quarter.', 'The hall seats 20 projectors.',
        'We shipped 40 userscripts.', 'The union sent 300 teamsters.']) {
        expect(groups(clean), isNot(contains(_proof)), reason: clean);
      }
    });

    test('allowProof reports but does not score', () {
      final strict = _linter.check('Trusted by 25 businesses.', markdown: false);
      final lax = _linter.check('Trusted by 25 businesses.', markdown: false, allowProof: true);
      expect(strict.score, 4);
      expect(lax.score, 5);
      expect(lax.isClean, isTrue);
      expect(lax.byCategory.keys, contains(_proof));
      expect(lax.summary(), contains('(unscored)'));
    });
  });

  group('punctuation', () {
    test('four stacked compounds fire', () {
      expect(groups('Our industry-leading, context-aware, best-in-class, AI-powered platform ships.'),
          contains(_punct));
    });

    test('ordinary hyphenated copy stays clean', () {
      for (final ok in [
        'We fitted a 25-year warranty and a 4.2-hour call-out on a two-storey roof.',
        'The built-up roof needs a full-width strip before the tear-off.',
        'A well-known, long-standing trade name.',
      ]) {
        expect(groups(ok), isNot(contains(_punct)), reason: ok);
      }
    });

    test('two em-dashes in a sentence fire; one per sentence does not', () {
      expect(groups('We ship fast — really fast — every week.'), contains(_punct));
      expect(groups('We ship fast — really. Then rest — always.'), isNot(contains(_punct)));
    });

    test('semicolon density needs more than three', () {
      expect(groups('a; b; c; d; e.'), contains(_punct));
      expect(groups('a; b; c.'), isNot(contains(_punct)));
    });
  });

  group('UTF-8 and typography', () {
    const tells = 'It’s not just a tool, it’s a platform. Whether you’re a startup '
        'or an agency, we ship fast — really fast — every week.';

    test('curly apostrophes and em-dashes are read', () {
      final g = groups(tells);
      expect(g, contains(_phr));
      expect(g, contains(_punct));
      expect(_linter.check(tells, markdown: false).isClean, isFalse);
    });

    test('non-Latin snippet still scores', () {
      final r = _linter.check('Our seamless platform 你好 — 世界 — delivers robust value today.',
          markdown: false);
      expect(r.byCategory.keys, containsAll([_vocab, _punct]));
    });

    test('non-breaking hyphen and nbsp are folded', () {
      expect(groups('Our cutting‑edge tool.'), contains(_vocab));
      expect(groups('It is not just a tool, it is a platform.'), contains(_phr));
    });
  });

  group('clean copy and empty input', () {
    test('clean human copy scores 5/5', () {
      for (final ok in [
        'Six nails per shingle, every shingle.',
        'You get a written scope and a fixed number before anyone climbs a ladder.',
        'We do not do overlays. If the roof needs replacing, it gets stripped.',
      ]) {
        final r = _linter.check(ok, markdown: false);
        expect(r.isClean, isTrue, reason: '$ok -> ${r.summary()}');
        expect(r.findings, isEmpty);
        expect(_linter.check(ok).isClean, isTrue, reason: ok);
      }
    });

    test('empty and blank input is not clean', () {
      for (final t in ['', '   ', '\n\t ']) {
        final r = _linter.check(t);
        expect(r.score, 0);
        expect(r.isClean, isFalse);
        expect(r.findings, isEmpty);
      }
    });

    test('score is 5 minus categories hit', () {
      final r = _linter.check('We leverage this. The result? Fast — so — fast. Trusted, reliable and built to last. '
          'Used by 20 teams.');
      expect(r.score, 0);
      expect(r.byCategory.keys.length, 5);
      expect(r.summary(), startsWith('slop score 0/5'));
    });
  });

  group('markdown', () {
    test('inline code is not scored, link text is', () {
      expect(mdGroups('Use `delve` here. See [the guide](u.md) for more.'), isEmpty);
      const t = 'See [seamless guide](u.md) now.';
      final r = _linter.check(t);
      expect(r.findings.single.match, 'seamless');
      expect(t.substring(r.findings.single.start, r.findings.single.end), 'seamless');
    });

    test('images and struck text are skipped', () {
      expect(mdGroups('Look ![seamless robust](a.png) here.'), isEmpty);
      expect(mdGroups('> ~~Trusted, reliable and built to last.~~\n> **Six nails per shingle.**'), isEmpty);
    });

    test('fenced block is not scored; prose around it is', () {
      expect(mdGroups('Intro.\n```\nleverage seamless unlock\n```\nOutro.'), isEmpty);
      expect(mdGroups('Intro.\n```\nx\n```\nWe leverage it.'), contains(_vocab));
    });

    test('plain mode does score code spans', () {
      expect(groups('Use `delve` here.'), contains(_vocab));
    });

    test('stripping code invents no tricolon', () {
      expect(mdGroups('If a claim needs a number you do not have, write `[needs number]` and move on.'),
          isNot(contains(_rhythm)));
    });

    test('table rows do not merge into one cadence', () {
      expect(mdGroups('| a | **3/5** — one thing |\n| b | **5/5** — another thing |'), isNot(contains(_punct)));
    });

    test('headings do not weld to the body', () {
      expect(mdGroups('## One — two\nThree — four.'), isNot(contains(_punct)));
    });

    test('markdown does not soften real slop', () {
      expect(mdGroups('We leverage seamless, robust and cutting-edge tooling to empower teams.'), contains(_vocab));
      expect(mdGroups('It is not just a tool, it is a journey.'), contains(_phr));
    });

    test('bullets and blockquotes do not merge', () {
      expect(mdGroups('- Tier 1 — delete on sight\n- Tier 2 — usually cut'), isNot(contains(_punct)));
      expect(mdGroups('- Our team — trained, certified and local — is ready to help.'), contains(_punct));
      expect(mdGroups('> ~~Em-dash pile-up~~\n> **Thirty-eight on the crew, factory-trained today.**'),
          isNot(contains(_punct)));
    });

    test('markdown tells with smart quotes still fire', () {
      expect(mdGroups('It’s not just a tool, it’s a platform.'), contains(_phr));
    });

    test('code-only input has nothing to score', () {
      expect(_linter.check('```\nleverage\n```').score, 0);
    });
  });

  group('offsets', () {
    test('substring(start, end) == match for every finding, in both modes', () {
      const samples = [
        'Intro ’quoted’.\n```\nleverage\n```\n## Head — a\n- We **leverage** seamless, robust and cutting‑edge tools — now — ok.\n'
            '> It isn’t just a tool, it’s a gate. Trusted, reliable and built to last. Used by 20 teams; a; b; c; d.\n'
            '| x | `delve` | ~~empower~~ [intuitive](u) ![alt robust](p.png) |\n',
        'Our industry-leading, context-aware, best-in-class, AI-powered platform ships. Loved by 10,000+ happy homeowners.',
      ];
      for (final s in samples) {
        for (final md in [true, false]) {
          final r = _linter.check(s, markdown: md);
          expect(r.findings, isNotEmpty);
          for (final f in r.findings) {
            expect(s.substring(f.start, f.end), f.match, reason: f.toString());
          }
        }
      }
    });

    test('masked spans keep later offsets valid', () {
      const t = 'Use `code here` then leverage it.';
      final f = _linter.check(t).findings.single;
      expect(f.match, 'leverage');
      expect(f.start, t.indexOf('leverage'));
    });

    test('summary lists findings', () {
      final s = _linter.check('We leverage seamless tools. Say goodbye to pain.').summary();
      expect(s, contains('AI vocabulary'));
      expect(s, contains('leverage'));
      expect(s, contains("'say goodbye to'"));
    });
  });
}
