import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/forensic/ai/neural/model_delivery_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late MockPathProviderPlatform mockPathProvider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_delivery_test');
    mockPathProvider = MockPathProviderPlatform(tempDir);
    PathProviderPlatform.instance = mockPathProvider;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelDeliveryService Tests', () {
    test('initial state is notDownloaded', () async {
      final service = ModelDeliveryService();
      expect(service.status.value, equals(ModelDeliveryStatus.notDownloaded));
      expect(service.downloadProgress.value, equals(0.0));

      final ready = await service.isModelReady();
      expect(ready, isFalse);
      expect(service.status.value, equals(ModelDeliveryStatus.notDownloaded));
    });

    test('downloads model and verifies completion', () async {
      // Create 2MB of dummy weights
      final dummyBytes = List<int>.filled(2 * 1024 * 1024, 42);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          dummyBytes,
          200,
          headers: {'content-length': dummyBytes.length.toString()},
        );
      });

      final service = ModelDeliveryService(httpClient: mockClient);

      final progressValues = <double>[];
      service.downloadProgress.addListener(() {
        progressValues.add(service.downloadProgress.value);
      });

      final success = await service.downloadModel(
        overrideUrl: 'https://example.com/model.onnx',
      );

      expect(success, isTrue);
      expect(service.status.value, equals(ModelDeliveryStatus.ready));
      expect(service.downloadProgress.value, equals(1.0));
      expect(progressValues.isNotEmpty, isTrue);

      final isReady = await service.isModelReady();
      expect(isReady, isTrue);

      final localPath = await service.getModelLocalPath();
      expect(localPath, isNotNull);
      expect(File(localPath!).existsSync(), isTrue);

      final size = await service.getDownloadedModelSize();
      expect(size, equals(2 * 1024 * 1024));

      // Test deletion
      final deleted = await service.deleteModel();
      expect(deleted, isTrue);
      expect(await service.isModelReady(), isFalse);
      expect(service.status.value, equals(ModelDeliveryStatus.notDownloaded));
    });

    test('handles HTTP 404/500 failure gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = ModelDeliveryService(httpClient: mockClient);
      final success = await service.downloadModel(
        overrideUrl: 'https://example.com/missing.onnx',
      );

      expect(success, isFalse);
      expect(service.status.value, equals(ModelDeliveryStatus.failed));
    });

    test('accepts a download whose SHA-256 matches the pinned digest', () async {
      final payload = List<int>.generate(2 * 1024 * 1024, (i) => i % 251);
      final client = MockClient((request) async => http.Response.bytes(payload, 200));
      final service = ModelDeliveryService(httpClient: client);
      final ok = await service.downloadModel(
        overrideUrl: 'https://example.com/model.onnx',
        expectedSha256: sha256.convert(payload).toString(),
      );
      expect(ok, isTrue);
      expect(await service.isModelReady(), isTrue);
    });

    test('rejects and removes a download whose SHA-256 differs', () async {
      final payload = List<int>.generate(2 * 1024 * 1024, (i) => i % 251);
      final client = MockClient((request) async => http.Response.bytes(payload, 200));
      final service = ModelDeliveryService(httpClient: client);
      final ok = await service.downloadModel(
        overrideUrl: 'https://example.com/model.onnx',
        expectedSha256: '0' * 64,
      );
      expect(ok, isFalse);
      expect(service.status.value, equals(ModelDeliveryStatus.failed));
      expect(await service.isModelReady(), isFalse);
      expect(await service.getModelLocalPath(), isNull);
      final leftovers = tempDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });

    test('automatic background download never runs under flutter test', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('x', 200);
      });
      final service = ModelDeliveryService(httpClient: client);
      service.ensureInBackground();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests, 0);
    });

    test('pinned model digest is a 64-char hex SHA-256', () {
      expect(ModelDeliveryService.defaultModelSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
