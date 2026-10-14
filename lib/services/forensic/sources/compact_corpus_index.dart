import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'match_tokenizer.dart';
import 'winnowing_engine.dart';

/// Random-access bytes of an LSC1 file: in memory (tests, small corpora) or on disk
/// (production: resident memory stays at the header + block index, not the whole file).
abstract class CompactByteSource {
  int get length;
  Uint8List read(int offset, int length);
  void close() {}
}

class MemoryByteSource implements CompactByteSource {
  final Uint8List bytes;
  MemoryByteSource(this.bytes);

  @override
  int get length => bytes.length;

  @override
  Uint8List read(int offset, int length) {
    final end = math.min(offset + length, bytes.length);
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  void close() {}
}

class FileByteSource implements CompactByteSource {
  final RandomAccessFile _raf;
  @override
  final int length;
  FileByteSource._(this._raf, this.length);

  factory FileByteSource.open(String path) {
    final raf = File(path).openSync();
    return FileByteSource._(raf, raf.lengthSync());
  }

  @override
  Uint8List read(int offset, int length) {
    final n = math.min(length, this.length - offset);
    if (n <= 0) return Uint8List(0);
    _raf.setPositionSync(offset);
    return _raf.readSync(n);
  }

  @override
  void close() => _raf.closeSync();
}

/// One reportable source for a query, with the matched runs that justify it.
class CompactSourceReport {
  final int docId;
  final int coveredTokens;
  final double coverage;
  final List<CompactRun> runs;
  const CompactSourceReport({
    required this.docId,
    required this.coveredTokens,
    required this.coverage,
    required this.runs,
  });
}

/// A run of consecutive shared fingerprints (indices into the query's fingerprint list).
class CompactRun {
  final int firstFp;
  final int lastFp;
  final int matchedFps;
  final int spanTokens;
  const CompactRun({required this.firstFp, required this.lastFp, required this.matchedFps, required this.spanTokens});
}

class CompactDocInfo {
  final int family;
  final String title;
  final String key;
  final String familyName;
  final String? url;
  const CompactDocInfo({
    required this.family,
    required this.title,
    required this.key,
    required this.familyName,
    required this.url,
  });
}

/// Decision parameters (stored in the index metadata so they can be tuned without code changes).
class CompactDecision {
  final int gap;
  final int minRunFps;
  final int minSpan;
  final double minCoverage;
  final int strongTokens;

  /// Defaults are the rule validated by tool/corpus/build (zero reported negatives on the
  /// human-text benchmark); a shipped index carries its own values in its header, which win.
  const CompactDecision({
    this.gap = 10,
    this.minRunFps = 5,
    this.minSpan = 14,
    this.minCoverage = 0.20,
    this.strongTokens = 60,
  });

  factory CompactDecision.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CompactDecision();
    return CompactDecision(
      gap: (j['gap'] as num?)?.toInt() ?? 10,
      minRunFps: (j['minRunFps'] as num?)?.toInt() ?? 5,
      minSpan: (j['minSpan'] as num?)?.toInt() ?? 14,
      minCoverage: (j['minCoverage'] as num?)?.toDouble() ?? 0.20,
      strongTokens: (j['strongTokens'] as num?)?.toInt() ?? 60,
    );
  }
}

class _BitReader {
  final Uint8List buf;
  int pos;
  _BitReader(this.buf, this.pos);

  int read(int n) {
    var v = 0;
    var got = 0;
    while (got < n) {
      final byte = buf[pos >> 3];
      final off = pos & 7;
      final take = math.min(8 - off, n - got);
      v |= ((byte >> off) & ((1 << take) - 1)) << got;
      got += take;
      pos += take;
    }
    return v;
  }

  int readRice(int r) {
    var q = 0;
    while (true) {
      final byte = buf[pos >> 3];
      final off = pos & 7;
      final rest = byte >> off;
      if (rest != 0) {
        var tz = 0;
        var x = rest;
        while ((x & 1) == 0) {
          x >>= 1;
          tz++;
        }
        q += tz;
        pos += tz + 1;
        break;
      }
      q += 8 - off;
      pos += 8 - off;
    }
    return (q << r) | read(r);
  }
}

/// Fingerprint-only offline corpus index (format LSC1, see tool/corpus/build/lsc_format.py).
///
/// Holds no source text: a query is winnowed with the index's own (k, w), looked up by
/// truncated 32-bit hash, and only sources that pass the conservative decision rule
/// (minimum run of consecutive shared fingerprints + minimum span + minimum coverage)
/// are reported.
class CompactCorpusIndex {
  static const String assetPath = 'assets/source_corpus_v2.bin';
  static const String idAssetPath = 'assets/source_corpus_v2.id';
  static const int headerSize = 96;
  static const int docGroup = 16;

  final CompactByteSource _src;
  final int k;
  final int w;
  final int hashBits;
  final int docIdBits;
  final int blockSize;
  final int docCount;
  final int fpCount;
  final int blockCount;
  final Map<String, dynamic> meta;
  final CompactDecision decision;

  final Map<String, List<int>> _sec = {};
  late final Uint32List _blockFirst;
  late final Uint32List _blockBit;
  late final Uint32List _overIdx;
  late final Uint32List _overOff;
  late final int _overDataPos;
  late final Uint32List _docIndex;

  CompactCorpusIndex._(this._src, this.k, this.w, this.hashBits, this.docIdBits, this.blockSize, this.docCount,
      this.fpCount, this.blockCount, this.meta, this.decision);

  /// Parses the header and loads only the small index sections (block index, overflow index, doc index).
  factory CompactCorpusIndex.fromSource(CompactByteSource src) {
    final head = src.read(0, headerSize);
    if (head.length < headerSize || String.fromCharCodes(head.sublist(0, 4)) != 'LSC1') {
      throw const FormatException('not an LSC1 corpus index');
    }
    final bd = ByteData.sublistView(head);
    final version = bd.getUint16(4, Endian.little);
    if (version != 1) throw FormatException('unsupported LSC1 version $version');
    final k = bd.getUint8(8);
    final w = bd.getUint8(9);
    final hashBits = bd.getUint8(10);
    final docBits = bd.getUint8(11);
    final blockSize = bd.getUint16(12, Endian.little);
    final docCount = bd.getUint32(16, Endian.little);
    final fpCount = bd.getUint32(20, Endian.little);
    final blockCount = bd.getUint32(24, Endian.little);
    final secs = <String, List<int>>{};
    const names = ['meta', 'docTable', 'docIndex', 'blockIndex', 'hashStream', 'docStream', 'overflow'];
    for (var i = 0; i < names.length; i++) {
      secs[names[i]] = [bd.getUint32(32 + 8 * i, Endian.little), bd.getUint32(36 + 8 * i, Endian.little)];
    }
    final metaBytes = src.read(secs['meta']![0], secs['meta']![1]);
    final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
    final decision = CompactDecision.fromJson(meta['decision'] as Map<String, dynamic>?);
    final idx = CompactCorpusIndex._(src, k, w, hashBits, docBits, blockSize, docCount, fpCount, blockCount, meta, decision);
    idx._sec.addAll(secs);

    final bi = src.read(secs['blockIndex']![0], secs['blockIndex']![1]);
    final bib = ByteData.sublistView(bi);
    idx._blockFirst = Uint32List(blockCount);
    idx._blockBit = Uint32List(blockCount);
    for (var b = 0; b < blockCount; b++) {
      idx._blockFirst[b] = bib.getUint32(8 * b, Endian.little);
      idx._blockBit[b] = bib.getUint32(8 * b + 4, Endian.little);
    }
    final ov = src.read(secs['overflow']![0], secs['overflow']![1]);
    final ovb = ByteData.sublistView(ov);
    final cnt = ov.isEmpty ? 0 : ovb.getUint32(0, Endian.little);
    idx._overIdx = Uint32List(cnt);
    idx._overOff = Uint32List(cnt);
    for (var i = 0; i < cnt; i++) {
      idx._overIdx[i] = ovb.getUint32(4 + 4 * i, Endian.little);
      idx._overOff[i] = ovb.getUint32(4 + 4 * cnt + 4 * i, Endian.little);
    }
    idx._overDataPos = secs['overflow']![0] + 4 + 8 * cnt;
    final di = src.read(secs['docIndex']![0], secs['docIndex']![1]);
    final dib = ByteData.sublistView(di);
    idx._docIndex = Uint32List(di.length ~/ 4);
    for (var i = 0; i < idx._docIndex.length; i++) {
      idx._docIndex[i] = dib.getUint32(4 * i, Endian.little);
    }
    return idx;
  }

  void close() => _src.close();

  /// Identical to `truncate_hash` in tool/corpus/build/lsc_text.py.
  static int truncateHash(int h, int bits) {
    if (bits >= 32) return h;
    return (((h * 0x9E3779B1) & 0xFFFFFFFF) >> (32 - bits));
  }

  /// Winnowing engine matching this index's fingerprint parameters.
  WinnowingEngine get engine => WinnowingEngine(k: k, w: w);

  // -------------------------------------------------------------------------- lookup

  Uint32List _decodeBlock(int b) {
    final n = math.min(blockSize, fpCount - b * blockSize);
    final secOff = _sec['hashStream']![0];
    final secLen = _sec['hashStream']![1];
    final startBit = _blockBit[b];
    final endBit = b + 1 < blockCount ? _blockBit[b + 1] : secLen * 8;
    final byteStart = startBit >> 3;
    final byteEnd = math.min(secLen, ((endBit + 7) >> 3) + 4);
    final bytes = _src.read(secOff + byteStart, byteEnd - byteStart);
    final br = _BitReader(bytes, startBit & 7);
    final r = br.read(5);
    final out = Uint32List(n);
    var h = _blockFirst[b];
    out[0] = h;
    for (var i = 1; i < n; i++) {
      h += br.readRice(r) + 1;
      out[i] = h;
    }
    return out;
  }

  int _blockFor(int hash) {
    var lo = 0;
    var hi = blockCount - 1;
    var ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_blockFirst[mid] <= hash) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  List<int> _docsOf(int fpIndex) {
    final secOff = _sec['docStream']![0];
    final bitPos = fpIndex * docIdBits;
    final bytes = _src.read(secOff + (bitPos >> 3), ((docIdBits + 7) >> 3) + 2);
    final v = _BitReader(bytes, bitPos & 7).read(docIdBits);
    if (v != docCount) return [v];
    var lo = 0;
    var hi = _overIdx.length - 1;
    var j = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_overIdx[mid] == fpIndex) {
        j = mid;
        break;
      }
      if (_overIdx[mid] < fpIndex) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (j < 0) return const [];
    final pos = _overDataPos + _overOff[j];
    final raw = _src.read(pos, 1 + 5 * 8);
    final n = raw[0];
    final out = <int>[];
    var p = 1;
    for (var i = 0; i < n; i++) {
      var shift = 0;
      var x = 0;
      while (true) {
        final b = raw[p++];
        x |= (b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
      }
      out.add(x);
    }
    return out;
  }

  /// Documents containing an already-truncated hash (empty when absent or dropped by the DF cap).
  List<int> docsForTruncatedHash(int key) {
    final b = _blockFor(key);
    if (b < 0) return const [];
    final block = _decodeBlock(b);
    var lo = 0;
    var hi = block.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (block[mid] == key) return _docsOf(b * blockSize + mid);
      if (block[mid] < key) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return const [];
  }

  /// Per-document list of matching query-fingerprint indices (ascending).
  Map<int, List<int>> findCandidates(List<WinnowingFingerprint> queryFps) {
    final byHash = <int, List<int>>{};
    for (var i = 0; i < queryFps.length; i++) {
      byHash.putIfAbsent(truncateHash(queryFps[i].hash, hashBits), () => []).add(i);
    }
    final keys = byHash.keys.toList()..sort();
    final perDoc = <int, List<int>>{};
    var curBlock = -1;
    Uint32List cur = Uint32List(0);
    for (final key in keys) {
      final b = _blockFor(key);
      if (b < 0) continue;
      if (b != curBlock) {
        cur = _decodeBlock(b);
        curBlock = b;
      }
      var lo = 0;
      var hi = cur.length - 1;
      var at = -1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (cur[mid] == key) {
          at = mid;
          break;
        }
        if (cur[mid] < key) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (at < 0) continue;
      for (final d in _docsOf(curBlock * blockSize + at)) {
        perDoc.putIfAbsent(d, () => []).addAll(byHash[key]!);
      }
    }
    for (final l in perDoc.values) {
      l.sort();
    }
    return perDoc;
  }

  /// Query fingerprints whose k-gram contains at least one content word. All-stopword k-grams
  /// ("one of the most") are dropped at build time and ignored here, mirroring `doc_fingerprints`.
  List<WinnowingFingerprint> contentFingerprints(List<WinnowingFingerprint> fps, List<MatchToken> tokens) {
    return [
      for (final f in fps)
        if (_hasContentWord(tokens, f.tokenIndex)) f,
    ];
  }

  bool _hasContentWord(List<MatchToken> tokens, int start) {
    for (var i = start; i < start + k && i < tokens.length; i++) {
      if (!tokens[i].isStopword) return true;
    }
    return false;
  }

  /// Winnows [tokens] with this index's (k, w), drops all-stopword k-grams.
  List<WinnowingFingerprint> queryFingerprints(List<MatchToken> tokens) =>
      contentFingerprints(engine.fingerprintTokens(tokens), tokens);

  /// Sources that pass the decision rule, best first. Mirrors `report_sources` in lsc_index.py.
  /// [queryFps] must come from [queryFingerprints] (already stopword-filtered).
  List<CompactSourceReport> reportSources(List<WinnowingFingerprint> queryFps, int nTokens, {CompactDecision? override}) {
    final dec = override ?? decision;
    if (queryFps.isEmpty || nTokens == 0) return const [];
    final reports = <CompactSourceReport>[];
    findCandidates(queryFps).forEach((docId, idxs) {
      if (idxs.length < dec.minRunFps) return;
      var covered = 0;
      final runs = <CompactRun>[];
      void close(int from, int to) {
        final matched = to - from + 1;
        if (matched < dec.minRunFps) return;
        final first = idxs[from];
        final last = idxs[to];
        final span = queryFps[last].tokenIndex + k - queryFps[first].tokenIndex;
        if (span >= dec.minSpan) {
          covered += span;
          runs.add(CompactRun(firstFp: first, lastFp: last, matchedFps: matched, spanTokens: span));
        }
      }

      var runStart = 0;
      for (var j = 1; j < idxs.length; j++) {
        if (queryFps[idxs[j]].tokenIndex - queryFps[idxs[j - 1]].tokenIndex <= dec.gap) continue;
        close(runStart, j - 1);
        runStart = j;
      }
      close(runStart, idxs.length - 1);
      final cov = covered / nTokens;
      if (covered > 0 && (cov >= dec.minCoverage || covered >= dec.strongTokens)) {
        reports.add(CompactSourceReport(docId: docId, coveredTokens: covered, coverage: cov, runs: runs));
      }
    });
    reports.sort((a, b) => b.coveredTokens.compareTo(a.coveredTokens));
    return reports;
  }

  // -------------------------------------------------------------------------- doc table

  CompactDocInfo docInfo(int docId) {
    final tableOff = _sec['docTable']![0];
    final tableLen = _sec['docTable']![1];
    final g = docId ~/ docGroup;
    final start = _docIndex[g];
    final end = g + 1 < _docIndex.length ? _docIndex[g + 1] : tableLen;
    final bytes = _src.read(tableOff + start, end - start);
    var p = 0;
    int varint() {
      var shift = 0;
      var x = 0;
      while (true) {
        final b = bytes[p++];
        x |= (b & 0x7F) << shift;
        if ((b & 0x80) == 0) return x;
        shift += 7;
      }
    }

    var prev = Uint8List(0);
    var fam = 0;
    var title = Uint8List(0);
    var key = Uint8List(0);
    for (var i = 0; i <= docId % docGroup; i++) {
      fam = bytes[p++];
      final shared = varint();
      final slen = varint();
      title = Uint8List.fromList([...prev.sublist(0, shared), ...bytes.sublist(p, p + slen)]);
      p += slen;
      final klen = varint();
      key = Uint8List.sublistView(bytes, p, p + klen);
      p += klen;
      prev = title;
    }
    final families = (meta['families'] as List?) ?? const [];
    final f = fam < families.length ? families[fam] as Map<String, dynamic> : const <String, dynamic>{};
    final titleStr = utf8.decode(title);
    final keyStr = utf8.decode(key);
    final template = f['urlTemplate'] as String?;
    String? url;
    if (keyStr.startsWith('http')) {
      url = keyStr; // absolute URL stored for documents whose URL cannot be derived from the template
    } else if (template != null) {
      url = template
          .replaceAll('{title_}', Uri.encodeComponent(titleStr.replaceAll(' ', '_')))
          .replaceAll('{key}', keyStr);
    }
    return CompactDocInfo(
      family: fam,
      title: titleStr,
      key: keyStr,
      familyName: (f['name'] as String?) ?? '',
      url: url,
    );
  }

  // -------------------------------------------------------------------------- lazy singleton

  static CompactCorpusIndex? _current;
  static bool _triedOpen = false;

  /// Cache file shared by every isolate of the process (extracted once by [ensureReady]).
  static String get cachePath => '${Directory.systemTemp.path}/lauriva_source_corpus_v2.lsc';

  /// The loaded index, or null when no corpus is available. Works inside `compute` isolates:
  /// it opens the extracted cache file lazily (no asset access needed).
  static CompactCorpusIndex? get current {
    if (_current != null) return _current;
    if (_triedOpen) return null;
    _triedOpen = true;
    try {
      final f = File(cachePath);
      if (f.existsSync()) _current = CompactCorpusIndex.fromSource(FileByteSource.open(cachePath));
    } catch (_) {
      _current = null;
    }
    return _current;
  }

  /// Installs an index explicitly (tests, or callers that built one in memory).
  static void install(CompactCorpusIndex? index) {
    _current?.close();
    _current = index;
    _triedOpen = index != null;
  }

  /// Extracts the bundled corpus to [cachePath] once (re-extracts when the bundled build id changes)
  /// and opens it. Cheap on later launches: it reads a 32-byte id asset, not the corpus.
  static Future<CompactCorpusIndex?> ensureReady({AssetBundle? bundle}) async {
    if (_current != null) return _current;
    try {
      final b = bundle ?? rootBundle;
      final idBytes = (await b.load(idAssetPath)).buffer.asUint8List();
      final id = utf8.decode(idBytes).trim();
      final cache = File(cachePath);
      final side = File('$cachePath.id');
      final fresh = cache.existsSync() && side.existsSync() && side.readAsStringSync().trim() == id;
      if (!fresh) {
        final data = await b.load(assetPath);
        final tmp = File('$cachePath.tmp');
        await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
        if (cache.existsSync()) cache.deleteSync();
        await tmp.rename(cachePath);
        await side.writeAsString(id, flush: true);
      }
      _triedOpen = false;
      return current;
    } catch (_) {
      return null; // no bundled corpus: callers simply have no offline index
    }
  }
}
