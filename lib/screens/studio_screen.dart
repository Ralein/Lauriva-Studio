import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/header_bar.dart';
import '../widgets/zone1_input.dart';
import '../widgets/zone2_action_chips.dart';
import '../widgets/zone3_output.dart';

/// Studio Screen: Core writing assistant with live dictation, tone shapers,
/// language translation, and speech studio.
class StudioScreen extends StatelessWidget {
  final VoidCallback? onNavigateToDetector;
  final VoidCallback? onNavigateToHumanizer;
  final VoidCallback? onNavigateToSettings;

  const StudioScreen({
    super.key,
    this.onNavigateToDetector,
    this.onNavigateToHumanizer,
    this.onNavigateToSettings,
  });

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 1320 : 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: Brand, Title, Status & Settings
                  HeaderBar(
                    onSettingsPressed: onNavigateToSettings,
                  ),
                  const SizedBox(height: 18),

                  // Dual-pane layout on wide screens (> 900px), stacked on mobile
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Zone 1 Input Area + Zone 2 Action Chips
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Zone1Input(),
                              const SizedBox(height: 16),
                              Zone2ActionChips(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        // Right Pane: Zone 3 Output Area
                        Expanded(child: Zone3Output()),
                      ],
                    )
                  else ...[
                    // ZONE 1: Input Area (Multi-line + STT Mic button + metrics)
                    Zone1Input(),
                    const SizedBox(height: 16),

                    // ZONE 2: Middle Action Bar (Tone & Transform Chips + Language Selector)
                    Zone2ActionChips(),
                    const SizedBox(height: 16),

                    // ZONE 3: Output Area (Result + TTS Player + Revision Diff)
                    Zone3Output(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
