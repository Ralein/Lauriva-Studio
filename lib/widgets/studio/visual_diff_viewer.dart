import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';

enum DiffType { insertion, deletion, unchanged }

class DiffChunk {
  final DiffType type;
  final String text;
  const DiffChunk(this.type, this.text);
}

/// Myers' diff algorithm (word-level) comparing [originalText] to [modifiedText].
class _DiffEngine {
  static List<DiffChunk> compute(String original, String modified) {
    final orig = original.split(RegExp(r'(\s+)')).where((s) => s.isNotEmpty).toList();
    final mod  = modified.split(RegExp(r'(\s+)')).where((s) => s.isNotEmpty).toList();
    return _diffTokens(orig, mod);
  }

  static List<DiffChunk> _diffTokens(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    // LCS DP table
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // Backtrack
    final result = <DiffChunk>[];
    int i = n, j = m;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
        result.add(DiffChunk(DiffType.unchanged, '${a[i - 1]} '));
        i--; j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        result.add(DiffChunk(DiffType.insertion, '${b[j - 1]} '));
        j--;
      } else {
        result.add(DiffChunk(DiffType.deletion, '${a[i - 1]} '));
        i--;
      }
    }
    return result.reversed.toList();
  }
}

/// Displays word-level diff with strike-through deletions and highlighted insertions.
class VisualDiffViewer extends StatefulWidget {
  final String originalText;
  final String modifiedText;
  /// Called when the user taps "Revert" on a deletion chunk.
  final void Function(int chunkIndex)? onChunkRevert;

  const VisualDiffViewer({
    super.key,
    required this.originalText,
    required this.modifiedText,
    this.onChunkRevert,
  });

  @override
  State<VisualDiffViewer> createState() => _VisualDiffViewerState();
}

class _VisualDiffViewerState extends State<VisualDiffViewer> {
  late List<DiffChunk> _chunks;
  int _insertions = 0;
  int _deletions  = 0;

  @override
  void initState() {
    super.initState();
    _computeDiff();
  }

  @override
  void didUpdateWidget(VisualDiffViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalText != widget.originalText ||
        oldWidget.modifiedText != widget.modifiedText) {
      _computeDiff();
    }
  }

  void _computeDiff() {
    _chunks    = _DiffEngine.compute(widget.originalText, widget.modifiedText);
    _insertions = _chunks.where((c) => c.type == DiffType.insertion).length;
    _deletions  = _chunks.where((c) => c.type == DiffType.deletion).length;
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _insertions > 0 || _deletions > 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassOutputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasChanges
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with stats
          _buildHeader(hasChanges),
          const Divider(height: 1, thickness: 1),
          // Diff content
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(14),
              child: _buildDiffText(),
            ),
          ),
          // Legend
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildHeader(bool hasChanges) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(LucideIcons.gitCompare, size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            'REVISION INSPECTOR',
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const Spacer(),
          if (hasChanges) ...[
            _statBadge('−$_deletions', AppColors.error),
            const SizedBox(width: 6),
            _statBadge('+$_insertions', AppColors.success),
          ] else
            Text(
              'No changes',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDiffText() {
    return RichText(
      text: TextSpan(
        children: _chunks.asMap().entries.map((entry) {
          final chunk = entry.value;
          switch (chunk.type) {
            case DiffType.unchanged:
              return TextSpan(
                text: chunk.text,
                style: GoogleFonts.outfit(
                  fontSize: 15.5,
                  color: AppColors.textPrimary,
                  height: 1.6,
                ),
              );
            case DiffType.deletion:
              return WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Tooltip(
                  message: 'Original phrasing — tap to copy',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Clipboard.setData(ClipboardData(text: chunk.text.trim()));
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        chunk.text,
                        style: GoogleFonts.outfit(
                          fontSize: 15.5,
                          color: AppColors.error,
                          height: 1.6,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: AppColors.error.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            case DiffType.insertion:
              return WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    chunk.text,
                    style: GoogleFonts.outfit(
                      fontSize: 15.5,
                      color: AppColors.success,
                      height: 1.6,
                    ),
                  ),
                ),
              );
          }
        }).toList(),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendDot(AppColors.error, 'Removed'),
          const SizedBox(width: 12),
          _legendDot(AppColors.success, 'Added'),
          const SizedBox(width: 12),
          _legendDot(AppColors.textMuted, 'Unchanged'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.8), shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
