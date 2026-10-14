# Lauriva Engineering Guidelines

- **Framework:** Flutter 3.13+ with Dart 3.x.
- **Architecture:** Decoupled service layer (`lib/services/`) injected into state management (`lib/providers/`).
- **UI Design System:** Dark glassmorphic styling utilizing `AppColors` tokens, `GoogleFonts.outfit`, Lucide icons, and explicit pixel/semantic constraints.
- **Performance:** Never trigger global `notifyListeners()` on high-frequency streams (such as audio decibels or sound level changes). Keep streams isolated to `ValueNotifier` or local widget state.
- **Resilience:** Preserve root error boundaries in `main.dart` and maintain auto-failover chains for LLM inference.
