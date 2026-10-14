import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/reach/url_guard.dart';

void main() {
  group('UrlGuard.isAllowed', () {
    test('accepts ordinary public http(s) URLs', () {
      for (final url in [
        'https://en.wikipedia.org/wiki/Photosynthesis',
        'http://example.com/',
        'https://example.com:443/a?b=c',
        'http://example.com:80',
        'https://8.8.8.8/',
        'https://[2606:4700:4700::1111]/',
        '  https://example.com/x  ',
      ]) {
        expect(UrlGuard.isAllowed(url), isTrue, reason: url);
      }
    });

    test('rejects bad schemes, userinfo, ports, empty and overlong', () {
      for (final url in [
        '',
        '   ',
        'ftp://example.com/',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'example.com/no-scheme',
        'http://user:pw@example.com',
        'http://user@example.com',
        'https://example.com:8443/',
        'http://example.com:22/',
        'https://${'a' * 2100}.com/',
      ]) {
        expect(UrlGuard.isAllowed(url), isFalse, reason: url);
      }
    });

    test('rejects local and internal host names', () {
      for (final url in [
        'http://localhost:8080',
        'http://localhost/',
        'http://app.localhost/',
        'http://printer.local/',
        'http://db.internal/',
        'http://router.lan/',
        'http://intranet/',
      ]) {
        expect(UrlGuard.isAllowed(url), isFalse, reason: url);
      }
    });

    test('rejects private, loopback, metadata and reserved IPv4 literals', () {
      for (final url in [
        'http://127.0.0.1/',
        'http://10.1.2.3/',
        'http://172.16.0.1/',
        'http://172.31.255.255/',
        'http://192.168.1.1/',
        'http://169.254.169.254/latest/meta-data/',
        'http://100.64.0.1/',
        'http://0.0.0.0/',
        'http://224.0.0.1/',
        'http://255.255.255.255/',
      ]) {
        expect(UrlGuard.isAllowed(url), isFalse, reason: url);
      }
      expect(UrlGuard.isAllowed('http://172.32.0.1/'), isTrue);
    });

    test('rejects IPv6 loopback, ULA, link-local, mapped private', () {
      for (final url in [
        'http://[::1]/',
        'http://[::]/',
        'http://[fc00::1]/',
        'http://[fd12:3456::1]/',
        'http://[fe80::1]/',
        'http://[ff02::1]/',
        'http://[::ffff:10.0.0.1]/',
        'http://[::ffff:127.0.0.1]/',
        'http://[64:ff9b::a00:1]/',
      ]) {
        expect(UrlGuard.isAllowed(url), isFalse, reason: url);
      }
    });

    test('rejects obfuscated numeric hosts', () {
      for (final url in [
        'http://2130706433/',
        'http://0x7f.1/',
        'http://0x7f000001/',
        'http://127.1/',
        'http://017700000001/',
        'http://010.0.0.1/',
        'http://1.2.3.4.5/',
        'http://256.1.1.1/',
      ]) {
        expect(UrlGuard.isAllowed(url), isFalse, reason: url);
      }
    });
  });

  group('UrlGuard.normalize', () {
    test('strips the fragment and keeps the query', () {
      expect(UrlGuard.normalize('https://example.com/a?b=1#frag'), 'https://example.com/a?b=1');
    });

    test('returns null for rejected URLs', () {
      expect(UrlGuard.normalize('http://127.0.0.1/'), isNull);
    });
  });

  group('UrlGuard.resolvesPublicly', () {
    final original = UrlGuard.resolver;
    tearDown(() => UrlGuard.resolver = original);

    test('public answers pass', () async {
      UrlGuard.resolver = (_) async => [InternetAddress('93.184.216.34')];
      expect(await UrlGuard.resolvesPublicly(Uri.parse('https://example.com/')), isTrue);
    });

    test('any non-public answer fails the whole lookup', () async {
      UrlGuard.resolver =
          (_) async => [InternetAddress('93.184.216.34'), InternetAddress('10.0.0.5')];
      expect(await UrlGuard.resolvesPublicly(Uri.parse('https://example.com/')), isFalse);
    });

    test('lookup failure or empty answer is a rejection', () async {
      UrlGuard.resolver = (_) async => throw const SocketException('nxdomain');
      expect(await UrlGuard.resolvesPublicly(Uri.parse('https://example.com/')), isFalse);
      UrlGuard.resolver = (_) async => [];
      expect(await UrlGuard.resolvesPublicly(Uri.parse('https://example.com/')), isFalse);
    });

    test('IP literals are judged without DNS', () async {
      UrlGuard.resolver = (_) async => throw StateError('must not resolve');
      expect(await UrlGuard.resolvesPublicly(Uri.parse('http://8.8.8.8/')), isTrue);
      expect(await UrlGuard.resolvesPublicly(Uri.parse('http://[::1]/')), isFalse);
    });
  });
}
