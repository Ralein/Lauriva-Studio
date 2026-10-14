import 'package:flutter/foundation.dart';
import '../models/history_record.dart';
import '../models/toast_notification.dart';
import '../services/storage_service.dart';
import 'toast_provider.dart';

/// Owns the persisted transformation history list. Notifies listeners
/// precisely when the list changes, rather than piggybacking on an
/// unrelated provider's blanket notify.
class HistoryProvider extends ChangeNotifier {
  final StorageService _storageService;
  final ToastProvider _toast;

  HistoryProvider({
    required StorageService storage,
    required ToastProvider toast,
  })  : _storageService = storage,
        _toast = toast;

  /// Raw string history or parsed outputText strings for backward compatibility.
  List<String> get history => _storageService.getHistory();

  /// Structured transformation records with rich studio metadata.
  List<HistoryRecord> get structuredHistory => _storageService.getStructuredHistory();

  Future<void> addHistoryRecord(HistoryRecord record) async {
    await _storageService.addHistoryRecord(record);
    notifyListeners();
  }

  Future<void> addHistoryItem(String item) async {
    await _storageService.addHistoryItem(item);
    notifyListeners();
  }

  Future<void> removeHistoryItem(int index) async {
    await _storageService.removeHistoryItem(index);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _storageService.clearHistory();
    notifyListeners();
    _toast.showToast('History cleared', ToastType.info);
  }
}
