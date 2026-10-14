import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_chunk_engine.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_model.dart';
import 'package:lauriva/services/llm_service.dart';

/// Stands in for a cloud model whose every call fails (offline / quota).
class _FailingCloud implements HumanizerModel {
  int calls = 0;
  @override
  String get name => 'failing cloud';
  @override
  int get maxContextTokens => 4096;
  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    calls++;
    throw StateError('cloud down');
  }
}

/// Stands in for the on-device T5: a safe, same-length edit.
class _FakeOnDevice implements HumanizerModel {
  int calls = 0;
  @override
  String get name => 'fake on-device';
  @override
  int get maxContextTokens => 256;
  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    calls++;
    return context.targetChunk.replaceFirst('house', 'cottage');
  }
}

const _provider = LlmProvider(
  id: 'test',
  name: 'Test',
  tag: 'test',
  baseUrl: 'https://test',
  keyPortalUrl: 'https://test',
  keyHint: '',
  description: '',
  defaultModel: 'test',
  requiresKey: false,
  curatedModels: [],
);

const _input = 'The old house stood on a hill beside the river and watched the village below for many long years. '
    'Children played near its gate every summer afternoon, and nobody ever remembered who had built it.';

Future<HumanizerResult> _run(HumanizerModel cloud, Future<HumanizerModel?> Function() t5) {
  return HumanizerChunkEngine(onDeviceT5Provider: t5).processDocument(
    rawText: _input,
    tone: WritingToneProfile.professional,
    llmService: LlmService(),
    activeProvider: _provider,
    activeApiKey: '',
    activeModel: 'test',
    customModel: cloud,
  );
}

void main() {
  test('cloud failure falls back to the on-device T5 when it is available', () async {
    final cloud = _FailingCloud();
    final t5 = _FakeOnDevice();
    final result = await _run(cloud, () async => t5);
    expect(cloud.calls, greaterThan(0));
    expect(t5.calls, greaterThan(0), reason: 'T5 stage must run after the cloud fails');
    expect(result.humanizedText, contains('cottage'));
  });

  test('cloud failure with no T5 downloaded falls back to the rule engine (unchanged behaviour)', () async {
    final cloud = _FailingCloud();
    final result = await _run(cloud, () async => null);
    expect(result.humanizedText.trim(), isNotEmpty);
    expect(result.humanizedText, isNot(contains('cottage')));
  });

  test('a T5 that throws falls through to the rule engine', () async {
    final cloud = _FailingCloud();
    final result = await _run(cloud, () async => throw StateError('ort exploded'));
    expect(result.humanizedText.trim(), isNotEmpty);
  });

  test('default provider (registry) yields null in unit tests and does not break the chain', () async {
    final result = await HumanizerChunkEngine().processDocument(
      rawText: _input,
      tone: WritingToneProfile.professional,
      llmService: LlmService(),
      activeProvider: _provider,
      activeApiKey: '',
      activeModel: 'test',
      customModel: _FailingCloud(),
    );
    expect(result.humanizedText.trim(), isNotEmpty);
    expect(File('pubspec.yaml').existsSync(), isTrue);
  });
}
