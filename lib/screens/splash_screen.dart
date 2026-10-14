import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../widgets/lauriva_logo.dart';

/// Brand lockup metrics shared by the splash and the onboarding hand-off so
/// both screens draw the exact same mark at the exact same size and position.
const double kLockupLogoSize = 52;
const double kLockupFontSize = 40;
const double kLockupGap = 16;
const double kLockupLetterSpacing = -0.5;

/// Distance (px) the logo and wordmark travel while converging.
const double kLockupConvergeDistance = 56;

/// Brand splash: the sprout mark and the wordmark start apart and glide
/// toward each other until they form the centered lockup.
///
/// Motion design (~1.9s total):
/// - 1000ms Converge: logo glides in from the left, wordmark from the right,
///   both fading in and settling together.
/// - 500ms Hold: lockup rests centered.
/// - 400ms Exit: gentle fade + 1.04 zoom revealing the app underneath.
///
/// When [handoff] is provided the splash waits for it after the hold. If it
/// resolves to `true` the splash finishes instantly (no exit) so the next
/// screen can continue from the identical centered lockup.
/// Tap-to-skip is supported at any time.
class SplashScreen extends StatefulWidget {
  final VoidCallback? onFinish;
  final bool autoDismiss;
  final Future<bool>? handoff;

  /// Fires once the converge animation has fully played. Heavy startup work
  /// should begin here so it cannot freeze the animation.
  final VoidCallback? onEntered;
  final Duration entranceDuration;
  final Duration holdDuration;
  final Duration exitDuration;

  const SplashScreen({
    super.key,
    this.onFinish,
    this.autoDismiss = true,
    this.handoff,
    this.onEntered,
    this.entranceDuration = const Duration(milliseconds: 1000),
    this.holdDuration = const Duration(milliseconds: 500),
    this.exitDuration = const Duration(milliseconds: 400),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _exitController;

  // Entrance animations
  late final Animation<double> _logoSlide;
  late final Animation<double> _textSlide;
  late final Animation<double> _textFade;

  // Exit animations
  late final Animation<double> _exitFade;
  late final Animation<double> _exitScale;

  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: widget.entranceDuration,
    );

    final easeOutCubic = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeInOutCubic,
    );

    _logoSlide = Tween<double>(
      begin: -kLockupConvergeDistance,
      end: 0.0,
    ).animate(easeOutCubic);

    _textSlide = Tween<double>(
      begin: kLockupConvergeDistance,
      end: 0.0,
    ).animate(easeOutCubic);

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: widget.exitDuration,
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInOutCubic),
    );

    _exitScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOutCubic),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    try {
      await _entranceController.forward().orCancel;
      if (!mounted) return;
      widget.onEntered?.call();

      if (widget.autoDismiss) {
        await Future.delayed(widget.holdDuration);
        if (!mounted || _isDismissed) return;
        if (widget.handoff != null && await widget.handoff! && mounted) {
          if (_isDismissed) return;
          _isDismissed = true;
          widget.onFinish?.call();
          return;
        }
        if (!mounted || _isDismissed) return;
        await _exitController.forward().orCancel;
        if (!mounted || _isDismissed) return;
        _isDismissed = true;
        widget.onFinish?.call();
      }
    } catch (_) {
      // Ignored if cancelled on unmount or tap dismiss
    }
  }

  void _dismissNow() {
    if (_isDismissed) return;
    _isDismissed = true;
    // A tap before the converge ends must not leave startup waiting forever.
    widget.onEntered?.call();
    widget.onFinish?.call();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        behavior: HitTestBehavior.opaque,
        onTap: _dismissNow,
        child: AnimatedBuilder(
          animation: _exitController,
          builder: (context, _) {
            return Opacity(
              opacity: _exitFade.value,
              child: Transform.scale(
                scale: _exitScale.value,
                child: Material(
                  color: AppColors.bgCenter,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, _) {
                        return Opacity(
                          opacity: _textFade.value,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Transform.translate(
                                offset: Offset(_logoSlide.value, 0),
                                child: LaurivaLogo(size: kLockupLogoSize),
                              ),
                              const SizedBox(width: kLockupGap),
                              Transform.translate(
                                offset: Offset(_textSlide.value, 0),
                                child: Text(
                                  'Lauriva',
                                  style: GoogleFonts.outfit(
                                    fontSize: kLockupFontSize,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    letterSpacing: kLockupLetterSpacing,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
