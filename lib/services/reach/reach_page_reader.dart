import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../circuit_breaker.dart';
import 'reach_channels.dart';
import 'reach_models.dart';
import 'url_guard.dart';

/// Production [PageReader]: validates the URL, then tries jina -> exa -> direct
/// and returns the first substantial result. Never throws.
///
/// Each channel sits behind its own [CircuitBreaker] (3 failures, 2 min
/// cooldown, as in the online source retrievers), and successful reads are
/// kept in a small in-memory LRU cache with a TTL.
class ReachPageReader implements PageReader {
  /// Pages shorter than this are treated as "this channel got nothing useful".
  static const int minUsefulChars = 200;

  final List<ReachChannel> channels;
  final int cacheCapacity;
  final Duration cacheTtl;
  final DateTime Function() _now;
  final Map<String, CircuitBreaker> _breakers = {};
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();

  ReachPageReader({
    http.Client? client,
    List<ReachChannel>? channels,
    this.cacheCapacity = 64,
    this.cacheTtl = const Duration(minutes: 30),
    DateTime Function()? now,
  })  : channels = channels ?? _defaultChannels(client ?? http.Client()),
        _now = now ?? DateTime.now {
    for (final channel in this.channels) {
      _breakers[channel.id] = CircuitBreaker(
        name: 'reach_${channel.id}',
        failureThreshold: 3,
        cooldownDuration: const Duration(minutes: 2),
      );
    }
  }

  static List<ReachChannel> _defaultChannels(http.Client client) => [
        JinaReaderChannel(client),
        ExaFetchChannel(client),
        DirectChannel(client),
      ];

  @override
  Future<ReachPage?> read(String url, {int maxChars = 60000}) async {
    try {
      final uri = UrlGuard.parse(url);
      if (uri == null) return null;
      return await _readUri(uri, maxChars);
    } catch (e) {
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
      debugPrint('[Reach] read failed: $e');
      return null;
    }
  }

  Future<ReachPage?> _readUri(Uri uri, int maxChars) async {
    final normalized = uri.toString();
    final key = sha256.convert(utf8.encode(normalized)).toString();

    final cached = _cacheGet(key);
    if (cached != null) return _capped(cached, maxChars);

    for (final channel in channels) {
      final breaker = _breakers[channel.id]!;
      if (breaker.isOpen) continue;
      try {
        final page = await breaker.execute(() async {
          final result = await channel.read(uri, maxChars: maxChars).timeout(channel.timeout);
          if (result == null) throw ReachChannelException('${channel.id} returned nothing');
          return result;
        });
        final text = capReachText(page.text.trim(), maxChars);
        if (text.length < minUsefulChars) continue;
        final result = ReachPage(url: normalized, title: page.title, text: text, via: channel.id);
        _cachePut(key, result);
        return result;
      } catch (e) {
        if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
        debugPrint('[Reach:${channel.id}] failed: $e');
      }
    }
    return null;
  }

  ReachPage _capped(ReachPage page, int maxChars) => page.text.length <= maxChars
      ? page
      : ReachPage(
          url: page.url,
          title: page.title,
          text: capReachText(page.text, maxChars),
          via: page.via,
        );

  ReachPage? _cacheGet(String key) {
    final entry = _cache.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.storedAt) > cacheTtl) return null;
    _cache[key] = entry; // re-insert as most recently used
    return entry.page;
  }

  void _cachePut(String key, ReachPage page) {
    _cache.remove(key);
    _cache[key] = _CacheEntry(page, _now());
    while (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
  }

  @override
  Future<Map<String, ReachPage>> readMany(
    List<String> urls, {
    int maxChars = 60000,
    Duration deadline = const Duration(seconds: 8),
    int concurrency = 3,
  }) async {
    try {
      // Identical (after normalisation) URLs are fetched once.
      final queue = Queue<String>();
      final requestedKeys = <String, String>{}; // requested string -> normalised
      for (final url in urls) {
        final normalized = UrlGuard.normalize(url);
        if (normalized == null) continue;
        requestedKeys[url] = normalized;
      }
      queue.addAll(requestedKeys.values.toSet());

      final byUrl = <String, ReachPage>{};
      var closed = false;

      Future<void> worker() async {
        while (!closed && queue.isNotEmpty) {
          final next = queue.removeFirst();
          final page = await read(next, maxChars: maxChars);
          if (closed) return;
          if (page != null) byUrl[next] = page;
        }
      }

      final workers = List.generate(
        concurrency.clamp(1, 16),
        (_) => worker(),
      );
      await Future.wait(workers).timeout(deadline, onTimeout: () => const []);
      closed = true;

      final snapshot = Map<String, ReachPage>.of(byUrl);
      return {
        for (final entry in requestedKeys.entries)
          if (snapshot[entry.value] != null) entry.key: snapshot[entry.value]!,
      };
    } catch (e) {
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
      debugPrint('[Reach] readMany failed: $e');
      return const {};
    }
  }

  @override
  Future<List<ChannelHealth>> doctor() async {
    final probe = Uri.parse('https://example.com/');
    final report = <ChannelHealth>[];
    for (final channel in channels) {
      final stopwatch = Stopwatch()..start();
      try {
        final page = await channel.read(probe, maxChars: 2000).timeout(channel.timeout);
        stopwatch.stop();
        final ok = page != null && page.text.trim().isNotEmpty;
        report.add(ChannelHealth(
          channelId: channel.id,
          ok: ok,
          latency: stopwatch.elapsed,
          detail: ok ? null : 'empty',
        ));
      } on TimeoutException {
        stopwatch.stop();
        report.add(ChannelHealth(
          channelId: channel.id,
          ok: false,
          latency: stopwatch.elapsed,
          detail: 'timeout',
        ));
      } catch (e) {
        if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
        stopwatch.stop();
        report.add(ChannelHealth(
          channelId: channel.id,
          ok: false,
          latency: stopwatch.elapsed,
          detail: e is ReachChannelException ? e.message : e.runtimeType.toString(),
        ));
      }
    }
    return report;
  }
}

class _CacheEntry {
  final ReachPage page;
  final DateTime storedAt;
  const _CacheEntry(this.page, this.storedAt);
}
