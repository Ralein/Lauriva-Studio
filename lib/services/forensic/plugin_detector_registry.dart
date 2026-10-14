import 'dart:async';
import 'package:flutter/foundation.dart';

/// Result returned by an external or plugin forensic detector.
class PluginDetectorResult {
  final String pluginId;
  final double aiProbability; // 0.0 to 100.0
  final double uncertainty; // 0.0 to 1.0
  final String? diagnosticSignal;
  final String summary;

  const PluginDetectorResult({
    required this.pluginId,
    required this.aiProbability,
    required this.uncertainty,
    this.diagnosticSignal,
    required this.summary,
  });
}

/// Abstract contract for pluggable, drop-in forensic detectors.
///
/// Enables external or third-party engines to inject detection signals
/// into Lauriva's master fusion pipeline without modifying core engine logic.
abstract class ForensicDetectorPlugin {
  String get id;
  String get name;
  String get description;
  double get weight; // Contribution weight in ensemble fusion (0.0 to 1.0)

  Future<PluginDetectorResult> analyze(String text);
}

/// Central registry managing all dynamic forensic detector plugins.
class PluginDetectorRegistry {
  static final PluginDetectorRegistry _instance = PluginDetectorRegistry._internal();
  factory PluginDetectorRegistry() => _instance;
  PluginDetectorRegistry._internal();

  final Map<String, ForensicDetectorPlugin> _plugins = {};

  /// Registers a new detector plugin.
  void register(ForensicDetectorPlugin plugin) {
    _plugins[plugin.id] = plugin;
    debugPrint('[PluginDetectorRegistry] Registered detector plugin: ${plugin.name} (${plugin.id})');
  }

  /// Unregisters a detector plugin by [id].
  void unregister(String id) {
    _plugins.remove(id);
  }

  /// All currently active detector plugins.
  List<ForensicDetectorPlugin> get all => List.unmodifiable(_plugins.values);

  /// Total registered plugin count.
  int get count => _plugins.length;

  /// Runs all registered plugins in parallel across [text].
  Future<List<PluginDetectorResult>> runAll(String text) async {
    if (_plugins.isEmpty) return const [];

    final futures = _plugins.values.map((plugin) async {
      try {
        return await plugin.analyze(text).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[PluginDetectorRegistry] Plugin ${plugin.id} threw non-fatal error: $e');
        return PluginDetectorResult(
          pluginId: plugin.id,
          aiProbability: 50.0,
          uncertainty: 1.0,
          summary: 'Plugin evaluation failed: $e',
        );
      }
    });

    return Future.wait(futures);
  }
}
