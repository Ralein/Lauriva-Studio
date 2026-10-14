import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/local_ai/ollama_discovery_service.dart';

void main() {
  group('OllamaModel and Discovery Result Tests', () {
    test('OllamaModel displayName formats tags and underscores cleanly', () {
      const model = OllamaModel(
        name: 'llama3:latest',
        sizeBytes: 4661224676,
      );

      expect(model.name, equals('llama3:latest'));
      expect(model.displayName, contains('latest'));
      expect(model.sizeLabel, equals('4.3 GB'));
    });

    test('OllamaModel fromJson correctly deserializes payload', () {
      final json = {
        'name': 'mistral:latest',
        'digest': 'sha256:abc1234567890',
        'size': 4109844736,
        'modified_at': '2024-03-15T12:00:00Z',
      };

      final model = OllamaModel.fromJson(json);

      expect(model.name, equals('mistral:latest'));
      expect(model.digest, equals('sha256:abc1234567890'));
      expect(model.sizeLabel, equals('3.8 GB'));
      expect(model.modifiedAt, isNotNull);
    });

    test('LocalDiscoveryResult default availability and model collection', () {
      const result = LocalDiscoveryResult(
        endpoint: 'http://localhost:11434',
        providerName: 'Ollama',
        models: [
          OllamaModel(name: 'llama3.2:latest'),
          OllamaModel(name: 'qwen2.5:latest'),
        ],
        isAvailable: true,
      );

      expect(result.isAvailable, isTrue);
      expect(result.models.length, equals(2));
      expect(result.models.first.name, equals('llama3.2:latest'));
    });
  });
}
