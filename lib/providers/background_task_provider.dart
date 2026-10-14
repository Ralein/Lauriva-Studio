import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/toast_notification.dart';
import '../services/background_processing_service.dart';
import 'toast_provider.dart';

/// Provider managing active and recent background processing tasks.
/// Dispatches rich in-app HUD notifications when long-running jobs finish.
class BackgroundTaskProvider extends ChangeNotifier {
  final BackgroundProcessingService _service;
  final ToastProvider _toast;
  StreamSubscription<BackgroundJob>? _subscription;

  BackgroundTaskProvider({
    BackgroundProcessingService? service,
    required ToastProvider toast,
  })  : _service = service ?? BackgroundProcessingService(),
        _toast = toast {
    _subscription = _service.jobUpdates.listen(_onJobUpdate);
  }

  BackgroundProcessingService get service => _service;
  List<BackgroundJob> get activeJobs => _service.activeJobs;
  bool get hasActiveJobs => activeJobs.isNotEmpty;

  BackgroundJob? get mostRecentActiveJob =>
      activeJobs.isNotEmpty ? activeJobs.last : null;

  void _onJobUpdate(BackgroundJob job) {
    notifyListeners();

    if (job.status == BackgroundJobStatus.completed) {
      HapticFeedback.lightImpact();
      // Foreground providers (Plagiarism/Humanizer) present dedicated, contextual result HUDs
    } else if (job.status == BackgroundJobStatus.failed) {
      HapticFeedback.mediumImpact();
      _toast.showToast(
        '${job.title} failed: ${job.errorMessage ?? "Unknown error"}',
        ToastType.error,
        duration: const Duration(milliseconds: 5000),
      );
    }
  }

  void cancelJob(String id) {
    _service.cancelJob(id);
    _toast.showToast('Task cancelled.', ToastType.info);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}
