import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_config.dart';
import 'package:lauriva/services/forensic/ai/neural/typography_normalizer.dart';

void main() {
  test('maps smart punctuation to ASCII one code unit at a time', () {
    const input = '“It’s spin‑polarized—really, ‘fast’” − 1–2';
    final out = TypographyNormalizer.normalize(input);
    expect(out, '"It\'s spin-polarized-really, \'fast\'" - 1-2');
    expect(out.length, input.length);
  });

  test('leaves plain text and non-punctuation Unicode untouched', () {
    const input = 'Schrödinger’s cat … été';
    expect(TypographyNormalizer.normalize('plain ascii'), 'plain ascii');
    expect(TypographyNormalizer.normalize(input), 'Schrödinger\'s cat … été');
  });

  test('matches the training-side mapping in tool/eval/typography.py', () {
    final py = File('tool/eval/typography.py').readAsStringSync();
    final groups = RegExp(r'dict\.fromkeys\("([^"]+)", (\x27.\x27|"."|"\x27")\)').allMatches(py).toList();
    expect(groups, hasLength(4));
    for (final g in groups) {
      final chars = g.group(1)!.replaceAllMapped(
          RegExp(r'\\u([0-9a-fA-F]{4})'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
      final target = g.group(2)!.substring(1, 2);
      for (final c in chars.split('')) {
        expect(TypographyNormalizer.normalize(c), target, reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
      }
    }
  });

  test('is on for the shipped detector and can be disabled per model', () {
    expect(const NeuralModelConfig().normalizeTypography, isTrue);
    expect(NeuralModelConfig.fromJson(const {'normalizeTypography': false}).normalizeTypography, isFalse);
    expect(const NeuralModelConfig(normalizeTypography: false).toJson()['normalizeTypography'], isFalse);
  });
}
