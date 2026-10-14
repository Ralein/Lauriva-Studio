import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

enum ModelDeliveryStatus {
  notDownloaded,
  downloading,
  ready,
  failed,
}

/// Manages dynamic on-demand acquisition, caching, and integrity verification
/// of heavy transformer neural weights without bloating initial APK download size.
class ModelDeliveryService {
  static const String defaultModelVersion = 'omni_p3_int8';
  static const String defaultModelFileName = 'lauvira_omni_p3_int8.onnx';

  /// Release asset for the detector. Upload `tool/release/omni_p3_int8/lauvira_omni_p3_int8.onnx`
  /// to this release (see tool/release/omni_p3_int8/README.md) before shipping.
  static const String defaultRemoteUrl =
      'https://github.com/Ralein/Lauriva-Mobile/releases/download/omni-p3-int8/lauvira_omni_p3_int8.onnx';

  /// Pinned integrity data for [defaultRemoteUrl]. A download whose SHA-256 or size
  /// differs is discarded, so a swapped or truncated release asset can never be loaded.
  static const String defaultModelSha256 =
      'bb47f5dd63bc28885b7395885c8086702d60567a6e9b5740a74122efb31c3d5f';

  /// Minimum gap between automatic download attempts after a failure.
  static const Duration autoRetryBackoff = Duration(hours: 6);

  final http.Client _httpClient;
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<ModelDeliveryStatus> status =
      ValueNotifier<ModelDeliveryStatus>(ModelDeliveryStatus.notDownloaded);

  bool _isCancelled = false;

  ModelDeliveryService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Returns the persistent directory where neural models are cached.
  Future<Directory?> get _modelsDir async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${baseDir.path}/neural_models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      return modelsDir;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the destination File for a given model version.
  Future<File?> getModelFile({String modelVersion = defaultModelVersion}) async {
    try {
      final dir = await _modelsDir;
      if (dir == null) return null;
      // Matches the bundled asset name so extractBundledModel can find it.
      return File('${dir.path}/lauvira_$modelVersion.onnx');
    } catch (_) {
      return null;
    }
  }

  /// Extracts the model file from Flutter app assets to local filesystem if bundled.
  Future<bool> extractBundledModel({
    String modelVersion = defaultModelVersion,
  }) async {
    try {
      final file = await getModelFile(modelVersion: modelVersion);
      if (file == null) return false;
      if (await file.exists() && (await file.length()) > 1024 * 1024) {
        status.value = ModelDeliveryStatus.ready;
        return true;
      }

      final filename = file.uri.pathSegments.last;
      ByteData byteData;
      bool isCompressed = false;
      // The detector ships bundled as a raw .onnx: the APK already deflates it, and a .gz
      // would need ~2x the memory (compressed + decoded) on first launch.
      try {
        byteData = await rootBundle.load('assets/models/$filename');
      } catch (_) {
        try {
          byteData = await rootBundle.load('assets/models/$filename.gz');
          isCompressed = true;
        } catch (_) {
          // Nothing bundled: fall back to the on-demand download (see ensureInBackground).
          return false;
        }
      }

      final rawBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final Uint8List finalBytes = isCompressed ? Uint8List.fromList(gzip.decode(rawBytes)) : rawBytes;

      if (modelVersion == defaultModelVersion &&
          await _sha256Hex(finalBytes) != defaultModelSha256) {
        // A corrupted/foreign bundled asset must never be loaded.
        return false;
      }
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(finalBytes, flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);

      if (await file.exists() && (await file.length()) > 1024 * 1024) {
        status.value = ModelDeliveryStatus.ready;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Ensures model weights are accessible on local storage.
  /// 1. Checks if already present on disk.
  /// 2. If bundled in Flutter assets, extracts to disk (instant offline).
  /// 3. Otherwise downloads over network if URL provided or default remote.
  Future<bool> ensureModelAvailable({
    String modelVersion = defaultModelVersion,
    String? overrideUrl,
  }) async {
    if (await isModelReady(modelVersion: modelVersion)) {
      return true;
    }
    final extracted = await extractBundledModel(modelVersion: modelVersion);
    if (extracted) {
      status.value = ModelDeliveryStatus.ready;
      return true;
    }
    return await downloadModel(
      modelVersion: modelVersion,
      overrideUrl: overrideUrl,
      expectedSha256: overrideUrl == null && modelVersion == defaultModelVersion ? defaultModelSha256 : null,
    );
  }

  /// SHA-256 of [bytes] in 1 MiB slices, yielding to the event loop between slices so
  /// hashing a 170 MB model on first launch does not freeze the UI.
  Future<String> _sha256Hex(Uint8List bytes) async {
    final out = _DigestSink();
    final conv = sha256.startChunkedConversion(out);
    const slice = 1 << 20;
    for (var i = 0; i < bytes.length; i += slice) {
      conv.add(Uint8List.sublistView(bytes, i, i + slice > bytes.length ? bytes.length : i + slice));
      await Future<void>.delayed(Duration.zero);
    }
    conv.close();
    return out.value.toString();
  }

  DateTime? _lastAutoAttempt;
  Future<bool>? _autoDownload;

  /// Starts the detector download in the background when it is missing, on an
  /// unmetered network only, at most once per [autoRetryBackoff] after a failure.
  /// Returns immediately; scans keep using the statistical engine until it lands.
  /// Safe to call on every scan.
  void ensureInBackground({String modelVersion = defaultModelVersion}) {
    // Never hit the network from unit tests (a dev machine would look "unmetered").
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_autoDownload != null || status.value == ModelDeliveryStatus.downloading) return;
    final last = _lastAutoAttempt;
    if (last != null && DateTime.now().difference(last) < autoRetryBackoff) return;
    _autoDownload = () async {
      try {
        if (await isModelReady(modelVersion: modelVersion)) return true;
        if (!await isUnmeteredNetwork()) return false;
        _lastAutoAttempt = DateTime.now();
        return await ensureModelAvailable(modelVersion: modelVersion);
      } catch (_) {
        _lastAutoAttempt = DateTime.now();
        return false;
      } finally {
        _autoDownload = null;
      }
    }();
  }

  /// Heuristic for Wi-Fi/Ethernet (no cellular data for a 170 MB download):
  /// an up interface named wlan*/wifi*/eth*/en0/en1 with a non-link-local address.
  /// Unknown or failing detection means "do not auto-download".
  @visibleForTesting
  Future<bool> isUnmeteredNetwork() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
      final unmetered = RegExp(r'^(wlan|wifi|eth|en0$|en1$)', caseSensitive: false);
      return interfaces.any((i) => unmetered.hasMatch(i.name) && i.addresses.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Checks if the model weights are already downloaded and present on the filesystem.
  Future<bool> isModelReady({String modelVersion = defaultModelVersion}) async {
    try {
      final file = await getModelFile(modelVersion: modelVersion);
      if (file != null && await file.exists()) {
        final length = await file.length();
        if (length > 1024 * 1024) {
          // Model file exists and is substantial (>1MB)
          status.value = ModelDeliveryStatus.ready;
          return true;
        }
      }
      status.value = ModelDeliveryStatus.notDownloaded;
      return false;
    } catch (_) {
      status.value = ModelDeliveryStatus.notDownloaded;
      return false;
    }
  }

  /// Returns the absolute path to the local model file if present, or null.
  Future<String?> getModelLocalPath({
    String modelVersion = defaultModelVersion,
  }) async {
    try {
      final file = await getModelFile(modelVersion: modelVersion);
      if (file != null && await file.exists()) {
        return file.path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the neural model weights over HTTP with chunked streaming progress.
  Future<bool> downloadModel({
    String modelVersion = defaultModelVersion,
    String? overrideUrl,
    String? expectedSha256,
  }) async {
    if (status.value == ModelDeliveryStatus.downloading) {
      return false;
    }

    _isCancelled = false;
    status.value = ModelDeliveryStatus.downloading;
    downloadProgress.value = 0.0;

    final targetFile = await getModelFile(modelVersion: modelVersion);
    if (targetFile == null) {
      status.value = ModelDeliveryStatus.failed;
      return false;
    }
    final tempFile = File('${targetFile.path}.tmp');

    try {
      final url = Uri.parse(overrideUrl ?? defaultRemoteUrl);
      final request = http.Request('GET', url);
      final response = await _httpClient.send(request);

      if (response.statusCode != 200) {
        status.value = ModelDeliveryStatus.failed;
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      int bytesReceived = 0;
      final sink = tempFile.openWrite();
      // Hash while streaming: reading a 170 MB file back into memory would risk OOM on low-RAM phones.
      final digestSink = _DigestSink();
      final hashSink = sha256.startChunkedConversion(digestSink);

      await for (final chunk in response.stream) {
        if (_isCancelled) {
          await sink.close();
          if (await tempFile.exists()) await tempFile.delete();
          status.value = ModelDeliveryStatus.notDownloaded;
          return false;
        }

        sink.add(chunk);
        hashSink.add(chunk);
        bytesReceived += chunk.length;

        if (contentLength > 0) {
          downloadProgress.value =
              (bytesReceived / contentLength).clamp(0.0, 1.0);
        }
      }

      await sink.flush();
      await sink.close();
      hashSink.close();

      // SHA-256 verification (streamed above)
      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final actualSha256 = digestSink.value.toString();
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          if (await tempFile.exists()) await tempFile.delete();
          status.value = ModelDeliveryStatus.failed;
          return false;
        }
      }

      // Atomic rename
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      status.value = ModelDeliveryStatus.ready;
      downloadProgress.value = 1.0;
      return true;
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      status.value = ModelDeliveryStatus.failed;
      return false;
    }
  }

  /// Cancels an active model download.
  void cancelDownload() {
    _isCancelled = true;
  }

  /// Deletes the local neural model file to reclaim storage if needed.
  Future<bool> deleteModel({String modelVersion = defaultModelVersion}) async {
    try {
      final file = await getModelFile(modelVersion: modelVersion);
      if (file != null && await file.exists()) {
        await file.delete();
        status.value = ModelDeliveryStatus.notDownloaded;
        downloadProgress.value = 0.0;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns size of the downloaded model in bytes (0 if not present).
  Future<int> getDownloadedModelSize({
    String modelVersion = defaultModelVersion,
  }) async {
    try {
      final file = await getModelFile(modelVersion: modelVersion);
      if (file != null && await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  void dispose() {
    downloadProgress.dispose();
    status.dispose();
  }
}

/// Captures the single digest emitted by a chunked hash conversion.
class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
