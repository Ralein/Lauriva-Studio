import 'background_task_status.dart';

/// Domain entity representing a native or background activity in Lauriva.
class BackgroundTask {
  final String id;
  final String title;
  final String? stage;
  final double progress; // 0.0 to 1.0
  final BackgroundTaskStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? errorMessage;
  final String? taskType;
  final Map<String, dynamic>? metadata;

  const BackgroundTask({
    required this.id,
    required this.title,
    this.stage,
    this.progress = 0.0,
    this.status = BackgroundTaskStatus.running,
    required this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.taskType,
    this.metadata,
  });

  /// Total elapsed or recorded run duration.
  Duration get duration {
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  /// Formatted duration string (e.g. "12s" or "2m 14s").
  String get formattedDuration {
    final dur = duration;
    if (dur.inSeconds < 60) return '${dur.inSeconds}s';
    final min = dur.inMinutes;
    final sec = dur.inSeconds % 60;
    return '${min}m ${sec}s';
  }

  /// Formatted percentage string (e.g. "65%").
  String get formattedProgress => '${(progress * 100).clamp(0, 100).toInt()}%';

  /// Defensive copy with modified fields.
  BackgroundTask copyWith({
    String? id,
    String? title,
    String? stage,
    double? progress,
    BackgroundTaskStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? errorMessage,
    String? taskType,
    Map<String, dynamic>? metadata,
  }) {
    return BackgroundTask(
      id: id ?? this.id,
      title: title ?? this.title,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      taskType: taskType ?? this.taskType,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Resolves the notification title and body corresponding to Lauriva's native activity spec:
  /// - Forensic analysis: "Lauriva — Analyzing your text…"
  /// - Source matching: "Lauriva — Checking for matching sources…"
  /// - Report generation: "Lauriva — Preparing your report…"
  /// - Task completed: "Lauriva — Your report is ready."
  /// - Task failed: "Lauriva — Analysis couldn't be completed."
  ({String title, String body}) resolveNotificationContent() {
    const title = 'Lauriva';

    if (status == BackgroundTaskStatus.completed) {
      return (title: title, body: 'Your report is ready.');
    }

    if (status == BackgroundTaskStatus.failed) {
      return (title: title, body: 'Analysis couldn\'t be completed.');
    }

    if (status == BackgroundTaskStatus.interrupted) {
      return (title: title, body: 'Analysis was interrupted by the system.');
    }

    // Running states mapped from current execution stage
    final stageText = (stage ?? '').toLowerCase();

    if (stageText.contains('source') ||
        stageText.contains('matching') ||
        stageText.contains('literature') ||
        stageText.contains('shingle')) {
      return (title: title, body: 'Checking for matching sources…');
    }

    if (stageText.contains('report') ||
        stageText.contains('prepar') ||
        stageText.contains('generat') ||
        stageText.contains('fus')) {
      return (title: title, body: 'Preparing your report…');
    }

    return (title: title, body: 'Analyzing your text…');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'stage': stage,
    'progress': progress,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'errorMessage': errorMessage,
    'taskType': taskType,
    'metadata': metadata,
  };

  factory BackgroundTask.fromJson(Map<String, dynamic> json) => BackgroundTask(
    id:
        json['id'] as String? ??
        'task_${DateTime.now().millisecondsSinceEpoch}',
    title: json['title'] as String? ?? 'Forensic Analysis',
    stage: json['stage'] as String?,
    progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    status: BackgroundTaskStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => BackgroundTaskStatus.completed,
    ),
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now(),
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'] as String)
        : null,
    errorMessage: json['errorMessage'] as String?,
    taskType: json['taskType'] as String?,
    metadata: json['metadata'] as Map<String, dynamic>?,
  );
}
