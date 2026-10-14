import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';

/// Execution lifecycle states for Lauriva's background activities.
enum BackgroundTaskStatus {
  running,
  completed,
  interrupted,
  failed,
  cancelled;

  /// Whether this state represents a final, non-running task state.
  bool get isTerminal =>
      this == BackgroundTaskStatus.completed ||
      this == BackgroundTaskStatus.interrupted ||
      this == BackgroundTaskStatus.failed ||
      this == BackgroundTaskStatus.cancelled;

  /// User-facing label for the status.
  String get displayName {
    switch (this) {
      case BackgroundTaskStatus.running:
        return 'Running';
      case BackgroundTaskStatus.completed:
        return 'Completed';
      case BackgroundTaskStatus.interrupted:
        return 'Interrupted';
      case BackgroundTaskStatus.failed:
        return 'Failed';
      case BackgroundTaskStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// Visual theme color associated with the status state.
  Color get color {
    switch (this) {
      case BackgroundTaskStatus.running:
        return AppColors.paletteTeal;
      case BackgroundTaskStatus.completed:
        return AppColors.success;
      case BackgroundTaskStatus.interrupted:
        return AppColors.warning;
      case BackgroundTaskStatus.failed:
        return AppColors.error;
      case BackgroundTaskStatus.cancelled:
        return AppColors.textMuted;
    }
  }

  /// Short badge string for compact chips.
  String get badgeText {
    switch (this) {
      case BackgroundTaskStatus.running:
        return 'ACTIVE';
      case BackgroundTaskStatus.completed:
        return 'SUCCESS';
      case BackgroundTaskStatus.interrupted:
        return 'INTERRUPTED';
      case BackgroundTaskStatus.failed:
        return 'FAILED';
      case BackgroundTaskStatus.cancelled:
        return 'CANCELLED';
    }
  }
}
