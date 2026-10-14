import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/logger.dart';

/// Represents a locally discovered Ollama model.
class OllamaModel {
  final String name;
  final String? digest;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  const OllamaModel({
    required this.name,
    this.digest,
    this.sizeBytes,
    this.modifiedAt,
  });

  String get displayName {
    // "llama3:latest" → "Llama 3 (latest)"
    final parts = name.split(':');
    final model = parts[0]
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(\d+)'), (m) => ' ${m[0]}')
        .trim();
    final tag = parts.length > 1 ? parts[1] : null;
    return tag != null ? '$model ($tag)' : model;
  }

  String get sizeLabel {
    if (sizeBytes == null) return '';
    final gb = sizeBytes! / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  factory OllamaModel.fromJson(Map<String, dynamic> json) => OllamaModel(
        name: json['name'] as String? ?? '',
        digest: json['digest'] as String?,
        sizeBytes: json['size'] as int?,
        modifiedAt: json['modified_at'] != null
            ? DateTime.tryParse(json['modified_at'] as String)
            : null,
      );
}

/// Result of an auto-discovery scan.
class LocalDiscoveryResult {
  final String endpoint;
  final String providerName;
  final List<OllamaModel> models;
  final bool isAvailable;

  const LocalDiscoveryResult({
    required this.endpoint,
    required this.providerName,
    required this.models,
    required this.isAvailable,
  });
}

/// Scans well-known local AI server endpoints and returns discovered providers.
///
/// Probes:
/// - Ollama  → http://localhost:11434/api/tags
/// - LM Studio → http://localhost:1234/v1/models
/// - vLLM   → http://localhost:8000/v1/models
class OllamaDiscoveryService {
  static const _probeTimeoutMs = 2500;

  static const _endpoints = [
    _LocalEndpoint(
      name: 'Ollama',
      tagsUrl: 'http://localhost:11434/api/tags',
      baseUrl: 'http://localhost:11434/v1',
      isOllamaFormat: true,
    ),
    _LocalEndpoint(
      name: 'LM Studio',
      tagsUrl: 'http://localhost:1234/v1/models',
      baseUrl: 'http://localhost:1234/v1',
      isOllamaFormat: false,
    ),
    _LocalEndpoint(
      name: 'vLLM / LocalAI',
      tagsUrl: 'http://localhost:8000/v1/models',
      baseUrl: 'http://localhost:8000/v1',
      isOllamaFormat: false,
    ),
  ];

  /// Runs all endpoint probes concurrently.
  Future<List<LocalDiscoveryResult>> discoverAll() async {
    final futures = _endpoints.map(_probe);
    final results = await Future.wait(futures, eagerError: false);
    return results.where((r) => r.isAvailable).toList();
  }

  /// Probe a single endpoint.
  Future<LocalDiscoveryResult> _probe(_LocalEndpoint ep) async {
    try {
      final response = await http
          .get(Uri.parse(ep.tagsUrl))
          .timeout(Duration(milliseconds: _probeTimeoutMs));

      if (response.statusCode != 200) {
        return LocalDiscoveryResult(
          endpoint: ep.baseUrl,
          providerName: ep.name,
          models: [],
          isAvailable: false,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = <OllamaModel>[];

      if (ep.isOllamaFormat) {
        // Ollama: { "models": [...] }
        final modelList = data['models'] as List<dynamic>? ?? [];
        for (final m in modelList) {
          models.add(OllamaModel.fromJson(m as Map<String, dynamic>));
        }
      } else {
        // OpenAI-compatible: { "data": [ { "id": "..." } ] }
        final dataList = data['data'] as List<dynamic>? ?? [];
        for (final m in dataList) {
          final id = (m as Map<String, dynamic>)['id'] as String? ?? '';
          if (id.isNotEmpty) models.add(OllamaModel(name: id));
        }
      }

      AppLogger.info(
        '${ep.name} discovered at ${ep.baseUrl} with ${models.length} models',
        'OllamaDiscovery',
      );

      return LocalDiscoveryResult(
        endpoint: ep.baseUrl,
        providerName: ep.name,
        models: models,
        isAvailable: true,
      );
    } catch (e) {
      // Connection refused, timeout, etc. — silently not available.
      return LocalDiscoveryResult(
        endpoint: ep.baseUrl,
        providerName: ep.name,
        models: [],
        isAvailable: false,
      );
    }
  }
}

class _LocalEndpoint {
  final String name;
  final String tagsUrl;
  final String baseUrl;
  final bool isOllamaFormat;

  const _LocalEndpoint({
    required this.name,
    required this.tagsUrl,
    required this.baseUrl,
    required this.isOllamaFormat,
  });
}
