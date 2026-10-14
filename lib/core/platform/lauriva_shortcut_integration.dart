import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/forensic/forensic_scan_mode.dart';
import '../../providers/plagiarism_provider.dart';
import '../../widgets/history_drawer.dart';
import 'lauriva_quick_actions.dart';

/// Connects native launcher shortcuts to Lauriva's navigation layer and state.
///
/// Queues shortcut invocations if received before the UI/router is mounted,
/// and executes them once navigation is ready.
class LaurivaShortcutIntegration {
  LaurivaShortcutIntegration([
    this.openExistingFeature,
    LaurivaQuickActions? quickActions,
  ]) : _quickActions = quickActions ?? LaurivaQuickActions();

  final void Function(String shortcutId)? openExistingFeature;
  final LaurivaQuickActions _quickActions;

  static LaurivaShortcutIntegration? _instance;
  static LaurivaShortcutIntegration get instance =>
      _instance ??= LaurivaShortcutIntegration();

  @visibleForTesting
  static void setMockInstance(LaurivaShortcutIntegration mock) {
    _instance = mock;
  }

  void Function(String shortcutId)? _activeHandler;
  String? _pendingShortcutId;
  bool _isInitialized = false;

  String? get pendingShortcutId => _pendingShortcutId;
  bool get isInitialized => _isInitialized;

  /// Registers native shortcut items and listens for OS launcher actions.
  /// If [onAction] is provided, it is invoked on each shortcut action.
  void initialize({void Function(String shortcutId)? onAction}) {
    if (_isInitialized) return;
    _isInitialized = true;

    _quickActions.initialize(
      onAction: (shortcutId) {
        if (onAction != null) {
          onAction(shortcutId);
        } else if (openExistingFeature != null) {
          openExistingFeature!(shortcutId);
        } else {
          dispatchShortcut(shortcutId);
        }
      },
    );
  }

  /// Dispatches the given [shortcutId] to the active handler or queues it
  /// if the UI/router is not yet mounted.
  void dispatchShortcut(String shortcutId) {
    if (_activeHandler != null) {
      _activeHandler!(shortcutId);
    } else {
      _pendingShortcutId = shortcutId;
    }
  }

  /// Attaches the navigation handler (typically from `LaurivaHomeScreenState`).
  /// If a shortcut action arrived prior to mounting, it is immediately flushed.
  void attachHandler(void Function(String shortcutId) handler) {
    _activeHandler = handler;
    if (_pendingShortcutId != null) {
      final queued = _pendingShortcutId!;
      _pendingShortcutId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_activeHandler != null) {
          _activeHandler!(queued);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  /// Detaches the navigation handler when the hosting widget is disposed.
  void detachHandler() {
    _activeHandler = null;
  }

  /// Clears any pending queued action.
  void clearPendingShortcut() {
    _pendingShortcutId = null;
  }

  /// Navigates to the appropriate existing Lauriva screen or feature for the given [shortcutId].
  ///
  /// Reuses existing screens, state, and forensic scan modes:
  /// - [LaurivaQuickActions.newScan]: Forensics tab, [ForensicScanMode.fullForensic]
  /// - [LaurivaQuickActions.aiAuthorship]: Forensics tab, [ForensicScanMode.forensic]
  /// - [LaurivaQuickActions.plagiarism]: Forensics tab, [ForensicScanMode.sourceScan]
  /// - [LaurivaQuickActions.history]: Opens existing Scan History modal
  static void navigateToFeature({
    required BuildContext context,
    required String shortcutId,
    required void Function(int tabIndex) onSelectTab,
  }) {
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }

    switch (shortcutId) {
      case LaurivaQuickActions.newScan:
        onSelectTab(1);
        try {
          context.read<PlagiarismProvider>().setScanMode(
            ForensicScanMode.fullForensic,
          );
        } catch (_) {}
        break;

      case LaurivaQuickActions.aiAuthorship:
        onSelectTab(1);
        try {
          context.read<PlagiarismProvider>().setScanMode(
            ForensicScanMode.forensic,
          );
        } catch (_) {}
        break;

      case LaurivaQuickActions.plagiarism:
        onSelectTab(1);
        try {
          context.read<PlagiarismProvider>().setScanMode(
            ForensicScanMode.sourceScan,
          );
        } catch (_) {}
        break;

      case LaurivaQuickActions.history:
        showHistoryModal(context);
        break;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _pendingShortcutId = null;
    _activeHandler = null;
    _isInitialized = false;
  }
}
