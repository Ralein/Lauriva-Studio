import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/multilingual_feature_profiles.dart';

/// The neural detector is English-only; [LanguageDetector.isEnglish] decides
/// when it may run. Every Studio language other than English must be kept away
/// from it, and English text (including LLM output) must reach it.
void main() {
  final fixture = jsonDecode(File('test/forensic/fixtures/wiki_language_samples.json').readAsStringSync())
      as Map<String, dynamic>;
  final paragraphs = (fixture['paragraphs'] as Map<String, dynamic>)
      .map((lang, ps) => MapEntry(lang, (ps as List).cast<String>()));

  test('covers every Studio language', () {
    expect(paragraphs.keys.toSet(), containsAll(<String>[
      'en', 'ta', 'es', 'fr', 'de', 'hi', 'ja', 'zh', 'ar', 'pt', 'ru', //
      'it', 'ko', 'nl', 'tr', 'bn', 'vi', 'id', 'pl', 'te', 'mr', 'sv',
    ]));
  });

  for (final entry in paragraphs.entries) {
    test('${entry.key} Wikipedia text is ${entry.key == 'en' ? '' : 'not '}judged English', () {
      for (final p in entry.value) {
        expect(LanguageDetector.isEnglish(p), entry.key == 'en', reason: p.substring(0, 80));
      }
    });
  }

  test('English LLM output and academic prose reach the neural detector', () {
    for (final f in ['modern_frontier_test.jsonl', 'coverage_test.jsonl']) {
      final rows = File('tool/eval/data/$f').readAsLinesSync().where((l) => l.trim().isNotEmpty).take(200);
      final english = rows.where((l) => LanguageDetector.isEnglish((jsonDecode(l) as Map)['text'] as String)).length;
      expect(english / 200, greaterThanOrEqualTo(0.99), reason: f);
    }
  });

  test('text with no letters is not treated as English', () {
    expect(LanguageDetector.isEnglish('12345 ... !!!'), isFalse);
    expect(LanguageDetector.isEnglish(''), isFalse);
  });
}
