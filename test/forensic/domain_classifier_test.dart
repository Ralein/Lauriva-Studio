import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/domain_classifier.dart';

void main() {
  group('DomainClassifier', () {
    late DomainClassifier classifier;

    setUp(() {
      classifier = DomainClassifier();
    });

    test('classifies recipe/procedural text as instructional with 82.0 threshold', () {
      const recipeText = '''
      Preheat the oven to 375 degrees. In a large skillet, melt two tablespoons of butter
      and saute the chopped onions. In a separate bowl, whisk together the flour, sugar,
      and salt. Pour the mixture into a casserole dish and bake for 25 minutes until golden.
      Garnish before serving.
      ''';

      final domain = classifier.classify(recipeText);
      expect(domain, equals(TextDomain.instructional));
      expect(classifier.domainLabel(domain), equals('Instructional'));
      expect(classifier.aiThreshold(domain), equals(82.0));
    });

    test('classifies medical text with high threshold', () {
      const medicalText = '''
      The patient presented with acute hypertension and pulmonary distress.
      Preoperative clinical evaluation indicated renal contraindications.
      Laboratory specimen cultures and biopsy results confirmed etiology.
      ''';

      final domain = classifier.classify(medicalText);
      expect(domain, equals(TextDomain.medical));
      expect(classifier.domainLabel(domain), equals('Medical'));
      expect(classifier.aiThreshold(domain), equals(80.0));
    });

    test('classifies legal contract text with high threshold', () {
      const legalText = '''
      Pursuant to the aforementioned agreement, the lessee covenants to indemnify
      and hold harmless the lessor from all claims of breach, negligence, and liability.
      Jurisdiction shall reside within designated arbitration forums.
      ''';

      final domain = classifier.classify(legalText);
      expect(domain, equals(TextDomain.legal));
      expect(classifier.domainLabel(domain), equals('Legal'));
      expect(classifier.aiThreshold(domain), equals(82.0));
    });

    test('classifies technical systems text with 75.0 threshold', () {
      const techText = '''
      The microservice architecture utilizes an asynchronous event queue to optimize latency
      and throughput. The cluster allocator handles mutex contention across goroutine threads
      and manages socket descriptor buffers.
      ''';

      final domain = classifier.classify(techText);
      expect(domain, equals(TextDomain.technical));
      expect(classifier.domainLabel(domain), equals('Technical'));
      expect(classifier.aiThreshold(domain), equals(75.0));
    });

    test('falls back to generalProse for neutral or empty text', () {
      expect(classifier.classify(''), equals(TextDomain.generalProse));
      expect(classifier.classify('   '), equals(TextDomain.generalProse));
      expect(
        classifier.classify('The dog walked through the park on a sunny afternoon with friends.'),
        equals(TextDomain.generalProse),
      );
      expect(classifier.aiThreshold(TextDomain.generalProse), equals(65.0));
      expect(classifier.domainLabel(TextDomain.generalProse), equals('General'));
    });
  });
}
