import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lauriva/core/platform/notification_service.dart';
import 'package:lauriva/features/background_activity/data/background_activity_repository.dart';
import 'package:lauriva/features/background_activity/domain/background_task.dart';
import 'package:lauriva/features/background_activity/domain/background_task_status.dart';
import 'package:lauriva/features/background_activity/presentation/background_activity_controller.dart';
import 'package:lauriva/features/background_activity/presentation/background_activity_screen.dart';
import 'package:lauriva/services/background_processing_service.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundTask Domain & Notification Mapping Tests', () {
    test('resolves exact notification text according to Lauriva specification', () {
      final now = DateTime.now();

      // 1. Forensic analysis stage
      final forensicTask = BackgroundTask(
        id: '1',
        title: 'Forensic AI & Plagiarism Scan',
        stage: 'Neural tokenization & perplexity scoring...',
        progress: 0.2,
        status: BackgroundTaskStatus.running,
        startedAt: now,
      );
      final forensicContent = forensicTask.resolveNotificationContent();
      expect(forensicContent.title, equals('Lauriva'));
      expect(forensicContent.body, equals('Analyzing your text…'));

      // 2. Source matching stage
      final sourceTask = BackgroundTask(
        id: '2',
        title: 'Source Literature Audit',
        stage: 'Checking for matching sources and web shingles…',
        progress: 0.6,
        status: BackgroundTaskStatus.running,
        startedAt: now,
      );
      final sourceContent = sourceTask.resolveNotificationContent();
      expect(sourceContent.title, equals('Lauriva'));
      expect(sourceContent.body, equals('Checking for matching sources…'));

      // 3. Report generation stage
      final reportTask = BackgroundTask(
        id: '3',
        title: 'Forensic Audit',
        stage: 'Preparing your report and calibration metrics…',
        progress: 0.9,
        status: BackgroundTaskStatus.running,
        startedAt: now,
      );
      final reportContent = reportTask.resolveNotificationContent();
      expect(reportContent.title, equals('Lauriva'));
      expect(reportContent.body, equals('Preparing your report…'));

      // 4. Task completed
      final completedTask = BackgroundTask(
        id: '4',
        title: 'Forensic AI & Plagiarism Scan',
        progress: 1.0,
        status: BackgroundTaskStatus.completed,
        startedAt: now,
        completedAt: now.add(const Duration(seconds: 4)),
      );
      final completedContent = completedTask.resolveNotificationContent();
      expect(completedContent.title, equals('Lauriva'));
      expect(completedContent.body, equals('Your report is ready.'));

      // 5. Task failed
      final failedTask = BackgroundTask(
        id: '5',
        title: 'Forensic AI Scan',
        status: BackgroundTaskStatus.failed,
        startedAt: now,
        errorMessage: 'Connection lost',
      );
      final failedContent = failedTask.resolveNotificationContent();
      expect(failedContent.title, equals('Lauriva'));
      expect(failedContent.body, equals('Analysis couldn\'t be completed.'));
    });

    test('serializes and deserializes BackgroundTask accurately', () {
      final now = DateTime.now();
      final task = BackgroundTask(
        id: 'task_100',
        title: 'AI Authorship Scan',
        stage: 'Analyzing document structure',
        progress: 0.75,
        status: BackgroundTaskStatus.running,
        startedAt: now,
        taskType: 'forensic',
      );

      final json = task.toJson();
      final recreated = BackgroundTask.fromJson(json);

      expect(recreated.id, equals(task.id));
      expect(recreated.title, equals(task.title));
      expect(recreated.stage, equals(task.stage));
      expect(recreated.progress, equals(0.75));
      expect(recreated.status, equals(BackgroundTaskStatus.running));
      expect(recreated.formattedProgress, equals('75%'));
    });
  });

  group('BackgroundActivityRepository Tests', () {
    late SharedPreferences prefs;
    late BackgroundActivityRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repository = BackgroundActivityRepository(prefs: prefs);
      await repository.init();
    });

    test('reconciles orphaned running tasks into interrupted on startup', () async {
      final task = BackgroundTask(
        id: 'orphaned_1',
        title: 'Interrupted Scan',
        status: BackgroundTaskStatus.running,
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await repository.saveOrUpdateTask(task);
      expect(repository.tasks.first.status, equals(BackgroundTaskStatus.running));

      // Simulate app restart / new repository instance
      final restartRepo = BackgroundActivityRepository(prefs: prefs);
      await restartRepo.init();

      expect(restartRepo.tasks.first.status, equals(BackgroundTaskStatus.interrupted));
      expect(restartRepo.tasks.first.errorMessage, contains('suspended or terminated'));
    });

    test('persists notificationsEnabled and lastActivityTime preferences', () async {
      expect(repository.notificationsEnabled, isTrue);

      await repository.setNotificationsEnabled(false);
      expect(repository.notificationsEnabled, isFalse);

      final task = BackgroundTask(
        id: 'done_1',
        title: 'Finished Task',
        status: BackgroundTaskStatus.completed,
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
      );
      await repository.saveOrUpdateTask(task);
      expect(repository.lastActivityTime, isNotNull);
    });
  });

  group('BackgroundActivityController & Screen Widget Tests', () {
    late SharedPreferences prefs;
    late BackgroundActivityRepository repository;
    late BackgroundProcessingService processingService;
    late NotificationService notificationService;
    late BackgroundActivityController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repository = BackgroundActivityRepository(prefs: prefs);
      await repository.init();

      processingService = BackgroundProcessingService();
      notificationService = NotificationService();

      controller = BackgroundActivityController(
        repository: repository,
        notificationService: notificationService,
        processingService: processingService,
      );
    });

    tearDown(() {
      controller.dispose();
      processingService.dispose();
    });

    test('observes engine updates and updates task status and progress', () async {
      expect(controller.isRunning, isFalse);
      expect(controller.currentTask, isNull);

      processingService.startJob(
        id: 'job_1',
        title: 'Deep Forensic Scan',
        description: 'Analyzing document structure...',
        type: BackgroundJobType.forensicScan,
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(controller.isRunning, isTrue);
      expect(controller.currentTask?.title, equals('Deep Forensic Scan'));

      processingService.updateProgress(
        'job_1',
        0.5,
        message: 'Checking for matching sources…',
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(controller.currentTask?.progress, equals(0.5));
      expect(controller.currentTask?.stage, equals('Checking for matching sources…'));

      processingService.completeJob('job_1');
      await Future.delayed(const Duration(milliseconds: 10));
      expect(controller.isRunning, isFalse);
      expect(controller.recentTasks.first.status, equals(BackgroundTaskStatus.completed));
    });

    testWidgets('BackgroundActivityScreen renders Idle state and platform cards', (tester) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final historyProvider = HistoryProvider(storage: storage, toast: toast);
      final themeProvider = ThemeProvider(storage: storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BackgroundActivityController>.value(
              value: controller,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(
              value: themeProvider,
            ),
            ChangeNotifierProvider<HistoryProvider>.value(
              value: historyProvider,
            ),
          ],
          child: const MaterialApp(
            home: BackgroundActivityScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Background Activity'), findsOneWidget);
      expect(find.text('All Forensic Tasks Completed'), findsOneWidget);
      expect(find.text('Background Notifications'), findsOneWidget);
      expect(find.text('Platform Execution & Capabilities'), findsOneWidget);
      expect(find.text('Android Architecture'), findsOneWidget);
      expect(find.text('iOS Architecture'), findsOneWidget);
      expect(find.text('Lauriva Interruption Recovery'), findsOneWidget);
    });

    testWidgets('BackgroundActivityScreen renders Active Running state with progress', (tester) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final historyProvider = HistoryProvider(storage: storage, toast: toast);
      final themeProvider = ThemeProvider(storage: storage);

      processingService.startJob(
        id: 'active_ui_job',
        title: 'Source Literature Audit',
        description: 'Verifying sources',
        type: BackgroundJobType.forensicScan,
      );
      processingService.updateProgress(
        'active_ui_job',
        0.65,
        message: 'Checking for matching sources…',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BackgroundActivityController>.value(
              value: controller,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(
              value: themeProvider,
            ),
            ChangeNotifierProvider<HistoryProvider>.value(
              value: historyProvider,
            ),
          ],
          child: const MaterialApp(
            home: BackgroundActivityScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Source Literature Audit'), findsAtLeastNWidgets(1));
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('Checking for matching sources…'), findsAtLeastNWidgets(1));
      expect(find.text('Cancel'), findsOneWidget);

      // Complete job and unmount to cancel repeating animation ticker
      processingService.completeJob('active_ui_job');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
