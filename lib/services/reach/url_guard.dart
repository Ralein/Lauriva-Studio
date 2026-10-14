import 'dart:io';

/// Safety policy for every URL Lauriva Reach touches.
///
/// URLs come from untrusted search results, so they are treated as hostile:
/// only plain public http(s) on the standard ports is allowed, never anything
/// that could address the device's own network (SSRF), cloud metadata
/// endpoints, or credentials embedded in the URL.
///
/// [isAllowed] is a pure string-level check. [resolvesPublicly] adds the DNS
/// half (a public-looking name can still point at 10.0.0.1) and is re-run on
/// every redirect hop by the direct channel.
class UrlGuard {
  UrlGuard._();

  static const int maxUrlLength = 2048;

  /// Hostname resolver; overridable so tests never touch real DNS.
  static Future<List<InternetAddress>> Function(String host) resolver =
      (host) => InternetAddress.lookup(host);

  static const Duration _dnsTimeout = Duration(seconds: 4);

  static const List<String> _blockedSuffixes = [
    '.localhost',
    '.local',
    '.internal',
    '.lan',
    '.localdomain',
    '.intranet',
    '.corp',
    '.home',
    '.private',
    '.home.arpa',
  ];

  /// Normalised form of [url] (fragment stripped, query kept), or `null` when
  /// the policy rejects it.
  static String? normalize(String url) => parse(url)?.toString();

  /// True when [url] passes every string-level rule.
  static bool isAllowed(String url) => parse(url) != null;

  /// Parses and validates [url]; `null` when rejected.
  static Uri? parse(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.length > maxUrlLength) return null;
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (!uri.hasAuthority || uri.userInfo.isNotEmpty) return null;
    if (uri.hasPort && uri.port != 80 && uri.port != 443) return null;
    if (!_hostAllowed(uri.host)) return null;
    return uri.hasFragment ? uri.removeFragment() : uri;
  }

  /// DNS check: every resolved address must be public. Failure => `false`.
  static Future<bool> resolvesPublicly(Uri uri) async {
    final host = _cleanHost(uri.host);
    if (host.isEmpty) return false;
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return isPublicAddress(literal);
    try {
      final addresses = await resolver(host).timeout(_dnsTimeout);
      if (addresses.isEmpty) return false;
      return addresses.every(isPublicAddress);
    } catch (_) {
      return false;
    }
  }

  /// True only for globally routable unicast addresses.
  static bool isPublicAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (b.length == 4) return _publicV4(b);
    if (b.length != 16) return false;

    // ::/96 covers ::, ::1 and the deprecated IPv4-compatible form.
    if (b.take(12).every((x) => x == 0)) return false;
    // ::ffff:a.b.c.d (IPv4-mapped): judge the embedded IPv4 address.
    if (b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff) {
      return _publicV4(b.sublist(12));
    }
    // 64:ff9b::/96 (NAT64) embeds an IPv4 address in the last 32 bits.
    if (b[0] == 0x00 &&
        b[1] == 0x64 &&
        b[2] == 0xff &&
        b[3] == 0x9b &&
        b.sublist(4, 12).every((x) => x == 0)) {
      return _publicV4(b.sublist(12));
    }
    // 2002::/16 (6to4) embeds an IPv4 address after the prefix.
    if (b[0] == 0x20 && b[1] == 0x02) return _publicV4(b.sublist(2, 6));
    if ((b[0] & 0xfe) == 0xfc) return false; // fc00::/7 unique local
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return false; // fe80::/10 link-local
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return false; // fec0::/10 site-local
    if (b[0] == 0xff) return false; // multicast
    return true;
  }

  static bool _publicV4(List<int> b) {
    final a = b[0];
    final c = b[1];
    if (a == 0 || a == 10 || a == 127) return false;
    if (a == 169 && c == 254) return false; // link-local, cloud metadata
    if (a == 172 && c >= 16 && c <= 31) return false;
    if (a == 192 && c == 168) return false;
    if (a == 192 && c == 0 && b[2] == 0) return false; // IETF protocol assignments
    if (a == 100 && c >= 64 && c <= 127) return false; // CGNAT
    if (a == 198 && (c == 18 || c == 19)) return false; // benchmarking
    if (a >= 224) return false; // multicast + reserved + broadcast
    return true;
  }

  static String _cleanHost(String host) {
    var h = host.toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    return h;
  }

  static bool _hostAllowed(String rawHost) {
    final host = _cleanHost(rawHost);
    if (host.isEmpty) return false;

    if (host.contains(':')) {
      final v6 = InternetAddress.tryParse(host);
      return v6 != null && isPublicAddress(v6);
    }

    final labels = host.split('.');
    if (labels.any((l) => l.isEmpty)) return false;

    // Numeric-looking hosts (2130706433, 0x7f.1, 127.1, 010.0.0.1) are parsed
    // as IPv4 by some stacks, so only a plain dotted-decimal quad is accepted.
    final last = labels.last;
    if (_allDigits(last) || last.startsWith('0x')) {
      if (labels.length != 4) return false;
      for (final l in labels) {
        if (!_allDigits(l) || l.length > 3 || (l.length > 1 && l.startsWith('0'))) {
          return false;
        }
        if (int.parse(l) > 255) return false;
      }
      final v4 = InternetAddress.tryParse(host);
      return v4 != null && isPublicAddress(v4);
    }

    if (labels.length < 2) return false; // single-label: intranet name
    if (host == 'localhost') return false;
    for (final suffix in _blockedSuffixes) {
      if (host.endsWith(suffix)) return false;
    }
    return true;
  }

  static bool _allDigits(String s) {
    if (s.isEmpty) return false;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }
}
