import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/forensic/source_similarity_evidence.dart';
import '../models/toast_notification.dart';
import '../providers/toast_provider.dart';
import '../services/forensic/sources/citation_generator_service.dart';
import '../utils/share_helper.dart';

/// Interactive modal sheet enabling 1-tap academic citations and full bibliography export.
/// Supports APA 7th, MLA 9th, Chicago 17th, IEEE, and Harvard citation standards.
class CitationExportModal extends StatefulWidget {
  final List<SourceMatchSegment> matches;
  final int initialIndex;

  const CitationExportModal({
    super.key,
    required this.matches,
    this.initialIndex = 0,
  });

  /// Static helper to display the modal bottom sheet cleanly.
  static Future<void> show(
    BuildContext context, {
    required List<SourceMatchSegment> matches,
    int initialIndex = 0,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CitationExportModal(
        matches: matches,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  State<CitationExportModal> createState() => _CitationExportModalState();
}

class _CitationExportModalState extends State<CitationExportModal> {
  late CitationStyle _selectedStyle;
  late int _selectedSourceIndex;
  bool _exportAllBibliography = false;
  final CitationGeneratorService _citationService = CitationGeneratorService();

  @override
  void initState() {
    super.initState();
    _selectedStyle = CitationStyle.apa7;
    _selectedSourceIndex = widget.initialIndex.clamp(0, widget.matches.isEmpty ? 0 : widget.matches.length - 1);
    if (widget.matches.length > 1 && widget.initialIndex < 0) {
      _exportAllBibliography = true;
    }
  }

  SourceMetadata _convertSegmentToMetadata(SourceMatchSegment m) {
    final title = m.sourceTitle;
    final yearMatch = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(title);
    final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;

    final url = m.sourceUrl ?? m.oaUrl;
    String? host;
    if (url != null && url.isNotEmpty) {
      try {
        host = Uri.parse(url).host.replaceFirst('www.', '');
      } catch (_) {
        host = null;
      }
    }

    return SourceMetadata(
      title: title,
      authors: const [],
      year: year,
      publisherOrJournal: host,
      url: url,
    );
  }

  String _generateSingleCitation(SourceMatchSegment m, CitationStyle style) {
    final metadata = _convertSegmentToMetadata(m);
    return _citationService.formatCitation(metadata, style);
  }

  String _generateBibliography(CitationStyle style) {
    if (widget.matches.isEmpty) return 'No matched sources available for bibliography.';
    final buffer = StringBuffer();
    final uniqueTitles = <String>{};
    final uniqueMatches = <SourceMatchSegment>[];

    for (final m in widget.matches) {
      if (!uniqueTitles.contains(m.sourceTitle.toLowerCase().trim())) {
        uniqueTitles.add(m.sourceTitle.toLowerCase().trim());
        uniqueMatches.add(m);
      }
    }

    // Sort alphabetically by title
    uniqueMatches.sort((a, b) => a.sourceTitle.toLowerCase().compareTo(b.sourceTitle.toLowerCase()));

    buffer.writeln('# References & Works Cited (${style.label})\n');
    for (int i = 0; i < uniqueMatches.length; i++) {
      final citation = _generateSingleCitation(uniqueMatches[i], style);
      buffer.writeln('${i + 1}. $citation\n');
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final hasMatches = widget.matches.isNotEmpty;
    final activeMatch = hasMatches ? widget.matches[_selectedSourceIndex] : null;

    final currentCitationText = _exportAllBibliography
        ? _generateBibliography(_selectedStyle)
        : (activeMatch != null ? _generateSingleCitation(activeMatch, _selectedStyle) : 'No source selected.');

    final mediaQuery = MediaQuery.of(context);
    final systemBottomPadding = math.max(
      mediaQuery.padding.bottom,
      mediaQuery.viewPadding.bottom,
    );
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final effectiveBottomPadding = 20.0 + systemBottomPadding + keyboardInset;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: mediaQuery.size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 28,
                offset: Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            top: 14,
            left: 20,
            right: 20,
            bottom: effectiveBottomPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.glassBorderHover,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withAlpha(80)),
                    ),
                    child: Icon(LucideIcons.graduationCap, color: AppColors.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACADEMIC CITATION GENERATOR',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        _exportAllBibliography ? 'Full Bibliography' : 'Source Citation',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMuted),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Scope Switcher (Single Source vs All Sources)
          if (widget.matches.length > 1) ...[
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.glassInputBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _exportAllBibliography = false);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: !_exportAllBibliography ? AppColors.surfaceElevated : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: !_exportAllBibliography ? Border.all(color: AppColors.primary.withAlpha(120)) : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Current Source (${_selectedSourceIndex + 1}/${widget.matches.length})',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: !_exportAllBibliography ? FontWeight.w700 : FontWeight.w500,
                            color: !_exportAllBibliography ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _exportAllBibliography = true);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _exportAllBibliography ? AppColors.surfaceElevated : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: _exportAllBibliography ? Border.all(color: AppColors.primary.withAlpha(120)) : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'All Bibliography (${widget.matches.length})',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: _exportAllBibliography ? FontWeight.w700 : FontWeight.w500,
                            color: _exportAllBibliography ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Citation Style Selector Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: CitationStyle.values.map((style) {
                final isSelected = style == _selectedStyle;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(style.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedStyle = style);
                      }
                    },
                    selectedColor: AppColors.primary.withAlpha(45),
                    checkmarkColor: AppColors.primary,
                    backgroundColor: AppColors.glassInputBg,
                    labelStyle: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary.withAlpha(160) : AppColors.glassBorder,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Source Title Context (When viewing single source)
          if (!_exportAllBibliography && activeMatch != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.glassInputBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.fileText, size: 13, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activeMatch.sourceTitle,
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.matches.length > 1) ...[
                    IconButton(
                      onPressed: _selectedSourceIndex > 0
                          ? () => setState(() => _selectedSourceIndex--)
                          : null,
                      icon: const Icon(LucideIcons.chevronLeft, size: 14),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _selectedSourceIndex < widget.matches.length - 1
                          ? () => setState(() => _selectedSourceIndex++)
                          : null,
                      icon: const Icon(LucideIcons.chevronRight, size: 14),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Formatted Citation Output Card
          Flexible(
            child: Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.glassBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorderHover),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  currentCitationText,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textPrimary,
                    fontStyle: _exportAllBibliography ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons: Copy & Share
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await Clipboard.setData(ClipboardData(text: currentCitationText));
                    if (context.mounted) {
                      context.read<ToastProvider>().showToast(
                            _exportAllBibliography
                                ? 'Full ${_selectedStyle.label} Bibliography copied!'
                                : '${_selectedStyle.label} Citation copied to clipboard!',
                            ToastType.success,
                          );
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(LucideIcons.copy, size: 15),
                  label: Text(
                    _exportAllBibliography ? 'Copy Bibliography' : 'Copy Citation',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ShareHelper.shareText(
                      title: 'Lauriva Academic Citation',
                      text: currentCitationText,
                    );
                  },
                  icon: const Icon(LucideIcons.share2, size: 14),
                  label: Text(
                    'Share',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.glassBorderHover),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
  }
}
