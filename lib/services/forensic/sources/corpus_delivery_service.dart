import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'compact_corpus_index.dart';

/// On-demand delivery of the offline source corpus (`source_corpus_v2.bin`).
///
/// The 24 MB fingerprint index is not bundled in the app: it is downloaded once
/// on Wi-Fi and verified against a pinned SHA-256, then kept at
/// [CompactCorpusIndex.cachePath]. Until it lands, scans use the online
/// retrievers alone, and every scan after it lands also uses the offline index.
/// Publish the file from `tool/corpus/` to [defaultRemoteUrl] before shipping
/// (see tool/corpus/README.md).
class CorpusDeliveryService {
  static const String defaultRemoteUrl =
      'https://github.com/Ralein/Lauriva-Mobile/releases/download/source-corpus-v2/source_corpus_v2.bin';

  /// Integrity pins for [defaultRemoteUrl]; a download that differs is discarded.
  static const String defaultSha256 = 'e025a9e403e7be6d2fbe35d774a9ceef7fd50dc7f81ff5240215179ddf3bba56';
  static const int defaultSizeBytes = 25146470;

  /// Build id written beside the cache; equals `assets/source_corpus_v2.id`
  /// (the first 32 hex characters of the SHA-256), which `ensureReady` compares.
  static String get buildId => defaultSha256.substring(0, 32);

  /// Minimum gap between automatic attempts after a failure.
  static const Duration autoRetryBackoff = Duration(hours: 6);

  /// Limits for a dead connection: no response at all, or no bytes for this long mid-download.
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration stallTimeout = Duration(seconds: 30);

  static Future<bool>? _inFlight;
  static DateTime? _lastAttempt;

  /// Starts the download in the background when the corpus is missing, on an
  /// unmetered network only, at most once per [autoRetryBackoff]. Returns
  /// immediately and is safe to call on every scan.
  static void ensureInBackground({http.Client? client}) {
    // Never hit the network from unit tests.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_inFlight != null) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < autoRetryBackoff) return;
    _inFlight = () async {
      // Yield so `_inFlight` is assigned before the `finally` below can clear it.
      await Future<void>.delayed(Duration.zero);
      try {
        if (CompactCorpusIndex.current != null) return true;
        if (!await isUnmeteredNetwork()) return false;
        // Back off only after a failure, so a purged cache is re-fetched on the next launch.
        final ok = await download(client: client);
        if (!ok) _lastAttempt = DateTime.now();
        return ok;
      } catch (_) {
        _lastAttempt = DateTime.now();
        return false;
      } finally {
        _inFlight = null;
      }
    }();
  }

  /// Downloads, verifies and installs the corpus, then opens it. Returns false
  /// (leaving no partial file) on any failure.
  static Future<bool> download({
    http.Client? client,
    String? url,
    String? expectedSha256,
    int? expectedSize,
    void Function(double progress)? onProgress,
  }) async {
    final httpClient = client ?? http.Client();
    final target = File(CompactCorpusIndex.cachePath);
    final tmp = File('${target.path}.tmp');
    IOSink? out;
    try {
      final response = await httpClient
          .send(http.Request('GET', Uri.parse(url ?? defaultRemoteUrl)))
          .timeout(connectTimeout);
      if (response.statusCode != 200) return false;

      final total = response.contentLength ?? 0;
      var received = 0;
      final digestSink = _DigestSink();
      final hash = sha256.startChunkedConversion(digestSink);
      out = tmp.openWrite();
      // Hash while streaming: reading 24 MB back into memory is avoidable. The per-chunk
      // timeout stops a stalled connection from holding the download slot forever.
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        out.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await out.flush();
      await out.close();
      out = null;
      hash.close();

      final pin = (expectedSha256 ?? (url == null ? defaultSha256 : null))?.toLowerCase();
      final size = expectedSize ?? (url == null ? defaultSizeBytes : null);
      if ((pin != null && digestSink.value.toString() != pin) || (size != null && received != size)) {
        await _deleteQuietly(tmp);
        return false;
      }

      // rename() replaces atomically on POSIX; deleting first would open a window in which
      // another isolate sees no corpus and caches that.
      await tmp.rename(target.path);
      final id = (pin ?? digestSink.value.toString()).substring(0, 32);
      await File('${target.path}.id').writeAsString(id, flush: true);
      onProgress?.call(1.0);
      // Open it now (cheap: the id sidecar matches the bundled id asset).
      await CompactCorpusIndex.ensureReady();
      return true;
    } catch (e) {
      debugPrint('[CorpusDelivery] download failed: $e');
      try {
        await out?.close();
      } catch (_) {}
      await _deleteQuietly(tmp);
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Wi-Fi/Ethernet heuristic (no cellular data for a 24 MB download): an up
  /// interface named wlan*/wifi*/eth*/en0/en1 with a non-link-local address.
  /// Unknown or failing detection means "do not auto-download".
  static Future<bool> isUnmeteredNetwork() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
      final unmetered = RegExp(r'^(wlan|wifi|eth|en0$|en1$)', caseSensitive: false);
      return interfaces.any((i) => unmetered.hasMatch(i.name) && i.addresses.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
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
