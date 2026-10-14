import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'reach_models.dart';
import 'url_guard.dart';

/// Thrown by a channel on any failure; the reader turns it into a fallback
/// to the next channel and a circuit-breaker failure.
class ReachChannelException implements Exception {
  final String message;
  const ReachChannelException(this.message);

  @override
  String toString() => 'ReachChannelException: $message';
}

/// One way of turning a public URL into readable text. Channels throw
/// [ReachChannelException] (or any error) on failure; only the reader's public
/// API is required to be exception-free.
abstract class ReachChannel {
  String get id;

  /// Hard per-request deadline, applied by the reader.
  Duration get timeout;

  Future<ReachPage?> read(Uri url, {required int maxChars});
}

/// Caps [text] at [max] code units without splitting a surrogate pair.
String capReachText(String text, int max) {
  if (max <= 0) return '';
  if (text.length <= max) return text;
  var end = max;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return text.substring(0, end);
}

String _utf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// r.jina.ai: free keyless reader that returns clean markdown.
class JinaReaderChannel implements ReachChannel {
  final http.Client client;

  @override
  final Duration timeout;

  JinaReaderChannel(this.client, {this.timeout = const Duration(seconds: 9)});

  @override
  String get id => 'jina';

  @override
  Future<ReachPage?> read(Uri url, {required int maxChars}) async {
    final response = await client.get(
      Uri.parse('https://r.jina.ai/$url'),
      headers: const {'Accept': 'text/plain'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReachChannelException('jina HTTP ${response.statusCode}');
    }
    final parsed = parseJinaResponse(_utf8(response.bodyBytes));
    if (parsed.text.isEmpty) throw const ReachChannelException('jina empty');
    return ReachPage(
      url: url.toString(),
      title: parsed.title,
      text: capReachText(parsed.text, maxChars),
      via: id,
    );
  }

  /// Parses the `Title:` / `URL Source:` header block followed by `Markdown Content:`.
  static ({String title, String text}) parseJinaResponse(String body) {
    const marker = 'Markdown Content:';
    final idx = body.indexOf(marker);
    var title = '';
    String content = body;
    if (idx >= 0) {
      for (final line in body.substring(0, idx).split('\n')) {
        if (line.startsWith('Title:')) {
          title = line.substring(6).trim();
          break;
        }
      }
      content = body.substring(idx + marker.length);
    }
    return (title: title, text: content.trim());
  }
}

/// mcp.exa.ai `web_fetch_exa` over JSON-RPC (reply is an SSE `data:` line).
class ExaFetchChannel implements ReachChannel {
  final http.Client client;

  @override
  final Duration timeout;

  ExaFetchChannel(this.client, {this.timeout = const Duration(seconds: 10)});

  @override
  String get id => 'exa';

  @override
  Future<ReachPage?> read(Uri url, {required int maxChars}) async {
    final response = await client.post(
      Uri.parse('https://mcp.exa.ai/mcp'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'web_fetch_exa',
          'arguments': {
            'urls': [url.toString()],
            'maxCharacters': maxChars,
          },
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReachChannelException('exa HTTP ${response.statusCode}');
    }
    final parsed = parseExaResponse(_utf8(response.bodyBytes));
    if (parsed.text.isEmpty) throw const ReachChannelException('exa empty');
    return ReachPage(
      url: url.toString(),
      title: parsed.title,
      text: capReachText(parsed.text, maxChars),
      via: id,
    );
  }

  /// Accepts an SSE body or a plain JSON body; throws on JSON-RPC errors.
  static ({String title, String text}) parseExaResponse(String body) {
    final envelope = _findEnvelope(body);
    if (envelope == null) throw const ReachChannelException('exa unparseable');
    if (envelope['error'] != null) {
      throw const ReachChannelException('exa rpc error');
    }
    final result = envelope['result'];
    if (result is! Map) throw const ReachChannelException('exa no result');
    if (result['isError'] == true) throw const ReachChannelException('exa tool error');
    final content = result['content'];
    if (content is! List || content.isEmpty) {
      throw const ReachChannelException('exa no content');
    }
    final first = content.first;
    final raw = first is Map ? first['text'] : null;
    if (raw is! String) throw const ReachChannelException('exa no text');

    var text = raw.trim();
    var title = '';
    if (text.startsWith('# ')) {
      final nl = text.indexOf('\n');
      title = (nl < 0 ? text.substring(2) : text.substring(2, nl)).trim();
      text = nl < 0 ? '' : text.substring(nl + 1);
      final trimmed = text.trimLeft();
      if (trimmed.startsWith('URL:')) {
        final nl2 = trimmed.indexOf('\n');
        text = nl2 < 0 ? '' : trimmed.substring(nl2 + 1);
      }
    }
    return (title: title, text: text.trim());
  }

  static Map<String, dynamic>? _findEnvelope(String body) {
    Map<String, dynamic>? tryDecode(String s) {
      try {
        final v = jsonDecode(s);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{')) return tryDecode(trimmed);
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final decoded = tryDecode(line.substring(5).trim());
      if (decoded != null && (decoded.containsKey('result') || decoded.containsKey('error'))) {
        return decoded;
      }
    }
    return null;
  }
}

/// The device fetches the page itself. Every hop (including redirects) is
/// re-validated by [UrlGuard]; the body is size-capped while streaming.
class DirectChannel implements ReachChannel {
  final http.Client client;

  @override
  final Duration timeout;

  static const int maxBodyBytes = 1500 * 1024;
  static const int maxRedirects = 3;
  static const String userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
  static const Set<String> _acceptedTypes = {
    'text/html',
    'text/plain',
    'application/xhtml+xml',
  };

  DirectChannel(this.client, {this.timeout = const Duration(seconds: 8)});

  @override
  String get id => 'direct';

  @override
  Future<ReachPage?> read(Uri url, {required int maxChars}) async {
    Uri current = url;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final checked = UrlGuard.parse(current.toString());
      if (checked == null || !await UrlGuard.resolvesPublicly(checked)) {
        throw const ReachChannelException('direct blocked');
      }
      current = checked;

      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(const {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9',
        });
      final response = await client.send(request);

      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw const ReachChannelException('direct redirect without location');
        }
        final Uri? next = Uri.tryParse(location);
        if (next == null) throw const ReachChannelException('direct bad redirect');
        current = current.resolveUri(next);
        continue;
      }
      if (status < 200 || status >= 300) {
        await response.stream.listen((_) {}).cancel();
        throw ReachChannelException('direct HTTP $status');
      }

      final contentType = (response.headers['content-type'] ?? '').toLowerCase();
      final mime = contentType.split(';').first.trim();
      if (!_acceptedTypes.contains(mime)) {
        await response.stream.listen((_) {}).cancel();
        throw ReachChannelException('direct unsupported type "$mime"');
      }

      final bytes = await _readCapped(response.stream);
      final body = contentType.contains('charset=iso-8859-1') ||
              contentType.contains('charset=latin1')
          ? latin1.decode(bytes)
          : _utf8(bytes);

      String title = '';
      String text;
      if (mime == 'text/plain') {
        text = body.trim();
      } else {
        final converted = htmlToReadableText(body);
        title = converted.title;
        text = converted.text;
      }
      if (text.isEmpty) throw const ReachChannelException('direct empty');
      return ReachPage(
        url: url.toString(),
        title: title,
        text: capReachText(text, maxChars),
        via: id,
      );
    }
    throw const ReachChannelException('direct too many redirects');
  }

  static Future<Uint8List> _readCapped(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      final room = maxBodyBytes - builder.length;
      if (chunk.length >= room) {
        builder.add(chunk.sublist(0, room));
        break; // leaving the loop cancels the subscription
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

// ---------------------------------------------------------------------------
// HTML -> readable text
// ---------------------------------------------------------------------------

const Set<String> _dropBlocks = {
  'script', 'style', 'noscript', 'svg', 'nav', 'footer', 'form', 'template',
  'iframe', 'object',
};

/// Blocks whose open tag without a matching close means "the rest is junk".
const Set<String> _dropRestIfUnclosed = {
  'script', 'style', 'template', 'iframe', 'object', 'noscript', 'svg',
};

const Set<String> _blockTags = {
  'p', 'div', 'br', 'tr', 'ul', 'ol', 'table', 'section', 'article', 'header',
  'main', 'aside', 'blockquote', 'pre', 'hr', 'dt', 'dd', 'figcaption',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li',
};

const Map<String, String> _entities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'mdash': '—', 'ndash': '–', 'hellip': '…', 'rsquo': '’',
  'lsquo': '‘', 'ldquo': '“', 'rdquo': '”', 'copy': '©',
  'middot': '·', 'bull': '•', 'times': '×', 'reg': '®',
};

String _asciiLower(String s) {
  final units = Uint16List(s.length);
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    units[i] = (c >= 0x41 && c <= 0x5A) ? c + 32 : c;
  }
  return String.fromCharCodes(units);
}

bool _isNameChar(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2D ||
    c == 0x3A;

/// Linear-time HTML to text converter. Single forward scan with bounded
/// look-ahead: an unterminated construct ends the scan instead of being
/// re-searched, so hostile input cannot cause quadratic work.
({String title, String text}) htmlToReadableText(String html) {
  final n = html.length;
  final lower = _asciiLower(html);
  final out = StringBuffer();
  final unclosed = <String>{};
  var title = '';
  var i = 0;

  while (i < n) {
    final lt = html.indexOf('<', i);
    if (lt < 0) {
      out.write(html.substring(i));
      break;
    }
    if (lt > i) out.write(html.substring(i, lt));
    i = lt;

    if (lower.startsWith('<!--', i)) {
      final end = html.indexOf('-->', i + 4);
      if (end < 0) break;
      i = end + 3;
      continue;
    }

    var j = i + 1;
    final closing = j < n && html.codeUnitAt(j) == 0x2F;
    if (closing) j++;
    final nameStart = j;
    while (j < n && _isNameChar(html.codeUnitAt(j))) {
      j++;
    }
    if (j == nameStart) {
      // "<!doctype", "<?xml", or a literal "<" in text.
      if (!closing && j < n && (html[j] == '!' || html[j] == '?')) {
        final end = html.indexOf('>', j);
        if (end < 0) break;
        i = end + 1;
        continue;
      }
      out.write('<');
      i++;
      continue;
    }
    final name = lower.substring(nameStart, j);

    // Find the end of the tag, honouring quoted attribute values.
    var k = j;
    var quote = 0;
    while (k < n) {
      final c = html.codeUnitAt(k);
      if (quote != 0) {
        if (c == quote) quote = 0;
      } else if (c == 0x22 || c == 0x27) {
        quote = c;
      } else if (c == 0x3E) {
        break;
      }
      k++;
    }
    if (k >= n) break; // unterminated tag: the rest is junk
    final selfClosing = html.codeUnitAt(k - 1) == 0x2F;
    i = k + 1;

    if (closing) {
      if (_blockTags.contains(name)) out.write('\n');
      continue;
    }

    if (name == 'title') {
      if (unclosed.contains(name)) continue;
      final close = lower.indexOf('</title', i);
      if (close < 0) {
        unclosed.add(name);
        continue;
      }
      if (title.isEmpty) title = _tidy(html.substring(i, close)).replaceAll('\n', ' ');
      final end = html.indexOf('>', close);
      if (end < 0) break;
      i = end + 1;
      continue;
    }

    if (_dropBlocks.contains(name) && !selfClosing) {
      if (unclosed.contains(name)) continue;
      final close = lower.indexOf('</$name', i);
      if (close < 0) {
        if (_dropRestIfUnclosed.contains(name)) break;
        unclosed.add(name);
        continue;
      }
      final end = html.indexOf('>', close);
      if (end < 0) break;
      i = end + 1;
      out.write('\n');
      continue;
    }

    if (name == 'li') {
      out.write('\n- ');
    } else if (_blockTags.contains(name)) {
      out.write('\n');
    }
  }

  return (title: title, text: _tidy(out.toString()));
}

/// Decodes entities and collapses whitespace (at most one blank line).
String _tidy(String raw) {
  final decoded = _decodeEntities(raw);
  final lines = <String>[];
  var blank = false;
  for (final line in decoded.split('\n')) {
    final buf = StringBuffer();
    var pendingSpace = false;
    for (var p = 0; p < line.length; p++) {
      final c = line.codeUnitAt(p);
      final isSpace = c == 0x20 || c == 0x09 || c == 0x0D || c == 0xA0 || c == 0x0C;
      if (isSpace) {
        pendingSpace = buf.isNotEmpty;
      } else {
        if (pendingSpace) buf.write(' ');
        pendingSpace = false;
        buf.writeCharCode(c);
      }
    }
    final cleaned = buf.toString();
    if (cleaned.isEmpty) {
      if (!blank && lines.isNotEmpty) lines.add('');
      blank = true;
    } else {
      lines.add(cleaned);
      blank = false;
    }
  }
  return lines.join('\n').trim();
}

String _decodeEntities(String s) {
  if (!s.contains('&')) return s;
  final out = StringBuffer();
  var i = 0;
  final n = s.length;
  while (i < n) {
    final amp = s.indexOf('&', i);
    if (amp < 0) {
      out.write(s.substring(i));
      break;
    }
    out.write(s.substring(i, amp));
    // Entities are short; look at most 10 characters ahead for ';'.
    var semi = -1;
    final limit = amp + 11 < n ? amp + 11 : n;
    for (var p = amp + 1; p < limit; p++) {
      if (s.codeUnitAt(p) == 0x3B) {
        semi = p;
        break;
      }
    }
    String? replacement;
    if (semi > amp + 1) {
      final body = s.substring(amp + 1, semi);
      if (body.codeUnitAt(0) == 0x23) {
        final isHex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
        final code = int.tryParse(body.substring(isHex ? 2 : 1), radix: isHex ? 16 : 10);
        if (code != null && code > 0 && code <= 0x10FFFF && !(code >= 0xD800 && code <= 0xDFFF)) {
          replacement = String.fromCharCode(code);
        }
      } else {
        replacement = _entities[body];
      }
    }
    if (replacement == null) {
      out.write('&');
      i = amp + 1;
    } else {
      out.write(replacement);
      i = semi + 1;
    }
  }
  return out.toString();
}
