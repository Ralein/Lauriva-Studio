import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/forensic/humanizer/on_device_t5_humanizer_model.dart';
import 'package:lauriva/services/forensic/humanizer/t5_humanizer_registry.dart';
import 'package:lauriva/services/forensic/humanizer/t5_model_store.dart';

T5ModelFile _file(String name, List<int> bytes) =>
    T5ModelFile(name: name, sha256: sha256.convert(bytes).toString(), bytes: bytes.length);

void main() {
  late Directory tmp;
  final encBytes = List<int>.generate(5000, (i) => i % 251);
  final decBytes = List<int>.generate(7000, (i) => (i * 7) % 253);
  final vocabBytes = utf8.encode('#lauriva-spm-unigram v1\nfake');
  late T5ModelManifest manifest;
  late Map<String, List<int>> served;
  late int requests;

  http.Client client() => MockClient.streaming((request, _) async {
        requests++;
        final name = request.url.pathSegments.last;
        final body = served[name];
        if (body == null) return http.StreamedResponse(const Stream.empty(), 404);
        // Stream in small chunks to exercise the incremental hash.
        final chunks = <List<int>>[for (var i = 0; i < body.length; i += 1000) body.sublist(i, i + 1000 > body.length ? body.length : i + 1000)];
        return http.StreamedResponse(Stream.fromIterable(chunks), 200, contentLength: body.length);
      });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('t5store');
    manifest = T5ModelManifest(
      baseUrl: 'https://example.test/models/',
      encoder: _file('enc.onnx', encBytes),
      decoder: _file('dec.onnx', decBytes),
      vocab: _file('vocab.txt', vocabBytes),
    );
    served = {'enc.onnx': encBytes, 'dec.onnx': decBytes, 'vocab.txt': vocabBytes};
    requests = 0;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  T5ModelStore store({http.Client? c}) =>
      T5ModelStore(manifest: manifest, client: c ?? client(), directoryProvider: () async => tmp);

  test('downloads, verifies and reports ready; second call makes no requests', () async {
    final s = store();
    expect(await s.isReady(), isFalse);
    final progress = <double>[];
    expect(await s.ensureHumanizerModels(onProgress: progress.add), T5DeliveryStatus.ready);
    expect(await s.isReady(), isTrue);
    expect(requests, 3);
    expect(progress.last, 1.0);
    expect(progress, orderedEquals([...progress]..sort()), reason: 'progress is monotone');
    expect(File(await s.encoderPath() as String).readAsBytesSync(), encBytes);
    final before = requests;
    expect(await s.ensureHumanizerModels(), T5DeliveryStatus.ready);
    expect(requests, before);
  });

  test('a hash mismatch is rejected and leaves no file behind', () async {
    served['dec.onnx'] = List<int>.from(decBytes)..[10] ^= 0xFF;
    final s = store();
    expect(await s.ensureHumanizerModels(), T5DeliveryStatus.hashMismatch);
    expect(await s.decoderPath(), isNull);
    expect(tmp.listSync().where((e) => e.path.contains('dec.onnx')), isEmpty);
    expect(await s.isReady(), isFalse);
  });

  test('a short download is rejected', () async {
    served['enc.onnx'] = encBytes.sublist(0, 4000);
    expect(await store().ensureHumanizerModels(), T5DeliveryStatus.hashMismatch);
  });

  test('HTTP errors fail without partial state', () async {
    served.remove('vocab.txt');
    final s = store();
    expect(await s.ensureHumanizerModels(), T5DeliveryStatus.failed);
    expect(await s.isReady(), isFalse);
    // The two good files were kept; once the third is available it completes.
    served['vocab.txt'] = vocabBytes;
    requests = 0;
    expect(await s.ensureHumanizerModels(), T5DeliveryStatus.ready);
    expect(requests, 1, reason: 'only the missing file is fetched');
  });

  test('cancellation stops the download and cleans the temp file', () async {
    final s = store();
    final status = await s.ensureHumanizerModels(isCancelled: () => true);
    expect(status, T5DeliveryStatus.cancelled);
    expect(tmp.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    expect(await s.isReady(), isFalse);
  });

  test('tampering with a verified file invalidates it', () async {
    final s = store();
    await s.ensureHumanizerModels();
    File(await s.decoderPath() as String).writeAsBytesSync([1, 2, 3]);
    expect(await s.decoderPath(), isNull);
    expect(await s.isReady(), isFalse);
  });

  test('unavailable storage is reported, not thrown', () async {
    final s = T5ModelStore(manifest: manifest, client: client(), directoryProvider: () async => null);
    expect(await s.ensureHumanizerModels(), T5DeliveryStatus.storageUnavailable);
    expect(await s.isReady(), isFalse);
  });

  test('the shipped manifest has well-formed hashes and the last-position decoder', () {
    for (final f in T5ModelManifest.release.files) {
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(f.bytes, greaterThan(100000));
    }
    expect(T5ModelManifest.release.decoder.name, contains('_last'));
  });

  group('T5HumanizerRegistry', () {
    test('tryGet is null (and cheap) while the files are not downloaded', () async {
      final r = T5HumanizerRegistry.forTesting(store());
      expect(await r.tryGet(), isNull);
      expect(await r.tryGet(), isNull);
    });

    test('files present but ONNX Runtime unavailable -> null, remembered', () async {
      final s = store();
      await s.ensureHumanizerModels();
      final r = T5HumanizerRegistry.forTesting(s);
      // The fake vocab is not a valid tokenizer export, so loading fails; the
      // registry must swallow it and stay unavailable instead of throwing.
      expect(await r.tryGet(), isNull);
      expect(await r.tryGet(), isNull);
    });

    test('override is returned as-is', () async {
      final r = T5HumanizerRegistry.forTesting(store());
      expect(await r.tryGet(), isNull);
      r.overrideModel(null);
      expect(r.store, isNotNull);
    });
  });

  test('OnDeviceT5HumanizerModel reports stats type (smoke)', () {
    expect(T5RewriteStats().toString(), contains('chunks=0'));
  });
}
