import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/background_task.dart';
import '../domain/background_task_status.dart';

/// Repository responsible for persisting background task history, tracking
/// notification preferences, and reconciling tasks interrupted by OS termination.
class BackgroundActivityRepository {
  static const String _keyTasks = 'lauriva_background_tasks_history_v1';
  static const String _keyNotifEnabled =
      'lauriva_activity_notifications_enabled';
  static const String _keyLastActivity =
      'lauriva_last_background_activity_time';
  static const int _maxRetainedTasks = 30;

  final SharedPreferences? _prefsInstance;
  SharedPreferences? _prefs;

  final List<BackgroundTask> _tasks = [];
  bool _notificationsEnabled = true;
  DateTime? _lastActivityTime;

  BackgroundActivityRepository({SharedPreferences? prefs})
    : _prefsInstance = prefs;

  List<BackgroundTask> get tasks => List.unmodifiable(_tasks);
  bool get notificationsEnabled => _notificationsEnabled;
  DateTime? get lastActivityTime => _lastActivityTime;

  /// Initializes the repository and loads saved activities from persistent storage.
  Future<void> init() async {
    _prefs = _prefsInstance ?? await SharedPreferences.getInstance();

    _notificationsEnabled = _prefs?.getBool(_keyNotifEnabled) ?? true;

    final lastActMillis = _prefs?.getInt(_keyLastActivity);
    if (lastActMillis != null) {
      _lastActivityTime = DateTime.fromMillisecondsSinceEpoch(lastActMillis);
    }

    _loadTasksFromStorage();
    await reconcileOrphanedTasks();
  }

  void _loadTasksFromStorage() {
    _tasks.clear();
    final jsonList = _prefs?.getStringList(_keyTasks) ?? [];
    for (final raw in jsonList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _tasks.add(BackgroundTask.fromJson(map));
      } catch (e) {
        debugPrint('[BackgroundActivityRepository] Error parsing task: $e');
      }
    }
  }

  Future<void> _persistTasks() async {
    if (_prefs == null) return;
    final cappedList = _tasks.take(_maxRetainedTasks).toList();
    final stringList = cappedList.map((t) => jsonEncode(t.toJson())).toList();
    await _prefs!.setStringList(_keyTasks, stringList);
  }

  /// Reconciles tasks that were running when Lauriva was terminated by the OS.
  /// Converts orphaned active tasks to 'interrupted' status so users have accurate state.
  Future<void> reconcileOrphanedTasks() async {
    bool modified = false;
    for (int i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      if (task.status == BackgroundTaskStatus.running) {
        _tasks[i] = task.copyWith(
          status: BackgroundTaskStatus.interrupted,
          completedAt: DateTime.now(),
          errorMessage: 'Task interrupted: Lauriva was suspended or terminated by the operating system.',
        );
        modified = true;
      }
    }

    if (modified) {
      await _persistTasks();
    }
  }

  /// Inserts or updates a task in the active repository.
  Future<void> saveOrUpdateTask(BackgroundTask task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _tasks[index] = task;
    } else {
      _tasks.insert(0, task);
    }

    if (task.status.isTerminal) {
      _lastActivityTime = task.completedAt ?? DateTime.now();
      if (_prefs != null) {
        await _prefs!.setInt(
          _keyLastActivity,
          _lastActivityTime!.millisecondsSinceEpoch,
        );
      }
    }

    await _persistTasks();
  }

  /// Updates user preference for OS background activity notifications.
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    if (_prefs != null) {
      await _prefs!.setBool(_keyNotifEnabled, enabled);
    }
  }

  /// Clears persisted task history.
  Future<void> clearHistory() async {
    _tasks.removeWhere((t) => t.status.isTerminal);
    await _persistTasks();
  }
}
