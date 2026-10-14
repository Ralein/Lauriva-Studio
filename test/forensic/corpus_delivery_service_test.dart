import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/forensic/sources/compact_corpus_index.dart';
import 'package:lauriva/services/forensic/sources/corpus_delivery_service.dart';

void main() {
  final cache = File(CompactCorpusIndex.cachePath);
  final side = File('${CompactCorpusIndex.cachePath}.id');
  final tmp = File('${CompactCorpusIndex.cachePath}.tmp');

  void clean() {
    for (final f in [cache, side, tmp]) {
      if (f.existsSync()) f.deleteSync();
    }
    CompactCorpusIndex.install(null);
  }

  setUp(clean);
  tearDown(clean);

  test('pinned build id matches the bundled id asset', () {
    expect(CorpusDeliveryService.buildId, File(CompactCorpusIndex.idAssetPath).readAsStringSync().trim());
  });

  test('pinned hash and size match the corpus file when it is present locally', () {
    final bin = File(CompactCorpusIndex.assetPath);
    if (!bin.existsSync()) return; // already moved out of the repo
    expect(bin.lengthSync(), CorpusDeliveryService.defaultSizeBytes);
    expect(sha256.convert(bin.readAsBytesSync()).toString(), CorpusDeliveryService.defaultSha256);
  });

  test('a download that fails the hash check is discarded and leaves no files', () async {
    final client = MockClient((_) async => http.Response('not the corpus', 200));
    final ok = await CorpusDeliveryService.download(client: client, url: 'https://x.test/c.bin', expectedSha256: 'a' * 64);
    expect(ok, isFalse);
    expect(cache.existsSync(), isFalse);
    expect(tmp.existsSync(), isFalse);
  });

  test('HTTP errors and network failures return false', () async {
    expect(await CorpusDeliveryService.download(client: MockClient((_) async => http.Response('', 404))), isFalse);
    expect(await CorpusDeliveryService.download(client: MockClient((_) async => throw http.ClientException('offline'))), isFalse);
    expect(cache.existsSync(), isFalse);
  });

  test('a verified download is installed with its build id sidecar', () async {
    final bytes = utf8.encode('fake corpus payload for install test');
    final digest = sha256.convert(bytes).toString();
    final client = MockClient((_) async => http.Response.bytes(bytes, 200));
    final progress = <double>[];
    final ok = await CorpusDeliveryService.download(
      client: client,
      url: 'https://x.test/c.bin',
      expectedSha256: digest,
      expectedSize: bytes.length,
      onProgress: progress.add,
    );
    expect(ok, isTrue);
    expect(cache.readAsBytesSync(), bytes);
    expect(side.readAsStringSync(), digest.substring(0, 32));
    expect(progress.last, 1.0);
  });

  test('ensureInBackground never touches the network under flutter test', () {
    CorpusDeliveryService.ensureInBackground(client: MockClient((_) async => throw StateError('network used')));
  });
}
