import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/constants/app_colors.dart';
import 'package:lauriva/core/platform/notification_service.dart';
import 'package:lauriva/screens/onboarding_screen.dart';
import 'package:lauriva/widgets/lauriva_logo.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('OnboardingScreen displays 3 slides with correct copy and icons', (WidgetTester tester) async {
    bool completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.bgCenter,
        ),
        home: OnboardingScreen(
          onComplete: () {
            completed = true;
          },
        ),
      ),
    );

    // Slide 1
    expect(find.text('Lauriva'), findsOneWidget);
    expect(find.byType(LaurivaLogo), findsOneWidget);
    expect(find.text('Check originality'), findsOneWidget);
    expect(find.byIcon(LucideIcons.searchCheck), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // Tap Continue -> Slide 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Humanize with care'), findsOneWidget);
    expect(find.byIcon(LucideIcons.eraser), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    // Tap Continue -> Slide 3
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Private by design'), findsOneWidget);
    expect(find.byIcon(LucideIcons.shieldCheck), findsOneWidget);
    expect(find.text('Skip'), findsNothing); // Skip hidden on last slide
    expect(find.text('Get started'), findsOneWidget);

    // Tap Get started -> onComplete called
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });

  testWidgets('OnboardingScreen with animateFromSplash starts centered and completes', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.bgCenter,
        ),
        home: const OnboardingScreen(
          animateFromSplash: true,
        ),
      ),
    );

    // Initial frame: Splash entrance
    expect(find.text('Lauriva'), findsOneWidget);
    expect(find.byType(LaurivaLogo), findsOneWidget);

    // Advance through the 3.2-second sequence
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // After animation completes, Onboarding Slide 1 content is visible
    expect(find.text('Check originality'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('OnboardingScreen resumes from the splash lockup after a splash hand-off', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: AppColors.bgCenter),
        home: const OnboardingScreen(animateFromSplash: true, splashAlreadyShown: true),
      ),
    );

    // Lockup is already fully visible (no converge replay) and content is hidden.
    expect(find.text('Lauriva'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Lauriva'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1.0);

    await tester.pumpAndSettle();
    expect(find.text('Check originality'), findsOneWidget);
  });

  testWidgets('Prompts user to enable notification after onboarding when not yet granted', (WidgetTester tester) async {
    bool completed = false;
    final fakeNotif = _TestNotificationService(granted: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: AppColors.bgCenter),
        home: OnboardingScreen(
          notificationService: fakeNotif,
          onComplete: () {
            completed = true;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Skip onboarding
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Notification permission prompt is displayed
    expect(find.text('Enable Notifications'), findsNWidgets(2)); // Title and button
    expect(find.text('Maybe Later'), findsOneWidget);
    expect(completed, isFalse);

    // Tap Maybe Later
    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(fakeNotif.requested, isFalse);
  });

  testWidgets('User can grant notification permission from post-onboarding prompt', (WidgetTester tester) async {
    bool completed = false;
    final fakeNotif = _TestNotificationService(granted: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: AppColors.bgCenter),
        home: OnboardingScreen(
          notificationService: fakeNotif,
          onComplete: () {
            completed = true;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Skip to trigger prompt
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Tap Enable Notifications button
    final enableButton = find.widgetWithText(FilledButton, 'Enable Notifications');
    expect(enableButton, findsOneWidget);
    await tester.tap(enableButton);
    await tester.pumpAndSettle();

    expect(fakeNotif.requested, isTrue);
    expect(completed, isTrue);
  });
}

class _TestNotificationService implements NotificationService {
  bool granted;
  bool requested = false;

  _TestNotificationService({this.granted = false});

  @override
  Future<bool> isPermissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requested = true;
    granted = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

