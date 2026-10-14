// Lauriva Reach: the app's own keyless web-reading layer (a Dart take on the
// "give the agent internet access" idea, scoped to what a phone can do safely).
//
// This file is the shared contract. Implementations live beside it:
//  - `reach_page_reader.dart`  [ReachPageReader], the production [PageReader]
//  - `url_guard.dart`          [UrlGuard], the SSRF / scheme / size policy
//  - `reach_channels.dart`     the individual backends tried in order
// Consumers (e.g. the source-page enricher) depend only on this file.

/// Plain text of one web page, as returned by a reach backend.
class ReachPage {
  /// The URL that was requested (normalised).
  final String url;

  /// Page title, or empty when the backend did not provide one.
  final String title;

  /// Readable text (markdown-ish is fine), already length-capped.
  final String text;

  /// Id of the backend that produced it (e.g. `jina`, `exa`, `direct`).
  final String via;

  const ReachPage({required this.url, required this.title, required this.text, required this.via});
}

/// Health of one backend as seen from this device right now.
class ChannelHealth {
  final String channelId;
  final bool ok;
  final Duration latency;

  /// Short reason when not [ok] (HTTP status, "timeout", "blocked", ...).
  final String? detail;

  const ChannelHealth({required this.channelId, required this.ok, required this.latency, this.detail});
}

/// Reads public web pages as text. Implementations must never throw: a failure
/// is `null` (or absent from the map) and the caller keeps what it already has.
abstract class PageReader {
  /// Reads one page, trying backends in order. `null` when every backend failed
  /// or the URL was rejected by the safety policy.
  Future<ReachPage?> read(String url, {int maxChars = 60000});

  /// Reads several pages concurrently (bounded) within one overall [deadline].
  /// The result maps each *requested* URL to its page; failures and anything
  /// that missed the deadline are simply absent.
  Future<Map<String, ReachPage>> readMany(
    List<String> urls, {
    int maxChars = 60000,
    Duration deadline = const Duration(seconds: 8),
    int concurrency = 3,
  });

  /// Probes every backend with a tiny public page. For diagnostics and tests;
  /// there is deliberately no UI for it.
  Future<List<ChannelHealth>> doctor();
}
