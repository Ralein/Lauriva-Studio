import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/multilingual_feature_profiles.dart';

void main() {
  group('Multilingual Forensics Tests (Phase 4)', () {
    test('LanguageDetector identifies English, Spanish, French, German, Arabic, Hindi', () {
      expect(
        LanguageDetector.detect('The dominant sequence transduction models are based on complex neural networks.'),
        equals('en'),
      );

      expect(
        LanguageDetector.detect('El modelo de aprendizaje profundo es muy importante para el procesamiento del lenguaje.'),
        equals('es'),
      );

      expect(
        LanguageDetector.detect('Le modèle de réseau de neurones est très efficace pour la traduction automatique.'),
        equals('fr'),
      );

      expect(
        LanguageDetector.detect('Die künstliche Intelligenz hat in den letzten Jahren große Fortschritte gemacht.'),
        equals('de'),
      );

      expect(
        LanguageDetector.detect('يعتبر الذكاء الاصطناعي من أهم التقنيات الحديثة في معالجة اللغة الطبيعية.'),
        equals('ar'),
      );

      expect(
        LanguageDetector.detect('कृत्रिम बुद्धिमत्ता आधुनिक युग में भाषा प्रसंस्करण के लिए अत्यंत महत्वपूर्ण है।'),
        equals('hi'),
      );
    });

    test('MultilingualProfiles retrieves dedicated parameters for supported languages', () {
      final esProfile = MultilingualProfiles.forCode('es');
      expect(esProfile.languageName, equals('Spanish'));
      expect(esProfile.expectedAiThreshold, equals(68.0));

      final deProfile = MultilingualProfiles.forCode('de');
      expect(deProfile.languageName, equals('German'));
      expect(deProfile.expectedAiThreshold, equals(70.0));

      final unknownProfile = MultilingualProfiles.forCode('xyz');
      expect(unknownProfile.languageCode, equals('en'));
    });
  });
}
