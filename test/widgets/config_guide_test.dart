import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/screens/settings_screen.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/header_bar.dart';
import 'package:lauriva/widgets/settings/interactive_config_guide_modal.dart';
import '../test_mocks.dart';

/// The horizontal provider chooser inside the guide sheet.
Finder chooserScrollable() => find
    .descendant(
      of: find.byType(InteractiveConfigGuideModal),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal),
    )
    .first;

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  setUp(() {
    clearMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsScreen top header renders Config Guide info button and opens modal', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService();
    await storage.init();
    final toast = ToastProvider();
    final history = HistoryProvider(storage: storage, toast: toast);
    final llmSettings = LlmSettingsProvider(storage: storage);
    final theme = ThemeProvider(storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ToastProvider>.value(value: toast),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ChangeNotifierProvider<LlmSettingsProvider>.value(value: llmSettings),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify top header has Settings title and Config Guide button
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(HeaderBar),
        matching: find.byIcon(LucideIcons.compass),
      ),
      findsOneWidget,
    );

    // Tap Config Guide button
    await tester.tap(find.text('Guide'));
    await tester.pumpAndSettle();

    // Verify InteractiveConfigGuideModal opened
    expect(find.byType(InteractiveConfigGuideModal), findsOneWidget);
    expect(find.text('Provider Guide'), findsOneWidget);

    // Verify provider chooser exists
    expect(find.text('Groq'), findsWidgets);
    expect(find.text('Google Gemini'), findsWidgets);
    expect(find.text('OpenRouter'), findsWidgets);

    // Verify stepper and actions for default selected provider (Groq)
    expect(find.text('Open the Groq Console'), findsOneWidget);
    expect(find.text('Create the key'), findsOneWidget);
    expect(find.text('Open Groq'), findsOneWidget);
    expect(find.text('PASTE YOUR KEY'), findsOneWidget);
    expect(find.text('Check & Save Key'), findsOneWidget);

    // Switch to Google Gemini tab
    final geminiTab = find.descendant(
      of: find.byType(InteractiveConfigGuideModal),
      matching: find.text('Google Gemini'),
    );
    await tester.tap(geminiTab.first);
    await tester.pumpAndSettle();

    expect(find.text('Open Google AI Studio'), findsOneWidget); // step title
    expect(find.text('Open Google Gemini'), findsOneWidget); // action button

    final pollinationsTab = find.descendant(
      of: find.byType(InteractiveConfigGuideModal),
      matching: find.text('Pollinations.ai'),
    );
    await tester.scrollUntilVisible(
      pollinationsTab,
      120,
      scrollable: chooserScrollable(),
    );
    expect(pollinationsTab, findsOneWidget);
    await tester.tap(pollinationsTab);
    await tester.pumpAndSettle();

    // Verify Zero Config instructions
    expect(find.text('Use Pollinations.ai'), findsOneWidget);
  });

  testWidgets('Config guide has no overflow at textScaler 1.3 and shows all providers', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final storage = StorageService();
    await storage.init();
    final toast = ToastProvider();
    final llmSettings = LlmSettingsProvider(storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ToastProvider>.value(value: toast),
          ChangeNotifierProvider<LlmSettingsProvider>.value(value: llmSettings),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: InteractiveConfigGuideModal())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every provider the app supports must be reachable in the chooser.
    final chooser = chooserScrollable();
    for (final p in LlmProvider.allProviders) {
      final chip = find.descendant(of: chooser, matching: find.text(p.name));
      await tester.scrollUntilVisible(chip, 120, scrollable: chooser);
      expect(chip, findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Something not working?'),
      200,
      scrollable: find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Something not working?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
