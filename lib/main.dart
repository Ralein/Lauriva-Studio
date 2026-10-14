import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'constants/app_colors.dart';
import 'providers/history_provider.dart';
import 'providers/humanizer_provider.dart';
import 'providers/llm_settings_provider.dart';
import 'providers/plagiarism_provider.dart';
import 'providers/background_task_provider.dart';
import 'providers/speech_provider.dart';
import 'providers/studio_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/toast_provider.dart';
import 'services/forensic/forensic_coordinator_service.dart';
import 'services/forensic/sources/corpus_loader.dart';
import 'services/storage_service.dart';
import 'utils/crash_guard.dart';
import 'utils/logger.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'screens/studio_screen.dart';
import 'widgets/background_glow.dart';
import 'widgets/nav_bar.dart';
import 'widgets/toast_overlay.dart';
import 'core/platform/lauriva_shortcut_integration.dart';
import 'core/platform/notification_service.dart';
import 'features/background_activity/data/background_activity_repository.dart';
import 'features/background_activity/presentation/background_activity_controller.dart';
import 'features/background_activity/presentation/background_activity_screen.dart';

/// Top-level Workmanager background isolate callback dispatcher.
@pragma('vm:entry-point')
void laurivaBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    AppLogger.info(
      'Workmanager background task executed: $task',
      'Workmanager',
    );
    return true;
  });
}

/// Global navigator key — exposes navigation from outside the widget tree
/// so error recovery can pop back to LaurivaHomeScreen from ErrorWidget.
final GlobalKey<NavigatorState> laurivaNavigatorKey =
    GlobalKey<NavigatorState>();
GlobalKey<NavigatorState> get clarivaNavigatorKey => laurivaNavigatorKey;

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Native launcher quick actions (Android dynamic shortcuts / iOS Quick Actions)
      LaurivaShortcutIntegration.instance.initialize();

      // Workmanager background task scheduler (Android / iOS)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          Workmanager().initialize(laurivaBackgroundCallbackDispatcher);
        } catch (e) {
          AppLogger.warn(
            'Workmanager initialization deferred: $e',
            'Workmanager',
          );
        }
      }

      // Native operating system notification service
      unawaited(
        NotificationService().initialize(
          onSelectNotification: (payload) {
            if (payload == 'background_activity' ||
                (payload != null && payload.startsWith('task_'))) {
              laurivaNavigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => const BackgroundActivityScreen(),
                ),
              );
            }
          },
        ),
      );

      // Immediately resolve system brightness so the splash frame matches the device's light/dark mode
      final platformBrightness = PlatformDispatcher.instance.platformBrightness;
      AppColors.setBrightness(
        platformBrightness == Brightness.dark
            ? AppBrightness.dark
            : AppBrightness.light,
      );

      // --- Production Error Boundaries & Crash Resilience ---
      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.error(
          'Flutter framework error: ${details.exceptionAsString()}',
          error: details.exception,
          stackTrace: details.stack,
          tag: 'FrameworkError',
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.error(
          'Uncaught async platform error: $error',
          error: error,
          stackTrace: stack,
          tag: 'PlatformDispatcher',
        );
        return true; // Prevents crash from bubbling to OS
      };

      // Custom luxury error widget replacing default red error screen
      ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
        return Material(
          color: AppColors.bgCenter,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.paletteCerulean.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      LucideIcons.alertCircle,
                      color: AppColors.paletteCerulean,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Lauriva Encountered an Issue',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The application recovered safely without data loss.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Self-healing restart action — returns to LaurivaHomeScreen.
                  TextButton.icon(
                    onPressed: () {
                      laurivaNavigatorKey.currentState?.pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const LaurivaHomeScreen(),
                        ),
                        (_) => false,
                      );
                    },
                    icon: Icon(
                      LucideIcons.refreshCw,
                      size: 16,
                      color: AppColors.paletteCerulean,
                    ),
                    label: Text(
                      'Return to App',
                      style: GoogleFonts.outfit(
                        color: AppColors.paletteCerulean,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      };

      // Paint the brand splash on the very first frame; storage + providers
      // initialise behind it (see _BootGate) so the user never stares at a
      // blank native launch screen.
      runApp(
        _BootGate(
          boot: () async {
            final startupWatch = Stopwatch()..start();
            AppLogger.info('Startup watch started', 'StartupPerf');

            // --- Bootstrap: fault-tolerant storage initialization ---
            // A PlatformException from SharedPreferences (corrupted DB) must NOT kill
            // the app before the first frame. StorageService already retries internally;
            // here we add a final safety net at the outermost level.
            final storageService = StorageService();
            await CrashGuard.runAsync(
              () => storageService.init(),
              tag: 'BootstrapInit',
            );
            // Immediately apply saved theme preference or platform brightness
            final savedTheme = storageService.getThemeMode();
            final resolvedBrightness = savedTheme == 'light'
                ? Brightness.light
                : (savedTheme == 'dark'
                      ? Brightness.dark
                      : PlatformDispatcher.instance.platformBrightness);
            AppColors.setBrightness(
              resolvedBrightness == Brightness.dark
                  ? AppBrightness.dark
                  : AppBrightness.light,
            );
            _bootFirstLaunch =
                _forceFirstLaunch || !storageService.getHasSeenOnboarding();
            AppLogger.info(
              'storageService.init took ${startupWatch.elapsedMilliseconds}ms',
              'StartupPerf',
            );

            // Pre-warm Outfit font in the background; never block the first frame
            // on a potential network fetch (fallback font swaps in when ready).
            unawaited(
              CrashGuard.runAsync(
                () => GoogleFonts.pendingFonts([
                  GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  GoogleFonts.outfit(fontWeight: FontWeight.w400),
                ]),
                tag: 'FontPreload',
              ).whenComplete(
                () => AppLogger.info(
                  'FontPreload finished at ${startupWatch.elapsedMilliseconds}ms',
                  'StartupPerf',
                ),
              ),
            );

            // Pre-warm forensic source corpus index in background
            unawaited(
              CrashGuard.runAsync(
                () => CorpusLoader.warmup(),
                tag: 'CorpusLoaderWarmup',
              ),
            );

            // Pre-load the trained on-device AI detector so the first scan is not
            // delayed by model loading (resolves to null where ONNX is unsupported).
            unawaited(
              CrashGuard.runAsync(
                () => ForensicCoordinatorService.loadBundledNeuralDetector(),
                tag: 'NeuralDetectorWarmup',
              ),
            );

            final toastProvider = ToastProvider();
            final themeProvider = ThemeProvider(storage: storageService);
            final historyProvider = HistoryProvider(
              storage: storageService,
              toast: toastProvider,
            );
            final llmSettingsProvider = LlmSettingsProvider(
              storage: storageService,
            );
            final speechProvider = SpeechProvider(
              storage: storageService,
              toast: toastProvider,
            );
            final backgroundTaskProvider = BackgroundTaskProvider(
              toast: toastProvider,
            );
            final plagiarismProvider = PlagiarismProvider(
              storage: storageService,
              toast: toastProvider,
              history: historyProvider,
              llmSettings: llmSettingsProvider,
              backgroundTask: backgroundTaskProvider,
            );
            final humanizerProvider = HumanizerProvider(
              storage: storageService,
              toast: toastProvider,
              history: historyProvider,
              llmSettings: llmSettingsProvider,
              plagiarism: plagiarismProvider,
              speech: speechProvider,
              backgroundTask: backgroundTaskProvider,
            );
            final studioProvider = StudioProvider(
              storage: storageService,
              speech: speechProvider,
              llmSettings: llmSettingsProvider,
              history: historyProvider,
              toast: toastProvider,
              plagiarism: plagiarismProvider,
            );

            final backgroundActivityRepository = BackgroundActivityRepository();
            await CrashGuard.runAsync(
              () => backgroundActivityRepository.init(),
              tag: 'BackgroundActivityRepoInit',
            );

            final backgroundActivityController = BackgroundActivityController(
              repository: backgroundActivityRepository,
              notificationService: NotificationService(),
              processingService: backgroundTaskProvider.service,
            );

            AppLogger.info(
              'runApp called at ${startupWatch.elapsedMilliseconds}ms',
              'StartupPerf',
            );

            return MultiProvider(
              providers: [
                ChangeNotifierProvider<ToastProvider>.value(
                  value: toastProvider,
                ),
                ChangeNotifierProvider<BackgroundTaskProvider>.value(
                  value: backgroundTaskProvider,
                ),
                ChangeNotifierProvider<BackgroundActivityController>.value(
                  value: backgroundActivityController,
                ),
                ChangeNotifierProvider<ThemeProvider>.value(
                  value: themeProvider,
                ),
                ChangeNotifierProvider<HistoryProvider>.value(
                  value: historyProvider,
                ),
                ChangeNotifierProvider<LlmSettingsProvider>.value(
                  value: llmSettingsProvider,
                ),
                ChangeNotifierProvider<SpeechProvider>.value(
                  value: speechProvider,
                ),
                ChangeNotifierProvider<PlagiarismProvider>.value(
                  value: plagiarismProvider,
                ),
                ChangeNotifierProvider<StudioProvider>.value(
                  value: studioProvider,
                ),
                ChangeNotifierProvider<HumanizerProvider>.value(
                  value: humanizerProvider,
                ),
              ],
              child: LaurivaApp(
                showSplashOnLaunch: false, // _BootGate already showed it
                // First install: onboarding continues from the splash lockup.
                showOnboardingOnLaunch: _bootFirstLaunch,
                onboardingFromSplash: true,
                storageService: storageService,
              ),
            );
          },
        ),
      );
    },
    (error, stackTrace) {
      AppLogger.fatal(
        'Zone-level uncaught exception: $error',
        error: error,
        stackTrace: stackTrace,
        tag: 'RootZoneGuard',
      );
    },
  );
}

/// Set during boot: true when this is the first launch after install.
bool _bootFirstLaunch = false;

/// QA switch: `flutter run --dart-define=FORCE_FIRST_LAUNCH=true` replays the
/// first-install flow (splash -> onboarding) without wiping app data.
const bool _forceFirstLaunch = bool.fromEnvironment('FORCE_FIRST_LAUNCH');

/// Shows the splash immediately, runs [boot] behind it, then fades into the app.
class _BootGate extends StatefulWidget {
  final Future<Widget> Function() boot;
  const _BootGate({required this.boot});

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  Widget? _app;
  bool _splashCompleted = false;
  bool _firstLaunch = false;
  final Completer<bool> _handoff = Completer<bool>();

  @override
  void initState() {
    super.initState();
    final platformBrightness = PlatformDispatcher.instance.platformBrightness;
    AppColors.setBrightness(
      platformBrightness == Brightness.dark
          ? AppBrightness.dark
          : AppBrightness.light,
    );
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (isTest) {
      _splashCompleted = true;
    }
    if (isTest) {
      _startBoot();
    }
    // Otherwise boot starts from SplashScreen.onEntered: boot work is
    // synchronous-heavy and would freeze the splash animation if it ran
    // alongside the converge.
  }

  bool _bootStarted = false;

  void _startBoot() {
    if (_bootStarted) return;
    _bootStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = await widget.boot();
      // Only when onboarding follows does the splash skip its exit, so the
      // lockup carries straight into onboarding.
      _firstLaunch = _bootFirstLaunch;
      if (!_handoff.isCompleted) _handoff.complete(_firstLaunch);
      if (mounted) setState(() => _app = app);
    });
  }

  void _onSplashFinish() {
    if (mounted) {
      setState(() => _splashCompleted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showApp = _app != null && _splashCompleted;
    if (_app == null) {
      final pb = View.of(context).platformDispatcher.platformBrightness;
      AppColors.setBrightness(
        pb == Brightness.dark ? AppBrightness.dark : AppBrightness.light,
      );
    }
    final isDark = AppColors.isDark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppColors.bgCenter,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: TextDirection.ltr,
        // Returning launches mount the app *beneath* the splash so its exit
        // fade reveals Studio instead of the bare (black) window, and the
        // heavy first build happens while the splash is still painting.
        // First launch keeps the splash on top alone: its lockup hands off
        // pixel for pixel to onboarding.
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_app != null && (showApp || !_firstLaunch))
              KeyedSubtree(key: const ValueKey('boot_app'), child: _app!),
            if (!showApp)
              SplashScreen(
                key: const ValueKey('boot_splash'),
                autoDismiss: true,
                handoff: _handoff.future,
                onEntered: _startBoot,
                onFinish: _onSplashFinish,
              ),
          ],
        ),
      ),
    );
  }
}

typedef ClarivaApp = LaurivaApp;

class LaurivaApp extends StatefulWidget {
  final bool? showSplashOnLaunch;
  final bool? showOnboardingOnLaunch;

  /// True when a splash already played the converge animation, so onboarding
  /// continues from the centered lockup instead of replaying it.
  final bool onboardingFromSplash;
  final StorageService? storageService;

  const LaurivaApp({
    super.key,
    this.showSplashOnLaunch,
    this.showOnboardingOnLaunch,
    this.onboardingFromSplash = false,
    this.storageService,
  });

  @override
  State<LaurivaApp> createState() => _LaurivaAppState();
}

class _LaurivaAppState extends State<LaurivaApp> with WidgetsBindingObserver {
  late bool _showSplash;
  bool _showOnboarding = false;

  /// First launch: the home screen is mounted only after onboarding's intro
  /// animation settles, so its heavy first build cannot swallow the glide.
  bool _mountHome = true;

  @override
  void initState() {
    super.initState();
    // Show splash only on cold start; skip in test environments to avoid timeouts.
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    // On first download / install, show onboarding tutorial seamlessly
    final storage = widget.storageService ?? StorageService();
    final hasSeen = storage.getHasSeenOnboarding();
    _showOnboarding = widget.showOnboardingOnLaunch ?? (!isTest && !hasSeen);
    _mountHome = !(_showOnboarding && widget.onboardingFromSplash);
    // On first download, the splash hands off to OnboardingScreen, which morphs the lockup to its header.
    // On subsequent launches, SplashScreen runs the standard cold-start splash directly into Studio.
    _showSplash = widget.showSplashOnLaunch ?? (!isTest && !_showOnboarding);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Live-updates when themeMode == 'system' and the OS theme flips while
    // the app is open (without this observer, a system-mode user would only
    // see the new brightness after their next state change / app relaunch).
    try {
      final theme = context.read<ThemeProvider>();
      if (theme.themeMode == 'system') {
        final pb =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        AppColors.setBrightness(
          pb == Brightness.dark ? AppBrightness.dark : AppBrightness.light,
        );
      }
    } catch (_) {}
    setState(() {});
  }

  Brightness _resolveBrightness(String mode) {
    switch (mode) {
      case 'light':
        return Brightness.light;
      case 'dark':
        return Brightness.dark;
      case 'system':
      default:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    AppColors.setBrightness(isDark ? AppBrightness.dark : AppBrightness.light);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppColors.bgCenter,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    final baseTextTheme = GoogleFonts.outfitTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            tertiary: AppColors.accent,
            onTertiary: const Color(0xFF0F1216),
            surface: AppColors.glassBg,
            onSurface: AppColors.textPrimary,
            error: AppColors.error,
            onError: Colors.white,
          )
        : ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            tertiary: AppColors.accent,
            onTertiary: Colors.white,
            surface: AppColors.glassBg,
            onSurface: AppColors.textPrimary,
            error: AppColors.error,
            onError: Colors.white,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bgCenter,
      textTheme: baseTextTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      colorScheme: colorScheme,
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 15),
        border: InputBorder.none,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.glassBorderHover),
        ),
        textStyle: GoogleFonts.outfit(
          color: isDark ? const Color(0xFF0F1216) : Colors.white,
          fontSize: 12.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // context.select (not watch) scopes the dependency to themeMode alone,
    // so this rebuilds — and re-resolves AppColors' brightness, cascading
    // down through the non-const LaurivaHomeScreen/BackgroundGlow chain
    // below — only when the theme preference actually changes, not on every
    // provider notification (e.g. every keystroke in the input field).
    final themeMode = context.select<ThemeProvider, String>((p) => p.themeMode);
    final brightness = _resolveBrightness(themeMode);

    return MaterialApp(
      title: 'Lauriva - AI Writing Assistant & Speech Studio',
      debugShowCheckedModeBanner: false,
      navigatorKey: laurivaNavigatorKey,
      theme: _buildTheme(brightness),
      home: const LaurivaHomeScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            if (_mountHome) ?child,
            if (_showOnboarding)
              Positioned.fill(
                child: OnboardingScreen(
                  key: const ValueKey('onboarding_first_launch'),
                  storageService: widget.storageService,
                  animateFromSplash: widget.onboardingFromSplash,
                  splashAlreadyShown: widget.onboardingFromSplash,
                  onIntroSettled: () {
                    if (mounted && !_mountHome) {
                      setState(() => _mountHome = true);
                    }
                  },
                  onComplete: () {
                    if (mounted) {
                      setState(() {
                        _showOnboarding = false;
                        _mountHome = true;
                      });
                    }
                  },
                ),
              ),
            if (_showSplash)
              Positioned.fill(
                child: SplashScreen(
                  key: const ValueKey('splash_cold_start'),
                  autoDismiss: true,
                  onFinish: () {
                    if (mounted) {
                      setState(() => _showSplash = false);
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

typedef ClarivaHomeScreen = LaurivaHomeScreen;

class LaurivaHomeScreen extends StatefulWidget {
  const LaurivaHomeScreen({super.key});

  @override
  State<LaurivaHomeScreen> createState() => _LaurivaHomeScreenState();
}

class _LaurivaHomeScreenState extends State<LaurivaHomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    LaurivaShortcutIntegration.instance.attachHandler(_handleShortcutAction);
  }

  @override
  void dispose() {
    LaurivaShortcutIntegration.instance.detachHandler();
    super.dispose();
  }

  void _handleShortcutAction(String shortcutId) {
    if (!mounted) return;
    LaurivaShortcutIntegration.navigateToFeature(
      context: context,
      shortcutId: shortcutId,
      // Scan shortcuts target the Forensics feature, which is not in this app.
      onSelectTab: (_) {},
    );
  }

  void _navigateToTab(int index) {
    if (mounted) setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;
    // Re-sync AppColors brightness so every widget in this subtree reads the
    // correct palette when it rebuilds due to ThemeProvider changes.
    // (LaurivaApp._buildTheme also does this, but IndexedStack children may
    //  rebuild from ThemeProvider before LaurivaApp gets a frame.)
    Brightness brightness;
    switch (themeMode) {
      case 'light':
        brightness = Brightness.light;
        break;
      case 'dark':
        brightness = Brightness.dark;
        break;
      default:
        brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
    AppColors.setBrightness(
      brightness == Brightness.dark ? AppBrightness.dark : AppBrightness.light,
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Cmd/Ctrl + Enter: Run active transform
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          context.read<StudioProvider>().runActiveTransformIfIdle();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          context.read<StudioProvider>().runActiveTransformIfIdle();
        },
        // Cmd/Ctrl + Shift + C: Copy result
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          meta: true,
          shift: true,
        ): () {
          context.read<StudioProvider>().copyOutputToClipboard();
        },
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): () {
          context.read<StudioProvider>().copyOutputToClipboard();
        },
        // Cmd/Ctrl + Shift + F: Navigate to Detector (Forensic Scan)
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): () {
          // Forensic scan is not part of this app.
        },
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () {
          // Forensic scan is not part of this app.
        },
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (didPop) return;
          if (_currentIndex != 0) {
            _navigateToTab(0);
          } else {
            SystemNavigator.pop();
          }
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: BackgroundGlow(
              child: SafeArea(
                bottom: true,
                child: Stack(
                  children: [
                    // Screen Body — IndexedStack preserves state & scroll position
                    Positioned.fill(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: [
                          StudioScreen(
                            onNavigateToSettings: () => _navigateToTab(1),
                          ),
                          SettingsScreen(),
                        ],
                      ),
                    ),

                    // Floating Luxury Glass Bottom Navigation Bar
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FloatingGlassNavBar(
                        currentIndex: _currentIndex,
                        onTabSelected: _navigateToTab,
                      ),
                    ),

                    // Toast HUD overlay
                    const ToastOverlay(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
