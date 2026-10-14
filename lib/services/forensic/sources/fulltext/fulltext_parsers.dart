import 'dart:convert';

import '../online/source_retriever.dart';

/// Pure, network-free parsers that turn public open-access documents into
/// clean prose paragraphs for the local aligner.
///
/// All parsers are regex based (no HTML/XML package, no PDF parser): the
/// inputs are machine-generated (LaTeXML, JATS, MediaWiki) with flat,
/// stable markup, and avoiding a DOM keeps memory proportional to the
/// (already capped) response instead of to a parsed tree.
class FullTextParsers {
  FullTextParsers._();

  /// Paragraphs shorter than this (in words) are dropped: headings, figure
  /// labels, and affiliation lines only add false-positive surface.
  static const int minParagraphWords = 8;

  static final RegExp _ws = RegExp(r'\s+');

  /// Removes every `<tag …>…</tag>` block (non-greedy; the listed elements do
  /// not nest in LaTeXML/JATS output).
  static String dropElements(String s, List<String> tags) {
    var out = s;
    for (final t in tags) {
      out = out.replaceAll(RegExp('<$t\\b[^>]*/>', caseSensitive: false), ' ');
      out = out.replaceAll(RegExp('<$t\\b[^>]*>[\\s\\S]*?</$t>', caseSensitive: false), ' ');
    }
    return out;
  }

  /// Tag-strips and entity-decodes one paragraph, collapses whitespace, and
  /// terminates it with a period so adjacent paragraphs never merge into one
  /// pseudo-sentence during paraphrase alignment.
  static String cleanParagraph(String raw) {
    var s = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = OnlineTextUtils.decodeEntities(s).replaceAll(_ws, ' ').trim();
    // Citation debris left by removed <xref>/<cite>: "( , )", "[ ]".
    s = s.replaceAll(RegExp(r'\s*[\[(]\s*[,;–-]?\s*[\])]'), '').replaceAll(RegExp(r'\s+([,.;:])'), r'$1');
    if (s.isEmpty) return s;
    if (!RegExp(r'[.!?:;"”)\]]$').hasMatch(s)) s = '$s.';
    return s;
  }

  /// Keeps paragraphs with at least [minParagraphWords] words and joins them
  /// with blank lines, stopping at [maxChars] on a paragraph boundary.
  static String joinParagraphs(Iterable<String> paragraphs, {required int maxChars}) {
    final sb = StringBuffer();
    final seen = <int>{};
    for (final p in paragraphs) {
      if (OnlineTextUtils.wordCount(p) < minParagraphWords) continue;
      if (!seen.add(p.hashCode)) continue; // repeated boilerplate
      final addLen = p.length + (sb.isEmpty ? 0 : 2);
      if (sb.length + addLen > maxChars) {
        if (sb.isEmpty) sb.write(p.substring(0, maxChars));
        break;
      }
      if (sb.isNotEmpty) sb.write('\n\n');
      sb.write(p);
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // arXiv HTML (LaTeXML: arxiv.org/html/<id>, ar5iv.labs.arxiv.org/html/<id>)
  // ---------------------------------------------------------------------------

  static final RegExp _ltxPara = RegExp(
    r'''<p\b[^>]*class="[^"]*\bltx_p\b[^"]*"[^>]*>([\s\S]*?)</p>''',
    caseSensitive: false,
  );

  /// Extracts body paragraphs (`<p class="ltx_p">`) from a LaTeXML page.
  /// The abstract block, figures, tables, citation markers and all MathML
  /// are removed first; bibliography entries are `ltx_bibblock` spans, not
  /// `ltx_p`, so they never match.
  static String parseArxivHtml(String html, {int maxChars = 60000}) {
    var h = html;
    h = h.replaceAll(RegExp(r'<div\b[^>]*class="[^"]*\bltx_abstract\b[^"]*"[^>]*>[\s\S]*?</div>', caseSensitive: false), ' ');
    h = dropElements(h, const ['script', 'style', 'math', 'figure', 'table', 'nav', 'header', 'footer', 'cite']);
    final paras = _ltxPara.allMatches(h).map((m) => cleanParagraph(m.group(1)!));
    return joinParagraphs(paras, maxChars: maxChars);
  }

  // ---------------------------------------------------------------------------
  // JATS XML (Europe PMC fullTextXML, JATS from other OA hosts)
  // ---------------------------------------------------------------------------

  static final RegExp _jatsBody = RegExp(r'<body\b[^>]*>([\s\S]*?)</body>', caseSensitive: false);
  static final RegExp _jatsP = RegExp(r'<p\b[^>]*>([\s\S]*?)</p>', caseSensitive: false);

  /// Extracts `<body>` paragraphs from a JATS article. Reference lists,
  /// tables, figures (incl. captions), formulas, footnotes and supplementary
  /// material are dropped, as are `<xref>` citation markers ("[5]").
  /// Returns '' when the document has no body (metadata-only record).
  static String parseJats(String xml, {int maxChars = 60000}) {
    final body = _jatsBody.firstMatch(xml)?.group(1);
    if (body == null) return '';
    final b = dropElements(body, const [
      'ref-list',
      'table-wrap',
      'fig',
      'disp-formula',
      'inline-formula',
      'mml:math',
      'tex-math',
      'supplementary-material',
      'fn-group',
      'xref',
      'label',
    ]);
    final paras = _jatsP.allMatches(b).map((m) => cleanParagraph(m.group(1)!));
    return joinParagraphs(paras, maxChars: maxChars);
  }

  /// True when [text] looks like a JATS/NLM article (Unpaywall repository
  /// copies are occasionally served as XML).
  static bool looksLikeJats(String text) =>
      text.contains('<article') && (text.contains('<body') || text.contains('<front'));

  // ---------------------------------------------------------------------------
  // Generic open-access HTML landing / full-text page (Unpaywall locations)
  // ---------------------------------------------------------------------------

  /// A landing page counts as full text only if it yields at least this many
  /// words of paragraph prose — publisher abstract pages have ~200–400.
  static const int minLandingWords = 700;
  static const int minLandingParagraphs = 5;

  /// Extracts article prose from a publisher HTML page, or '' when the page
  /// is only an abstract/landing page (see [minLandingWords]).
  static String parseLandingHtml(String html, {int maxChars = 60000}) {
    var h = dropElements(html, const [
      'script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside', 'form', 'figure', 'table', 'svg', 'math',
    ]);
    final article = RegExp(r'<article\b[^>]*>([\s\S]*)</article>', caseSensitive: false).firstMatch(h);
    if (article != null) h = article.group(1)!;
    final paras = RegExp(r'<p\b[^>]*>([\s\S]*?)</p>', caseSensitive: false)
        .allMatches(h)
        .map((m) => cleanParagraph(m.group(1)!))
        .where((p) => OnlineTextUtils.wordCount(p) >= 15)
        .toList();
    final words = paras.fold<int>(0, (a, p) => a + OnlineTextUtils.wordCount(p));
    if (paras.length < minLandingParagraphs || words < minLandingWords) return '';
    return joinParagraphs(paras, maxChars: maxChars);
  }

  /// `<meta name="citation_pdf_url">` — the page advertises a PDF.
  static bool advertisesPdf(String html) =>
      RegExp(r'''<meta\s+[^>]*name=["']citation_pdf_url["']''', caseSensitive: false).hasMatch(html);

  // ---------------------------------------------------------------------------
  // Wikipedia (Action API, prop=extracts&explaintext=1&exsectionformat=plain)
  // ---------------------------------------------------------------------------

  static const Set<String> _wikiTailSections = {
    'see also', 'references', 'notes', 'external links', 'further reading', 'bibliography', 'sources',
    'citations', 'footnotes', 'works cited', 'notes and references',
    // de / fr / es / it / pt / nl
    'siehe auch', 'literatur', 'weblinks', 'einzelnachweise', 'anmerkungen',
    'voir aussi', 'références', 'notes et références', 'liens externes', 'bibliographie',
    'véase también', 'referencias', 'enlaces externos', 'bibliografía',
    'voci correlate', 'note', 'collegamenti esterni', 'bibliografia',
    'ver também', 'referências', 'ligações externas',
    'zie ook', 'externe links', 'bronnen',
  };

  /// Parses an Action API `prop=extracts` JSON response (formatversion 1 or
  /// 2) into paragraphs. Section headings are dropped, and everything from
  /// the first reference-style section ("See also", "References", …) on is
  /// cut. Returns '' for missing pages.
  static String parseWikipediaExtract(String json, {int maxChars = 60000}) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return '';
    final pagesObj = (decoded['query'] as Map?)?['pages'];
    final pages = pagesObj is List ? pagesObj : (pagesObj is Map ? pagesObj.values.toList() : const []);
    for (final p in pages) {
      if (p is! Map || p['missing'] != null) continue;
      final extract = p['extract'];
      if (extract is! String || extract.trim().isEmpty) continue;
      return wikipediaPlainTextToParagraphs(extract, maxChars: maxChars);
    }
    return '';
  }

  static String wikipediaPlainTextToParagraphs(String extract, {int maxChars = 60000}) {
    final out = <String>[];
    for (final rawLine in extract.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final folded = line.toLowerCase().replaceAll(RegExp(r'^=+\s*|\s*=+$'), '');
      if (_wikiTailSections.contains(folded)) break;
      // Headings are short lines without sentence punctuation.
      if (OnlineTextUtils.wordCount(line) < minParagraphWords && !RegExp(r'[.!?]$').hasMatch(line)) continue;
      out.add(cleanParagraph(line));
    }
    return joinParagraphs(out, maxChars: maxChars);
  }

  // ---------------------------------------------------------------------------
  // Unpaywall v2 JSON
  // ---------------------------------------------------------------------------

  static UnpaywallRecord? parseUnpaywall(String json) {
    final d = jsonDecode(json);
    if (d is! Map) return null;
    final locs = <UnpaywallLocation>[];
    final best = d['best_oa_location'];
    if (best is Map) locs.add(UnpaywallLocation.fromJson(best));
    for (final l in (d['oa_locations'] as List? ?? const [])) {
      if (l is! Map) continue;
      final loc = UnpaywallLocation.fromJson(l);
      if (locs.any((e) => e.url == loc.url)) continue;
      locs.add(loc);
    }
    return UnpaywallRecord(isOa: d['is_oa'] == true, locations: locs);
  }
}

/// Parsed Unpaywall response: whether the DOI is OA and its OA locations,
/// best location first.
class UnpaywallRecord {
  final bool isOa;
  final List<UnpaywallLocation> locations;
  const UnpaywallRecord({required this.isOa, required this.locations});
}

class UnpaywallLocation {
  final String? url;
  final String? landingUrl;
  final String? pdfUrl;
  final String? hostType;
  final String? license;

  const UnpaywallLocation({this.url, this.landingUrl, this.pdfUrl, this.hostType, this.license});

  factory UnpaywallLocation.fromJson(Map<dynamic, dynamic> j) => UnpaywallLocation(
        url: j['url'] as String?,
        landingUrl: j['url_for_landing_page'] as String?,
        pdfUrl: j['url_for_pdf'] as String?,
        hostType: j['host_type'] as String?,
        license: j['license'] as String?,
      );

  /// PMCID when the location is a PubMed Central / Europe PMC copy.
  String? get pmcid {
    for (final u in [url, landingUrl, pdfUrl]) {
      if (u == null) continue;
      final m = RegExp(r'(?:ncbi\.nlm\.nih\.gov/pmc/articles/|europepmc\.org/(?:articles?/)?(?:pmc/)?)(?:PMC)?(\d{4,})', caseSensitive: false)
          .firstMatch(u);
      if (m != null) return 'PMC${m.group(1)}';
    }
    return null;
  }

  /// arXiv id when the location is an arXiv copy.
  String? get arxivId {
    for (final u in [url, landingUrl, pdfUrl]) {
      final id = FullTextIds.arxivIdFromUrl(u);
      if (id != null) return id;
    }
    return null;
  }

  /// A fetchable non-PDF page (the landing page, or a URL that is not the PDF).
  String? get htmlUrl {
    if (landingUrl != null && landingUrl != pdfUrl && !FullTextIds.looksLikePdfUrl(landingUrl!)) return landingUrl;
    if (url != null && url != pdfUrl && !FullTextIds.looksLikePdfUrl(url!)) return url;
    return null;
  }
}

/// Identifier extraction for routing a work to a full-text source.
class FullTextIds {
  FullTextIds._();

  static final RegExp _arxivNew = RegExp(r'arxiv\.org/(?:abs|pdf|html)/(\d{4}\.\d{4,5})(?:v\d+)?', caseSensitive: false);
  static final RegExp _arxivOld = RegExp(r'arxiv\.org/(?:abs|pdf|html)/([a-z\-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?', caseSensitive: false);
  static final RegExp _arxivDoi = RegExp(r'^10\.48550/arxiv\.(.+)$', caseSensitive: false);

  static String? arxivIdFromUrl(String? url) {
    if (url == null) return null;
    final m = _arxivNew.firstMatch(url) ?? _arxivOld.firstMatch(url);
    return m?.group(1);
  }

  /// arXiv-minted DataCite DOI (`10.48550/arXiv.<id>`) → arXiv id.
  static String? arxivIdFromDoi(String? normalizedDoi) {
    if (normalizedDoi == null) return null;
    return _arxivDoi.firstMatch(normalizedDoi)?.group(1);
  }

  static String? pmidFromUrl(String? url) {
    if (url == null) return null;
    return RegExp(r'pubmed\.ncbi\.nlm\.nih\.gov/(\d+)').firstMatch(url)?.group(1);
  }

  static String? pmcidFromUrl(String? url) {
    if (url == null) return null;
    return UnpaywallLocation(url: url).pmcid;
  }

  /// (language, title) for a `https://<lang>.wikipedia.org/wiki/<Title>` URL.
  static ({String lang, String title})? wikipediaFromUrl(String? url) {
    if (url == null) return null;
    final m = RegExp(r'^https?://([a-z\-]{2,12})\.(?:m\.)?wikipedia\.org/wiki/([^?#]+)', caseSensitive: false).firstMatch(url);
    if (m == null) return null;
    String title;
    try {
      title = Uri.decodeComponent(m.group(2)!);
    } catch (_) {
      title = m.group(2)!;
    }
    return (lang: m.group(1)!.toLowerCase(), title: title.replaceAll('_', ' '));
  }

  static bool looksLikePdfUrl(String url) {
    final u = url.toLowerCase();
    return RegExp(r'\.pdf($|[?#])').hasMatch(u) || u.contains('/pdf/') || u.endsWith('/pdf');
  }
}
