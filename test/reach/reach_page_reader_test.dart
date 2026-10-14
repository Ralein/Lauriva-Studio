import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/reach/reach_channels.dart';
import 'package:lauriva/services/reach/reach_page_reader.dart';
import 'package:lauriva/services/reach/url_guard.dart';

final String _body = List.filled(30, 'Photosynthesis converts light into chemical energy.').join(' ');

String _jinaBody({String title = 'Photosynthesis - Wikipedia'}) =>
    'Title: $title\n\nURL Source: https://en.wikipedia.org/wiki/Photosynthesis\n\n'
    'Published Time: 2024-01-01\n\nMarkdown Content:\n# $title\n\n$_body';

String _exaSse({String title = 'Photosynthesis', String? text}) {
  final payload = {
    'jsonrpc': '2.0',
    'id': 1,
    'result': {
      'content': [
        {'type': 'text', 'text': text ?? '# $title\nURL: https://example.org/p\n\n$_body'},
      ],
    },
  };
  return 'event: message\ndata: ${jsonEncode(payload)}\n\n';
}

http.Response _utf8Response(String body, int status, {Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(body), status, headers: headers ?? const {});

http.Response _html(String html) => _utf8Response(html, 200,
    headers: {'content-type': 'text/html; charset=utf-8'});

final String _page =
    '<html><head><title>Hello &amp; Welcome</title><style>p{color:red}</style></head>'
    '<body><nav>MENU</nav><h1>Heading</h1><p>$_body</p><script>var x=1;</script>'
    '<footer>FOOT</footer></body></html>';

void main() {
  final originalResolver = UrlGuard.resolver;
  setUp(() => UrlGuard.resolver = (_) async => [InternetAddress('93.184.216.34')]);
  tearDown(() => UrlGuard.resolver = originalResolver);

  group('JinaReaderChannel', () {
    test('parses title and markdown body, sends only the URL', () async {
      late http.Request seen;
      final channel = JinaReaderChannel(MockClient((req) async {
        seen = req;
        return _utf8Response(_jinaBody(), 200);
      }));
      final page = await channel.read(Uri.parse('https://en.wikipedia.org/wiki/Photosynthesis'),
          maxChars: 60000);
      expect(seen.url.toString(),
          'https://r.jina.ai/https://en.wikipedia.org/wiki/Photosynthesis');
      expect(seen.headers['Accept'], 'text/plain');
      expect(seen.headers.containsKey('cookie'), isFalse);
      expect(page!.title, 'Photosynthesis - Wikipedia');
      expect(page.text, startsWith('# Photosynthesis - Wikipedia'));
      expect(page.text, isNot(contains('URL Source')));
      expect(page.via, 'jina');
    });

    test('caps text and fails on HTTP errors or empty content', () async {
      final ok = JinaReaderChannel(MockClient((_) async => _utf8Response(_jinaBody(), 200)));
      final page = await ok.read(Uri.parse('https://example.com/'), maxChars: 100);
      expect(page!.text.length, 100);

      final err = JinaReaderChannel(MockClient((_) async => _utf8Response('nope', 429)));
      expect(() => err.read(Uri.parse('https://example.com/'), maxChars: 100),
          throwsA(isA<ReachChannelException>()));
      final empty = JinaReaderChannel(
          MockClient((_) async => _utf8Response('Title: x\n\nMarkdown Content:\n   ', 200)));
      expect(() => empty.read(Uri.parse('https://example.com/'), maxChars: 100),
          throwsA(isA<ReachChannelException>()));
    });
  });

  group('ExaFetchChannel', () {
    test('parses the SSE reply and posts the JSON-RPC call', () async {
      late http.Request seen;
      final channel = ExaFetchChannel(MockClient((req) async {
        seen = req;
        return _utf8Response(_exaSse(), 200);
      }));
      final page = await channel.read(Uri.parse('https://example.org/p'), maxChars: 5000);
      final sent = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(seen.url.toString(), 'https://mcp.exa.ai/mcp');
      expect(seen.headers['Accept'], 'application/json, text/event-stream');
      expect(sent['method'], 'tools/call');
      expect(sent['params']['name'], 'web_fetch_exa');
      expect(sent['params']['arguments']['urls'], ['https://example.org/p']);
      expect(sent['params']['arguments']['maxCharacters'], 5000);
      expect(page!.title, 'Photosynthesis');
      expect(page.text, startsWith('Photosynthesis converts'));
      expect(page.via, 'exa');
    });

    test('accepts plain JSON bodies', () {
      final parsed = ExaFetchChannel.parseExaResponse(jsonEncode({
        'result': {
          'content': [
            {'text': '# T\nURL: u\n\nbody text'}
          ]
        }
      }));
      expect(parsed.title, 'T');
      expect(parsed.text, 'body text');
    });

    test('JSON-RPC error and isError are failures', () {
      expect(
          () => ExaFetchChannel.parseExaResponse(
              'data: ${jsonEncode({'error': {'code': -1, 'message': 'x'}})}\n'),
          throwsA(isA<ReachChannelException>()));
      expect(
          () => ExaFetchChannel.parseExaResponse(jsonEncode({
                'result': {'isError': true, 'content': []}
              })),
          throwsA(isA<ReachChannelException>()));
      expect(() => ExaFetchChannel.parseExaResponse('garbage'),
          throwsA(isA<ReachChannelException>()));
    });
  });

  group('htmlToReadableText', () {
    test('drops chrome blocks, keeps text, decodes entities', () {
      final r = htmlToReadableText(
          '<title>A &amp; B</title><nav>MENU</nav><p>Tom&nbsp;&amp;&#32;Jerry &lt;3 &#x41;</p>'
          '<script>evil()</script><ul><li>one</li><li>two</li></ul><form>F</form>');
      expect(r.title, 'A & B');
      expect(r.text, contains('Tom & Jerry <3 A'));
      expect(r.text, contains('- one'));
      expect(r.text, isNot(contains('MENU')));
      expect(r.text, isNot(contains('evil')));
      expect(r.text, isNot(contains('F\n')));
    });

    test('linear time on 1 MB hostile input', () {
      final hostile = <String>[
        '<a ' * 350000,
        '<div' * 250000,
        '<script>' * 130000,
        '<nav>' * 200000,
        '<title>' * 140000,
        '<!--' * 250000,
        '&' * 1000000,
        '<a href="' * 100000,
        '<p>x</p><nav>' * 70000,
        '<' * 1000000,
      ];
      for (final input in hostile) {
        final sw = Stopwatch()..start();
        htmlToReadableText(input);
        expect(sw.elapsedMilliseconds, lessThan(1500), reason: input.substring(0, 12));
      }
    });
  });

  group('DirectChannel', () {
    test('converts HTML and sends a browser UA', () async {
      late http.BaseRequest seen;
      final channel = DirectChannel(MockClient((req) async {
        seen = req;
        return _html(_page);
      }));
      final page = await channel.read(Uri.parse('https://example.com/p'), maxChars: 60000);
      expect(seen.headers['User-Agent'], contains('Mobile'));
      expect(seen.followRedirects, isFalse);
      expect(page!.title, 'Hello & Welcome');
      expect(page.text, contains('Heading'));
      expect(page.text, isNot(contains('MENU')));
      expect(page.text, isNot(contains('FOOT')));
      expect(page.via, 'direct');
    });

    test('rejects PDFs and binary types', () async {
      final channel = DirectChannel(MockClient((_) async =>
          _utf8Response('%PDF', 200, headers: {'content-type': 'application/pdf'})));
      expect(() => channel.read(Uri.parse('https://example.com/a.pdf'), maxChars: 1000),
          throwsA(isA<ReachChannelException>()));
    });

    test('follows a public redirect and re-validates each hop', () async {
      var calls = 0;
      final channel = DirectChannel(MockClient((req) async {
        calls++;
        if (req.url.path == '/old') {
          return http.Response('', 302, headers: {'location': '/new'});
        }
        return _html(_page);
      }));
      final page = await channel.read(Uri.parse('https://example.com/old'), maxChars: 60000);
      expect(page, isNotNull);
      expect(calls, 2);
    });

    test('refuses a redirect to a private address', () async {
      final requested = <Uri>[];
      final channel = DirectChannel(MockClient((req) async {
        requested.add(req.url);
        return http.Response('', 302, headers: {'location': 'http://127.0.0.1/admin'});
      }));
      await expectLater(channel.read(Uri.parse('https://example.com/x'), maxChars: 1000),
          throwsA(isA<ReachChannelException>()));
      expect(requested.length, 1);
    });

    test('refuses a redirect whose DNS resolves privately', () async {
      UrlGuard.resolver = (host) async =>
          [InternetAddress(host == 'evil.example.net' ? '10.0.0.9' : '93.184.216.34')];
      final channel = DirectChannel(MockClient((req) async =>
          http.Response('', 301, headers: {'location': 'https://evil.example.net/'})));
      await expectLater(channel.read(Uri.parse('https://example.com/x'), maxChars: 1000),
          throwsA(isA<ReachChannelException>()));
    });

    test('gives up after 3 redirects', () async {
      final channel = DirectChannel(MockClient((req) async =>
          http.Response('', 302, headers: {'location': '/again'})));
      await expectLater(channel.read(Uri.parse('https://example.com/x'), maxChars: 1000),
          throwsA(isA<ReachChannelException>()));
    });

    test('stops reading the body at the size cap', () async {
      var pulled = 0;
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < 100; i++) {
          pulled++;
          yield List.filled(100 * 1024, 0x61);
        }
      }

      final channel = DirectChannel(MockClient.streaming((req, _) async =>
          http.StreamedResponse(chunks(), 200, headers: {'content-type': 'text/plain'})));
      final page = await channel.read(Uri.parse('https://example.com/big'), maxChars: 10000000);
      expect(page!.text.length, DirectChannel.maxBodyBytes);
      expect(pulled, lessThan(20));
    });
  });

  group('ReachPageReader', () {
    ReachPageReader build(
      Future<http.Response> Function(http.Request) handler, {
      List<String>? log,
      DateTime Function()? now,
    }) {
      final client = MockClient((req) async {
        log?.add(req.url.host);
        return handler(req);
      });
      return ReachPageReader(client: client, now: now);
    }

    Future<http.Response> allGood(http.Request req) async {
      switch (req.url.host) {
        case 'r.jina.ai':
          return _utf8Response(_jinaBody(), 200);
        case 'mcp.exa.ai':
          return _utf8Response(_exaSse(), 200);
        default:
          return _html(_page);
      }
    }

    test('rejected URLs return null without any network', () async {
      final log = <String>[];
      final reader = build(allGood, log: log);
      for (final url in ['http://127.0.0.1/', 'ftp://example.com', 'http://u:p@example.com', '']) {
        expect(await reader.read(url), isNull);
      }
      expect(log, isEmpty);
    });

    test('first channel (jina) wins and result is capped', () async {
      final log = <String>[];
      final reader = build(allGood, log: log);
      final page = await reader.read('https://example.com/a#section', maxChars: 500);
      expect(page!.via, 'jina');
      expect(page.url, 'https://example.com/a');
      expect(page.text.length, 500);
      expect(log, ['r.jina.ai']);
    });

    test('falls back jina -> exa -> direct, and ignores trivial results', () async {
      final log = <String>[];
      final reader = build((req) async {
        switch (req.url.host) {
          case 'r.jina.ai':
            return _utf8Response('Title: t\n\nMarkdown Content:\nshort', 200);
          case 'mcp.exa.ai':
            return _utf8Response('boom', 500);
          default:
            return _html(_page);
        }
      }, log: log);
      final page = await reader.read('https://example.com/a');
      expect(page!.via, 'direct');
      expect(log, ['r.jina.ai', 'mcp.exa.ai', 'example.com']);
    });

    test('returns null when every channel fails', () async {
      final reader = build((_) async => _utf8Response('x', 503));
      expect(await reader.read('https://example.com/a'), isNull);
    });

    test('breaker opens after 3 failures and skips that channel', () async {
      final log = <String>[];
      final reader = build((req) async {
        if (req.url.host == 'r.jina.ai') return _utf8Response('x', 500);
        return _utf8Response(_exaSse(), 200);
      }, log: log);
      for (var i = 0; i < 3; i++) {
        final page = await reader.read('https://example.com/p$i');
        expect(page!.via, 'exa');
      }
      log.clear();
      final page = await reader.read('https://example.com/p4');
      expect(page!.via, 'exa');
      expect(log, ['mcp.exa.ai'], reason: 'jina is skipped while its breaker is open');
    });

    test('cache hit avoids the network; failures are not cached; TTL expires', () async {
      var clock = DateTime(2026, 1, 1);
      final log = <String>[];
      final reader = build(allGood, log: log, now: () => clock);
      await reader.read('https://example.com/c');
      await reader.read('https://example.com/c#other-fragment');
      expect(log.length, 1);
      final smaller = await reader.read('https://example.com/c', maxChars: 300);
      expect(smaller!.text.length, 300);
      expect(log.length, 1);

      clock = clock.add(const Duration(minutes: 31));
      await reader.read('https://example.com/c');
      expect(log.length, 2);
    });

    test('cache evicts the least recently used entry beyond capacity', () async {
      final log = <String>[];
      final client = MockClient((req) async {
        log.add(req.url.toString());
        return _utf8Response(_jinaBody(), 200);
      });
      final reader = ReachPageReader(client: client, cacheCapacity: 2);
      await reader.read('https://example.com/1');
      await reader.read('https://example.com/2');
      await reader.read('https://example.com/1'); // refresh 1
      await reader.read('https://example.com/3'); // evicts 2
      log.clear();
      await reader.read('https://example.com/1');
      expect(log, isEmpty);
      await reader.read('https://example.com/2');
      expect(log.length, 1);
    });

    test('readMany keeps requested keys, de-duplicates and drops failures', () async {
      final log = <String>[];
      final reader = build((req) async {
        if (req.url.toString().contains('bad')) return _utf8Response('x', 500);
        return _utf8Response(_jinaBody(), 200);
      }, log: log);
      final result = await reader.readMany([
        'https://example.com/a',
        'https://example.com/a#frag',
        'https://example.com/bad',
        'http://127.0.0.1/',
      ]);
      expect(result.keys.toSet(), {'https://example.com/a', 'https://example.com/a#frag'});
      expect(result['https://example.com/a']!.url, 'https://example.com/a');
      // One jina call for /a (fragment variant de-duplicated) plus one for /bad.
      expect(log.where((h) => h == 'r.jina.ai').length, 2);
    });

    test('readMany honours the concurrency bound', () async {
      var inFlight = 0;
      var peak = 0;
      final reader = ReachPageReader(
          channels: [
            JinaReaderChannel(MockClient((req) async {
              inFlight++;
              peak = math.max(peak, inFlight);
              await Future<void>.delayed(const Duration(milliseconds: 40));
              inFlight--;
              return _utf8Response(_jinaBody(), 200);
            }))
          ]);
      final urls = [for (var i = 0; i < 8; i++) 'https://example.com/$i'];
      final result = await reader.readMany(urls, concurrency: 2);
      expect(result.length, 8);
      expect(peak, 2);
    });

    test('readMany keeps in-time results and drops late ones at the deadline', () async {
      final reader = ReachPageReader(
          channels: [
            JinaReaderChannel(MockClient((req) async {
              if (req.url.toString().endsWith('slow')) {
                await Future<void>.delayed(const Duration(milliseconds: 1500));
              }
              return _utf8Response(_jinaBody(), 200);
            }))
          ]);
      final sw = Stopwatch()..start();
      final result = await reader.readMany(
        ['https://example.com/fast', 'https://example.com/slow'],
        deadline: const Duration(milliseconds: 300),
      );
      expect(sw.elapsedMilliseconds, lessThan(1200));
      expect(result.keys, ['https://example.com/fast']);
    });

    test('doctor reports every channel and never throws', () async {
      final reader = build((req) async {
        switch (req.url.host) {
          case 'r.jina.ai':
            return _utf8Response(_jinaBody(), 200);
          case 'mcp.exa.ai':
            return _utf8Response('down', 500);
          default:
            throw const SocketException('offline');
        }
      });
      final report = await reader.doctor();
      expect(report.map((c) => c.channelId), ['jina', 'exa', 'direct']);
      expect(report.map((c) => c.ok), [true, false, false]);
      expect(report[1].detail, contains('500'));
      expect(report.every((c) => c.latency >= Duration.zero), isTrue);
    });
  });
}
