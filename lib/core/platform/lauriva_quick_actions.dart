import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../utils/crash_guard.dart';

export 'lauriva_shortcut_integration.dart';

/// Native launcher shortcuts for Lauriva.
///
/// This service only dispatches shortcut IDs. Existing feature screens,
/// controllers, repositories and forensic engines remain unchanged.
class LaurivaQuickActions {
  LaurivaQuickActions({QuickActions? quickActions})
    : _quickActions = quickActions ?? const QuickActions();

  final QuickActions _quickActions;

  static const newScan = 'lauriva_new_scan';
  static const aiAuthorship = 'lauriva_ai_authorship';
  static const plagiarism = 'lauriva_plagiarism';
  static const history = 'lauriva_history';

  static const iconNewScan = 'ic_shortcut_scan';
  static const iconAiAuthorship = 'ic_shortcut_ai';
  static const iconPlagiarism = 'ic_shortcut_plagiarism';
  static const iconHistory = 'ic_shortcut_history';

  void initialize({required ValueChanged<String> onAction}) {
    CrashGuard.run(() {
      _quickActions.initialize((String shortcutType) {
        switch (shortcutType) {
          case newScan:
          case aiAuthorship:
          case plagiarism:
          case history:
            onAction(shortcutType);
            break;
        }
      });

      _quickActions.setShortcutItems(const <ShortcutItem>[
        ShortcutItem(
          type: newScan,
          localizedTitle: 'New Forensic Scan',
          icon: iconNewScan,
        ),
        ShortcutItem(
          type: aiAuthorship,
          localizedTitle: 'AI Authorship',
          icon: iconAiAuthorship,
        ),
        ShortcutItem(
          type: plagiarism,
          localizedTitle: 'Plagiarism Check',
          icon: iconPlagiarism,
        ),
        ShortcutItem(
          type: history,
          localizedTitle: 'Scan History',
          icon: iconHistory,
        ),
      ]);
    }, tag: 'LaurivaQuickActions');
  }
}
