import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/platform/notification_service.dart';
import '../../../services/background_processing_service.dart';
import '../data/background_activity_repository.dart';
import '../domain/background_task.dart';
import '../domain/background_task_status.dart';

/// Presentation controller orchestrating Lauriva's background activity dashboard,
/// OS notification dispatch, and state synchronization with the forensic engine.
class BackgroundActivityController extends ChangeNotifier {
  final BackgroundActivityRepository _repository;
  final NotificationService _notificationService;
  final BackgroundProcessingService _processingService;

  StreamSubscription<BackgroundJob>? _jobSubscription;
  BackgroundTask? _currentTask;
  bool _hasNotificationPermission = false;

  BackgroundActivityController({
    required BackgroundActivityRepository repository,
    required NotificationService notificationService,
    required BackgroundProcessingService processingService,
  }) : _repository = repository,
       _notificationService = notificationService,
       _processingService = processingService {
    _jobSubscription = _processingService.jobUpdates.listen(_onEngineJobUpdate);
    _checkInitialPermissions();
  }

  BackgroundTask? get currentTask => _currentTask;
  bool get isRunning =>
      _currentTask != null && !_currentTask!.status.isTerminal;
  List<BackgroundTask> get recentTasks => _repository.tasks;
  bool get notificationsEnabled => _repository.notificationsEnabled;
  DateTime? get lastActivityTime => _repository.lastActivityTime;
  bool get hasNotificationPermission => _hasNotificationPermission;

  Future<void> _checkInitialPermissions() async {
    _hasNotificationPermission = await _notificationService
        .isPermissionGranted();
    notifyListeners();
  }

  /// Handles incoming job lifecycle updates emitted by Lauriva's forensic engine.
  void _onEngineJobUpdate(BackgroundJob job) {
    final status = _mapJobStatus(job.status);

    final task = BackgroundTask(
      id: job.id,
      title: job.title,
      stage: job.statusMessage ?? job.description,
      progress: job.progress,
      status: status,
      startedAt: job.startedAt,
      completedAt: job.completedAt,
      errorMessage: job.errorMessage,
      taskType: job.type.name,
    );

    if (status.isTerminal) {
      _currentTask = null;
    } else {
      _currentTask = task;
    }

    _repository.saveOrUpdateTask(task);
    _dispatchNotification(task);
    notifyListeners();
  }

  BackgroundTaskStatus _mapJobStatus(BackgroundJobStatus status) {
    switch (status) {
      case BackgroundJobStatus.queued:
      case BackgroundJobStatus.running:
        return BackgroundTaskStatus.running;
      case BackgroundJobStatus.completed:
        return BackgroundTaskStatus.completed;
      case BackgroundJobStatus.failed:
        return BackgroundTaskStatus.failed;
      case BackgroundJobStatus.cancelled:
        return BackgroundTaskStatus.cancelled;
    }
  }

  /// Dispatches state-aware operating-system notifications according to user preference.
  Future<void> _dispatchNotification(BackgroundTask task) async {
    if (!_repository.notificationsEnabled) return;

    final content = task.resolveNotificationContent();

    switch (task.status) {
      case BackgroundTaskStatus.running:
        await _notificationService.showTaskProgress(
          id: task.id,
          title: content.title,
          message: content.body,
          progress: task.progress,
        );
        break;
      case BackgroundTaskStatus.completed:
        await _notificationService.showTaskCompleted(
          id: task.id,
          title: content.title,
          message: content.body,
          payload: 'task_${task.id}',
        );
        break;
      case BackgroundTaskStatus.failed:
      case BackgroundTaskStatus.interrupted:
        await _notificationService.showTaskFailed(
          id: task.id,
          title: content.title,
          message: content.body,
          payload: 'task_${task.id}',
        );
        break;
      case BackgroundTaskStatus.cancelled:
        await _notificationService.cancelTaskNotification(task.id);
        break;
    }
  }

  /// Toggles activity notifications on or off.
  Future<void> toggleNotifications(bool enabled) async {
    await _repository.setNotificationsEnabled(enabled);
    if (!enabled) {
      await _notificationService.cancelAll();
    }
    notifyListeners();
  }

  /// Prompts the OS for notification permissions.
  Future<void> requestNotificationPermission() async {
    final granted = await _notificationService.requestPermission();
    _hasNotificationPermission = granted;
    notifyListeners();
  }

  /// Cancels the actively running background task.
  void cancelCurrentTask() {
    if (_currentTask != null) {
      _processingService.cancelJob(_currentTask!.id);
      _currentTask = null;
      notifyListeners();
    }
  }

  /// Clears completed activity history.
  Future<void> clearHistory() async {
    await _repository.clearHistory();
    notifyListeners();
  }

  /// Simulates a multi-stage background forensic audit for user inspection and testing.
  Future<void> simulateTestTask() async {
    if (isRunning) return;

    final testId = 'sim_${DateTime.now().millisecondsSinceEpoch}';
    _processingService.startJob(
      id: testId,
      title: 'Forensic AI & Plagiarism Scan',
      description:
          'Analyzing document structure, stylometry, and perplexity...',
      type: BackgroundJobType.forensicScan,
    );

    // Stage 1: Forensic analysis (25%)
    await Future.delayed(const Duration(milliseconds: 1000));
    _processingService.updateProgress(
      testId,
      0.25,
      message: 'Analyzing your text…',
    );

    // Stage 2: Source matching (65%)
    await Future.delayed(const Duration(milliseconds: 1400));
    _processingService.updateProgress(
      testId,
      0.65,
      message: 'Checking for matching sources…',
    );

    // Stage 3: Report generation (90%)
    await Future.delayed(const Duration(milliseconds: 1200));
    _processingService.updateProgress(
      testId,
      0.90,
      message: 'Preparing your report…',
    );

    // Completion (100%)
    await Future.delayed(const Duration(milliseconds: 1000));
    _processingService.completeJob(testId, message: 'Your report is ready.');
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    super.dispose();
  }
}
