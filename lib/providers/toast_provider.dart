import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/toast_notification.dart';

/// Owns the transient toast/snackbar HUD notification queue. Standalone with
/// no dependencies so every other provider can hold a reference to it.
class ToastProvider extends ChangeNotifier {
  final List<ToastNotification> _toasts = [];

  List<ToastNotification> get toasts => List.unmodifiable(_toasts);

  void showToast(
    String message,
    ToastType type, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return;

    // Discard identical duplicate toast
    if (_toasts.isNotEmpty && _toasts.last.message == cleanMessage) {
      return;
    }

    // Keep HUD clean and minimal: always show only one active toast at a time
    _toasts.clear();

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final toast = ToastNotification(
      id: id,
      message: cleanMessage,
      type: type,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
    _toasts.add(toast);
    notifyListeners();

    Timer(duration, () {
      _toasts.removeWhere((t) => t.id == id);
      notifyListeners();
    });
  }

  void dismissToast(String id) {
    _toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}
