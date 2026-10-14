import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/screens/splash_screen.dart';

void main() {
  testWidgets('SplashScreen renders without gradient and completes sequence', (tester) async {
    bool finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          autoDismiss: true,
          entranceDuration: const Duration(milliseconds: 100),
          holdDuration: const Duration(milliseconds: 50),
          exitDuration: const Duration(milliseconds: 100),
          onFinish: () => finished = true,
        ),
      ),
    );

    // Verify brand name exists and tagline is removed for minimalist styling
    expect(find.text('Lauriva'), findsOneWidget);
    expect(find.text('AI WRITING ASSISTANT & STUDIO'), findsNothing);

    // Verify no RadialGradient is present
    final containerFinder = find.byType(Container);
    for (final element in containerFinder.evaluate()) {
      final container = element.widget as Container;
      final decoration = container.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.gradient, isNull);
      }
    }

    // Step through the entrance, hold, and exit animations
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
  });

  testWidgets('SplashScreen dismisses immediately on tap', (tester) async {
    bool finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          autoDismiss: false,
          onFinish: () => finished = true,
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    expect(finished, isTrue);
  });
}
