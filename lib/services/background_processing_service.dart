import 'dart:async';

/// Types of background jobs supported by Lauriva's processing engine.
enum BackgroundJobType {
  forensicScan,
  humanization,
  corpusIndexing,
  modelWarmup,
}

/// Execution lifecycle states of a background job.
enum BackgroundJobStatus {
  queued,
  running,
  completed,
  failed,
  cancelled,
}

/// Model encapsulating the state of an ongoing or completed background job.
class BackgroundJob {
  final String id;
  final BackgroundJobType type;
  final String title;
  final String description;
  final DateTime startedAt;
  double progress; // 0.0 to 1.0
  BackgroundJobStatus status;
  String? statusMessage;
  dynamic result;
  String? errorMessage;
  DateTime? completedAt;

  BackgroundJob({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.progress = 0.0,
    this.status = BackgroundJobStatus.queued,
    this.statusMessage,
    this.result,
    this.errorMessage,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isRunning => status == BackgroundJobStatus.running;
  bool get isDone =>
      status == BackgroundJobStatus.completed ||
      status == BackgroundJobStatus.failed ||
      status == BackgroundJobStatus.cancelled;
}

/// Decoupled service that tracks, executes, and orchestrates background jobs.
class BackgroundProcessingService {
  final Map<String, BackgroundJob> _jobs = {};
  final StreamController<BackgroundJob> _jobUpdatesController =
      StreamController<BackgroundJob>.broadcast();

  Stream<BackgroundJob> get jobUpdates => _jobUpdatesController.stream;

  List<BackgroundJob> get activeJobs =>
      _jobs.values.where((j) => j.isRunning).toList();

  List<BackgroundJob> get allJobs => _jobs.values.toList();

  BackgroundJob? getJob(String id) => _jobs[id];

  /// Enqueues and starts a background job.
  BackgroundJob startJob({
    required String id,
    required BackgroundJobType type,
    required String title,
    required String description,
  }) {
    final job = BackgroundJob(
      id: id,
      type: type,
      title: title,
      description: description,
      status: BackgroundJobStatus.running,
    );
    _jobs[id] = job;
    _jobUpdatesController.add(job);
    return job;
  }

  /// Updates progress ratio (0.0 to 1.0) and status message.
  void updateProgress(String id, double ratio, {String? message}) {
    final job = _jobs[id];
    if (job == null || job.isDone) return;
    job.progress = ratio.clamp(0.0, 1.0);
    if (message != null) job.statusMessage = message;
    _jobUpdatesController.add(job);
  }

  /// Marks a job as completed with an optional result payload.
  void completeJob(String id, {dynamic result, String? message}) {
    final job = _jobs[id];
    if (job == null || job.isDone) return;
    job.status = BackgroundJobStatus.completed;
    job.progress = 1.0;
    job.completedAt = DateTime.now();
    job.result = result;
    if (message != null) job.statusMessage = message;
    _jobUpdatesController.add(job);
  }

  /// Marks a job as failed.
  void failJob(String id, String error) {
    final job = _jobs[id];
    if (job == null || job.isDone) return;
    job.status = BackgroundJobStatus.failed;
    job.errorMessage = error;
    job.completedAt = DateTime.now();
    _jobUpdatesController.add(job);
  }

  /// Cancels an active job.
  void cancelJob(String id) {
    final job = _jobs[id];
    if (job == null || job.isDone) return;
    job.status = BackgroundJobStatus.cancelled;
    job.completedAt = DateTime.now();
    _jobUpdatesController.add(job);
  }

  void dispose() {
    _jobUpdatesController.close();
  }
}
