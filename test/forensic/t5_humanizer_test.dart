import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/document_style_profiler.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_model.dart';
import 'package:lauriva/services/forensic/humanizer/on_device_t5_humanizer_model.dart';
import 'package:lauriva/services/forensic/humanizer/t5_backend.dart';
import 'package:lauriva/services/forensic/humanizer/t5_chunker.dart';
import 'package:lauriva/services/forensic/humanizer/t5_greedy_decoder.dart';
import 'package:lauriva/services/forensic/humanizer/t5_guards.dart';
import 'package:lauriva/services/forensic/humanizer/t5_tokenizer.dart';

/// Scripted backend: "encodes" by remembering the source text, then emits the
/// token ids of the configured response (then `</s>`), one token per step.
class ScriptedT5Backend implements T5Backend {
  final T5Tokenizer tokenizer;
  final String Function(String source) respond;
  final List<String> sources = [];
  int decoderCalls = 0;
  bool disposed = false;
  List<int> _target = const [];

  ScriptedT5Backend(this.tokenizer, this.respond);

  @override
  Future<T5EncoderOutput> encode(List<int> inputIds) async {
    final text = tokenizer.decode(inputIds);
    final source = text.startsWith('humanize: ') ? text.substring('humanize: '.length) : text;
    sources.add(source);
    _target = tokenizer.encode(respond(source)); // ends with </s>
    return T5EncoderOutput(hidden: Float32List(4), srcLen: inputIds.length, dModel: 1);
  }

  @override
  Future<Float32List> nextTokenLogits(T5EncoderOutput encoder, List<int> decoderIds) async {
    decoderCalls++;
    final step = decoderIds.length - 1; // decoderIds = [start, ...generated]
    final next = step < _target.length ? _target[step] : T5Tokenizer.eosId;
    final logits = Float32List(32100)..fillRange(0, 32100, -10.0);
    logits[next] = 10.0;
    return logits;
  }

  @override
  void dispose() => disposed = true;
}

class _ThrowingBackend implements T5Backend {
  @override
  Future<T5EncoderOutput> encode(List<int> inputIds) async => throw const T5UnavailableException('no ort');
  @override
  Future<Float32List> nextTokenLogits(T5EncoderOutput encoder, List<int> decoderIds) async => throw StateError('unreachable');
  @override
  void dispose() {}
}

ChunkRewriteContext _ctx(String text) => ChunkRewriteContext(
      targetChunk: text,
      styleProfile: DocumentStyleProfiler().profile(text),
    );

void main() {
  final vocab = File('tool/humanizer_release/t5_spm_unigram.txt');
  final skip = vocab.existsSync() ? null : 'T5 vocab export missing';
  late T5Tokenizer tok;
  setUpAll(() {
    if (skip == null) tok = T5Tokenizer.fromVocabString(vocab.readAsStringSync());
  });

  group('T5GreedyDecoder', () {
    test('emits the scripted tokens, stops at </s>, excludes the start id', () async {
      final backend = ScriptedT5Backend(tok, (_) => 'Hello there, world.');
      final out = await T5GreedyDecoder(backend: backend).generate(tok.encode('humanize: hi'));
      expect(tok.decode(out), 'Hello there, world.');
      expect(out.first, isNot(T5GreedyDecoder.startId));
      expect(out, isNot(contains(T5Tokenizer.eosId)));
    }, skip: skip);

    test('respects the generation cap', () async {
      final backend = ScriptedT5Backend(tok, (_) => List.filled(40, 'word').join(' '));
      final out = await T5GreedyDecoder(backend: backend, noRepeatNgramSize: 0)
          .generate(tok.encode('humanize: x'), maxNewTokensOverride: 5);
      expect(out.length, 5);
      expect(backend.decoderCalls, 5);
    }, skip: skip);

    test('bannedTokens matches HF no_repeat_ngram semantics', () {
      expect(T5GreedyDecoder.bannedTokens([0, 7, 8, 9, 7, 8], 3), {9});
      expect(T5GreedyDecoder.bannedTokens([0, 7, 8], 3), isEmpty);
      expect(T5GreedyDecoder.bannedTokens([0, 5, 6, 5, 6], 3), {5});
      expect(T5GreedyDecoder.bannedTokens([0, 1, 2, 3], 3), isEmpty);
      expect(T5GreedyDecoder.bannedTokens([0, 1], 3), isEmpty);
      expect(T5GreedyDecoder.bannedTokens([0, 1, 1, 1], 0), isEmpty);
    });

    test('no_repeat_ngram stops a repetition loop', () async {
      // Backend that always prefers token 100, then 200 as runner-up.
      final backend = _LoopBackend();
      final out = await T5GreedyDecoder(backend: backend, noRepeatNgramSize: 3)
          .generate([5, 1], maxNewTokensOverride: 12);
      // With n=3 the sequence cannot contain the trigram (100,100,100) twice.
      var trigramRepeats = 0;
      final seen = <String>{};
      for (var i = 0; i + 3 <= out.length; i++) {
        if (!seen.add(out.sublist(i, i + 3).join(','))) trigramRepeats++;
      }
      expect(trigramRepeats, 0);
    });
  });

  group('T5Guards', () {
    test('passes a faithful rewrite', () {
      final r = T5Guards.check(
        'The committee found that the plan was not feasible in 2024, costing 5 percent more.',
        'In 2024 the committee found the plan was not feasible, and it cost 5% more.',
      );
      expect(r.passed, isTrue, reason: '${r.failure}');
    });

    test('rejects under- and over-length', () {
      expect(T5Guards.check('one two three four five six seven eight nine ten', 'one two three').failure, 'length');
      expect(T5Guards.check('one two three four five', 'one two three four five six seven eight').failure, 'length');
    });

    test('rejects a changed negation count', () {
      final r = T5Guards.check('The drug did not work for most of the patients in the study.',
          'The drug worked for most of the patients in the study overall.');
      expect(r.failure, 'negation');
    });

    test('rejects dropped numbers, accepts reformatted ones', () {
      expect(T5Guards.check('Sales rose 18 percent to 1,200 units across the whole quarter.',
          'Sales rose strongly to many units across the whole quarter overall.').failure, 'numbers');
      expect(T5Guards.check('Sales rose 18 percent to 1,200 units across the whole quarter.',
          'Across the whole quarter, sales rose 18% to 1200 units.').passed, isTrue);
    });

    test('rejects dropped citations', () {
      expect(T5Guards.check('This was shown before [1, 2] and later (Smith et al., 2021) by others.',
          'It was shown before in 1, 2 and later by Smith et al. 2021 by others.').failure, 'citations');
      expect(T5Guards.check('This was shown before [1, 2] and later (Smith et al., 2021) by others.',
          'Others showed this before [1,2] and later (Smith et al., 2021) too.').passed, isTrue);
    });
  });

  group('T5Guards degeneration', () {
    test('rejects the observed on-device repetition failure', () {
      final r = T5Guards.check('The tumour was found early, in the first stages of the disease, by the doctors.',
          'The tumour was found in the tumour in the early stages of the tumour.');
      expect(r.repetitionOk, isFalse);
      expect(r.failure, anyOf('repetition', 'length'));
    });

    test('rejects a repeated trigram', () {
      expect(T5Guards.degenerates('It rained all day long over the city.',
          'It rained all day and it rained all day over the city.'), isTrue);
    });

    test('allows legitimate repetition that the source also had', () {
      expect(T5Guards.degenerates('The council, the council staff and the council chair met the council.',
          'The council met with its staff, and the council chair joined the council later.'), isFalse);
    });

    test('normal rewrites are not flagged', () {
      expect(T5Guards.degenerates('The big house stood on a hill near the quiet river.',
          'The large house stood on a hill near the quiet river.'), isFalse);
    });
  });

  group('T5Chunker', () {
    test('keeps chunks within the word cap and loses nothing', () {
      final text = List.generate(12, (i) => 'Sentence number $i has exactly seven words total.').join(' ');
      final chunks = T5Chunker.chunk(text, maxWords: 20);
      expect(chunks.every((c) => c.split(' ').length <= 20), isTrue);
      expect(chunks.join(' '), text);
    });

    test('an over-long single sentence is its own chunk', () {
      final long = 'word ' * 80;
      expect(T5Chunker.chunk('$long. Short one.', maxWords: 50).length, 2);
    });

    test('empty input yields no chunks', () {
      expect(T5Chunker.chunk('   '), isEmpty);
    });
  });

  group('OnDeviceT5HumanizerModel', () {
    OnDeviceT5HumanizerModel model(ScriptedT5Backend b) => OnDeviceT5HumanizerModel(tokenizer: tok, backend: b);

    test('accepts a guarded rewrite and keeps paragraph structure', () async {
      final backend = ScriptedT5Backend(tok, (s) => s.replaceFirst('big', 'large'));
      final m = model(backend);
      final out = await m.rewriteChunk(_ctx('The big house stood on a hill near the quiet river.\n\nA big dog slept inside the old barn.'));
      expect(out, 'The large house stood on a hill near the quiet river.\n\nA large dog slept inside the old barn.');
      expect(m.lastStats.rewritten, 2);
      expect(m.lastStats.guardFailures, isEmpty);
    }, skip: skip);

    test('keeps the source when the rewrite drops a negation', () async {
      final backend = ScriptedT5Backend(tok, (s) => s.replaceAll(' not', ''));
      final m = model(backend);
      const src = 'The committee did not approve the plan because the costs were far too high.';
      expect(await m.rewriteChunk(_ctx(src)), src);
      expect(m.lastStats.guardFailures['negation'], 1);
    }, skip: skip);

    test('keeps the source when the rewrite is too short', () async {
      final backend = ScriptedT5Backend(tok, (_) => 'It happened.');
      final m = model(backend);
      const src = 'The committee reviewed the proposal carefully and reached a clear decision after a long debate.';
      expect(await m.rewriteChunk(_ctx(src)), src);
      expect(m.lastStats.guardFailures['length'], 1);
    }, skip: skip);

    test('passes chunks with protected placeholders through without calling the model', () async {
      final backend = ScriptedT5Backend(tok, (s) => 'SHOULD NOT BE USED');
      final m = model(backend);
      const src = 'Revenue reached [PROTECTED_001] in the second quarter of the year.';
      expect(await m.rewriteChunk(_ctx(src)), src);
      expect(backend.sources, isEmpty);
      expect(m.lastStats.skippedProtected, 1);
    }, skip: skip);

    test('long chunks are split into sentence chunks of at most 50 words', () async {
      final backend = ScriptedT5Backend(tok, (s) => s);
      final m = model(backend);
      final src = List.generate(14, (i) => 'Sentence number $i has exactly seven words total.').join(' ');
      await m.rewriteChunk(_ctx(src));
      expect(backend.sources.every((s) => s.split(' ').length <= 50), isTrue);
      expect(backend.sources.length, greaterThanOrEqualTo(2));
    }, skip: skip);

    test('backend unavailability propagates as T5UnavailableException', () async {
      final m = OnDeviceT5HumanizerModel(tokenizer: tok, backend: _ThrowingBackend());
      await expectLater(m.rewriteChunk(_ctx('A perfectly ordinary sentence for the model to rewrite today.')),
          throwsA(isA<T5UnavailableException>()));
    }, skip: skip);
  });

  group('LocalHumanizerFallbackModel (cloud -> T5 -> rules chain, local part)', () {
    final rules = LocalAlgorithmicHumanizerModel();
    const src = 'Furthermore, it is crucial to remember that this approach works well for most teams.';

    test('uses T5 when available', () async {
      final backend = ScriptedT5Backend(tok, (s) => s.replaceFirst('works well', 'works nicely'));
      final chain = LocalHumanizerFallbackModel(
        t5Provider: () async => OnDeviceT5HumanizerModel(tokenizer: tok, backend: backend),
        rules: rules,
      );
      final out = await chain.rewriteChunk(_ctx(src));
      expect(chain.lastStage, 't5');
      expect(out, contains('works nicely'));
    }, skip: skip);

    test('falls back to rules when T5 is not downloaded', () async {
      final chain = LocalHumanizerFallbackModel(t5Provider: () async => null, rules: rules);
      final out = await chain.rewriteChunk(_ctx(src));
      expect(chain.lastStage, 'rules');
      expect(out.trim(), isNotEmpty);
    });

    test('falls back to rules when T5 throws unavailable', () async {
      final chain = LocalHumanizerFallbackModel(
        t5Provider: () async => OnDeviceT5HumanizerModel(tokenizer: tok, backend: _ThrowingBackend()),
        rules: rules,
      );
      await chain.rewriteChunk(_ctx(src));
      expect(chain.lastStage, 'rules');
    }, skip: skip);

    test('falls back to rules when the provider itself throws', () async {
      final chain = LocalHumanizerFallbackModel(t5Provider: () async => throw StateError('boom'), rules: rules);
      await chain.rewriteChunk(_ctx(src));
      expect(chain.lastStage, 'rules');
    });
  });
}

class _LoopBackend implements T5Backend {
  @override
  Future<T5EncoderOutput> encode(List<int> inputIds) async =>
      T5EncoderOutput(hidden: Float32List(1), srcLen: inputIds.length, dModel: 1);

  @override
  Future<Float32List> nextTokenLogits(T5EncoderOutput encoder, List<int> decoderIds) async {
    final l = Float32List(300)..fillRange(0, 300, -5.0);
    l[100] = 9.0;
    l[200] = 8.0;
    l[201] = 7.0;
    return l;
  }

  @override
  void dispose() {}
}
