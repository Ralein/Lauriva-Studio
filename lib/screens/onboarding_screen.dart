import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../constants/app_colors.dart';
import '../core/platform/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/lauriva_logo.dart';
import 'splash_screen.dart';
import 'studio_screen.dart';

/// Data model representing a feature slide in the minimalist onboarding flow.
class OnboardingSlide {
  final String title;
  final String description;
  final IconData icon;

  const OnboardingSlide({
    required this.title,
    required this.description,
    required this.icon,
  });
}

/// Minimal onboarding carousel.
///
/// With [animateFromSplash] the brand lockup converges at screen center (like
/// the splash), holds, then glides to the top-left header while the content
/// fades in. With [splashAlreadyShown] the splash has already played the
/// converge, so the sequence resumes from the centered lockup.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final StorageService? storageService;
  final NotificationService? notificationService;
  final bool animateFromSplash;
  final bool splashAlreadyShown;

  /// Fires once the lockup has settled in the header and content is visible.
  /// The host can start building heavy screens behind onboarding from here,
  /// so they never steal frames from the glide.
  final VoidCallback? onIntroSettled;

  const OnboardingScreen({
    super.key,
    this.onComplete,
    this.storageService,
    this.notificationService,
    this.animateFromSplash = false,
    this.splashAlreadyShown = false,
    this.onIntroSettled,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _resumeTimer;
  bool _showNotificationPrompt = false;
  bool _isRequestingPermission = false;

  late final AnimationController _splashController;
  late final Animation<double> _entranceFade;
  late final Animation<double> _logoEntranceSlide;
  late final Animation<double> _textEntranceSlide;
  late final Animation<double> _morphProgress;
  late final Animation<double> _contentOpacity;

  /// Fraction of the timeline taken by the converge phase.
  static const double _entranceEnd = 0.3125;

  static const List<OnboardingSlide> _slides = [
    OnboardingSlide(
      title: 'Check originality',
      description: 'Find where your text overlaps published sources, with the evidence. AI detection runs on your device.',
      icon: LucideIcons.searchCheck,
    ),
    OnboardingSlide(
      title: 'Humanize with care',
      description: 'Rewrites section by section, keeps facts, numbers and citations, then re-checks the result.',
      icon: LucideIcons.eraser,
    ),
    OnboardingSlide(
      title: 'Private by design',
      description: 'No account. Source search shares only a few short excerpts. Your API keys stay on this device.',
      icon: LucideIcons.shieldCheck,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _splashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    // 0.00 -> 0.31: converge (matches the splash entrance, 1000ms)
    _entranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _splashController,
        curve: const Interval(0.0, 0.22, curve: Curves.easeOut),
      ),
    );

    _logoEntranceSlide =
        Tween<double>(begin: -kLockupConvergeDistance, end: 0.0).animate(
          CurvedAnimation(
            parent: _splashController,
            curve: const Interval(
              0.0,
              _entranceEnd,
              curve: Curves.easeOutCubic,
            ),
          ),
        );

    _textEntranceSlide = Tween<double>(begin: kLockupConvergeDistance, end: 0.0)
        .animate(
          CurvedAnimation(
            parent: _splashController,
            curve: const Interval(
              0.0,
              _entranceEnd,
              curve: Curves.easeOutCubic,
            ),
          ),
        );

    // 0.31 -> 0.47: hold (500ms), 0.47 -> 0.88: lockup glides to the header (1300ms)
    _morphProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _splashController,
        curve: const Interval(0.47, 0.88, curve: Curves.easeInOutCubic),
      ),
    );

    // 0.72 -> 1.00: content reveals as the lockup settles
    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _splashController,
        curve: const Interval(0.72, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.animateFromSplash) {
      if (widget.splashAlreadyShown) {
        _splashController.value = _entranceEnd;
        // Let the Studio screen underneath finish its first build so the
        // glide to the header starts on a smooth frame.
        _resumeTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) _splashController.forward();
        });
      } else {
        _splashController.forward();
      }
    } else {
      _splashController.value = 1.0;
    }

    _splashController.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onIntroSettled?.call();
    });
    if (_splashController.value == 1.0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onIntroSettled?.call();
      });
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _pageController.dispose();
    _splashController.dispose();
    super.dispose();
  }

  void _skipIntroAnimation() {
    if (_splashController.value < 1.0) {
      _splashController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    HapticFeedback.mediumImpact();
    final notifService = widget.notificationService ?? NotificationService();
    final isGranted = await notifService.isPermissionGranted();

    if (!isGranted && mounted) {
      setState(() {
        _showNotificationPrompt = true;
      });
      return;
    }

    await _finishAndNavigate();
  }

  Future<void> _finishAndNavigate() async {
    if (mounted) {
      setState(() {
        _isRequestingPermission = false;
        _showNotificationPrompt = false;
      });
    }
    final storage = widget.storageService ?? StorageService();
    await storage.setHasSeenOnboarding(true);

    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StudioScreen()),
      );
    }
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;
    final isDark = AppColors.isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppColors.bgCenter,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _skipIntroAnimation,
        child: PopScope(
          canPop: !_showNotificationPrompt,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _showNotificationPrompt) {
              _finishAndNavigate();
            }
          },
          child: Scaffold(
          backgroundColor: AppColors.bgCenter,
          body: AnimatedBuilder(
          animation: _splashController,
          builder: (context, _) {
            final morphT = _morphProgress.value;
            final contentT = _contentOpacity.value;
            final entranceAlpha = widget.animateFromSplash
                ? _entranceFade.value
                : 1.0;
            final logoSlide = widget.animateFromSplash
                ? _logoEntranceSlide.value
                : 0.0;
            final textSlide = widget.animateFromSplash
                ? _textEntranceSlide.value
                : 0.0;

            // Morphing values between center splash and top-left header
            final currentLogoSize = lerpDouble(kLockupLogoSize, 26.0, morphT)!;
            final currentFontSize = lerpDouble(kLockupFontSize, 18.0, morphT)!;
            final currentGap = lerpDouble(kLockupGap, 10.0, morphT)!;
            final currentSpacing = lerpDouble(
              kLockupLetterSpacing,
              -0.4,
              morphT,
            )!;
            final safeTop = MediaQuery.paddingOf(context).top;
            final targetTopPadding =
                safeTop + 8.0 + (44.0 - currentLogoSize) / 2.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. Onboarding Content: Top Skip Button + PageView Carousel + Bottom Controls
                SafeArea(
                  child: Opacity(
                    opacity: contentT,
                    child: Transform.translate(
                      offset: Offset(0, 16.0 * (1.0 - contentT)),
                      child: Column(
                        children: [
                          // Top Navigation bar: Skip button only (brand lockup floats above via Stack)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: SizedBox(
                              height: 44,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (!isLastPage)
                                    Semantics(
                                      button: true,
                                      label: 'Skip onboarding',
                                      child: TextButton(
                                        onPressed: _completeOnboarding,
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.textMuted,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                        ),
                                        child: Text(
                                          'Skip',
                                          style: GoogleFonts.outfit(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                ],
                              ),
                            ),
                          ),

                          // Carousel Slides
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              physics: contentT < 0.9
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                              onPageChanged: (index) {
                                setState(() => _currentPage = index);
                              },
                              itemCount: _slides.length,
                              itemBuilder: (context, index) {
                                return _buildSlide(_slides[index]);
                              },
                            ),
                          ),

                          // Bottom Navigation Controls: Dots + Action Button
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Minimalist Indicator Dots
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(_slides.length, (
                                    index,
                                  ) {
                                    final isActive = index == _currentPage;
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      width: isActive ? 20 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppColors.primary
                                            : AppColors.textMuted.withValues(
                                                alpha: AppColors.isDark ? 0.35 : 0.22,
                                              ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    );
                                  }),
                                ),

                                const SizedBox(height: 24),

                                // Solid Vibrant Teal Action Button
                                Semantics(
                                  button: true,
                                  label: isLastPage
                                      ? 'Get started'
                                      : 'Continue',
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: FilledButton(
                                      onPressed: contentT < 0.9
                                          ? null
                                          : _nextPage,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        isLastPage ? 'Get started' : 'Continue',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Animated Brand Lockup (morphs from screen center to top-left)
                Align(
                  alignment: Alignment.lerp(
                    Alignment.center,
                    Alignment.topLeft,
                    morphT,
                  )!,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 24.0 * morphT,
                      top: targetTopPadding * morphT,
                    ),
                    child: Opacity(
                      opacity: entranceAlpha,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Transform.translate(
                            offset: Offset(logoSlide, 0),
                            child: LaurivaLogo(size: currentLogoSize),
                          ),
                          SizedBox(width: currentGap),
                          Transform.translate(
                            offset: Offset(textSlide, 0),
                            child: Text(
                              'Lauriva',
                              style: GoogleFonts.outfit(
                                fontSize: currentFontSize,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: currentSpacing,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 3. Post-onboarding Notification Permission Prompt
                if (_showNotificationPrompt)
                  _buildNotificationPromptOverlay(),
              ],
            );
          },
        ),
      ),
    ),
  ),
  );
  }

  Widget _buildNotificationPromptOverlay() {
    final isDark = AppColors.isDark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Dimmed & Blurred Scrim
            GestureDetector(
              onTap: _isRequestingPermission ? null : _finishAndNavigate,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 8.0 * animValue,
                  sigmaY: 8.0 * animValue,
                ),
                child: Container(
                  color: Colors.black.withValues(
                    alpha: (isDark ? 0.70 : 0.45) * animValue,
                  ),
                ),
              ),
            ),

            // Animated Bottom Floating Modal Card
            Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, 50.0 * (1.0 - animValue)),
                child: Opacity(
                  opacity: animValue,
                  child: SafeArea(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.glassBorder,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.5 : 0.15,
                            ),
                            blurRadius: 32,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header: Icon + Title & Category
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.28,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  LucideIcons.bell,
                                  size: 24,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Enable Notifications',
                                      style: GoogleFonts.outfit(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Background activity & progress',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Description
                          Text(
                            'Get notified when long-running plagiarism audits and AI humanization complete in the background, even when you switch to other apps.',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Enable Notifications Button
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: _isRequestingPermission
                                  ? null
                                  : () async {
                                      setState(
                                        () => _isRequestingPermission = true,
                                      );
                                      HapticFeedback.mediumImpact();
                                      final notifService =
                                          widget.notificationService ??
                                          NotificationService();
                                      await notifService.requestPermission();
                                      if (mounted) {
                                        await _finishAndNavigate();
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isRequestingPermission
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Enable Notifications',
                                      style: GoogleFonts.outfit(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Maybe Later Button
                          SizedBox(
                            height: 38,
                            child: TextButton(
                              onPressed: _isRequestingPermission
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      _finishAndNavigate();
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textMuted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                'Maybe Later',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSlide(OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 1),

          // Left-aligned Squircle Icon Container
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.28),
                width: 1.5,
              ),
            ),
            child: Icon(slide.icon, size: 28, color: AppColors.primary),
          ),

          const SizedBox(height: 32),

          // Left-aligned Title (adapted dynamically for light/dark mode)
          Text(
            slide.title,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.6,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 14),

          // Left-aligned Description (adapted dynamically for light/dark mode)
          Text(
            slide.description,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }
}
