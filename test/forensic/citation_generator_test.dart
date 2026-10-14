import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/sources/citation_generator_service.dart';

void main() {
  group('CitationGeneratorService Tests', () {
    late CitationGeneratorService service;

    setUp(() {
      service = CitationGeneratorService();
    });

    final sampleSource = const SourceMetadata(
      title: 'Attention Is All You Need',
      authors: [
        'Vaswani, Ashish',
        'Shazeer, Noam',
        'Parmar, Niki',
        'Uszkoreit, Jakob',
      ],
      year: 2017,
      publisherOrJournal: 'Advances in Neural Information Processing Systems',
      volume: 30,
      pages: '5998-6008',
      doi: '10.48550/arXiv.1706.03762',
      url: 'https://arxiv.org/abs/1706.03762',
    );

    test('APA 7th formatting follows style standards', () {
      final citation = service.formatCitation(sampleSource, CitationStyle.apa7);

      expect(citation, contains('(2017)'));
      expect(citation, contains('Attention Is All You Need.'));
      expect(citation, contains('*Advances in Neural Information Processing Systems*'));
      expect(citation, contains('https://doi.org/10.48550/arXiv.1706.03762'));
    });

    test('MLA 9th formatting uses quotes around article title', () {
      final citation = service.formatCitation(sampleSource, CitationStyle.mla9);

      expect(citation, contains('"Attention Is All You Need."'));
      expect(citation, contains('2017'));
      expect(citation, contains('doi:10.48550/arXiv.1706.03762'));
    });

    test('Chicago 17th formatting formats authors and journal volume', () {
      final citation = service.formatCitation(sampleSource, CitationStyle.chicago);

      expect(citation, contains('"Attention Is All You Need."'));
      expect(citation, contains('2017'));
    });

    test('IEEE style formats with quotes and initials', () {
      final citation = service.formatCitation(sampleSource, CitationStyle.ieee);

      expect(citation, contains('"Attention Is All You Need,"'));
      expect(citation, contains('2017'));
      expect(citation, contains('doi: 10.48550/arXiv.1706.03762'));
    });

    test('Harvard style includes year in parentheses and single quotes', () {
      final citation = service.formatCitation(sampleSource, CitationStyle.harvard);

      expect(citation, contains('(2017)'));
      expect(citation, contains('\'Attention Is All You Need\','));
      expect(citation, contains('https://doi.org/10.48550/arXiv.1706.03762'));
    });

    test('formatAll generates citations for all 5 major styles', () {
      final all = service.formatAll(sampleSource);

      expect(all.keys, containsAll([
        CitationStyle.apa7,
        CitationStyle.mla9,
        CitationStyle.chicago,
        CitationStyle.ieee,
        CitationStyle.harvard,
      ]));
      for (final text in all.values) {
        expect(text, isNotEmpty);
      }
    });

    test('Handles missing fields gracefully with fallbacks', () {
      const minimalSource = SourceMetadata(title: 'Untitled Note');
      final apa = service.formatCitation(minimalSource, CitationStyle.apa7);
      final mla = service.formatCitation(minimalSource, CitationStyle.mla9);

      expect(apa, contains('(n.d.)'));
      expect(apa, contains('Untitled Note'));
      expect(mla, contains('Untitled Note'));
    });
  });
}
