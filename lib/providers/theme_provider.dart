import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

/// Owns the app-wide theme preference ('system' / 'light' / 'dark').
class ThemeProvider extends ChangeNotifier {
  final StorageService _storageService;
  String _themeMode;

  ThemeProvider({required StorageService storage})
      : _storageService = storage,
        _themeMode = storage.getThemeMode();

  String get themeMode => _themeMode;

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    await _storageService.setThemeMode(mode);
    notifyListeners();
  }
}
