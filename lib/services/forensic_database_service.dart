import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forensic/forensic_report.dart';

/// Representation of a stored forensic scan for historical lookup.
class ForensicScanRecord {
  final String id;
  final DateTime createdAt;
  final String inputText;
  final double aiProbability;
  final double humanProbability;
  final String authorshipClass;
  final double overallScore;
  final int wordCount;
  final Map<String, dynamic> reportJson;

  const ForensicScanRecord({
    required this.id,
    required this.createdAt,
    required this.inputText,
    required this.aiProbability,
    required this.humanProbability,
    required this.authorshipClass,
    required this.overallScore,
    required this.wordCount,
    required this.reportJson,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'inputText': inputText,
    'aiProbability': aiProbability,
    'humanProbability': humanProbability,
    'authorshipClass': authorshipClass,
    'overallScore': overallScore,
    'wordCount': wordCount,
    'reportJson': reportJson,
  };

  factory ForensicScanRecord.fromJson(Map<String, dynamic> json) =>
      ForensicScanRecord(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        inputText: json['inputText'] as String,
        aiProbability: (json['aiProbability'] as num).toDouble(),
        humanProbability: (json['humanProbability'] as num).toDouble(),
        authorshipClass: json['authorshipClass'] as String,
        overallScore: (json['overallScore'] as num).toDouble(),
        wordCount: json['wordCount'] as int,
        reportJson: json['reportJson'] as Map<String, dynamic>,
      );
}

/// Representation of a stored humanization revision with before/after deltas.
class HumanizationRecord {
  final String id;
  final String? scanId;
  final DateTime createdAt;
  final String originalText;
  final String humanizedText;
  final double aiBefore;
  final double aiAfter;
  final double preservationScore;

  const HumanizationRecord({
    required this.id,
    this.scanId,
    required this.createdAt,
    required this.originalText,
    required this.humanizedText,
    required this.aiBefore,
    required this.aiAfter,
    required this.preservationScore,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'scanId': scanId,
    'createdAt': createdAt.toIso8601String(),
    'originalText': originalText,
    'humanizedText': humanizedText,
    'aiBefore': aiBefore,
    'aiAfter': aiAfter,
    'preservationScore': preservationScore,
  };

  factory HumanizationRecord.fromJson(Map<String, dynamic> json) =>
      HumanizationRecord(
        id: json['id'] as String,
        scanId: json['scanId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        originalText: json['originalText'] as String,
        humanizedText: json['humanizedText'] as String,
        aiBefore: (json['aiBefore'] as num).toDouble(),
        aiAfter: (json['aiAfter'] as num).toDouble(),
        preservationScore: (json['preservationScore'] as num).toDouble(),
      );
}

/// Persistent local storage service for forensic audit trails and humanizer revisions.
class ForensicDatabaseService {
  static const String _keyScans = 'lauriva_forensic_scans_v1';
  static const String _keyHumanizations = 'lauriva_humanizations_v1';
  static const String _legacyKeyScans = 'Lauriva_forensic_scans_v1';
  static const String _legacyKeyHumanizations = 'Lauriva_humanizations_v1';

  final SharedPreferences? _prefs;

  ForensicDatabaseService({SharedPreferences? prefs}) : _prefs = prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Saves a complete [ForensicReport] to local history.
  Future<ForensicScanRecord> saveScan(ForensicReport report) async {
    final prefs = await _getPrefs();
    final scans = await getScans();

    final record = ForensicScanRecord(
      id: report.metadata.analysisId,
      createdAt: report.metadata.analyzedAt,
      inputText: report.rawText,
      aiProbability: report.aiAuthorship.aiProbability,
      humanProbability: report.aiAuthorship.humanProbability,
      authorshipClass: report.aiAuthorship.authorshipClass.label,
      overallScore: report.overallScore,
      wordCount: report.wordCount,
      reportJson: report.toJson(),
    );

    // Keep most recent scans at head (capped at 100)
    scans.removeWhere((s) => s.id == record.id);
    scans.insert(0, record);
    if (scans.length > 100) {
      scans.removeRange(100, scans.length);
    }

    final encoded = scans.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_keyScans, encoded);
    return record;
  }

  /// Retrieves list of saved scan records up to [limit].
  Future<List<ForensicScanRecord>> getScans({int limit = 50}) async {
    final prefs = await _getPrefs();
    final rawList =
        prefs.getStringList(_keyScans) ??
        prefs.getStringList(_legacyKeyScans) ??
        [];

    final result = <ForensicScanRecord>[];
    for (final raw in rawList) {
      try {
        result.add(
          ForensicScanRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip malformed legacy records gracefully
      }
    }
    return result.take(limit).toList();
  }

  /// Deletes a single scan by [id].
  Future<bool> deleteScan(String id) async {
    final prefs = await _getPrefs();
    final scans = await getScans(limit: 200);
    final initialLen = scans.length;
    scans.removeWhere((s) => s.id == id);
    if (scans.length == initialLen) return false;

    final encoded = scans.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.remove(_legacyKeyScans);
    return prefs.setStringList(_keyScans, encoded);
  }

  /// Saves a humanization record with before/after scores.
  Future<void> saveHumanization(HumanizationRecord record) async {
    final prefs = await _getPrefs();
    final list = await getHumanizations();

    list.removeWhere((h) => h.id == record.id);
    list.insert(0, record);
    if (list.length > 100) {
      list.removeRange(100, list.length);
    }

    final encoded = list.map((h) => jsonEncode(h.toJson())).toList();
    await prefs.remove(_legacyKeyHumanizations);
    await prefs.setStringList(_keyHumanizations, encoded);
  }

  /// Retrieves humanization history.
  Future<List<HumanizationRecord>> getHumanizations({int limit = 50}) async {
    final prefs = await _getPrefs();
    final rawList =
        prefs.getStringList(_keyHumanizations) ??
        prefs.getStringList(_legacyKeyHumanizations) ??
        [];

    final result = <HumanizationRecord>[];
    for (final raw in rawList) {
      try {
        result.add(
          HumanizationRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip malformed
      }
    }
    return result.take(limit).toList();
  }

  /// Clears all local audit history.
  Future<void> clearAll() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyScans);
    await prefs.remove(_keyHumanizations);
    await prefs.remove(_legacyKeyScans);
    await prefs.remove(_legacyKeyHumanizations);
  }

  // ── Report Exporters ───────────────────────────────────────────────────────

  /// Formats a [ForensicReport] into a comprehensive, professional Markdown audit certificate.
  static String exportAsMarkdown(ForensicReport report) {
    final buffer = StringBuffer();
    buffer.writeln('# Lauriva Forensic Audit Report');
    buffer.writeln();
    buffer.writeln('**Analysis ID:** `${report.metadata.analysisId}`  ');
    buffer.writeln(
      '**Date:** ${report.metadata.analyzedAt.toUtc().toIso8601String()}  ',
    );
    buffer.writeln('**Engine Version:** ${report.metadata.engineVersion}  ');
    buffer.writeln(
      '**Document Length:** ${report.wordCount} words (${report.sentenceCount} sentences)  ',
    );
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('## 1. Executive Verdict');
    buffer.writeln();
    buffer.writeln('| Dimension | Score | Assessment |');
    buffer.writeln('|---|---|---|');
    buffer.writeln(
      '| **AI Authorship Probability** | **${report.aiAuthorship.aiProbability.toStringAsFixed(1)}%** | ${report.aiAuthorship.authorshipClass.label} |',
    );
    buffer.writeln(
      '| **External Literature Match** | **${report.sourceSimilarity.overallSimilarityScore.toStringAsFixed(1)}%** | ${report.sourceSimilarity.matches.isNotEmpty ? 'Overlap Found' : 'Clean'} |',
    );
    buffer.writeln(
      '| **Formulaic Repetition** | **${report.internalRepetition.repetitionScore.toStringAsFixed(1)}%** | ${report.internalRepetition.flaggedBoilerplates.length} boilerplate(s) |',
    );
    buffer.writeln(
      '| **Statistical Confidence** | **${report.confidence.level.label}** | ±${(report.confidence.uncertainty * 100).toStringAsFixed(0)}% uncertainty |',
    );
    buffer.writeln();
    buffer.writeln('**Summary:** ${report.summary}');
    buffer.writeln();

    if (report.aiAuthorship.detectedSignals.isNotEmpty) {
      buffer.writeln('## 2. Detected Forensic Stylometric Signals');
      buffer.writeln();
      for (final s in report.aiAuthorship.detectedSignals) {
        buffer.writeln(
          '- **${s.name}** (${s.score.toStringAsFixed(0)}%): ${s.description}',
        );
      }
      buffer.writeln();
    }

    if (report.sourceSimilarity.matches.isNotEmpty) {
      buffer.writeln('## 3. Literature Overlap Details');
      buffer.writeln();
      for (final m in report.sourceSimilarity.matches) {
        buffer.writeln(
          '- **"${m.sourceTitle}"** — ${m.similarityPercent.toStringAsFixed(1)}% match (${m.citationStatus.label})',
        );
        buffer.writeln('  > "${m.matchedText}"');
      }
      buffer.writeln();
    }

    buffer.writeln('## 4. Analyzed Text Excerpt');
    buffer.writeln();
    buffer.writeln('```');
    buffer.writeln(
      report.rawText.length > 500
          ? '${report.rawText.substring(0, 500)}...'
          : report.rawText,
    );
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln(
      '*Generated by Lauriva AI Writing Studio — Statistically Defensible Forensics*',
    );

    return buffer.toString();
  }

  /// Exports [ForensicReport] to serialized JSON string.
  static String exportAsJson(ForensicReport report) {
    return const JsonEncoder.withIndent('  ').convert(report.toJson());
  }
}
