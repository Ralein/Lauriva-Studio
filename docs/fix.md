# Lauriva App - Functional Inspection Report & Fix List

**Inspection Date:** 2026-09-22  
**Target Device:** Samsung Galaxy S24 Ultra (`SM S928B` / Android 16 API 36)  
**App ID:** `com.Lauriva.app.Lauriva`  

---

## Executive Summary
A live functional and UX audit was performed on the connected physical Android device (`RZCX10ZK5WB`). While core on-device stylometrics, animations, and the glassmorphic dark design system operate smoothly, several critical UX, layout, navigation, and model-filtering issues were identified that impact day-to-day usability.

---

## Detailed Findings & Fix Tasks

### 1. Bottom Navigation Bar Content Occlusion
- **Severity:** High (UI / Usability)
- **Affected Files:**
  - `lib/screens/studio_screen.dart` (line 27)
  - `lib/screens/detector_screen.dart` (line 73)
  - `lib/screens/humanizer_screen.dart` (line 151)
  - `lib/screens/history_screen.dart` (line 70)
  - `lib/screens/settings_screen.dart` (line 182)
- **Diagnosis:** All screens use a fixed bottom padding of `96dp` (or `120dp` on Settings) inside their `SingleChildScrollView`. However, `FloatingGlassNavBar` has an intrinsic height of ~68dp, plus a bottom margin of `10dp + bottomInset` (~34dp on Android gesture/button navigation), requiring ~118–130dp of total clearance.
- **Observed Bug:** The bottom-most interactive controls are partially or completely obscured behind the floating glass navigation bar:
  - **AI Detector:** "Sentence Details (9)" expander and the primary "Make Text Natural / Copy Report" action footer are clipped.
  - **Studio:** The TTS Player bar and "Export / Copy / Use as Input" action row are partially hidden when scrolled down.
  - **Settings:** The "About" section and version info are truncated at the bottom.
- **Recommended Fix:** Increase scroll view bottom padding to `EdgeInsets.fromLTRB(16, 16, 16, 136 + MediaQuery.of(context).padding.bottom)` across all screens, or dynamically compute safe clearance above the nav bar.

---

### 2. Floating Nav Bar Displaced by Soft Keyboard
- **Severity:** High (UX / Layout Breakdown)
- **Affected Files:**
  - `lib/main.dart` (`LaurivaHomeScreen`)
  - `lib/widgets/nav_bar.dart`
- **Diagnosis:** The `Scaffold` in `LaurivaHomeScreen` uses the default `resizeToAvoidBottomInset: true`. When the user focuses any `TextField` (in Studio, Detector, or Humanizer), the keyboard opens (~700px height).
- **Observed Bug:** The `FloatingGlassNavBar`, which is placed in an `Align(alignment: Alignment.bottomCenter)`, is pushed upwards by the window insets directly into the middle of the screen above the keyboard, obscuring the action chips, input text, and output containers.
- **Recommended Fix:** Conditionally hide or animate out `FloatingGlassNavBar` when the virtual keyboard is active:
  ```dart
  final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 100;
  if (!isKeyboardOpen)
    Align(
      alignment: Alignment.bottomCenter,
      child: FloatingGlassNavBar(...),
    ),
  ```

---

### 3. Lack of Background Tap to Dismiss Soft Keyboard (Unfocus)
- **Severity:** Medium (Usability)
- **Affected Files:**
  - `lib/main.dart` / Root Shell
  - `lib/screens/studio_screen.dart`
  - `lib/screens/detector_screen.dart`
  - `lib/screens/humanizer_screen.dart`
- **Diagnosis:** There is no `FocusManager.instance.primaryFocus?.unfocus()` or `GestureDetector` on the background canvas.
- **Observed Bug:** Once a text field is tapped, the keyboard remains up indefinitely. Tapping outside on the empty canvas, headers, or scrolling does not dismiss the keyboard.
- **Recommended Fix:** Wrap `LaurivaHomeScreen` body in a `GestureDetector`:
  ```dart
  GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: ...,
  )
  ```

---

### 4. Back Button / Gesture Instantly Terminates App (Missing PopScope)
- **Severity:** High (Navigation / Retention)
- **Affected Files:**
  - `lib/main.dart` (`LaurivaHomeScreen`)
- **Diagnosis:** `LaurivaHomeScreen` does not implement `PopScope` (or `WillPopScope`).
- **Observed Bug:** If the user is on the **AI Detector**, **Humanizer**, or **Settings** tab and presses the Android system Back button (or performs an edge-swipe back gesture), the app immediately exits/minimizes to the Android launcher instead of returning to the initial **Studio** tab.
- **Recommended Fix:** Wrap `LaurivaHomeScreen` in a `PopScope`:
  ```dart
  PopScope(
    canPop: _currentIndex == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _currentIndex != 0) {
        setState(() => _currentIndex = 0);
      }
    },
    child: Scaffold(...),
  )
  ```

---

### 5. Non-Chat Models (Whisper & Guardrails) Visible in Groq Model Catalog
- **Severity:** Medium (Functional Error)
- **Affected Files:**
  - `lib/services/llm_service.dart` (`fetchLiveModels`)
  - `lib/widgets/model_picker_modal.dart`
- **Diagnosis:** `fetchLiveModels` calls Groq's `/models` endpoint and parses every returned model ID without filtering out audio/speech-to-text or moderation models.
- **Observed Bug:** Models like `whisper-large-v3`, `whisper-large-v3-turbo` (audio transcription) and `meta-llama/llama-prompt-guard-2-22m` appear in the model picker. If a user selects Whisper as the active LLM, triggering any text transformation or humanization immediately fails with an HTTP 400 error (`Model not supported for chat completions`).
- **Recommended Fix:** In `LlmService.fetchLiveModels`, filter out non-generative / speech / guard models:
  ```dart
  final lowerId = id.toLowerCase();
  if (lowerId.contains('whisper') ||
      lowerId.contains('prompt-guard') ||
      lowerId.contains('safeguard') ||
      lowerId.contains('embedding') ||
      lowerId.contains('orpheus') ||
      lowerId.contains('tts')) {
    continue; // Exclude non-LLM chat completion models
  }
  ```

---

### 6. Redundant Re-triggering of Splash Screen on Every App Resume
- **Severity:** Low (UX Friction)
- **Affected Files:**
  - `lib/main.dart` (`didChangeAppLifecycleState`)
- **Diagnosis:** Line 180 of `main.dart` resets `_showSplash = true` and increments `_splashSession++` every time `AppLifecycleState.resumed` is received if `_lastPausedTime != null`.
- **Observed Bug:** Whenever a user tabs out to copy text from Chrome, notes, or email and switches back to Lauriva, they are subjected to the full 1.3-second splash animation again, disrupting their workflow.
- **Recommended Fix:** Only show the splash screen on cold start launch, or only if the app has been in the background for an extended duration (e.g. > 15 minutes).

---

### 7. Dual Settings Navigation Inconsistency
- **Severity:** Low (Architecture / UX)
- **Affected Files:**
  - `lib/screens/detector_screen.dart` (line 84)
  - `lib/screens/studio_screen.dart` (line 35)
  - `lib/widgets/header_bar.dart`
- **Diagnosis:** `HeaderBar` pushes `SettingsScreen` as a full-page modal route (`Navigator.push`), whereas Settings is already the 4th tab in `FloatingGlassNavBar`.
- **Observed Bug:** Opening Settings from the header hides the bottom navigation bar and creates a separate navigation stack, whereas opening it from the bottom bar retains the nav bar.
- **Recommended Fix:** Standardize header settings icon to call `onNavigateToSettings?.call()` which switches `_currentIndex = 3` in `LaurivaHomeScreen`.

---

## Action Plan & Verification
| Task | Target Component | Status |
|------|------------------|--------|
| **Fix 1** | Adjust bottom scroll padding across all screens | Identified |
| **Fix 2** | Hide bottom nav bar when keyboard is visible | Identified |
| **Fix 3** | Add root unfocus gesture detector | Identified |
| **Fix 4** | Implement `PopScope` tab back navigation | Identified |
| **Fix 5** | Filter non-LLM models from Groq live catalog | Identified |
| **Fix 6** | Remove splash re-trigger on brief app resume | Identified |
| **Fix 7** | Unify settings navigation to tab switch | Identified |
