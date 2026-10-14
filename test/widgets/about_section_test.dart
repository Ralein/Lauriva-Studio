import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lauriva/widgets/settings/about_section.dart';
import 'package:lauriva/widgets/lauriva_logo.dart';

void main() {
  group('AboutSection Widget Tests', () {
    testWidgets('renders LaurivaLogo with outlineOnly instead of feather icon',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AboutSection(),
          ),
        ),
      );

      // Verify ABOUT header is rendered
      expect(find.text('ABOUT'), findsOneWidget);

      // Verify Lauriva row with app information
      expect(find.text('Lauriva'), findsOneWidget);
      expect(find.text('AI Writing Assistant'), findsOneWidget);

      // Verify LaurivaLogo is used with outlineOnly = true
      final logoFinder = find.byType(LaurivaLogo);
      expect(logoFinder, findsOneWidget);
      final LaurivaLogo logoWidget = tester.widget(logoFinder);
      expect(logoWidget.outlineOnly, isTrue);
      expect(logoWidget.size, equals(15));

      // Verify LucideIcons.feather is not used
      expect(find.byIcon(LucideIcons.feather), findsNothing);

      // Verify other rows still have their standard icons
      expect(find.byIcon(LucideIcons.user), findsOneWidget);
      expect(find.byIcon(LucideIcons.code), findsOneWidget);
    });
  });
}
