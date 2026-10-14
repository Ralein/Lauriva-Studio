import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One downloadable humanizer model file.
class T5ModelFile {
  final String name;
  final String sha256;
  final int bytes;

  const T5ModelFile({required this.name, required this.sha256, required this.bytes});
}

/// The files the on-device T5 humanizer needs and where to get them.
///
/// [baseUrl] is a PLACEHOLDER: upload the files named below (see
/// tool/humanizer_release/README.md) to that location, or override it.
class T5ModelManifest {
  static const String defaultBaseUrl = 'https://github.com/Ralein/Lauriva-Mobile/releases/download/humanizer-v6.1/';

  final String baseUrl;
  final T5ModelFile encoder;
  final T5ModelFile decoder;
  final T5ModelFile vocab;

  const T5ModelManifest({
    this.baseUrl = defaultBaseUrl,
    required this.encoder,
    required this.decoder,
    required this.vocab,
  });

  List<T5ModelFile> get files => [encoder, decoder, vocab];

  /// The shipped release (SHA-256 of the files in tool/checkpoints/lauvira_humanize_v6 and
  /// tool/humanizer_release; regenerate with tool/humanizer_release/print_t5_manifest.py).
  static const T5ModelManifest release = T5ModelManifest(
    encoder: T5ModelFile(
      name: 'lauvira_humanize_v6_encoder_int8_pc.onnx',
      sha256: 'a042a1cbb6632837977e3c6e00451cc925fc097db9c9634456c09845286508f8',
      bytes: 35675398,
    ),
    decoder: T5ModelFile(
      name: 'lauvira_humanize_v6_decoder_int8_pc_last.onnx',
      sha256: '46698444feb266adb6627ebad38606138cfa1c5f9d255f0a11cb7c74e8774b4e',
      bytes: 58813098,
    ),
    vocab: T5ModelFile(
      name: 't5_spm_unigram.txt',
      sha256: '0c9dc631da71ec58ef7e49fcb31e82858c7f91ac3ddfec8e5d59682b68d1a70c',
      bytes: 1018887,
    ),
  );
}

enum T5DeliveryStatus { ready, failed, hashMismatch, cancelled, storageUnavailable }

/// Downloads and verifies the T5 humanizer files into app-support storage.
///
/// It never downloads on its own: the caller invokes [ensureHumanizerModels]
/// (for example after checking that the device is on an unmetered network).
class T5ModelStore {
  final T5ModelManifest manifest;
  final http.Client _client;
  final Future<Directory?> Function() _directoryProvider;
  Directory? _dir;

  T5ModelStore({
    this.manifest = T5ModelManifest.release,
    http.Client? client,
    Future<Directory?> Function()? directoryProvider,
  })  : _client = client ?? http.Client(),
        _directoryProvider = directoryProvider ?? _defaultDirectory;

  static Future<Directory?> _defaultDirectory() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/humanizer_models');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null; // e.g. unit tests without the path_provider plugin
    }
  }

  Future<Directory?> _directory() async => _dir ??= await _directoryProvider();

  Future<File?> _file(T5ModelFile f) async {
    final dir = await _directory();
    return dir == null ? null : File('${dir.path}/${f.name}');
  }

  /// Absolute path of [f] if it is present and was verified, else null.
  Future<String?> verifiedPath(T5ModelFile f) async {
    try {
      final file = await _file(f);
      if (file == null || !await file.exists() || await file.length() != f.bytes) return null;
      final marker = File('${file.path}.sha256');
      if (!await marker.exists()) return null;
      return (await marker.readAsString()).trim() == f.sha256.toLowerCase() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isReady() async {
    for (final f in manifest.files) {
      if (await verifiedPath(f) == null) return false;
    }
    return true;
  }

  Future<String?> encoderPath() => verifiedPath(manifest.encoder);
  Future<String?> decoderPath() => verifiedPath(manifest.decoder);
  Future<String?> vocabPath() => verifiedPath(manifest.vocab);

  /// Downloads whatever is missing, verifying each file's SHA-256 while it
  /// streams (no whole-file buffering). Safe to call repeatedly.
  Future<T5DeliveryStatus> ensureHumanizerModels({
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dir = await _directory();
    if (dir == null) return T5DeliveryStatus.storageUnavailable;
    final total = manifest.files.fold<int>(0, (a, f) => a + f.bytes);
    var done = 0;
    for (final f in manifest.files) {
      if (await verifiedPath(f) != null) {
        done += f.bytes;
        onProgress?.call(done / total);
        continue;
      }
      final status = await _download(f, dir, (received) => onProgress?.call((done + received) / total), isCancelled);
      if (status != T5DeliveryStatus.ready) return status;
      done += f.bytes;
    }
    onProgress?.call(1.0);
    return T5DeliveryStatus.ready;
  }

  Future<T5DeliveryStatus> _download(
    T5ModelFile f,
    Directory dir,
    void Function(int received) onBytes,
    bool Function()? isCancelled,
  ) async {
    final target = File('${dir.path}/${f.name}');
    final tmp = File('${target.path}.tmp');
    IOSink? sink;
    try {
      final response = await _client.send(http.Request('GET', Uri.parse('${manifest.baseUrl}${f.name}')));
      if (response.statusCode != 200) return T5DeliveryStatus.failed;
      sink = tmp.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) {
          await sink.close();
          if (await tmp.exists()) await tmp.delete();
          return T5DeliveryStatus.cancelled;
        }
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onBytes(received);
      }
      hasher.close();
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != f.bytes || digestSink.digest.toString() != f.sha256.toLowerCase()) {
        if (await tmp.exists()) await tmp.delete();
        return T5DeliveryStatus.hashMismatch;
      }
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      await File('${target.path}.sha256').writeAsString(f.sha256.toLowerCase());
      return T5DeliveryStatus.ready;
    } catch (e) {
      debugPrint('[T5ModelStore] download of ${f.name} failed: $e');
      try {
        await sink?.close();
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return T5DeliveryStatus.failed;
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
