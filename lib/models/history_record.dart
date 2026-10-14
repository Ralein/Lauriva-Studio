import 'dart:convert';

/// Enterprise structured record for studio text transformations and audits.
class HistoryRecord {
  final String id;
  final DateTime timestamp;
  final String inputText;
  final String outputText;
  final String featureId;
  final String featureLabel;
  final String providerName;
  final String modelUsed;
  final int inputWordCount;
  final int outputWordCount;
  final double? humanScore;
  final double? aiRiskScore;

  const HistoryRecord({
    required this.id,
    required this.timestamp,
    required this.inputText,
    required this.outputText,
    required this.featureId,
    required this.featureLabel,
    required this.providerName,
    required this.modelUsed,
    required this.inputWordCount,
    required this.outputWordCount,
    this.humanScore,
    this.aiRiskScore,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'inputText': inputText,
        'outputText': outputText,
        'featureId': featureId,
        'featureLabel': featureLabel,
        'providerName': providerName,
        'modelUsed': modelUsed,
        'inputWordCount': inputWordCount,
        'outputWordCount': outputWordCount,
        if (humanScore != null) 'humanScore': humanScore,
        if (aiRiskScore != null) 'aiRiskScore': aiRiskScore,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) {
    return HistoryRecord(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: json['timestamp'] != null
          ? (DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now())
          : DateTime.now(),
      inputText: json['inputText'] as String? ?? '',
      outputText: json['outputText'] as String? ?? '',
      featureId: json['featureId'] as String? ?? 'Transform',
      featureLabel: json['featureLabel'] as String? ??
          (json['featureId'] as String? ?? 'Transformation'),
      providerName: json['providerName'] as String? ?? 'Lauriva AI',
      modelUsed: json['modelUsed'] as String? ?? 'Default Model',
      inputWordCount: json['inputWordCount'] as int? ?? 0,
      outputWordCount: json['outputWordCount'] as int? ?? 0,
      humanScore: (json['humanScore'] as num?)?.toDouble(),
      aiRiskScore: (json['aiRiskScore'] as num?)?.toDouble(),
    );
  }

  static int _legacySeq = 0;

  /// Seamless migration factory supporting legacy raw string items from SharedPreferences
  factory HistoryRecord.fromLegacyString(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        return HistoryRecord.fromJson(decoded);
      } catch (_) {}
    }

    final words = trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
    return HistoryRecord(
      // Two entries saved in the same millisecond must not share an id: the
      // history store treats an equal id on the newest entry as a duplicate.
      id: '${DateTime.now().microsecondsSinceEpoch}_${_legacySeq++}',
      timestamp: DateTime.now(),
      inputText: '',
      outputText: trimmed,
      featureId: 'Transformation',
      featureLabel: 'Transformation',
      providerName: 'Lauriva',
      modelUsed: 'Standard',
      inputWordCount: 0,
      outputWordCount: words,
    );
  }

  /// Calculates the word count delta percentage between input and output
  int? get wordDeltaPercent {
    if (inputWordCount == 0 || outputWordCount == 0) return null;
    return (((outputWordCount - inputWordCount) / inputWordCount) * 100).round();
  }

  /// Returns a human-readable relative time representation
  String get relativeTime {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.month}/${timestamp.day}';
  }
}
