import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/plugin_detector_registry.dart';
import 'package:lauriva/services/lauriva_api_server.dart';

class _MockDetectorPlugin implements ForensicDetectorPlugin {
  @override
  String get id => 'test_plugin';

  @override
  String get name => 'Test Forensic Plugin';

  @override
  String get description => 'A test detector plugin.';

  @override
  double get weight => 0.15;

  @override
  Future<PluginDetectorResult> analyze(String text) async {
    return const PluginDetectorResult(
      pluginId: 'test_plugin',
      aiProbability: 80.0,
      uncertainty: 0.1,
      diagnosticSignal: 'Mock signal',
      summary: 'Mock plugin analyzed text successfully',
    );
  }
}

void main() {
  group('PluginDetectorRegistry & ApiServer Tests (Phase 8)', () {
    test('PluginDetectorRegistry registers, retrieves, and executes plugins', () async {
      final registry = PluginDetectorRegistry();
      final plugin = _MockDetectorPlugin();

      registry.register(plugin);

      expect(registry.all.any((p) => p.id == 'test_plugin'), isTrue);
      expect(registry.count, greaterThanOrEqualTo(1));

      final results = await registry.runAll('Sample text for plugin analysis.');
      expect(results.any((r) => r.pluginId == 'test_plugin'), isTrue);

      registry.unregister('test_plugin');
      expect(registry.all.any((p) => p.id == 'test_plugin'), isFalse);
    });

    test('LaurivaApiServer initializes and exposes default port', () {
      final server = LaurivaApiServer();
      expect(server.isRunning, isFalse);
      expect(LaurivaApiServer.defaultPort, equals(7341));
    });
  });
}
