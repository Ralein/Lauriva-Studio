import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/tts_highlight.dart';
import '../providers/speech_provider.dart';

/// High-fidelity, GPU-accelerated text view that renders word-by-word
/// highlighting synchronized with the active Text-To-Speech engine.
///
/// Features:
/// - Isolated `ValueListenableBuilder` listening to [SpeechProvider.highlightNotifier]
///   so word-level updates never trigger full-screen widget rebuilds.
/// - Dark glassmorphic design utilizing [AppColors.primary] glow and underline accents.
/// - Preserves full text selection capabilities and custom context menus.
/// - Smooth viewport auto-scrolling so the spoken word is always kept in view.
class TtsHighlightTextView extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final bool isStreaming;
  final Widget? streamingIndicator;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final void Function(TextSelection, SelectionChangedCause?)? onSelectionChanged;
  final bool autoScroll;

  const TtsHighlightTextView({
    super.key,
    required this.text,
    this.style,
    this.isStreaming = false,
    this.streamingIndicator,
    this.contextMenuBuilder,
    this.onSelectionChanged,
    this.autoScroll = true,
  });

  @override
  State<TtsHighlightTextView> createState() => _TtsHighlightTextViewState();
}

class _TtsHighlightTextViewState extends State<TtsHighlightTextView> {
  int _lastScrolledCharStart = -1;
  DateTime _lastScrollTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUserInteractionTime = DateTime.fromMillisecondsSinceEpoch(0);
  TextSelection? _activeUserSelection;

  void _onUserInteracted() {
    _lastUserInteractionTime = DateTime.now();
  }

  void _handleSelectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    if (selection.isValid && !selection.isCollapsed && selection.start >= 0) {
      _activeUserSelection = selection;
      _onUserInteracted();
    } else {
      _activeUserSelection = null;
    }
    widget.onSelectionChanged?.call(selection, cause);
  }

  TextStyle get _effectiveStyle =>
      widget.style ??
      GoogleFonts.outfit(
        fontSize: 16,
        color: AppColors.textPrimary,
        height: 1.55,
      );

  void _checkAutoScroll(TtsHighlight highlight, double maxWidth) {
    if (!widget.autoScroll || !mounted) return;

    final now = DateTime.now();
    // Do not auto-scroll if the user has touched or scrolled within the last 3.5 seconds
    if (now.difference(_lastUserInteractionTime).inMilliseconds < 3500) return;

    // Throttle scroll checks to prevent micro-stutter
    if (now.difference(_lastScrollTime).inMilliseconds < 180) return;
    if (_lastScrolledCharStart == highlight.charStart) return;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;

    final scrollPos = scrollable.position;
    // If the scroll position is actively undergoing a user drag or animation, do not interrupt
    if (scrollPos.isScrollingNotifier.value) {
      _lastUserInteractionTime = now;
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    try {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: _effectiveStyle),
        textDirection: TextDirection.ltr,
      );
      painter.layout(maxWidth: maxWidth);
      final wordOffset = painter.getOffsetForCaret(
        TextPosition(offset: highlight.charStart),
        Rect.zero,
      );

      final wordGlobalPos = renderBox.localToGlobal(wordOffset);
      final viewportHeight = scrollPos.viewportDimension;

      // Comfortable viewport threshold (20% to 75% of visible screen height)
      final topThreshold = viewportHeight * 0.20;
      final bottomThreshold = viewportHeight * 0.75;

      // Natural reading moves forward down the document.
      // Auto-scroll forward only when the word approaches or falls below the bottom threshold.
      // If a word is above topThreshold, we ONLY scroll backward if the audio cursor jumped
      // backwards in text (e.g. user seeked backwards). If reading forward, the word is above
      // topThreshold because the user scrolled down to read ahead — so never pull them back up!
      final isBackwardSeek = _lastScrolledCharStart >= 0 && highlight.charStart < _lastScrolledCharStart;
      final needsForwardScroll = wordGlobalPos.dy > bottomThreshold;
      final needsBackwardScroll = isBackwardSeek && (wordGlobalPos.dy < topThreshold);

      if (needsForwardScroll || needsBackwardScroll) {
        _lastScrolledCharStart = highlight.charStart;
        _lastScrollTime = now;

        final delta = wordGlobalPos.dy - (viewportHeight * 0.38);
        final targetScroll = (scrollPos.pixels + delta).clamp(
          scrollPos.minScrollExtent,
          scrollPos.maxScrollExtent,
        );

        if ((targetScroll - scrollPos.pixels).abs() > 16) {
          scrollPos.animateTo(
            targetScroll,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      }
    } catch (_) {
      // Non-blocking fallback for layout edge cases
    }
  }

  @override
  Widget build(BuildContext context) {
    final speech = context.watch<SpeechProvider?>();
    final highlightNotifier = speech?.highlightNotifier;

    return Listener(
      onPointerDown: (_) => _onUserInteracted(),
      onPointerMove: (_) => _onUserInteracted(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (highlightNotifier == null) {
            return _buildStaticText(widget.text, _effectiveStyle);
          }

          return ValueListenableBuilder<TtsHighlight?>(
            valueListenable: highlightNotifier,
            builder: (context, highlight, _) {
              final hasActiveHighlight = highlight != null &&
                  highlight.fullText == widget.text &&
                  highlight.charStart >= 0 &&
                  highlight.charEnd <= widget.text.length &&
                  highlight.charStart < highlight.charEnd;

              // If the user has an active manual selection, freeze span mutation so
              // Flutter's SelectableText won't collapse the selection or cause assertion crashes.
              final isUserSelecting = _activeUserSelection != null &&
                  !_activeUserSelection!.isCollapsed &&
                  _activeUserSelection!.isValid;

              if (hasActiveHighlight && !isUserSelecting) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkAutoScroll(highlight, constraints.maxWidth);
                });
                return _buildHighlightedText(highlight, _effectiveStyle);
              }

              return _buildStaticText(widget.text, _effectiveStyle);
            },
          );
        },
      ),
    );
  }

  Widget _buildStaticText(String text, TextStyle baseStyle) {
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text,
            style: baseStyle,
          ),
          if (widget.isStreaming) _buildStreamingCursor(),
        ],
      ),
      contextMenuBuilder: widget.contextMenuBuilder,
      onSelectionChanged: _handleSelectionChanged,
    );
  }

  Widget _buildHighlightedText(TtsHighlight highlight, TextStyle baseStyle) {
    final text = widget.text;
    final int start = highlight.charStart.clamp(0, text.length);
    final int end = highlight.charEnd.clamp(start, text.length);

    final before = text.substring(0, start);
    final word = text.substring(start, end);
    final after = text.substring(end);

    // Active Highlight Styling:
    // Soft glowing translucent teal badge with crisp white/slate text and a high-contrast underline
    final isDark = AppColors.isDark;
    final highlightStyle = baseStyle.copyWith(
      color: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A),
      backgroundColor: AppColors.primary.withValues(alpha: isDark ? 0.38 : 0.24),
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
      decorationThickness: 2.0,
      letterSpacing: 0.1,
    );

    // Subtle contrast for upcoming text so the spoken word naturally commands focus
    final upcomingStyle = baseStyle.copyWith(
      color: AppColors.textSecondary.withValues(alpha: 0.88),
    );

    return SelectableText.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty)
            TextSpan(
              text: before,
              style: baseStyle,
            ),
          if (word.isNotEmpty)
            TextSpan(
              text: word,
              style: highlightStyle,
            ),
          if (after.isNotEmpty)
            TextSpan(
              text: after,
              style: upcomingStyle,
            ),
          if (widget.isStreaming) _buildStreamingCursor(),
        ],
      ),
      contextMenuBuilder: widget.contextMenuBuilder,
      onSelectionChanged: _handleSelectionChanged,
    );
  }

  InlineSpan _buildStreamingCursor() {
    if (widget.streamingIndicator != null) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: widget.streamingIndicator!,
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        width: 7,
        height: 15,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
