import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/multilingual_feature_profiles.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

/// [LanguageDetector.detect] must recognise all 22 Studio languages so the
/// stylometric stream applies the right [MultilingualFeatureProfile].
void main() {
  final fixture = jsonDecode(File('test/forensic/fixtures/wiki_language_samples.json').readAsStringSync())
      as Map<String, dynamic>;
  final paragraphs = (fixture['paragraphs'] as Map<String, dynamic>)
      .map((lang, ps) => MapEntry(lang, (ps as List).cast<String>()));

  const studioLanguages = [
    'en', 'ta', 'es', 'fr', 'de', 'hi', 'ja', 'zh', 'ar', 'pt', 'ru', //
    'it', 'ko', 'nl', 'tr', 'bn', 'vi', 'id', 'pl', 'te', 'mr', 'sv',
  ];

  test('every Studio language has a registered profile', () {
    expect(MultilingualProfiles.profiles.keys.toSet(), studioLanguages.toSet());
    for (final code in studioLanguages) {
      final p = MultilingualProfiles.forCode(code);
      expect(p.languageCode, code);
      expect(p.expectedAiThreshold, inInclusiveRange(0.0, 100.0));
      expect(p.vocabularyRichnessBaseline, inInclusiveRange(0.0, 1.0));
      expect(p.functionWordRatio, inInclusiveRange(0.0, 1.0));
    }
  });

  group('Wikipedia paragraphs are detected as their own language', () {
    for (final entry in paragraphs.entries) {
      test(entry.key, () {
        for (final p in entry.value) {
          expect(LanguageDetector.detect(p), entry.key, reason: p.substring(0, 60));
        }
      });
    }
  });

  group('short and edge inputs', () {
    final cases = <String, String>{
      'The results of the study were published in a journal.': 'en',
      'Olá, como você está? Não sei.': 'pt',
      '¿Dónde está la biblioteca?': 'es',
      'Il fait très beau aujourd\'hui.': 'fr',
      'Ich weiß nicht, wo das ist.': 'de',
      'Questo è il libro della mia amica.': 'it',
      'Ik weet niet waar het is.': 'nl',
      'Jag vet inte var det är.': 'sv',
      'Nie wiem, gdzie to jest.': 'pl',
      'Bu kitap çok güzel ve ilginç.': 'tr',
      'Tôi không biết nó ở đâu.': 'vi',
      'Saya tidak tahu di mana itu.': 'id',
      'Я не знаю, где это.': 'ru',
      'لا أعرف أين هو.': 'ar',
      'मुझे नहीं पता कि यह कहाँ है।': 'hi',
      'मला माहित नाही ते कुठे आहे.': 'mr',
      'আমি জানি না এটা কোথায়।': 'bn',
      'அது எங்கே என்று எனக்குத் தெரியாது.': 'ta',
      'అది ఎక్కడ ఉందో నాకు తెలియదు.': 'te',
      '私はそれがどこにあるのか知りません。': 'ja',
      '我不知道它在哪里。': 'zh',
      '나는 그것이 어디에 있는지 모른다.': 'ko',
      // Latin names inside non-Latin prose do not flip the script decision.
      'Google и Microsoft объявили о новом партнёрстве в области ИИ.': 'ru',
      'OpenAI와 Google은 새로운 AI 모델을 발표했습니다.': 'ko',
      // Katakana loanwords mark Japanese even in Han-heavy text.
      '東京大学の研究者はデータを分析した。': 'ja',
    };
    cases.forEach((text, lang) {
      test('$lang: $text', () => expect(LanguageDetector.detect(text), lang));
    });

    test('no-evidence input falls back to English deterministically', () {
      expect(LanguageDetector.detect(''), 'en');
      expect(LanguageDetector.detect('   '), 'en');
      expect(LanguageDetector.detect('12345 ... !!!'), 'en');
      expect(LanguageDetector.detect('OK'), 'en');
    });
  });

  group('ForensicEngine analyzes every Studio language', () {
    final engine = ForensicEngine();
    for (final code in studioLanguages) {
      test(code, () {
        final text = paragraphs[code]!.first;
        final report = engine.analyze(text, enableOnlineSearch: false);
        final ai = report.aiAuthorship;
        expect(ai.aiProbability, inInclusiveRange(0.0, 100.0));
        expect(ai.humanProbability, inInclusiveRange(0.0, 100.0));
        expect(report.wordCount, greaterThan(0));
        final languageSignals = ai.detectedSignals.where((s) => s.family == 'Language').toList();
        if (code == 'en') {
          expect(languageSignals, isEmpty);
        } else {
          expect(languageSignals, hasLength(1));
          expect(languageSignals.single.name, contains(MultilingualProfiles.forCode(code).languageName));
        }
        // Genuine Cyrillic prose is not mistaken for a homoglyph attack.
        if (code == 'ru') {
          expect(ai.detectedSignals.where((s) => s.name == 'Unicode Homoglyph Substitution'), isEmpty);
        }
      });
    }
  });
}
