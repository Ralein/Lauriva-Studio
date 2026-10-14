import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/core/platform/lauriva_quick_actions.dart';
import 'package:lauriva/models/forensic/forensic_scan_mode.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/history_drawer.dart';
import 'package:lauriva/main.dart';
import 'package:lauriva/providers/background_task_provider.dart';
import 'package:lauriva/providers/humanizer_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:quick_actions_platform_interface/quick_actions_platform_interface.dart';

import '../test_mocks.dart';

class FakeQuickActionsPlatform extends QuickActionsPlatform {
  QuickActionHandler? handler;
  List<ShortcutItem> items = [];

  @override
  Future<void> initialize(QuickActionHandler handler) async {
    this.handler = handler;
  }

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) async {
    this.items = items;
  }

  @override
  Future<void> clearShortcutItems() async {
    items.clear();
  }
}

void main() {
  setupMockPlatformChannels();

  late FakeQuickActionsPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeQuickActionsPlatform();
    QuickActionsPlatform.instance = fakePlatform;
    LaurivaShortcutIntegration.instance.resetForTesting();
  });

  group('LaurivaQuickActions Service', () {
    test('defines required shortcut IDs and icon names', () {
      expect(LaurivaQuickActions.newScan, 'lauriva_new_scan');
      expect(LaurivaQuickActions.aiAuthorship, 'lauriva_ai_authorship');
      expect(LaurivaQuickActions.plagiarism, 'lauriva_plagiarism');
      expect(LaurivaQuickActions.history, 'lauriva_history');

      expect(LaurivaQuickActions.iconNewScan, 'ic_shortcut_scan');
      expect(LaurivaQuickActions.iconAiAuthorship, 'ic_shortcut_ai');
      expect(LaurivaQuickActions.iconPlagiarism, 'ic_shortcut_plagiarism');
      expect(LaurivaQuickActions.iconHistory, 'ic_shortcut_history');
    });

    test('initializes and registers four shortcuts with localized titles and icons', () {
      final quickActions = LaurivaQuickActions();
      final receivedActions = <String>[];

      quickActions.initialize(
        onAction: (action) => receivedActions.add(action),
      );

      expect(fakePlatform.items.length, 4);

      expect(fakePlatform.items[0].type, LaurivaQuickActions.newScan);
      expect(fakePlatform.items[0].localizedTitle, 'New Forensic Scan');
      expect(fakePlatform.items[0].icon, LaurivaQuickActions.iconNewScan);

      expect(fakePlatform.items[1].type, LaurivaQuickActions.aiAuthorship);
      expect(fakePlatform.items[1].localizedTitle, 'AI Authorship');
      expect(fakePlatform.items[1].icon, LaurivaQuickActions.iconAiAuthorship);

      expect(fakePlatform.items[2].type, LaurivaQuickActions.plagiarism);
      expect(fakePlatform.items[2].localizedTitle, 'Plagiarism Check');
      expect(fakePlatform.items[2].icon, LaurivaQuickActions.iconPlagiarism);

      expect(fakePlatform.items[3].type, LaurivaQuickActions.history);
      expect(fakePlatform.items[3].localizedTitle, 'Scan History');
      expect(fakePlatform.items[3].icon, LaurivaQuickActions.iconHistory);

      // Dispatching valid actions triggers the onAction callback
      fakePlatform.handler?.call(LaurivaQuickActions.newScan);
      fakePlatform.handler?.call(LaurivaQuickActions.aiAuthorship);
      fakePlatform.handler?.call(LaurivaQuickActions.plagiarism);
      fakePlatform.handler?.call(LaurivaQuickActions.history);

      expect(receivedActions, [
        LaurivaQuickActions.newScan,
        LaurivaQuickActions.aiAuthorship,
        LaurivaQuickActions.plagiarism,
        LaurivaQuickActions.history,
      ]);
    });

    test('ignores unknown shortcut types safely', () {
      final quickActions = LaurivaQuickActions();
      final receivedActions = <String>[];

      quickActions.initialize(
        onAction: (action) => receivedActions.add(action),
      );

      fakePlatform.handler?.call('unknown_action_id');
      expect(receivedActions, isEmpty);
    });
  });

  group('LaurivaShortcutIntegration Routing & Queuing', () {
    testWidgets(
      'queues shortcut when router is not ready, flushes upon attach',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        final integration = LaurivaShortcutIntegration.instance;
        integration.initialize();

        // Trigger shortcut from platform while no handler is attached (cold start)
        fakePlatform.handler?.call(LaurivaQuickActions.aiAuthorship);
        expect(integration.pendingShortcutId, LaurivaQuickActions.aiAuthorship);

        final receivedByHandler = <String>[];
        integration.attachHandler((action) {
          receivedByHandler.add(action);
        });

        // Pending action is handed off to postFrameCallback
        expect(integration.pendingShortcutId, isNull);
        await tester.pump(const Duration(milliseconds: 20));
        expect(receivedByHandler, contains(LaurivaQuickActions.aiAuthorship));
      },
    );

    test(
      'dispatches immediately when handler is already attached (running app)',
      () {
        final integration = LaurivaShortcutIntegration.instance;
        integration.initialize();

        final receivedByHandler = <String>[];
        integration.attachHandler((action) {
          receivedByHandler.add(action);
        });

        fakePlatform.handler?.call(LaurivaQuickActions.plagiarism);
        expect(receivedByHandler, [LaurivaQuickActions.plagiarism]);
        expect(integration.pendingShortcutId, isNull);
      },
    );

    test(
      'detachHandler clears active handler and clearPendingShortcut works',
      () {
        final integration = LaurivaShortcutIntegration.instance;
        final received = <String>[];
        integration.attachHandler((action) => received.add(action));
        integration.detachHandler();

        integration.dispatchShortcut(LaurivaQuickActions.history);
        expect(integration.pendingShortcutId, LaurivaQuickActions.history);
        expect(received, isEmpty);

        integration.clearPendingShortcut();
        expect(integration.pendingShortcutId, isNull);
      },
    );
  });

  group('LaurivaShortcutIntegration.navigateToFeature Destinations', () {
    testWidgets('newScan selects tab 1 and sets fullForensic scan mode', (
      tester,
    ) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final history = HistoryProvider(storage: storage, toast: toast);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
      );

      int selectedTab = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: plagiarism),
            ChangeNotifierProvider.value(value: toast),
            ChangeNotifierProvider.value(value: history),
            ChangeNotifierProvider.value(
              value: ThemeProvider(storage: storage),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      LaurivaShortcutIntegration.navigateToFeature(
                        context: context,
                        shortcutId: LaurivaQuickActions.newScan,
                        onSelectTab: (idx) => selectedTab = idx,
                      );
                    },
                    child: const Text('Trigger New Scan'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger New Scan'));
      await tester.pumpAndSettle();

      expect(selectedTab, 1);
      expect(plagiarism.scanMode, ForensicScanMode.fullForensic);
    });

    testWidgets('aiAuthorship selects tab 1 and sets forensic scan mode', (
      tester,
    ) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final history = HistoryProvider(storage: storage, toast: toast);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
      );

      int selectedTab = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: plagiarism),
            ChangeNotifierProvider.value(value: toast),
            ChangeNotifierProvider.value(value: history),
            ChangeNotifierProvider.value(
              value: ThemeProvider(storage: storage),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      LaurivaShortcutIntegration.navigateToFeature(
                        context: context,
                        shortcutId: LaurivaQuickActions.aiAuthorship,
                        onSelectTab: (idx) => selectedTab = idx,
                      );
                    },
                    child: const Text('Trigger AI Authorship'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger AI Authorship'));
      await tester.pumpAndSettle();

      expect(selectedTab, 1);
      expect(plagiarism.scanMode, ForensicScanMode.forensic);
    });

    testWidgets('plagiarism selects tab 1 and sets sourceScan scan mode', (
      tester,
    ) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final history = HistoryProvider(storage: storage, toast: toast);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
      );

      int selectedTab = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: plagiarism),
            ChangeNotifierProvider.value(value: toast),
            ChangeNotifierProvider.value(value: history),
            ChangeNotifierProvider.value(
              value: ThemeProvider(storage: storage),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      LaurivaShortcutIntegration.navigateToFeature(
                        context: context,
                        shortcutId: LaurivaQuickActions.plagiarism,
                        onSelectTab: (idx) => selectedTab = idx,
                      );
                    },
                    child: const Text('Trigger Plagiarism Check'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Plagiarism Check'));
      await tester.pumpAndSettle();

      expect(selectedTab, 1);
      expect(plagiarism.scanMode, ForensicScanMode.sourceScan);
    });

    testWidgets('history opens HistoryModalContent bottom sheet', (
      tester,
    ) async {
      int selectedTab = 0;
      final storage = StorageService();
      final toast = ToastProvider();
      final history = HistoryProvider(storage: storage, toast: toast);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: plagiarism),
            ChangeNotifierProvider.value(value: toast),
            ChangeNotifierProvider.value(value: history),
            ChangeNotifierProvider.value(
              value: ThemeProvider(storage: storage),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      LaurivaShortcutIntegration.navigateToFeature(
                        context: context,
                        shortcutId: LaurivaQuickActions.history,
                        onSelectTab: (idx) => selectedTab = idx,
                      );
                    },
                    child: const Text('Trigger History'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger History'));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryModalContent), findsOneWidget);
      expect(selectedTab, equals(0));
    });

    testWidgets('pops open subroute before navigating', (tester) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final history = HistoryProvider(storage: storage, toast: toast);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
      );

      int selectedTab = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: plagiarism),
            ChangeNotifierProvider.value(value: toast),
            ChangeNotifierProvider.value(value: history),
            ChangeNotifierProvider.value(
              value: ThemeProvider(storage: storage),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (subCtx) => Scaffold(
                            appBar: AppBar(title: const Text('Subpage')),
                            body: ElevatedButton(
                              onPressed: () {
                                LaurivaShortcutIntegration.navigateToFeature(
                                  context: subCtx,
                                  shortcutId: LaurivaQuickActions.newScan,
                                  onSelectTab: (idx) => selectedTab = idx,
                                );
                              },
                              child: const Text('From Subpage'),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Subpage'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Open subpage
      await tester.tap(find.text('Open Subpage'));
      await tester.pumpAndSettle();
      expect(find.text('Subpage'), findsOneWidget);

      // Trigger shortcut from subpage
      await tester.tap(find.text('From Subpage'));
      await tester.pumpAndSettle();

      // Subpage is popped and destination tab is selected
      expect(find.text('Subpage'), findsNothing);
      expect(selectedTab, 1);
      expect(plagiarism.scanMode, ForensicScanMode.fullForensic);
    });
  });

  group('LaurivaHomeScreen Quick Action Integration', () {
    testWidgets('switching tabs via quick actions inside LaurivaHomeScreen', (
      tester,
    ) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final backgroundTask = BackgroundTaskProvider(toast: toast);
      final history = HistoryProvider(storage: storage, toast: toast);
      final llmSettings = LlmSettingsProvider(storage: storage);
      final speech = SpeechProvider(storage: storage, toast: toast);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
        llmSettings: llmSettings,
        backgroundTask: backgroundTask,
      );
      final humanizer = HumanizerProvider(
        storage: storage,
        toast: toast,
        history: history,
        llmSettings: llmSettings,
        plagiarism: plagiarism,
        speech: speech,
        backgroundTask: backgroundTask,
      );
      final studio = StudioProvider(
        storage: storage,
        speech: speech,
        llmSettings: llmSettings,
        history: history,
        toast: toast,
        plagiarism: plagiarism,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: toast),
            ChangeNotifierProvider.value(value: backgroundTask),
            ChangeNotifierProvider.value(
              value: ThemeProvider(storage: storage),
            ),
            ChangeNotifierProvider.value(value: history),
            ChangeNotifierProvider.value(value: llmSettings),
            ChangeNotifierProvider.value(value: speech),
            ChangeNotifierProvider.value(value: plagiarism),
            ChangeNotifierProvider.value(value: studio),
            ChangeNotifierProvider.value(value: humanizer),
          ],
          child: MaterialApp(
            navigatorKey: laurivaNavigatorKey,
            home: const LaurivaHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially on Studio tab (0)
      IndexedStack indexedStack = tester.widget<IndexedStack>(
        find.byType(IndexedStack),
      );
      expect(indexedStack.index, 0);

      // Dispatch 'lauriva_ai_authorship'
      LaurivaShortcutIntegration.instance.dispatchShortcut(
        LaurivaQuickActions.aiAuthorship,
      );
      await tester.pumpAndSettle();

      // Now on Forensics tab (1) with forensic scan mode
      indexedStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(indexedStack.index, 1);
      expect(plagiarism.scanMode, ForensicScanMode.forensic);

      // Dispatch 'lauriva_history'
      LaurivaShortcutIntegration.instance.dispatchShortcut(
        LaurivaQuickActions.history,
      );
      await tester.pumpAndSettle();

      // History sheet is presented
      expect(find.byType(HistoryModalContent), findsOneWidget);
    });
  });
}
