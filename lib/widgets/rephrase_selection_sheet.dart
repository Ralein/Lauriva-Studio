import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/toast_notification.dart';
import '../providers/studio_provider.dart';
import '../providers/toast_provider.dart';
import '../services/rephrase_service.dart';
import 'lauriva_skeleton.dart';

/// Modal bottom sheet allowing users to inspect, rephrase, and replace a
/// highlighted word, phrase, or sentence in Studio or Humanizer output.
class RephraseSelectionSheet extends StatefulWidget {
  final String initialSelectedText;
  final String fullText;
  final int? initialStartIndex;
  final int? initialEndIndex;
  final String title;
  final IconData headerIcon;
  final void Function(String replacement, int start, int end)? onCustomApply;

  const RephraseSelectionSheet({
    super.key,
    required this.initialSelectedText,
    required this.fullText,
    this.initialStartIndex,
    this.initialEndIndex,
    this.title = 'Rephrase Selection',
    this.headerIcon = LucideIcons.repeat,
    this.onCustomApply,
  });

  /// Convenient helper to open the rephrase modal sheet.
  static Future<void> show(
    BuildContext context, {
    required String selectedText,
    required String fullText,
    int? startIndex,
    int? endIndex,
    String title = 'Rephrase Selection',
    IconData headerIcon = LucideIcons.repeat,
    void Function(String replacement, int start, int end)? onCustomApply,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RephraseSelectionSheet(
        initialSelectedText: selectedText,
        fullText: fullText,
        initialStartIndex: startIndex,
        initialEndIndex: endIndex,
        title: title,
        headerIcon: headerIcon,
        onCustomApply: onCustomApply,
      ),
    );
  }

  @override
  State<RephraseSelectionSheet> createState() => _RephraseSelectionSheetState();
}

class _RephraseSelectionSheetState extends State<RephraseSelectionSheet> {
  late String _currentTargetText;
  late int _targetStartIndex;
  late int _targetEndIndex;
  late SentenceSpan _enclosingSentence;
  bool _isWordMode = false;
  bool _isLoading = true;
  List<RephraseOption> _options = [];
  String? _selectedReplacement;
  late TextEditingController _customEditController;
  bool _isCustomEdit = false;

  @override
  void initState() {
    super.initState();
    final studio = context.read<StudioProvider>();
    final full = widget.fullText;

    var cleanSelected = widget.initialSelectedText.trim();
    if (cleanSelected.isEmpty && full.trim().isNotEmpty) {
      // If opened with no selection, default to the first sentence in output
      final sentences = studio.getOutputSentenceSpans();
      if (sentences.isNotEmpty) {
        cleanSelected = sentences.first.text;
        _targetStartIndex = sentences.first.startIndex;
        _targetEndIndex = sentences.first.endIndex;
      } else {
        cleanSelected = full.trim();
        _targetStartIndex = 0;
        _targetEndIndex = full.length;
      }
    } else {
      _targetStartIndex = widget.initialStartIndex ?? full.indexOf(cleanSelected);
      if (_targetStartIndex < 0) _targetStartIndex = 0;
      _targetEndIndex = widget.initialEndIndex ?? (_targetStartIndex + cleanSelected.length);
      if (_targetEndIndex > full.length) _targetEndIndex = full.length;
    }

    _currentTargetText = cleanSelected;
    _isWordMode = studio.rephraseService.isSingleWord(cleanSelected);
    _enclosingSentence = studio.rephraseService.findEnclosingSentence(
      full,
      _targetStartIndex,
      _targetEndIndex,
    );

    _customEditController = TextEditingController();
    _fetchRephraseOptions();
  }

  @override
  void dispose() {
    _customEditController.dispose();
    super.dispose();
  }

  Future<void> _fetchRephraseOptions() async {
    setState(() {
      _isLoading = true;
      _selectedReplacement = null;
    });

    final studio = context.read<StudioProvider>();
    try {
      final results = await studio.getRephraseOptionsForSelection(
        selectedText: _currentTargetText,
        startIndex: _targetStartIndex,
        endIndex: _targetEndIndex,
      );

      if (mounted) {
        setState(() {
          _options = results;
          _isLoading = false;
          if (_options.isNotEmpty) {
            _selectedReplacement = _options.first.text;
            _customEditController.text = _options.first.text;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _switchToSentenceMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _currentTargetText = _enclosingSentence.text;
      _targetStartIndex = _enclosingSentence.startIndex;
      _targetEndIndex = _enclosingSentence.endIndex;
      _isWordMode = false;
      _isCustomEdit = false;
    });
    _fetchRephraseOptions();
  }

  void _switchToWordMode(String word) {
    HapticFeedback.selectionClick();
    final wordStart = widget.fullText.indexOf(word, _enclosingSentence.startIndex);
    setState(() {
      _currentTargetText = word;
      _targetStartIndex = wordStart != -1 ? wordStart : _enclosingSentence.startIndex;
      _targetEndIndex = _targetStartIndex + word.length;
      _isWordMode = true;
      _isCustomEdit = false;
    });
    _fetchRephraseOptions();
  }

  void _applySelectedReplacement() {
    final replacement = _isCustomEdit
        ? _customEditController.text.trim()
        : (_selectedReplacement ?? _customEditController.text.trim());

    if (replacement.isEmpty) {
      context.read<ToastProvider>().showToast('Replacement text cannot be empty', ToastType.error);
      return;
    }

    HapticFeedback.mediumImpact();

    if (widget.onCustomApply != null) {
      widget.onCustomApply!(replacement, _targetStartIndex, _targetEndIndex);
    } else {
      context.read<StudioProvider>().replaceOutputSpan(
            startIndex: _targetStartIndex,
            endIndex: _targetEndIndex,
            replacement: replacement,
            fallbackTarget: _currentTargetText,
          );
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final studio = context.watch<StudioProvider>();
    final sentences = studio.getOutputSentenceSpans();
    final activeReplacement = _isCustomEdit
        ? _customEditController.text
        : (_selectedReplacement ?? _currentTargetText);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Handle Bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Header Row: Title, Scope Badge, and Close Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.headerIcon, size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _isWordMode ? 'Word replacement' : 'Sentence transformation',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 20, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: AppColors.glassBorder),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Scope Selector Chips (Word vs Full Sentence)
                    if (_enclosingSentence.text.trim().isNotEmpty &&
                        _enclosingSentence.text.trim() != _currentTargetText.trim()) ...[
                      Row(
                        children: [
                          _buildScopeChip(
                            label: 'Word: "$_currentTargetText"',
                            isSelected: _isWordMode,
                            icon: LucideIcons.type,
                            onTap: () {
                              if (!_isWordMode) {
                                final words = _enclosingSentence.text.split(RegExp(r'\s+'));
                                if (words.isNotEmpty) _switchToWordMode(words.first);
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildScopeChip(
                            label: 'Whole Sentence',
                            isSelected: !_isWordMode,
                            icon: LucideIcons.alignLeft,
                            onTap: () {
                              if (_isWordMode) _switchToSentenceMode();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Target Text Display Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ORIGINAL TARGET',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              if (_isWordMode)
                                Text(
                                  'Tap word to switch',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            _currentTargetText,
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section Title: Alternatives
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SUGGESTED REPHRASINGS',
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.primary,
                          ),
                        ),
                        if (!_isLoading)
                          InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _fetchRephraseOptions();
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.refreshCw, size: 11, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Regenerate',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Loading State
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LaurivaListSkeleton(
                          itemCount: 3,
                          itemHeight: 56,
                        ),
                      )
                    else if (_options.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Center(
                          child: Text(
                            'No automatic suggestions found. You can enter custom phrasing below.',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      // Suggestion Options List
                      ..._options.map((opt) {
                        final isSelected = !_isCustomEdit && _selectedReplacement == opt.text;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.glassBorder,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedReplacement = opt.text;
                                _customEditController.text = opt.text;
                                _isCustomEdit = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 2, right: 10),
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary : AppColors.textMuted,
                                        width: 1.5,
                                      ),
                                      color: isSelected ? AppColors.primary : Colors.transparent,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                                        : null,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                opt.styleLabel,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                opt.description,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 12,
                                                  color: AppColors.textMuted,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          opt.text,
                                          style: GoogleFonts.outfit(
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 14),

                    // Custom Phrasing Tweak Field
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCustomEdit ? AppColors.primary : AppColors.glassBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.pencil, size: 12, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text(
                                'FINE-TUNE OR TYPE CUSTOM PHRASING',
                                style: GoogleFonts.outfit(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _customEditController,
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Enter modified wording...',
                              hintStyle: GoogleFonts.outfit(
                                fontSize: 14.5,
                                color: AppColors.textMuted,
                              ),
                              border: InputBorder.none,
                            ),
                            onChanged: (val) {
                              setState(() {
                                _isCustomEdit = true;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Live In-Context Preview
                    if (_enclosingSentence.text.trim().isNotEmpty && activeReplacement.trim().isNotEmpty) ...[
                      Text(
                        'CONTEXT PREVIEW',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: _buildInContextPreview(activeReplacement),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Quick Jump: Other Sentences in Document
                    if (sentences.length > 1) ...[
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Switch to another sentence in output (${sentences.length})',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        children: sentences.map((s) {
                          final isCurrent = s.startIndex == _targetStartIndex;
                          return InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _currentTargetText = s.text;
                                _targetStartIndex = s.startIndex;
                                _targetEndIndex = s.endIndex;
                                _enclosingSentence = s;
                                _isWordMode = false;
                                _isCustomEdit = false;
                              });
                              _fetchRephraseOptions();
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isCurrent ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCurrent ? AppColors.primary : AppColors.glassBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.text,
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    LucideIcons.chevronRight,
                                    size: 14,
                                    color: isCurrent ? AppColors.primary : AppColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: AppColors.glassBorder),

            // Bottom Action Bar: Cancel + Apply Replacement Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.glassBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _applySelectedReplacement,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.check, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'Replace in Output',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeChip({
    required String label,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.glassBorder,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInContextPreview(String replacement) {
    final enc = _enclosingSentence.text;
    final target = _currentTargetText;

    if (!enc.contains(target)) {
      return Text(
        replacement,
        style: GoogleFonts.outfit(
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      );
    }

    final parts = enc.split(target);
    return RichText(
      text: TextSpan(
        style: GoogleFonts.outfit(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
        children: [
          TextSpan(text: parts.first),
          TextSpan(
            text: replacement,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            ),
          ),
          if (parts.length > 1) TextSpan(text: parts.sublist(1).join(target)),
        ],
      ),
    );
  }
}
