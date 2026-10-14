import 'package:flutter/material.dart';

enum ToastType { success, error, info }

class ToastNotification {
  final String id;
  final String message;
  final ToastType type;
  final DateTime timestamp;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  ToastNotification({
    required this.id,
    required this.message,
    required this.type,
    DateTime? timestamp,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(milliseconds: 3200),
  }) : timestamp = timestamp ?? DateTime.now();
}
